import Foundation

/// Tělo odpovědi (dekomprimované, v původním kódování znaků) v paměti nebo v temp souboru.
nonisolated enum ResponseBody: Sendable, Equatable {
    case data(Data)
    case file(URL, size: Int64)

    static let memLimit = 10 << 20
    static let sniffLen = 4096

    var size: Int64 {
        switch self {
        case .data(let dat): Int64(dat.count)
        case .file(_, let num): num
        }
    }

    var path: URL? { if case .file(let urlVal, _) = self { urlVal } else { nil } }

    /// Nejvýš `limit` bajtů od začátku (nil = celé tělo).
    func read(limit: Int? = nil) throws(CoreError) -> Data {
        switch self {
        case .data(let dat):
            return limit.map { Data(dat.prefix($0)) } ?? dat
        case .file(let urlVal, _):
            do {
                let hdr = try FileHandle(forReadingFrom: urlVal)
                defer { try? hdr.close() }
                return try (limit.map { try hdr.read(upToCount: $0) } ?? hdr.readToEnd()) ?? Data()
            } catch {
                throw CoreError(.fsError, error.localizedDescription)
            }
        }
    }

    /// Zápis celého těla do souboru (přepíše existující).
    func save(to url: URL) throws(CoreError) {
        do {
            switch self {
            case .data(let dat): try dat.write(to: url, options: .atomic)
            case .file(let urlVal, _):
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                try FileManager.default.copyItem(at: urlVal, to: url)
            }
        } catch {
            throw CoreError(.fsError, error.localizedDescription)
        }
    }

    func remove() {
        if let par = path { try? FileManager.default.removeItem(at: par) }
    }
}

/// Sbírá data z delegáta: do `memLimit` v paměti, pak do temp souboru; nad `max` ořízne.
nonisolated struct BodySink {
    let max: Int64
    private var buf = Data()
    private var file: FileHandle?
    private var url: URL?
    private(set) var size: Int64 = 0
    private(set) var truncated = false

    init(max: Int64) { self.max = max }

    /// Vrátí false, pokud je limit vyčerpán (další data se zahazují).
    mutating func append(_ dat: Data) throws(CoreError) -> Bool {
        guard !truncated else { return false }
        var dat = dat
        if size + Int64(dat.count) > max {
            dat = dat.prefix(Int(max - size))
            truncated = true
        }
        do {
            if file == nil, buf.count + dat.count > ResponseBody.memLimit {
                let urlVal = FileManager.default.temporaryDirectory.appending(
                    path: "minorrest-body-\(UUID().uuidString)")
                guard FileManager.default.createFile(atPath: urlVal.path, contents: buf) else {
                    throw CoreError(.fsError, urlVal.path)
                }
                url = urlVal
                file = try FileHandle(forWritingTo: urlVal)
                try file?.seekToEnd()
                buf = Data()
            }
            if let file { try file.write(contentsOf: dat) } else { buf.append(dat) }
        } catch let elem as CoreError {
            throw elem
        } catch {
            throw CoreError(.fsError, error.localizedDescription)
        }
        size += Int64(dat.count)
        return !truncated
    }

    mutating func finish() -> ResponseBody {
        guard let url else { return .data(buf) }
        try? file?.close()
        file = nil
        return .file(url, size: size)
    }

    mutating func discard() {
        try? file?.close()
        file = nil
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil
        buf = Data()
    }
}

/// Media type, charset a binárnost z Content-Type a začátku těla.
nonisolated enum ContentSniff {
    private static let textTypes = [
        "text/", "json", "xml", "javascript", "ecmascript", "yaml", "csv", "graphql",
        "x-www-form-urlencoded", "html"
    ]

    /// `text/HTML; charset=X` → (`text/html`, `x`)
    static func parse(_ contentType: String) -> (mediaType: String, charset: String) {
        let parts = contentType.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        let mt = parts.first?.lowercased() ?? ""
        var cs = ""
        for par in parts.dropFirst() {
            let kv = par.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, kv[0].lowercased() == "charset" {
                cs = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return (mt, cs)
    }

    static func sniff(_ contentType: String, _ sample: Data) -> (mediaType: String, charset: String, binary: Bool) {
        let (mt, param) = parse(contentType)
        if sample.isEmpty { return (mt, "", false) }
        if !textTypes.contains(where: { mt.contains($0) }), !looksText(sample) { return (mt, "", true) }
        if let bom = bom(sample) { return (mt, bom, false) }
        if !param.isEmpty { return (mt, canonical(param), false) }
        if mt.contains("json") { return (mt, "utf-8", false) }
        if mt.contains("html"), let meta = metaCharset(sample) { return (mt, canonical(meta), false) }
        if validUTF8(sample, cut: sample.count == ResponseBody.sniffLen) { return (mt, "utf-8", false) }
        var conv: NSString?
        let enc = NSString.stringEncoding(
            for: sample, encodingOptions: [.allowLossyKey: false], convertedString: &conv,
            usedLossyConversion: nil)
        return (mt, enc == 0 ? "windows-1252" : name(String.Encoding(rawValue: enc)) ?? "windows-1252", false)
    }

    /// Převod do UTF-8 pro zobrazení; neplatné sekvence nahradí `�`.
    static func toUTF8(_ dat: Data, _ charset: String) -> String {
        if let enc = encoding(charset), enc != .utf8, let str = String(data: dat, encoding: enc) { return str }
        let bomless = dat.starts(with: [0xEF, 0xBB, 0xBF]) ? dat.dropFirst(3) : dat[...]
        return String(decoding: bomless, as: UTF8.self)
    }

    static func encoding(_ charset: String) -> String.Encoding? {
        guard !charset.isEmpty else { return nil }
        let cf = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        guard cf != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }

    private static func name(_ elem: String.Encoding) -> String? {
        let cf = CFStringConvertNSStringEncodingToEncoding(elem.rawValue)
        return (CFStringConvertEncodingToIANACharSetName(cf) as String?)?.lowercased()
    }

    /// Kanonický název (`ISO-8859-2` → `iso-8859-2`, `cp1250` → `windows-1250`); neznámý jen malými písmeny.
    static func canonical(_ cs: String) -> String {
        encoding(cs).flatMap(name) ?? cs.lowercased()
    }

    private static func bom(_ dat: Data) -> String? {
        if dat.starts(with: [0xEF, 0xBB, 0xBF]) { return "utf-8" }
        if dat.starts(with: [0xFE, 0xFF]) { return "utf-16be" }
        if dat.starts(with: [0xFF, 0xFE]) { return "utf-16le" }
        return nil
    }

    /// `<meta charset="x">` nebo `content="…; charset=x"` v prvních 1024 bajtech.
    private static func metaCharset(_ dat: Data) -> String? {
        let head = String(decoding: dat.prefix(1024), as: UTF8.self).lowercased()
        guard let map = head.firstMatch(of: /<meta[^>]+charset\s*=\s*[\x22']?([a-z0-9_\-:.]+)/) else { return nil }
        return String(map.1)
    }

    /// Platné UTF-8 bez řídicích znaků (kromě běžných bílých); neúplný znak na konci nevadí.
    static func looksText(_ datVal: Data) -> Bool {
        guard validUTF8(datVal, cut: true) else { return false }
        return !datVal.contains { $0 < 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0D && $0 != 0x0C }
    }

    /// `cut` = vzorek je useknutý, neúplný znak na konci nevadí.
    static func validUTF8(_ datVal: Data, cut: Bool) -> Bool {
        var datVal = datVal[...]
        if cut, let i = datVal.indices.reversed().prefix(4).first(where: { datVal[$0] & 0xC0 != 0x80 }) {
            let lead = datVal[i]
            let need = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1
            if datVal.endIndex - i < need { datVal = datVal[..<i] }
        }
        return String(validating: datVal, as: UTF8.self) != nil
    }
}

/// Tělo pro zobrazení (UTF-8): celé do `maxView`, větší jen prvních `headView` bajtů (`partial`).
nonisolated struct BodyView: Sendable, Equatable {
    static let maxView: Int64 = 10_000_000
    static let headView = 1_000_000
    /// Větší tělo se automaticky neformátuje (Pretty až na vyžádání).
    static let autoPretty: Int64 = 5_000_000
    /// Větší obrázek se nenačítá (náhled jen do 10 MB).
    static let maxImage: Int64 = 10_000_000

    var text = ""
    /// json | xml | html | text
    var lang = "text"
    var size: Int64 = 0
    var partial = false
    /// Celé tělo binárního `image/*` do `maxImage`.
    var image: Data?

    init() {}

    static func lang(_ mediaType: String) -> String {
        if mediaType.contains("json") { return "json" }
        if mediaType.contains("html") { return "html" }
        if mediaType.contains("xml") { return "xml" }
        return "text"
    }
}

nonisolated enum TLSNames {
    static func version(_ val: UInt16) -> String {
        switch val {
        case 0x0301: "TLS 1.0"
        case 0x0302: "TLS 1.1"
        case 0x0303: "TLS 1.2"
        case 0x0304: "TLS 1.3"
        default: String(format: "0x%04X", val)
        }
    }

    static func cipher(_ cur: UInt16) -> String { ciphers[cur] ?? String(format: "0x%04X", cur) }

    private static let ciphers: [UInt16: String] = [
        0x1301: "TLS_AES_128_GCM_SHA256", 0x1302: "TLS_AES_256_GCM_SHA384", 0x1303: "TLS_CHACHA20_POLY1305_SHA256",
        0xC02B: "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256", 0xC02C: "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
        0xC02F: "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256", 0xC030: "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
        0xCCA8: "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256", 0xCCA9: "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256",
        0xC009: "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA", 0xC00A: "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA",
        0xC013: "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA", 0xC014: "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA",
        0x009C: "TLS_RSA_WITH_AES_128_GCM_SHA256", 0x009D: "TLS_RSA_WITH_AES_256_GCM_SHA384",
        0x002F: "TLS_RSA_WITH_AES_128_CBC_SHA", 0x0035: "TLS_RSA_WITH_AES_256_CBC_SHA"
    ]

    /// Subjekt, vydavatel (`CN=…,O=…`) a expirace (RFC 3339) leaf certifikátu.
    static func certificate(_ trust: SecTrust) -> (subject: String, issuer: String, notAfter: String)? {
        guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else { return nil }
        let keys = [kSecOIDX509V1SubjectName, kSecOIDX509V1IssuerName, kSecOIDX509V1ValidityNotAfter] as CFArray
        let vals = SecCertificateCopyValues(leaf, keys, nil) as? [String: [String: Any]] ?? [:]
        func dn(_ key: CFString) -> String {
            let parts = vals[key as String]?[kSecPropertyKeyValue as String] as? [[String: Any]] ?? []
            return parts.reversed().compactMap { part -> String? in
                guard let oid = part[kSecPropertyKeyLabel as String] as? String,
                    let val = part[kSecPropertyKeyValue as String] as? String,
                    let short = rdn[oid]
                else { return nil }
                return "\(short)=\(val)"
            }.joined(separator: ",")
        }
        var subject = dn(kSecOIDX509V1SubjectName)
        if subject.isEmpty { subject = (SecCertificateCopySubjectSummary(leaf) as String?) ?? "" }
        var notAfter = ""
        if let numVal = vals[kSecOIDX509V1ValidityNotAfter as String]?[kSecPropertyKeyValue as String] as? NSNumber {
            notAfter = ISO8601DateFormatter().string(from: Date(timeIntervalSinceReferenceDate: numVal.doubleValue))
        }
        return (subject, dn(kSecOIDX509V1IssuerName), notAfter)
    }

    private static let rdn = [
        "2.5.4.3": "CN", "2.5.4.10": "O", "2.5.4.11": "OU", "2.5.4.6": "C", "2.5.4.7": "L",
        "2.5.4.8": "ST", "2.5.4.5": "SERIALNUMBER"
    ]
}

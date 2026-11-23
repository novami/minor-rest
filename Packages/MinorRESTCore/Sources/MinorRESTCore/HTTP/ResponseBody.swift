import Foundation

/// Tělo odpovědi (dekomprimované, v původním kódování znaků) v paměti nebo v temp souboru.
enum ResponseBody: Sendable, Equatable {
    case data(Data)
    case file(URL, size: Int64)

    static let memLimit = 10 << 20
    static let sniffLen = 4096

    var size: Int64 {
        switch self {
        case .data(let d): Int64(d.count)
        case .file(_, let n): n
        }
    }

    var path: URL? { if case .file(let u, _) = self { u } else { nil } }

    /// Nejvýš `limit` bajtů od začátku (nil = celé tělo).
    func read(limit: Int? = nil) throws(CoreError) -> Data {
        switch self {
        case .data(let d):
            return limit.map { Data(d.prefix($0)) } ?? d
        case .file(let u, _):
            do {
                let h = try FileHandle(forReadingFrom: u)
                defer { try? h.close() }
                return try (limit.map { try h.read(upToCount: $0) } ?? h.readToEnd()) ?? Data()
            } catch {
                throw CoreError(.fsError, error.localizedDescription)
            }
        }
    }

    func remove() {
        if let p = path { try? FileManager.default.removeItem(at: p) }
    }
}

/// Sbírá data z delegáta: do `memLimit` v paměti, pak do temp souboru; nad `max` ořízne.
struct BodySink {
    let max: Int64
    private var buf = Data()
    private var file: FileHandle?
    private var url: URL?
    private(set) var size: Int64 = 0
    private(set) var truncated = false

    init(max: Int64) { self.max = max }

    /// Vrátí false, pokud je limit vyčerpán (další data se zahazují).
    mutating func append(_ d: Data) throws(CoreError) -> Bool {
        guard !truncated else { return false }
        var d = d
        if size + Int64(d.count) > max {
            d = d.prefix(Int(max - size))
            truncated = true
        }
        do {
            if file == nil, buf.count + d.count > ResponseBody.memLimit {
                let u = FileManager.default.temporaryDirectory.appending(path: "minorrest-body-\(UUID().uuidString)")
                guard FileManager.default.createFile(atPath: u.path, contents: buf) else {
                    throw CoreError(.fsError, u.path)
                }
                url = u
                file = try FileHandle(forWritingTo: u)
                try file?.seekToEnd()
                buf = Data()
            }
            if let file { try file.write(contentsOf: d) } else { buf.append(d) }
        } catch let e as CoreError {
            throw e
        } catch {
            throw CoreError(.fsError, error.localizedDescription)
        }
        size += Int64(d.count)
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
enum ContentSniff {
    private static let textTypes = ["text/", "json", "xml", "javascript", "ecmascript", "yaml", "csv", "graphql",
                                    "x-www-form-urlencoded", "html"]

    /// `text/HTML; charset=X` → (`text/html`, `x`)
    static func parse(_ contentType: String) -> (mediaType: String, charset: String) {
        let parts = contentType.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        let mt = parts.first?.lowercased() ?? ""
        var cs = ""
        for p in parts.dropFirst() {
            let kv = p.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, kv[0].lowercased() == "charset" { cs = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
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
        let enc = NSString.stringEncoding(for: sample, encodingOptions: [.allowLossyKey: false], convertedString: &conv,
                                          usedLossyConversion: nil)
        return (mt, enc == 0 ? "windows-1252" : name(String.Encoding(rawValue: enc)) ?? "windows-1252", false)
    }

    /// Převod do UTF-8 pro zobrazení; neplatné sekvence nahradí `�`.
    static func toUTF8(_ d: Data, _ charset: String) -> String {
        if let enc = encoding(charset), enc != .utf8, let s = String(data: d, encoding: enc) { return s }
        let bomless = d.starts(with: [0xEF, 0xBB, 0xBF]) ? d.dropFirst(3) : d[...]
        return String(decoding: bomless, as: UTF8.self)
    }

    static func encoding(_ charset: String) -> String.Encoding? {
        guard !charset.isEmpty else { return nil }
        let cf = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        guard cf != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }

    private static func name(_ e: String.Encoding) -> String? {
        let cf = CFStringConvertNSStringEncodingToEncoding(e.rawValue)
        return (CFStringConvertEncodingToIANACharSetName(cf) as String?)?.lowercased()
    }

    /// Kanonický název (`ISO-8859-2` → `iso-8859-2`, `cp1250` → `windows-1250`); neznámý jen malými písmeny.
    static func canonical(_ cs: String) -> String {
        encoding(cs).flatMap(name) ?? cs.lowercased()
    }

    private static func bom(_ d: Data) -> String? {
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { return "utf-8" }
        if d.starts(with: [0xFE, 0xFF]) { return "utf-16be" }
        if d.starts(with: [0xFF, 0xFE]) { return "utf-16le" }
        return nil
    }

    /// `<meta charset="x">` nebo `content="…; charset=x"` v prvních 1024 bajtech.
    private static func metaCharset(_ d: Data) -> String? {
        let head = String(decoding: d.prefix(1024), as: UTF8.self).lowercased()
        guard let m = head.firstMatch(of: /<meta[^>]+charset\s*=\s*["']?([a-z0-9_\-:.]+)/) else { return nil }
        return String(m.1)
    }

    /// Platné UTF-8 bez řídicích znaků (kromě běžných bílých); neúplný znak na konci nevadí.
    static func looksText(_ d: Data) -> Bool {
        guard validUTF8(d, cut: true) else { return false }
        return !d.contains { $0 < 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0D && $0 != 0x0C }
    }

    /// `cut` = vzorek je useknutý, neúplný znak na konci nevadí.
    static func validUTF8(_ d: Data, cut: Bool) -> Bool {
        var d = d[...]
        if cut, let i = d.indices.reversed().prefix(4).first(where: { d[$0] & 0xC0 != 0x80 }) {
            let lead = d[i], need = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1
            if d.endIndex - i < need { d = d[..<i] }
        }
        return String(validating: d, as: UTF8.self) != nil
    }
}

/// Tělo pro zobrazení (UTF-8, nejvýš `maxView` bajtů).
public struct BodyView: Sendable, Equatable {
    public static let maxView = 2 << 20
    /// Větší obrázek se nenačítá (náhled jen do 10 MB).
    public static let maxImage: Int64 = 10_000_000

    public var text = ""
    /// json | xml | html | text
    public var lang = "text"
    public var size: Int64 = 0
    public var partial = false
    /// Celé tělo binárního `image/*` do `maxImage`.
    public var image: Data?

    public init() {}

    static func lang(_ mediaType: String) -> String {
        if mediaType.contains("json") { return "json" }
        if mediaType.contains("html") { return "html" }
        if mediaType.contains("xml") { return "xml" }
        return "text"
    }
}

enum TLSNames {
    static func version(_ v: UInt16) -> String {
        switch v {
        case 0x0301: "TLS 1.0"
        case 0x0302: "TLS 1.1"
        case 0x0303: "TLS 1.2"
        case 0x0304: "TLS 1.3"
        default: String(format: "0x%04X", v)
        }
    }

    static func cipher(_ c: UInt16) -> String { ciphers[c] ?? String(format: "0x%04X", c) }

    private static let ciphers: [UInt16: String] = [
        0x1301: "TLS_AES_128_GCM_SHA256", 0x1302: "TLS_AES_256_GCM_SHA384", 0x1303: "TLS_CHACHA20_POLY1305_SHA256",
        0xC02B: "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256", 0xC02C: "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
        0xC02F: "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256", 0xC030: "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
        0xCCA8: "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256", 0xCCA9: "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256",
        0xC009: "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA", 0xC00A: "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA",
        0xC013: "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA", 0xC014: "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA",
        0x009C: "TLS_RSA_WITH_AES_128_GCM_SHA256", 0x009D: "TLS_RSA_WITH_AES_256_GCM_SHA384",
        0x002F: "TLS_RSA_WITH_AES_128_CBC_SHA", 0x0035: "TLS_RSA_WITH_AES_256_CBC_SHA",
    ]

    /// Subjekt, vydavatel (`CN=…,O=…`) a expirace (RFC 3339) leaf certifikátu.
    static func certificate(_ trust: SecTrust) -> (subject: String, issuer: String, notAfter: String)? {
        guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else { return nil }
        let keys = [kSecOIDX509V1SubjectName, kSecOIDX509V1IssuerName, kSecOIDX509V1ValidityNotAfter] as CFArray
        let vals = SecCertificateCopyValues(leaf, keys, nil) as? [String: [String: Any]] ?? [:]
        func dn(_ key: CFString) -> String {
            let parts = vals[key as String]?[kSecPropertyKeyValue as String] as? [[String: Any]] ?? []
            return parts.reversed().compactMap { p -> String? in
                guard let oid = p[kSecPropertyKeyLabel as String] as? String, let v = p[kSecPropertyKeyValue as String] as? String,
                      let short = rdn[oid] else { return nil }
                return "\(short)=\(v)"
            }.joined(separator: ",")
        }
        var subject = dn(kSecOIDX509V1SubjectName)
        if subject.isEmpty { subject = (SecCertificateCopySubjectSummary(leaf) as String?) ?? "" }
        var notAfter = ""
        if let n = vals[kSecOIDX509V1ValidityNotAfter as String]?[kSecPropertyKeyValue as String] as? NSNumber {
            notAfter = ISO8601DateFormatter().string(from: Date(timeIntervalSinceReferenceDate: n.doubleValue))
        }
        return (subject, dn(kSecOIDX509V1IssuerName), notAfter)
    }

    private static let rdn = ["2.5.4.3": "CN", "2.5.4.10": "O", "2.5.4.11": "OU", "2.5.4.6": "C", "2.5.4.7": "L",
                              "2.5.4.8": "ST", "2.5.4.5": "SERIALNUMBER"]
}

import Foundation
import UniformTypeIdentifiers

/// Připravené tělo requestu.
struct Payload: Sendable {
    enum Source: Sendable {
        case none
        case data(Data)
        /// Soubor se posílá streamem (při redirectu 307/308 se otevře znovu).
        case file(URL)
    }

    var source: Source = .none
    /// Automatický Content-Type ("" = žádný).
    var contentType = ""
    var size: Int64 = 0
    /// Náhled pro záložku Odesláno (u souboru prázdný).
    var preview = ""

    var isEmpty: Bool { if case .none = source { true } else { false } }

    func stream() -> InputStream? {
        switch source {
        case .none: nil
        case .data(let d): InputStream(data: d)
        case .file(let u): InputStream(url: u)
        }
    }

    static let previewLimit = 64 << 10

    static func bytes(_ d: Data, _ contentType: String) -> Payload {
        Payload(source: .data(d), contentType: contentType, size: Int64(d.count),
                preview: String(decoding: d.prefix(previewLimit), as: UTF8.self))
    }

    private static let rawTypes = [
        BodyType.json: "application/json; charset=utf-8",
        BodyType.xml: "application/xml; charset=utf-8",
        BodyType.text: "text/plain; charset=utf-8",
        BodyType.html: "text/html; charset=utf-8",
    ]

    /// Sestaví tělo; relativní cesty souborů se berou vůči `baseDir` (kořen projektu).
    static func build(_ b: Body, baseDir: String) throws(CoreError) -> Payload {
        if let ct = rawTypes[b.type] { return bytes(Data(b.raw.utf8), ct) }
        switch b.type {
        case BodyType.form:
            return bytes(Data(encodeForm(b.form).utf8), "application/x-www-form-urlencoded")
        case BodyType.multipart:
            return try multipart(b.multipart, baseDir: baseDir)
        case BodyType.binary:
            if b.binaryPath.isEmpty { return Payload() }
            let u = fileURL(b.binaryPath, baseDir)
            guard let size = fileSize(u) else { throw CoreError(.fileNotFound, b.binaryPath) }
            return Payload(source: .file(u), contentType: mimeType(u), size: size)
        default:
            return Payload()
        }
    }

    /// Zapnuté řádky v zadaném pořadí, kódování jako HTML formulář (mezera = `+`).
    static func encodeForm(_ rows: [KV]) -> String {
        rows.filter { $0.enabled && !$0.name.isEmpty }
            .map { formEscape($0.name) + "=" + formEscape($0.value) }
            .joined(separator: "&")
    }

    static func formEscape(_ s: String) -> String {
        var out = ""
        for b in s.utf8 {
            switch b {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "_"),
                 UInt8(ascii: "."), UInt8(ascii: "~"):
                out.unicodeScalars.append(Unicode.Scalar(b))
            case UInt8(ascii: " "):
                out += "+"
            default:
                out += String(format: "%%%02X", b)
            }
        }
        return out
    }

    /// Multipart do paměti (známá délka, opakovatelné při redirectu).
    static func multipart(_ parts: [MultipartPart], baseDir: String, boundary: String = newBoundary()) throws(CoreError) -> Payload {
        var d = Data()
        var first = true
        func line(_ s: String) { d.append(Data((s + "\r\n").utf8)) }
        for p in parts where p.enabled && !p.name.isEmpty {
            line(first ? "--\(boundary)" : "\r\n--\(boundary)")
            first = false
            if p.kind == "file" {
                let u = fileURL(p.path, baseDir)
                guard !p.path.isEmpty, let data = try? Data(contentsOf: u) else { throw CoreError(.fileNotFound, p.path) }
                line("Content-Disposition: form-data; name=\"\(quoteEscape(p.name))\"; filename=\"\(quoteEscape(u.lastPathComponent))\"")
                line("Content-Type: \(p.contentType.isEmpty ? mimeType(u) : p.contentType)")
                line("")
                d.append(data)
            } else {
                line("Content-Disposition: form-data; name=\"\(quoteEscape(p.name))\"")
                if !p.contentType.isEmpty { line("Content-Type: \(p.contentType)") }
                line("")
                d.append(Data(p.value.utf8))
            }
        }
        line(first ? "--\(boundary)--" : "\r\n--\(boundary)--")
        var pl = bytes(d, "multipart/form-data; boundary=\(boundary)")
        if parts.contains(where: { $0.enabled && $0.kind == "file" }) { pl.preview = "" }
        return pl
    }

    static func newBoundary() -> String {
        (0..<30).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    static func quoteEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "%0D").replacingOccurrences(of: "\n", with: "%0A")
    }

    static func fileURL(_ path: String, _ baseDir: String) -> URL {
        if path.hasPrefix("/") || baseDir.isEmpty { return URL(fileURLWithPath: path) }
        return URL(fileURLWithPath: baseDir).appendingPathComponent(path)
    }

    static func fileSize(_ u: URL) -> Int64? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: u.path),
              a[.type] as? FileAttributeType != .typeDirectory,
              let n = a[.size] as? NSNumber else { return nil }
        return n.int64Value
    }

    static func mimeType(_ u: URL) -> String {
        UTType(filenameExtension: u.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}

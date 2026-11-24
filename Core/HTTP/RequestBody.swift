import Foundation
import UniformTypeIdentifiers

/// Připravené tělo requestu.
nonisolated struct Payload: Sendable {
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
        case .data(let dat): InputStream(data: dat)
        case .file(let urlVal): InputStream(url: urlVal)
        }
    }

    static let previewLimit = 64 << 10

    static func bytes(_ dat: Data, _ contentType: String) -> Payload {
        Payload(
            source: .data(dat), contentType: contentType, size: Int64(dat.count),
            preview: String(decoding: dat.prefix(previewLimit), as: UTF8.self))
    }

    static let rawTypes = [
        BodyType.json: "application/json; charset=utf-8",
        BodyType.xml: "application/xml; charset=utf-8",
        BodyType.text: "text/plain; charset=utf-8",
        BodyType.html: "text/html; charset=utf-8"
    ]

    /// Sestaví tělo; relativní cesty souborů se berou vůči `baseDir` (kořen projektu).
    static func build(_ buf: Body, baseDir: String) throws(CoreError) -> Payload {
        if let ct = rawTypes[buf.type] { return bytes(Data(buf.raw.utf8), ct) }
        switch buf.type {
        case BodyType.form:
            return bytes(Data(encodeForm(buf.form).utf8), "application/x-www-form-urlencoded")
        case BodyType.multipart:
            return try multipart(buf.multipart, baseDir: baseDir)
        case BodyType.binary:
            if buf.binaryPath.isEmpty { return Payload() }
            let urlVal = fileURL(buf.binaryPath, baseDir)
            guard let size = fileSize(urlVal) else { throw CoreError(.fileNotFound, buf.binaryPath) }
            return Payload(source: .file(urlVal), contentType: mimeType(urlVal), size: size)
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

    static func formEscape(_ str: String) -> String {
        var out = ""
        for buf in str.utf8 {
            switch buf {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
                UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "_"),
                UInt8(ascii: "."), UInt8(ascii: "~"):
                out.unicodeScalars.append(Unicode.Scalar(buf))
            case UInt8(ascii: " "):
                out += "+"
            default:
                out += String(format: "%%%02X", buf)
            }
        }
        return out
    }

    /// Multipart do paměti (známá délka, opakovatelné při redirectu).
    static func multipart(_ parts: [MultipartPart], baseDir: String, boundary: String = newBoundary()) throws(CoreError)
        -> Payload {
        var dat = Data()
        var first = true
        func line(_ str: String) { dat.append(Data((str + "\r\n").utf8)) }
        for par in parts where par.enabled && !par.name.isEmpty {
            line(first ? "--\(boundary)" : "\r\n--\(boundary)")
            first = false
            if par.kind == "file" {
                let urlVal = fileURL(par.path, baseDir)
                guard !par.path.isEmpty, let data = try? Data(contentsOf: urlVal) else {
                    throw CoreError(.fileNotFound, par.path)
                }
                line(
                    "Content-Disposition: form-data; name=\"\(quoteEscape(par.name))\"; filename=\"\(quoteEscape(urlVal.lastPathComponent))\""
                )
                line("Content-Type: \(par.contentType.isEmpty ? mimeType(urlVal) : par.contentType)")
                line("")
                dat.append(data)
            } else {
                line("Content-Disposition: form-data; name=\"\(quoteEscape(par.name))\"")
                if !par.contentType.isEmpty { line("Content-Type: \(par.contentType)") }
                line("")
                dat.append(Data(par.value.utf8))
            }
        }
        line(first ? "--\(boundary)--" : "\r\n--\(boundary)--")
        var pl = bytes(dat, "multipart/form-data; boundary=\(boundary)")
        if parts.contains(where: { $0.enabled && $0.kind == "file" }) { pl.preview = "" }
        return pl
    }

    static func newBoundary() -> String {
        (0..<30).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    static func quoteEscape(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "%0D").replacingOccurrences(of: "\n", with: "%0A")
    }

    static func fileURL(_ path: String, _ baseDir: String) -> URL {
        if path.hasPrefix("/") || baseDir.isEmpty { return URL(fileURLWithPath: path) }
        return URL(fileURLWithPath: baseDir).appendingPathComponent(path)
    }

    static func fileSize(_ urlVal: URL) -> Int64? {
        guard let arg = try? FileManager.default.attributesOfItem(atPath: urlVal.path),
            arg[.type] as? FileAttributeType != .typeDirectory,
            let num = arg[.size] as? NSNumber
        else { return nil }
        return num.int64Value
    }

    static func mimeType(_ urlVal: URL) -> String {
        UTType(filenameExtension: urlVal.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}

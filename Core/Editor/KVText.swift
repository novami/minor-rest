import Foundation

/// Hromadná úprava řádků KvEditoru: řádek `název: hodnota`, prefix `//` = vypnutý.
nonisolated enum KVBulk {
    static func text(_ rows: [KeyValue]) -> String {
        rows.map { res in
            (res.enabled ? "" : "//") + res.name + (res.bare && res.value.isEmpty ? "" : ": \(res.value)")
        }.joined(separator: "\n")
    }

    /// Popisy se převezmou podle názvu z `prev`; řádek bez `:` je `bare` jen při `allowBare` (query).
    static func parse(_ text: String, prev: [KeyValue], allowBare: Bool = false) -> [KeyValue] {
        var desc: [String: String] = [:]
        for res in prev where !res.description.isEmpty && desc[res.name] == nil { desc[res.name] = res.description }
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let enabled = !line.hasPrefix("//")
            if !enabled { line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            let colon = line.firstIndex(of: ":")
            let name = String(colon.map { line[..<$0] } ?? line[...]).trimmingCharacters(in: .whitespaces)
            let value = colon.map { String(line[line.index(after: $0)...]).trimmingCharacters(in: .whitespaces) } ?? ""
            return KeyValue(
                name: name, value: value, enabled: enabled, description: desc[name] ?? "",
                bare: colon == nil && allowBare)
        }
    }
}

nonisolated enum PathParams {
    /// Názvy segmentů `:name` v cestě (stejná pravidla jako `URLBuilder`; port v hostu se nepočítá).
    static func names(_ url: String) -> [String] {
        var rest = Substring(url)
        if let str = rest.range(of: "://") { rest = rest[str.upperBound...] }
        guard let slash = rest.firstIndex(of: "/") else { return [] }
        rest = rest[slash...]
        if let end = rest.firstIndex(where: { $0 == "?" || $0 == "#" }) { rest = rest[..<end] }
        var out: [String] = []
        for seg in rest.split(separator: "/") where seg.first == ":" {
            let name = String(
                seg.dropFirst().prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
            if !name.isEmpty, !out.contains(name) { out.append(name) }
        }
        return out
    }

    /// Řádky odpovídající URL (hodnoty a popisy se drží podle názvu), `nil` = beze změny.
    static func sync(_ url: String, _ path: [PathParam]) -> [PathParam]? {
        let num = names(url)
        if num == path.map(\.name) { return nil }
        return num.map { name in path.first { $0.name == name } ?? PathParam(name: name) }
    }
}

/// Našeptávač hlaviček requestu: běžné názvy a typické hodnoty.
nonisolated enum HeaderHints {
    private static let mime = [
        "application/json", "application/xml", "application/x-www-form-urlencoded",
        "multipart/form-data", "text/plain", "text/html", "application/octet-stream"
    ]

    static let all: [(name: String, values: [String])] = [
        ("Accept", ["*/*"] + mime),
        ("Accept-Charset", ["utf-8"]),
        ("Accept-Encoding", ["gzip, deflate, br", "gzip", "identity"]),
        ("Accept-Language", ["cs-CZ,cs;q=0.9,en;q=0.8", "en-US,en;q=0.9"]),
        ("Authorization", ["Bearer {{token}}", "Basic "]),
        ("Cache-Control", ["no-cache", "no-store", "max-age=0"]),
        ("Connection", ["keep-alive", "close"]),
        ("Content-Encoding", ["gzip", "deflate", "br"]),
        ("Content-Type", mime + ["application/json; charset=utf-8"]),
        ("Cookie", []), ("DNT", ["1"]), ("If-Match", []), ("If-Modified-Since", []), ("If-None-Match", []),
        ("Origin", []), ("Pragma", ["no-cache"]), ("Range", ["bytes=0-"]), ("Referer", []),
        ("User-Agent", ["MinorREST"]),
        ("X-API-Key", ["{{apiKey}}"]),
        ("X-Correlation-ID", ["{{$uuid}}"]),
        ("X-Request-ID", ["{{$uuid}}"]),
        ("X-Forwarded-For", []),
        ("X-Requested-With", ["XMLHttpRequest"])
    ]

    static var names: [String] { all.map(\.name) }

    static func values(for name: String) -> [String] {
        let num = name.trimmingCharacters(in: .whitespaces).lowercased()
        return all.first { $0.name.lowercased() == num }?.values ?? []
    }

    /// Návrhy začínající na `prefix` (bez rozlišení velikosti), přesná shoda se nenabízí.
    static func complete(_ prefix: String, in options: [String]) -> [String] {
        let par = prefix.lowercased()
        return options.filter { $0.lowercased().hasPrefix(par) && $0 != prefix }
    }
}

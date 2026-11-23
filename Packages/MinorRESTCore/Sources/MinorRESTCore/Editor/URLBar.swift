import Foundation

/// Text URL baru = `url` + zapnuté query parametry (bez kódování; kóduje se při odeslání).
/// Parsuje se ručně (`&`, `=`), aby se nerozbily `{{proměnné}}`.
public enum URLBar {
    public static func compose(url: String, query: [KV]) -> String {
        let q = query.filter { $0.enabled && !($0.name.isEmpty && $0.value.isEmpty) }
            .map { $0.bare && $0.value.isEmpty ? $0.name : "\($0.name)=\($0.value)" }
        return q.isEmpty ? url : url + "?" + q.joined(separator: "&")
    }

    /// Rozdělí text na URL a query: rozparsované dvojice nahradí v pořadí zapnuté neprázdné řádky (popisy zůstanou),
    /// vypnuté a prázdné řádky zůstanou na svých místech, přebytečné zapnuté řádky zmizí.
    public static func parse(_ text: String, query: [KV]) -> (url: String, query: [KV]) {
        let (url, rest) = text.firstIndex(of: "?").map { (String(text[..<$0]), String(text[text.index(after: $0)...])) }
            ?? (text, "")
        var parsed = rest.split(separator: "&", omittingEmptySubsequences: true).map(pair)[...]
        var out: [KV] = []
        for row in query {
            if !row.enabled || (row.name.isEmpty && row.value.isEmpty) {
                out.append(row)
            } else if let p = parsed.popFirst() {
                var r = row
                (r.name, r.value, r.bare) = p
                out.append(r)
            }
        }
        out += parsed.map { KV(name: $0.0, value: $0.1, bare: $0.2) }
        return (url, out)
    }

    private static func pair(_ s: Substring) -> (String, String, Bool) {
        guard let i = s.firstIndex(of: "=") else { return (String(s), "", true) }
        return (String(s[..<i]), String(s[s.index(after: i)...]), false)
    }
}

/// Úsek textu se zvýrazněním proměnných (`{{…}}`; `\{{` je literál).
public struct VarToken: Hashable, Sendable {
    public enum Kind: Sendable { case variable, dynamic }
    public let range: NSRange
    public let name: String
    public let kind: Kind
}

extension VarToken {
    /// Tokeny proměnných v textu (rozsahy v UTF-16 pro AppKit).
    public static func scan(_ s: String) -> [VarToken] {
        guard s.contains("{{") else { return [] }
        let u = Array(s.utf16)
        let open: UInt16 = 0x7B, close: UInt16 = 0x7D, slash: UInt16 = 0x5C
        var out: [VarToken] = []
        var i = 0
        while i + 1 < u.count {
            guard u[i] == open, u[i + 1] == open else { i += 1; continue }
            if i > 0, u[i - 1] == slash { i += 2; continue }
            var j = i + 2
            while j + 1 < u.count, !(u[j] == close && u[j + 1] == close), u[j] != open { j += 1 }
            guard j + 1 < u.count, u[j] == close, u[j + 1] == close else { i = j; continue }
            let name = String(utf16CodeUnits: Array(u[(i + 2)..<j]), count: j - i - 2)
                .trimmingCharacters(in: .whitespaces)
            out.append(VarToken(range: NSRange(location: i, length: j + 2 - i), name: name,
                                kind: name.hasPrefix("$") ? .dynamic : .variable))
            i = j + 2
        }
        return out
    }
}

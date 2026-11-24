import Foundation

/// Text URL baru = `url` + zapnuté query parametry (bez kódování; kóduje se při odeslání).
/// Parsuje se ručně (`&`, `=`), aby se nerozbily `{{proměnné}}`.
nonisolated enum URLBar {
    static func compose(url: String, query: [KV]) -> String {
        let que = query.filter { $0.enabled && !($0.name.isEmpty && $0.value.isEmpty) }
            .map { $0.bare && $0.value.isEmpty ? $0.name : "\($0.name)=\($0.value)" }
        return que.isEmpty ? url : url + "?" + que.joined(separator: "&")
    }

    /// Rozdělí text na URL a query: rozparsované dvojice nahradí v pořadí zapnuté neprázdné řádky (popisy zůstanou),
    /// vypnuté a prázdné řádky zůstanou na svých místech, přebytečné zapnuté řádky zmizí.
    static func parse(_ text: String, query: [KV]) -> (url: String, query: [KV]) {
        let (url, rest) =
            text.firstIndex(of: "?").map { (String(text[..<$0]), String(text[text.index(after: $0)...])) }
            ?? (text, "")
        var parsed = rest.split(separator: "&", omittingEmptySubsequences: true).map(pair)[...]
        var out: [KV] = []
        for row in query {
            if !row.enabled || (row.name.isEmpty && row.value.isEmpty) {
                out.append(row)
            } else if let par = parsed.popFirst() {
                var res = row
                (res.name, res.value, res.bare) = par
                out.append(res)
            }
        }
        out += parsed.map { KV(name: $0.0, value: $0.1, bare: $0.2) }
        return (url, out)
    }

    private static func pair(_ str: Substring) -> (String, String, Bool) {
        guard let i = str.firstIndex(of: "=") else { return (String(str), "", true) }
        return (String(str[..<i]), String(str[str.index(after: i)...]), false)
    }
}

/// Úsek textu se zvýrazněním proměnných (`{{…}}`; `\{{` je literál).
nonisolated struct VarToken: Hashable, Sendable {
    enum Kind: Sendable { case variable, dynamic }
    let range: NSRange
    let name: String
    let kind: Kind
}

nonisolated extension VarToken {
    /// Tokeny proměnných v textu (rozsahy v UTF-16 pro AppKit).
    static func scan(_ str: String) -> [VarToken] {
        guard str.contains("{{") else { return [] }
        let urlVal = Array(str.utf16)
        let open: UInt16 = 0x7B
        let close: UInt16 = 0x7D
        let slash: UInt16 = 0x5C
        var out: [VarToken] = []
        var i = 0
        while i + 1 < urlVal.count {
            guard urlVal[i] == open, urlVal[i + 1] == open else {
                i += 1
                continue
            }
            if i > 0, urlVal[i - 1] == slash {
                i += 2
                continue
            }
            var j = i + 2
            while j + 1 < urlVal.count, !(urlVal[j] == close && urlVal[j + 1] == close), urlVal[j] != open { j += 1 }
            guard j + 1 < urlVal.count, urlVal[j] == close, urlVal[j + 1] == close else {
                i = j
                continue
            }
            let name = String(utf16CodeUnits: Array(urlVal[(i + 2)..<j]), count: j - i - 2)
                .trimmingCharacters(in: .whitespaces)
            out.append(
                VarToken(
                    range: NSRange(location: i, length: j + 2 - i), name: name,
                    kind: name.hasPrefix("$") ? .dynamic : .variable))
            i = j + 2
        }
        return out
    }
}

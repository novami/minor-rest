import Foundation

/// Jazyk zvýraznění v `CodeTextView`.
public enum SyntaxLang: String, Sendable {
    case json, xml, html, text

    /// Jazyk raw těla (`nil` = typ bez textového editoru).
    public init?(bodyType: String) {
        switch bodyType {
        case BodyType.json: self = .json
        case BodyType.xml: self = .xml
        case BodyType.html: self = .html
        case BodyType.text: self = .text
        default: return nil
        }
    }
}

/// Zvýrazněný úsek (rozsah v UTF-16 jako `NSString`).
public struct SyntaxToken: Equatable, Sendable {
    public enum Kind: Sendable { case string, number, property, keyword, comment }
    public var range: NSRange
    public var kind: Kind

    public init(_ location: Int, _ length: Int, _ kind: Kind) {
        range = NSRange(location: location, length: length)
        self.kind = kind
    }
}

/// Jednoduché lexery pro zvýraznění (bez stromu, tolerantní k rozepsanému textu). Tokeny seřazené podle pozice.
public enum Syntax {
    public static func tokens(_ text: String, _ lang: SyntaxLang) -> [SyntaxToken] {
        let s = Array(text.utf16)
        switch lang {
        case .json: return json(s)
        case .xml, .html: return markup(s)
        case .text: return []
        }
    }

    @inline(__always) private static func ch(_ c: Unicode.Scalar) -> UInt16 { UInt16(c.value) }

    private static func isSpace(_ c: UInt16) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D }
    private static func isWord(_ c: UInt16) -> Bool {
        (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F
    }

    // MARK: JSON

    private static func json(_ s: [UInt16]) -> [SyntaxToken] {
        var out: [SyntaxToken] = []
        var i = 0
        let n = s.count
        while i < n {
            let c = s[i]
            if c == ch("\"") {
                let start = i
                i += 1
                while i < n, s[i] != ch("\""), s[i] != 0x0A {
                    i += s[i] == ch("\\") ? 2 : 1
                }
                if i < n, s[i] == ch("\"") { i += 1 }
                i = min(i, n)
                var j = i
                while j < n, isSpace(s[j]) { j += 1 }
                out.append(SyntaxToken(start, i - start, j < n && s[j] == ch(":") ? .property : .string))
            } else if c == ch("-") || (c >= 0x30 && c <= 0x39) {
                let start = i
                i += 1
                while i < n, isWord(s[i]) || s[i] == ch(".") || s[i] == ch("+") || s[i] == ch("-") { i += 1 }
                out.append(SyntaxToken(start, i - start, .number))
            } else if isWord(c) {
                let start = i
                while i < n, isWord(s[i]) { i += 1 }
                let word = String(utf16CodeUnits: Array(s[start..<i]), count: i - start)
                if word == "true" || word == "false" || word == "null" {
                    out.append(SyntaxToken(start, i - start, .keyword))
                }
            } else {
                i += 1
            }
        }
        return out
    }

    // MARK: XML / HTML

    private static func markup(_ s: [UInt16]) -> [SyntaxToken] {
        var out: [SyntaxToken] = []
        var i = 0
        let n = s.count

        func starts(_ p: String, at k: Int) -> Bool {
            let u = Array(p.utf16)
            guard k + u.count <= n else { return false }
            return Array(s[k..<k + u.count]) == u
        }
        /// Konec úseku za ukončovacím `end` (nebo konec textu).
        func until(_ end: String, from k: Int) -> Int {
            var j = k
            while j < n, !starts(end, at: j) { j += 1 }
            return min(j + end.utf16.count, n)
        }

        while i < n {
            guard s[i] == ch("<") else { i += 1; continue }
            if starts("<!--", at: i) {
                let e = until("-->", from: i + 4)
                out.append(SyntaxToken(i, e - i, .comment)); i = e
            } else if starts("<![CDATA[", at: i) {
                let e = until("]]>", from: i + 9)
                out.append(SyntaxToken(i, e - i, .string)); i = e
            } else if starts("<?", at: i) || starts("<!", at: i) {
                let e = until(starts("<?", at: i) ? "?>" : ">", from: i + 2)
                out.append(SyntaxToken(i, e - i, .comment)); i = e
            } else {
                // <tag, </tag; jméno vč. `:`, `-`, `.`
                var j = i + 1
                if j < n, s[j] == ch("/") { j += 1 }
                let nameStart = j
                while j < n, isWord(s[j]) || s[j] == ch(":") || s[j] == ch("-") || s[j] == ch(".") { j += 1 }
                guard j > nameStart else { i += 1; continue }
                out.append(SyntaxToken(nameStart, j - nameStart, .keyword))
                // atributy až do `>`
                while j < n, s[j] != ch(">"), s[j] != ch("<") {
                    let c = s[j]
                    if c == ch("\"") || c == ch("'") {
                        let start = j
                        j += 1
                        while j < n, s[j] != c { j += 1 }
                        j = min(j + 1, n)
                        out.append(SyntaxToken(start, j - start, .string))
                    } else if isWord(c) {
                        let start = j
                        while j < n, isWord(s[j]) || s[j] == ch(":") || s[j] == ch("-") || s[j] == ch(".") { j += 1 }
                        out.append(SyntaxToken(start, j - start, .property))
                    } else {
                        j += 1
                    }
                }
                i = j
            }
        }
        return out
    }
}

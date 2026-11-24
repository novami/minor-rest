import Foundation

/// Jazyk zvýraznění v `CodeTextView`.
nonisolated enum SyntaxLang: String, Sendable {
    case json, xml, html, text, markdown, diff

    /// Jazyk raw těla (`nil` = typ bez textového editoru).
    init?(bodyType: String) {
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
nonisolated struct SyntaxToken: Equatable, Sendable {
    enum Kind: Sendable { case string, number, property, keyword, comment }
    var range: NSRange
    var kind: Kind

    init(_ location: Int, _ length: Int, _ kind: Kind) {
        range = NSRange(location: location, length: length)
        self.kind = kind
    }
}

/// Jednoduché lexery pro zvýraznění (bez stromu, tolerantní k rozepsanému textu). Tokeny seřazené podle pozice.
nonisolated enum Syntax {
    static func tokens(_ text: String, _ lang: SyntaxLang) -> [SyntaxToken] {
        let str = Array(text.utf16)
        switch lang {
        case .json: return json(str)
        case .xml, .html: return markup(str)
        case .markdown: return markdown(str)
        case .diff: return diff(str)
        case .text: return []
        }
    }

    /// `+ ` řádky = string (zelená), `- ` = keyword, `@@` = comment.
    private static func diff(_ str: [UInt16]) -> [SyntaxToken] {
        var out: [SyntaxToken] = []
        var i = 0
        while i < str.count {
            var j = i
            while j < str.count, str[j] != 0x0A { j += 1 }
            if j > i {
                let kind: SyntaxToken.Kind? =
                    str[i] == ch("+") ? .string : str[i] == ch("-") ? .keyword : str[i] == ch("@") ? .comment : nil
                if let kind { out.append(SyntaxToken(i, j - i, kind)) }
            }
            i = j + 1
        }
        return out
    }

    @inline(__always) private static func ch(_ cur: Unicode.Scalar) -> UInt16 { UInt16(cur.value) }

    private static func isSpace(_ cur: UInt16) -> Bool { cur == 0x20 || cur == 0x09 || cur == 0x0A || cur == 0x0D }
    private static func isWord(_ cur: UInt16) -> Bool {
        (cur >= 0x30 && cur <= 0x39) || (cur >= 0x41 && cur <= 0x5A) || (cur >= 0x61 && cur <= 0x7A) || cur == 0x5F
    }

    // MARK: JSON

    private static func json(_ str: [UInt16]) -> [SyntaxToken] {
        var out: [SyntaxToken] = []
        var i = 0
        let num = str.count
        while i < num {
            let cur = str[i]
            if cur == ch("\"") {
                let start = i
                i += 1
                while i < num, str[i] != ch("\""), str[i] != 0x0A {
                    i += str[i] == ch("\\") ? 2 : 1
                }
                if i < num, str[i] == ch("\"") { i += 1 }
                i = min(i, num)
                var j = i
                while j < num, isSpace(str[j]) { j += 1 }
                out.append(SyntaxToken(start, i - start, j < num && str[j] == ch(":") ? .property : .string))
            } else if cur == ch("-") || (cur >= 0x30 && cur <= 0x39) {
                let start = i
                i += 1
                while i < num, isWord(str[i]) || str[i] == ch(".") || str[i] == ch("+") || str[i] == ch("-") { i += 1 }
                out.append(SyntaxToken(start, i - start, .number))
            } else if isWord(cur) {
                let start = i
                while i < num, isWord(str[i]) { i += 1 }
                let word = String(utf16CodeUnits: Array(str[start..<i]), count: i - start)
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

    private static func markup(_ str: [UInt16]) -> [SyntaxToken] {
        var out: [SyntaxToken] = []
        var i = 0
        let num = str.count

        func starts(_ par: String, at key: Int) -> Bool {
            let url = Array(par.utf16)
            guard key + url.count <= num else { return false }
            return Array(str[key..<key + url.count]) == url
        }
        /// Konec úseku za ukončovacím `end` (nebo konec textu).
        func until(_ end: String, from key: Int) -> Int {
            var j = key
            while j < num, !starts(end, at: j) { j += 1 }
            return min(j + end.utf16.count, num)
        }

        while i < num {
            guard str[i] == ch("<") else {
                i += 1
                continue
            }
            if starts("<!--", at: i) {
                let elem = until("-->", from: i + 4)
                out.append(SyntaxToken(i, elem - i, .comment))
                i = elem
            } else if starts("<![CDATA[", at: i) {
                let elem = until("]]>", from: i + 9)
                out.append(SyntaxToken(i, elem - i, .string))
                i = elem
            } else if starts("<?", at: i) || starts("<!", at: i) {
                let elem = until(starts("<?", at: i) ? "?>" : ">", from: i + 2)
                out.append(SyntaxToken(i, elem - i, .comment))
                i = elem
            } else {
                // <tag, </tag; jméno vč. `:`, `-`, `.`
                var j = i + 1
                if j < num, str[j] == ch("/") { j += 1 }
                let nameStart = j
                while j < num, isWord(str[j]) || str[j] == ch(":") || str[j] == ch("-") || str[j] == ch(".") { j += 1 }
                guard j > nameStart else {
                    i += 1
                    continue
                }
                out.append(SyntaxToken(nameStart, j - nameStart, .keyword))
                // atributy až do `>`
                while j < num, str[j] != ch(">"), str[j] != ch("<") {
                    let cur = str[j]
                    if cur == ch("\"") || cur == ch("'") {
                        let start = j
                        j += 1
                        while j < num, str[j] != cur { j += 1 }
                        j = min(j + 1, num)
                        out.append(SyntaxToken(start, j - start, .string))
                    } else if isWord(cur) {
                        let start = j
                        while j < num, isWord(str[j]) || str[j] == ch(":") || str[j] == ch("-") || str[j] == ch(".") {
                            j += 1
                        }
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

    // MARK: Markdown

    /// Nadpis → keyword, blok/inline kód → string, značka seznamu → number, `(url)` odkazu → property, citace →
    /// comment.
    private static func markdown(_ str: [UInt16]) -> [SyntaxToken] {
        var out: [SyntaxToken] = []
        let num = str.count
        var i = 0
        var fence: Int?  // začátek otevřeného bloku ```
        while i < num {
            var elem = i
            while elem < num, str[elem] != 0x0A { elem += 1 }
            var key = i
            while key < elem, str[key] == 0x20 { key += 1 }
            let isFence = key + 3 <= elem && str[key] == ch("`") && str[key + 1] == ch("`") && str[key + 2] == ch("`")
            if let fn = fence {
                if isFence {
                    out.append(SyntaxToken(fn, elem - fn, .string))
                    fence = nil
                }
            } else if isFence {
                fence = i
            } else if key < elem, str[key] == ch("#") {
                out.append(SyntaxToken(i, elem - i, .keyword))
            } else if key < elem, str[key] == ch(">") {
                out.append(SyntaxToken(i, elem - i, .comment))
            } else {
                var j = key
                if j + 1 < elem, str[j] == ch("-") || str[j] == ch("*") || str[j] == ch("+"), str[j + 1] == 0x20 {
                    out.append(SyntaxToken(j, 1, .number))
                    j += 2
                } else {
                    while j < elem, str[j] >= 0x30, str[j] <= 0x39 { j += 1 }
                    if j > key, j + 1 < elem, str[j] == ch("."), str[j + 1] == 0x20 {
                        out.append(SyntaxToken(key, j + 1 - key, .number))
                        j += 2
                    } else {
                        j = key
                    }
                }
                inlineMarkdown(str, j, elem, &out)
            }
            i = elem + 1
        }
        if let fn = fence { out.append(SyntaxToken(fn, num - fn, .string)) }
        return out
    }

    private static func inlineMarkdown(_ str: [UInt16], _ from: Int, _ end: Int, _ out: inout [SyntaxToken]) {
        var j = from
        while j < end {
            if str[j] == ch("`") {
                var key = j + 1
                while key < end, str[key] != ch("`") { key += 1 }
                guard key < end else { return }
                out.append(SyntaxToken(j, key + 1 - j, .string))
                j = key + 1
            } else if str[j] == ch("]"), j + 1 < end, str[j + 1] == ch("(") {
                var key = j + 2
                while key < end, str[key] != ch(")") { key += 1 }
                guard key < end else { return }
                out.append(SyntaxToken(j + 1, key + 1 - (j + 1), .property))
                j = key + 1
            } else {
                j += 1
            }
        }
    }
}

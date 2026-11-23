import Foundation

/// Čísla v UI odpovědi: velikost B / kB / MB (1 kB = 1000 B), čas v ms do 1000, pak s.
public enum DisplayFormat {
    public static func bytes(_ n: Int64, locale: Locale) -> String {
        if n < 1000 { return "\(n) B" }
        let (v, unit) = n < 1_000_000 ? (Double(n) / 1000, "kB") : (Double(n) / 1_000_000, "MB")
        return v.formatted(.number.precision(.fractionLength(1)).locale(locale)) + " " + unit
    }

    public static func duration(ms: Double, locale: Locale) -> String {
        if ms < 999.5 { return "\(Int(ms.rounded())) ms" }
        return (ms / 1000).formatted(.number.precision(.fractionLength(2)).locale(locale)) + " s"
    }
}

/// Odsazení XML/HTML pro pohled Pretty (2 mezery). Prvek jen s textem zůstane na jednom řádku,
/// prázdný text mezi značkami se zahodí; obsah `script`/`style`/`pre`/`textarea` v HTML beze změny.
/// Neuzavřené HTML prvky (`<p>`) se uzavřou s nejbližší koncovou značkou nadřazeného prvku.
public enum MarkupFormatter {
    static let void: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
                                    "param", "source", "track", "wbr"]
    static let rawText: Set<String> = ["script", "style", "pre", "textarea"]

    enum Token: Equatable {
        case open(String, String)   // název, celý text značky
        case close(String, String)
        case single(String)         // samouzavírací, void, komentář, <?…?>, <!…>, CDATA
        case text(String)
    }

    public static func format(_ text: String, html: Bool) -> String {
        let tokens = tokenize(text, html: html)
        var out: [String] = []
        var stack: [String] = []
        func line(_ s: String) { out.append(String(repeating: "  ", count: stack.count) + s) }
        var i = 0
        while i < tokens.count {
            switch tokens[i] {
            case .open(let name, let raw):
                // <a>text</a> a <a></a> na jednom řádku
                if i + 1 < tokens.count, case .close(let n, let c) = tokens[i + 1], same(n, name, html) {
                    line(raw + c); i += 2; continue
                }
                if i + 2 < tokens.count, case .text(let t) = tokens[i + 1], case .close(let n, let c) = tokens[i + 2],
                   same(n, name, html), !t.contains("\n") || (html && rawText.contains(name.lowercased())) {
                    line(raw + (html && rawText.contains(name.lowercased()) ? t : t.trimmed) + c); i += 3; continue
                }
                line(raw)
                stack.append(name)
            case .close(let name, let raw):
                if let at = stack.lastIndex(where: { same($0, name, html) }) {
                    stack.removeSubrange(at...)
                }
                line(raw)
            case .single(let raw):
                line(raw)
            case .text(let t):
                let s = t.trimmed
                if !s.isEmpty {
                    let pad = String(repeating: "  ", count: stack.count)
                    out.append(contentsOf: s.split(separator: "\n", omittingEmptySubsequences: false)
                        .map { pad + $0.trimmingCharacters(in: .whitespaces) })
                }
            }
            i += 1
        }
        return out.joined(separator: "\n")
    }

    private static func same(_ a: String, _ b: String, _ html: Bool) -> Bool {
        html ? a.caseInsensitiveCompare(b) == .orderedSame : a == b
    }

    static func tokenize(_ text: String, html: Bool) -> [Token] {
        var tokens: [Token] = []
        let s = Array(text.unicodeScalars)
        var i = 0
        var textStart = 0
        func str(_ a: Int, _ b: Int) -> String { String(String.UnicodeScalarView(s[a..<b])) }
        func find(_ needle: String, from: Int) -> Int? {
            let n = Array(needle.unicodeScalars)
            var j = from
            while j + n.count <= s.count {
                if s[j..<j + n.count].elementsEqual(n) { return j }
                j += 1
            }
            return nil
        }
        func flushText(_ end: Int) {
            if end > textStart { tokens.append(.text(str(textStart, end))) }
        }
        while i < s.count {
            guard s[i] == "<", i + 1 < s.count else { i += 1; continue }
            let next = s[i + 1]
            var end: Int?
            if str(i, min(i + 4, s.count)) == "<!--" {
                end = find("-->", from: i + 4).map { $0 + 3 }
            } else if str(i, min(i + 9, s.count)) == "<![CDATA[" {
                end = find("]]>", from: i + 9).map { $0 + 3 }
            } else if next == "?" {
                end = find("?>", from: i + 2).map { $0 + 2 }
            } else if next == "!" || next == "/" || next.properties.isAlphabetic {
                end = tagEnd(s, from: i + 1)
            } else {
                i += 1; continue
            }
            guard let e = end else { break }   // neuzavřené = zbytek je text
            flushText(i)
            let raw = str(i, e)
            if next == "/" {
                tokens.append(.close(name(raw.dropFirst(2)), raw))
            } else if next == "!" || next == "?" || raw.hasSuffix("/>") {
                tokens.append(.single(raw))
            } else {
                let n = name(raw.dropFirst())
                if html, void.contains(n.lowercased()) {
                    tokens.append(.single(raw))
                } else {
                    tokens.append(.open(n, raw))
                    if html, rawText.contains(n.lowercased()), let c = closeTag(n, from: e) {
                        if c > e { tokens.append(.text(str(e, c))) }
                        i = c; textStart = c; continue
                    }
                }
            }
            i = e
            textStart = e
        }
        flushText(s.count)
        return tokens

        func closeTag(_ n: String, from: Int) -> Int? {
            var j = from
            while let k = find("</", from: j) {
                if str(k + 2, min(k + 2 + n.unicodeScalars.count, s.count)).lowercased() == n.lowercased() { return k }
                j = k + 2
            }
            return nil
        }
    }

    /// Konec značky za `>` mimo uvozovky.
    private static func tagEnd(_ s: [Unicode.Scalar], from: Int) -> Int? {
        var quote: Unicode.Scalar?
        var j = from
        while j < s.count {
            let c = s[j]
            if let q = quote {
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == ">" {
                return j + 1
            }
            j += 1
        }
        return nil
    }

    private static func name(_ s: Substring) -> String {
        String(s.prefix { !$0.isWhitespace && $0 != ">" && $0 != "/" })
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// HTML pro náhled: CSP zakáže síťové požadavky i skripty (inline styly a `data:` obrázky povolí).
/// Značka se vloží za `<!DOCTYPE …>`, aby stránka nepřešla do quirks režimu.
public enum HTMLPreview {
    public static let csp = #"<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:">"#

    public static func sandboxed(_ html: String) -> String {
        let lead = html.prefix { $0.isWhitespace }.count
        let rest = html.dropFirst(lead)
        if rest.prefix(9).lowercased() == "<!doctype", let end = rest.firstIndex(of: ">") {
            let i = rest.index(after: end)
            return String(html[..<i]) + csp + String(html[i...])
        }
        return csp + html
    }
}

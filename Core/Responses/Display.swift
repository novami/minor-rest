import Foundation

/// Čísla v UI odpovědi: velikost B / kB / MB (1 kB = 1000 B), čas v ms do 1000, pak s.
nonisolated enum DisplayFormat {
    static func bytes(_ num: Int64, locale: Locale) -> String {
        if num < 1000 { return "\(num) B" }
        let (val, unit) = num < 1_000_000 ? (Double(num) / 1000, "kB") : (Double(num) / 1_000_000, "MB")
        return val.formatted(.number.precision(.fractionLength(1)).locale(locale)) + " " + unit
    }

    static func duration(ms: Double, locale: Locale) -> String {
        if ms < 999.5 { return "\(Int(ms.rounded())) ms" }
        return (ms / 1000).formatted(.number.precision(.fractionLength(2)).locale(locale)) + " s"
    }
}

/// Odsazení XML/HTML pro pohled Pretty (2 mezery). Prvek jen s textem zůstane na jednom řádku,
/// prázdný text mezi značkami se zahodí; obsah `script`/`style`/`pre`/`textarea` v HTML beze změny.
/// Neuzavřené HTML prvky (`<p>`) se uzavřou s nejbližší koncovou značkou nadřazeného prvku.
nonisolated enum MarkupFormatter {
    static let void: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
        "param", "source", "track", "wbr"
    ]
    static let rawText: Set<String> = ["script", "style", "pre", "textarea"]

    enum Token: Equatable {
        case open(String, String)  // název, celý text značky
        case close(String, String)
        case single(String)  // samouzavírací, void, komentář, <?…?>, <!…>, CDATA
        case text(String)
    }

    static func format(_ text: String, html: Bool) -> String {
        let tokens = tokenize(text, html: html)
        var out: [String] = []
        var stack: [String] = []
        func line(_ strVal: String) { out.append(String(repeating: "  ", count: stack.count) + strVal) }
        var i = 0
        while i < tokens.count {
            switch tokens[i] {
            case .open(let name, let raw):
                // <a>text</a> a <a></a> na jednom řádku
                if i + 1 < tokens.count, case .close(let num, let cur) = tokens[i + 1], same(num, name, html) {
                    line(raw + cur)
                    i += 2
                    continue
                }
                if i + 2 < tokens.count, case .text(let txt) = tokens[i + 1],
                    case .close(let num, let cur) = tokens[i + 2],
                    same(num, name, html), !txt.contains("\n") || (html && rawText.contains(name.lowercased())) {
                    line(raw + (html && rawText.contains(name.lowercased()) ? txt : txt.trimmed) + cur)
                    i += 3
                    continue
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
            case .text(let txt):
                let strVal = txt.trimmed
                if !strVal.isEmpty {
                    let pad = String(repeating: "  ", count: stack.count)
                    out.append(
                        contentsOf: strVal.split(separator: "\n", omittingEmptySubsequences: false)
                            .map { pad + $0.trimmingCharacters(in: .whitespaces) })
                }
            }
            i += 1
        }
        return out.joined(separator: "\n")
    }

    private static func same(_ arg: String, _ buf: String, _ html: Bool) -> Bool {
        html ? arg.caseInsensitiveCompare(buf) == .orderedSame : arg == buf
    }

    static func tokenize(_ text: String, html: Bool) -> [Token] {
        var tokenizer = Tokenizer(text, html: html)
        return tokenizer.run()
    }

    fileprivate enum Scan {
        case notMarkup
        case unterminated
        case end(Int)
    }

    private struct Tokenizer {
        let scalars: [Unicode.Scalar]
        let html: Bool
        var tokens: [Token] = []
        var i = 0
        var textStart = 0

        init(_ text: String, html: Bool) {
            scalars = Array(text.unicodeScalars)
            self.html = html
        }

        mutating func run() -> [Token] {
            while i < scalars.count {
                guard scalars[i] == "<", i + 1 < scalars.count else {
                    i += 1
                    continue
                }
                let next = scalars[i + 1]
                switch scan(next) {
                case .notMarkup: i += 1
                case .unterminated:  // neuzavřené = zbytek je text
                    flushText(scalars.count)
                    return tokens
                case .end(let elem):
                    flushText(i)
                    consume(raw: str(i, elem), next: next, end: elem)
                }
            }
            flushText(scalars.count)
            return tokens
        }

        private func str(_ arg: Int, _ buf: Int) -> String { String(String.UnicodeScalarView(scalars[arg..<buf])) }

        private func find(_ needle: String, from: Int) -> Int? {
            let num = Array(needle.unicodeScalars)
            var j = from
            while j + num.count <= scalars.count {
                if scalars[j..<j + num.count].elementsEqual(num) { return j }
                j += 1
            }
            return nil
        }

        private mutating func flushText(_ end: Int) {
            if end > textStart { tokens.append(.text(str(textStart, end))) }
        }

        private func scan(_ next: Unicode.Scalar) -> Scan {
            let found: Int?
            if str(i, min(i + 4, scalars.count)) == "<!--" {
                found = find("-->", from: i + 4).map { $0 + 3 }
            } else if str(i, min(i + 9, scalars.count)) == "<![CDATA[" {
                found = find("]]>", from: i + 9).map { $0 + 3 }
            } else if next == "?" {
                found = find("?>", from: i + 2).map { $0 + 2 }
            } else if next == "!" || next == "/" || next.properties.isAlphabetic {
                found = MarkupFormatter.tagEnd(scalars, from: i + 1)
            } else {
                return .notMarkup
            }
            return found.map(Scan.end) ?? .unterminated
        }

        private mutating func consume(raw: String, next: Unicode.Scalar, end elem: Int) {
            defer {
                if i < elem { i = elem }
            }
            if next == "/" {
                tokens.append(.close(MarkupFormatter.name(raw.dropFirst(2)), raw))
            } else if next == "!" || next == "?" || raw.hasSuffix("/>") {
                tokens.append(.single(raw))
            } else {
                let num = MarkupFormatter.name(raw.dropFirst())
                if html, MarkupFormatter.void.contains(num.lowercased()) {
                    tokens.append(.single(raw))
                } else {
                    tokens.append(.open(num, raw))
                    if html, MarkupFormatter.rawText.contains(num.lowercased()), let cur = closeTag(num, from: elem) {
                        if cur > elem { tokens.append(.text(str(elem, cur))) }
                        i = cur
                        textStart = cur
                        return
                    }
                }
            }
            textStart = elem
        }

        private func closeTag(_ num: String, from: Int) -> Int? {
            var j = from
            while let key = find("</", from: j) {
                let closeEnd = min(key + 2 + num.unicodeScalars.count, scalars.count)
                if str(key + 2, closeEnd).lowercased() == num.lowercased() { return key }
                j = key + 2
            }
            return nil
        }
    }

    /// Konec značky za `>` mimo uvozovky.
    private static func tagEnd(_ strVal: [Unicode.Scalar], from: Int) -> Int? {
        var quote: Unicode.Scalar?
        var j = from
        while j < strVal.count {
            let cur = strVal[j]
            if let que = quote {
                if cur == que { quote = nil }
            } else if cur == "\"" || cur == "'" {
                quote = cur
            } else if cur == ">" {
                return j + 1
            }
            j += 1
        }
        return nil
    }

    private static func name(_ strVal: Substring) -> String {
        String(strVal.prefix { !$0.isWhitespace && $0 != ">" && $0 != "/" })
    }
}

nonisolated extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// HTML pro náhled: CSP zakáže síťové požadavky i skripty (inline styly a `data:` obrázky povolí).
/// Značka se vloží za `<!DOCTYPE …>`, aby stránka nepřešla do quirks režimu.
nonisolated enum HTMLPreview {
    static let csp =
        #"<meta http-equiv="Content-Security-Policy" "#
        + #"content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:">"#

    static func sandboxed(_ html: String) -> String {
        let lead = html.prefix { $0.isWhitespace }.count
        let rest = html.dropFirst(lead)
        if rest.prefix(9).lowercased() == "<!doctype", let end = rest.firstIndex(of: ">") {
            let i = rest.index(after: end)
            return String(html[..<i]) + csp + String(html[i...])
        }
        return csp + html
    }
}

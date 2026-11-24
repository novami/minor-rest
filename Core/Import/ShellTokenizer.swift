import Foundation

/// Shell tokeny: `'…'`, `"…"` (escape `\" \\ \$ \``), `$'…'` (ANSI-C), `\x` mimo uvozovky;
/// `\`+newline = spojení řádků.
nonisolated struct ShellTokenizer {
    private let str: [Character]
    private var i = 0
    private var cur = ""
    private var has = false
    private var out: [String] = []

    init(_ text: String) {
        str = Array(text.replacingOccurrences(of: "\\\r\n", with: " ").replacingOccurrences(of: "\\\n", with: " "))
    }

    mutating func run() throws(CoreError) -> [String] {
        while i < str.count {
            let curVal = str[i]
            switch curVal {
            case " ", "\t", "\n", "\r": endToken()
            case "'": try singleQuoted()
            case "\"": try doubleQuoted()
            case "$" where i + 1 < str.count && str[i + 1] == "'": try ansiC()
            case "\\":
                if i + 1 < str.count {
                    i += 1
                    cur.append(str[i])
                    has = true
                }
            default:
                cur.append(curVal)
                has = true
            }
            i += 1
        }
        if has, cur != " " { out.append(cur) }
        return out
    }

    private func unterminated() -> CoreError { CoreError(.curlInvalid, "quote") }

    private mutating func endToken() {
        // Samostatná mezera vzniká z `\`+newline slepeného jednořádkovým polem při vložení; zahodit.
        if has, cur != " " { out.append(cur) }
        cur = ""
        has = false
    }

    private mutating func singleQuoted() throws(CoreError) {
        i += 1
        while i < str.count, str[i] != "'" {
            cur.append(str[i])
            i += 1
        }
        guard i < str.count else { throw unterminated() }
        has = true
    }

    private mutating func doubleQuoted() throws(CoreError) {
        i += 1
        while i < str.count, str[i] != "\"" {
            if str[i] == "\\", i + 1 < str.count, "\"\\$`".contains(str[i + 1]) { i += 1 }
            cur.append(str[i])
            i += 1
        }
        guard i < str.count else { throw unterminated() }
        has = true
    }

    private mutating func ansiC() throws(CoreError) {
        i += 2
        while i < str.count, str[i] != "'" {
            if str[i] == "\\", i + 1 < str.count {
                i += 1
                ansiEscape()
            } else {
                cur.append(str[i])
            }
            i += 1
        }
        guard i < str.count else { throw unterminated() }
        has = true
    }

    /// Znak za `\` v `$'…'` (`i` ukazuje na něj).
    private mutating func ansiEscape() {
        switch str[i] {
        case "n": cur.append("\n")
        case "t": cur.append("\t")
        case "r": cur.append("\r")
        case "x", "u", "U":
            let num = str[i] == "x" ? 2 : str[i] == "u" ? 4 : 8
            let hex = String(str[(i + 1)..<min(i + 1 + num, str.count)])
            if let val = UInt32(hex, radix: 16), let sc = Unicode.Scalar(val) {
                cur.append(Character(sc))
                i += hex.count
            } else {
                cur.append(str[i])
            }
        default: cur.append(str[i])
        }
    }
}

import Foundation

/// Strom pro zápis YAML. Pořadí klíčů je dané pořadím položek.
public indirect enum YNode: Equatable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case map([YEntry])
    case seq([YNode])
}

public struct YEntry: Equatable, Sendable {
    public let key: String
    public let value: YNode
}

/// Stavitel mapy s vynecháváním prázdných hodnot (obdoba `omitempty`).
public struct YMap {
    public private(set) var entries: [YEntry] = []
    public init() {}

    public var node: YNode { .map(entries) }

    public mutating func add(_ key: String, _ value: String) { entries.append(YEntry(key: key, value: .string(value))) }
    public mutating func add(_ key: String, _ value: Int) { entries.append(YEntry(key: key, value: .int(value))) }
    public mutating func add(_ key: String, _ value: Bool) { entries.append(YEntry(key: key, value: .bool(value))) }
    public mutating func add(_ key: String, _ node: YNode) { entries.append(YEntry(key: key, value: node)) }

    public mutating func addIfNotEmpty(_ key: String, _ value: String) { if !value.isEmpty { add(key, value) } }
    public mutating func addIfTrue(_ key: String, _ value: Bool) { if value { add(key, value) } }
    public mutating func addIfPresent(_ key: String, _ value: String?) { if let value { add(key, value) } }
    public mutating func addIfPresent(_ key: String, _ value: Int?) { if let value { add(key, value) } }
    public mutating func addIfPresent(_ key: String, _ value: Bool?) { if let value { add(key, value) } }
    public mutating func addIfPresent<T: YAMLEncodable>(_ key: String, _ value: T?) { if let value { add(key, value.yaml) } }
    public mutating func addIfNotEmpty<T: YAMLEncodable>(_ key: String, _ list: [T]) {
        if !list.isEmpty { add(key, .seq(list.map(\.yaml))) }
    }
    public mutating func addIfNotEmpty(_ key: String, _ map: YMap) { if !map.entries.isEmpty { add(key, map.node) } }
}

/// Zápis YAML shodný s `gopkg.in/yaml.v3` (odsazení 2) – soubory z Go verze se při uložení nemění.
/// Volba stylu řetězce kopíruje yaml.v3 (`encode.go` stringv) a libyaml (`yaml_emitter_analyze_scalar`).
enum YAMLWriter {
    static func document(_ node: YNode) -> String {
        var out = ""
        switch node {
        case .map(let entries): writeMap(entries, indent: 0, into: &out)
        case .seq(let items): writeSeq(items, indent: 0, into: &out)
        default: out += scalar(node, indent: 0) + "\n"
        }
        return out
    }

    private static func writeMap(_ entries: [YEntry], indent: Int, firstInline: Bool = false, into out: inout String) {
        for (i, e) in entries.enumerated() {
            if !(firstInline && i == 0) { out += String(repeating: " ", count: indent) }
            out += e.key + ":"
            writeValue(e.value, indent: indent, into: &out)
        }
    }

    private static func writeSeq(_ items: [YNode], indent: Int, into out: inout String) {
        for item in items {
            out += String(repeating: " ", count: indent) + "-"
            switch item {
            case .map(let entries) where !entries.isEmpty:
                out += " "
                writeMap(entries, indent: indent + 2, firstInline: true, into: &out)
            case .seq(let inner) where !inner.isEmpty:
                out += "\n"
                writeSeq(inner, indent: indent + 2, into: &out)
            default:
                out += " " + scalar(item, indent: indent + 2) + "\n"
            }
        }
    }

    /// Hodnota za `klíč:` (včetně mezery / nového řádku).
    private static func writeValue(_ node: YNode, indent: Int, into out: inout String) {
        switch node {
        case .map(let entries) where !entries.isEmpty:
            out += "\n"
            writeMap(entries, indent: indent + 2, into: &out)
        case .seq(let items) where !items.isEmpty:
            out += "\n"
            writeSeq(items, indent: indent + 2, into: &out)
        default:
            out += " " + scalar(node, indent: indent + 2) + "\n"
        }
    }

    /// Skalár; víceřádkový blok má obsah odsazený o `indent` a nekončí novým řádkem.
    private static func scalar(_ node: YNode, indent: Int) -> String {
        switch node {
        case .int(let v): return String(v)
        case .bool(let v): return v ? "true" : "false"
        case .map: return "{}"
        case .seq: return "[]"
        case .string(let s): return string(s, indent: indent)
        }
    }

    static func string(_ s: String, indent: Int) -> String {
        let a = Analysis(s)
        if !resolvesToString(s) { return doubleQuoted(s) }
        if s.contains("\n") {
            return a.blockAllowed ? literal(s, indent: indent) : doubleQuoted(s)
        }
        if a.blockPlainAllowed { return s }
        if a.singleQuotedAllowed { return "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }
        return doubleQuoted(s)
    }

    // MARK: - Rozpoznání typu (yaml.v3 resolve)

    private static let oldBools: Set<String> = ["y", "Y", "yes", "Yes", "YES", "n", "N", "no", "No", "NO",
                                                "on", "On", "ON", "off", "Off", "OFF"]
    private static let special: Set<String> = ["", "~", "null", "Null", "NULL", "true", "True", "TRUE",
                                               "false", "False", "FALSE", ".inf", ".Inf", ".INF", "+.inf", "+.Inf",
                                               "+.INF", "-.inf", "-.Inf", "-.INF", ".nan", ".NaN", ".NAN", "<<"]
    private static var intRegex: Regex<(Substring, Substring)> { /^[-+]?(0[xX][0-9a-fA-F]+|0[oO][0-7]+|0[bB][01]+|[0-9]+)$/ }
    private static var floatRegex: Regex<(Substring, Substring, Substring?, Substring?)> { /^[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?$/ }
    private static var base60Regex: Regex<Substring> { /^[-+]?[0-9][0-9_]*(?::[0-5]?[0-9])+(?:\.[0-9_]*)?$/ }
    private static var timestampRegex: Regex<Substring> {
        /^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}(?:(?:[Tt][0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}(?:\.[0-9]+)?(?:Z|[-+][0-9]{2}:[0-9]{2}))|(?: [0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}(?:\.[0-9]+)?))?$/ }

    /// Zda by plain zápis řetězce zůstal řetězcem (jinak yaml.v3 použije dvojité uvozovky).
    static func resolvesToString(_ s: String) -> Bool {
        if special.contains(s) || oldBools.contains(s) { return false }
        guard let first = s.first, "+-.0123456789".contains(first) else { return true }
        let plain = s.replacingOccurrences(of: "_", with: "")
        if plain.wholeMatch(of: intRegex) != nil || plain.wholeMatch(of: floatRegex) != nil { return false }
        if s.wholeMatch(of: base60Regex) != nil || s.wholeMatch(of: timestampRegex) != nil { return false }
        return true
    }

    // MARK: - Styly zápisu

    private static func literal(_ s: String, indent: Int) -> String {
        let scalars = Array(s.unicodeScalars)
        var header = "|"
        if let first = scalars.first, first == " " || first == "\n" { header += "2" }
        if scalars.last != "\n" {
            header += "-"
        } else if scalars.count == 1 || scalars[scalars.count - 2] == "\n" {
            header += "+"
        }
        var body = s
        if body.hasSuffix("\n") { body.removeLast() }
        let pad = String(repeating: " ", count: indent)
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        return header + lines.map { $0.isEmpty ? "\n" : "\n" + pad + $0 }.joined()
    }

    private static func doubleQuoted(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\0": out += "\\0"
            case "\u{07}": out += "\\a"
            case "\u{08}": out += "\\b"
            case "\t": out += "\\t"
            case "\n": out += "\\n"
            case "\u{0B}": out += "\\v"
            case "\u{0C}": out += "\\f"
            case "\r": out += "\\r"
            case "\u{1B}": out += "\\e"
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{85}": out += "\\N"
            case "\u{A0}" where !isPrintable(c): out += "\\_"
            case "\u{2028}": out += "\\L"
            case "\u{2029}": out += "\\P"
            default:
                if isPrintable(c) && c != "\u{FEFF}" {
                    out.unicodeScalars.append(c)
                } else if c.value <= 0xFF {
                    out += String(format: "\\x%02X", c.value)
                } else if c.value <= 0xFFFF {
                    out += String(format: "\\u%04X", c.value)
                } else {
                    out += String(format: "\\U%08X", c.value)
                }
            }
        }
        return out + "\""
    }

    /// libyaml `is_printable` (bez 4bajtových znaků – ty se escapují).
    static func isPrintable(_ c: Unicode.Scalar) -> Bool {
        let v = c.value
        return v == 0x0A || (0x20...0x7E).contains(v) || (0xA0...0xD7FF).contains(v)
            || ((0xE000...0xFFFD).contains(v) && v != 0xFEFF)
    }

    /// Rozbor řetězce dle libyaml `yaml_emitter_analyze_scalar` (verze z yaml.v3: tabulátor povolí jen blok).
    struct Analysis {
        var blockPlainAllowed = true
        var singleQuotedAllowed = true
        var blockAllowed = true

        init(_ s: String) {
            let chars = Array(s.unicodeScalars)
            if chars.isEmpty {
                blockAllowed = false
                return
            }
            var blockIndicators = s.hasPrefix("---") || s.hasPrefix("...")
            var leadingSpace = false, leadingBreak = false, trailingSpace = false, trailingBreak = false
            var breakSpace = false, spaceBreak = false, previousSpace = false, previousBreak = false
            var lineBreaks = false, specialCharacters = false, tabCharacters = false
            var precededByWhitespace = true
            func isBreak(_ c: Unicode.Scalar) -> Bool { c == "\n" || c == "\r" || c == "\u{85}" || c == "\u{2028}" || c == "\u{2029}" }
            func isBlankz(_ c: Unicode.Scalar?) -> Bool { c == nil || c == " " || c == "\t" || c == "\0" || isBreak(c!) }

            for (i, c) in chars.enumerated() {
                let next: Unicode.Scalar? = i + 1 < chars.count ? chars[i + 1] : nil
                let followedByWhitespace = isBlankz(next)
                if i == 0 {
                    switch c {
                    case "#", ",", "[", "]", "{", "}", "&", "*", "!", "|", ">", "'", "\"", "%", "@", "`":
                        blockIndicators = true
                    case "?", ":", "-":
                        if followedByWhitespace { blockIndicators = true }
                    default: break
                    }
                } else {
                    switch c {
                    case ":": if followedByWhitespace { blockIndicators = true }
                    case "#": if precededByWhitespace { blockIndicators = true }
                    default: break
                    }
                }
                if c == "\t" {
                    tabCharacters = true
                } else if !isPrintable(c) {
                    specialCharacters = true
                }
                if c == " " {
                    if i == 0 { leadingSpace = true }
                    if i == chars.count - 1 { trailingSpace = true }
                    if previousBreak { breakSpace = true }
                    previousSpace = true
                    previousBreak = false
                } else if isBreak(c) {
                    lineBreaks = true
                    if i == 0 { leadingBreak = true }
                    if i == chars.count - 1 { trailingBreak = true }
                    if previousSpace { spaceBreak = true }
                    previousBreak = true
                    previousSpace = false
                } else {
                    previousSpace = false
                    previousBreak = false
                }
                precededByWhitespace = isBlankz(c)
            }
            if leadingSpace || leadingBreak || trailingSpace || trailingBreak { blockPlainAllowed = false }
            if trailingSpace { blockAllowed = false }
            if breakSpace { blockPlainAllowed = false; singleQuotedAllowed = false }
            if spaceBreak || specialCharacters { blockPlainAllowed = false; singleQuotedAllowed = false; blockAllowed = false }
            if tabCharacters { blockPlainAllowed = false; singleQuotedAllowed = false }
            if lineBreaks { blockPlainAllowed = false }
            if blockIndicators { blockPlainAllowed = false }
        }
    }
}

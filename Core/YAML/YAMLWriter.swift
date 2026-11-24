import Foundation

/// Strom pro zápis YAML. Pořadí klíčů je dané pořadím položek.
nonisolated indirect enum YNode: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case map([YEntry])
    case seq([YNode])
}

nonisolated struct YEntry: Equatable, Sendable {
    let key: String
    let value: YNode
}

/// Stavitel mapy s vynecháváním prázdných hodnot (obdoba `omitempty`).
nonisolated struct YMap {
    private(set) var entries: [YEntry] = []
    init() {}

    var node: YNode { .map(entries) }

    /// Řetězce se zapisují v NFC.
    mutating func add(_ key: String, _ value: String) { entries.append(YEntry(key: key, value: .string(value.nfc))) }
    mutating func add(_ key: String, _ value: Int) { entries.append(YEntry(key: key, value: .int(value))) }
    mutating func add(_ key: String, _ value: Double) { entries.append(YEntry(key: key, value: .double(value))) }
    mutating func add(_ key: String, _ value: Bool) { entries.append(YEntry(key: key, value: .bool(value))) }
    mutating func add(_ key: String, _ node: YNode) { entries.append(YEntry(key: key, value: node)) }

    mutating func addIfNotEmpty(_ key: String, _ value: String) { if !value.isEmpty { add(key, value) } }
    mutating func addIfTrue(_ key: String, _ value: Bool) { if value { add(key, value) } }
    mutating func addIfPresent(_ key: String, _ value: String?) { if let value { add(key, value) } }
    mutating func addIfPresent(_ key: String, _ value: Int?) { if let value { add(key, value) } }
    mutating func addIfPresent(_ key: String, _ value: Bool?) { if let value { add(key, value) } }
    mutating func addIfPresent<T: YAMLEncodable>(_ key: String, _ value: T?) { if let value { add(key, value.yaml) } }
    mutating func addIfNotEmpty<T: YAMLEncodable>(_ key: String, _ list: [T]) {
        if !list.isEmpty { add(key, .seq(list.map(\.yaml))) }
    }
    mutating func addIfNotEmpty(_ key: String, _ map: YMap) { if !map.entries.isEmpty { add(key, map.node) } }
}

/// Zápis YAML shodný s `gopkg.in/yaml.v3` (odsazení 2) – soubory z Go verze se při uložení nemění.
/// Volba stylu řetězce kopíruje yaml.v3 (`encode.go` stringv) a libyaml (`yaml_emitter_analyze_scalar`).
nonisolated enum YAMLWriter {
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
        for (i, elem) in entries.enumerated() {
            if !(firstInline && i == 0) { out += String(repeating: " ", count: indent) }
            out += elem.key + ":"
            writeValue(elem.value, indent: indent, into: &out)
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
        case .int(let val): return String(val)
        case .double(let val): return val.isFinite ? String((val * 1000).rounded() / 1000) : "0"
        case .bool(let val): return val ? "true" : "false"
        case .map: return "{}"
        case .seq: return "[]"
        case .string(let str): return string(str, indent: indent)
        }
    }

    static func string(_ str: String, indent: Int) -> String {
        let arg = Analysis(str)
        if !resolvesToString(str) { return doubleQuoted(str) }
        if str.contains("\n") {
            return arg.blockAllowed ? literal(str, indent: indent) : doubleQuoted(str)
        }
        if arg.blockPlainAllowed { return str }
        if arg.singleQuotedAllowed { return "'" + str.replacingOccurrences(of: "'", with: "''") + "'" }
        return doubleQuoted(str)
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
    static func resolvesToString(_ str: String) -> Bool {
        if special.contains(str) || oldBools.contains(str) { return false }
        guard let first = str.first, "+-.0123456789".contains(first) else { return true }
        let plain = str.replacingOccurrences(of: "_", with: "")
        if plain.wholeMatch(of: intRegex) != nil || plain.wholeMatch(of: floatRegex) != nil { return false }
        if str.wholeMatch(of: base60Regex) != nil || str.wholeMatch(of: timestampRegex) != nil { return false }
        return true
    }

    // MARK: - Styly zápisu

    private static func literal(_ str: String, indent: Int) -> String {
        let scalars = Array(str.unicodeScalars)
        var header = "|"
        if let first = scalars.first, first == " " || first == "\n" { header += "2" }
        if scalars.last != "\n" {
            header += "-"
        } else if scalars.count == 1 || scalars[scalars.count - 2] == "\n" {
            header += "+"
        }
        var body = str
        if body.hasSuffix("\n") { body.removeLast() }
        let pad = String(repeating: " ", count: indent)
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        return header + lines.map { $0.isEmpty ? "\n" : "\n" + pad + $0 }.joined()
    }

    private static func doubleQuoted(_ str: String) -> String {
        var out = "\""
        for cur in str.unicodeScalars {
            switch cur {
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
            case "\u{A0}" where !isPrintable(cur): out += "\\_"
            case "\u{2028}": out += "\\L"
            case "\u{2029}": out += "\\P"
            default:
                if isPrintable(cur) && cur != "\u{FEFF}" {
                    out.unicodeScalars.append(cur)
                } else if cur.value <= 0xFF {
                    out += String(format: "\\x%02X", cur.value)
                } else if cur.value <= 0xFFFF {
                    out += String(format: "\\u%04X", cur.value)
                } else {
                    out += String(format: "\\U%08X", cur.value)
                }
            }
        }
        return out + "\""
    }

    /// libyaml `is_printable` (bez 4bajtových znaků – ty se escapují).
    static func isPrintable(_ cur: Unicode.Scalar) -> Bool {
        let val = cur.value
        return val == 0x0A || (0x20...0x7E).contains(val) || (0xA0...0xD7FF).contains(val)
            || ((0xE000...0xFFFD).contains(val) && val != 0xFEFF)
    }

    /// Rozbor řetězce dle libyaml `yaml_emitter_analyze_scalar` (verze z yaml.v3: tabulátor povolí jen blok).
    struct Analysis {
        var blockPlainAllowed = true
        var singleQuotedAllowed = true
        var blockAllowed = true

        init(_ str: String) {
            let chars = Array(str.unicodeScalars)
            if chars.isEmpty {
                blockAllowed = false
                return
            }
            var blockIndicators = str.hasPrefix("---") || str.hasPrefix("...")
            var leadingSpace = false, leadingBreak = false, trailingSpace = false, trailingBreak = false
            var breakSpace = false, spaceBreak = false, previousSpace = false, previousBreak = false
            var lineBreaks = false, specialCharacters = false, tabCharacters = false
            var precededByWhitespace = true
            func isBreak(_ cur: Unicode.Scalar) -> Bool { cur == "\n" || cur == "\r" || cur == "\u{85}" || cur == "\u{2028}" || cur == "\u{2029}" }
            func isBlankz(_ cur: Unicode.Scalar?) -> Bool { cur == nil || cur == " " || cur == "\t" || cur == "\0" || isBreak(cur!) }

            for (i, cur) in chars.enumerated() {
                let next: Unicode.Scalar? = i + 1 < chars.count ? chars[i + 1] : nil
                let followedByWhitespace = isBlankz(next)
                if i == 0 {
                    switch cur {
                    case "#", ",", "[", "]", "{", "}", "&", "*", "!", "|", ">", "'", "\"", "%", "@", "`":
                        blockIndicators = true
                    case "?", ":", "-":
                        if followedByWhitespace { blockIndicators = true }
                    default: break
                    }
                } else {
                    switch cur {
                    case ":": if followedByWhitespace { blockIndicators = true }
                    case "#": if precededByWhitespace { blockIndicators = true }
                    default: break
                    }
                }
                if cur == "\t" {
                    tabCharacters = true
                } else if !isPrintable(cur) {
                    specialCharacters = true
                }
                if cur == " " {
                    if i == 0 { leadingSpace = true }
                    if i == chars.count - 1 { trailingSpace = true }
                    if previousBreak { breakSpace = true }
                    previousSpace = true
                    previousBreak = false
                } else if isBreak(cur) {
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
                precededByWhitespace = isBlankz(cur)
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

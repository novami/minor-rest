import Foundation
import Yams

nonisolated struct SpecNode {
    var node: Node?
    init(_ numVal: Node?) { node = numVal }
    subscript(_ keyVal: String) -> SpecNode { SpecNode(node?.mapping != nil ? node?[keyVal] : nil) }
    var exists: Bool { node != nil }
    var str: String? { node?.scalar?.string }
    var bool: Bool? { node?.scalar != nil ? node?.bool : nil }
    var items: [SpecNode] { node?.sequence?.map { SpecNode($0) } ?? [] }
    var pairs: [(key: String, value: SpecNode)] {
        node?.mapping?.map { ($0.key.string ?? "", SpecNode($0.value)) } ?? []
    }
    var isMapping: Bool { node?.mapping != nil }
    var isSequence: Bool { node?.sequence != nil }
}

/// Ordered JSON pro ukázková těla.
nonisolated indirect enum SpecJSON {
    case null
    case bool(Bool)
    case num(String)
    case str(String)
    case arr([SpecJSON])
    case obj([(String, SpecJSON)])

    var compact: String {
        switch self {
        case .null: "null"
        case .bool(let buf): buf ? "true" : "false"
        case .num(let strVal): strVal
        case .str(let strVal): Self.quote(strVal)
        case .arr(let arg): "[" + arg.map(\.compact).joined(separator: ",") + "]"
        case .obj(let opt): "{" + opt.map { Self.quote($0.0) + ":" + $0.1.compact }.joined(separator: ",") + "}"
        }
    }

    static func quote(_ strVal: String) -> String {
        var out = "\""
        for urlVal in strVal.unicodeScalars {
            switch urlVal {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if urlVal.value < 0x20 {
                    out += String(format: "\\u%04x", urlVal.value)
                } else {
                    out.unicodeScalars.append(urlVal)
                }
            }
        }
        return out + "\""
    }

    /// Řetězec pro hodnotu parametru / pole formuláře.
    var text: String {
        switch self {
        case .str(let strVal): strVal
        case .num(let strVal): strVal
        case .bool(let buf): buf ? "true" : "false"
        case .null: ""
        default: compact
        }
    }
}

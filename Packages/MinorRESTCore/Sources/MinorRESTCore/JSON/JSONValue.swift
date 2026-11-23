import Foundation

/// Hodnota JSON se zachovaným pořadím klíčů a přesným textem čísel (JSONPath filtr).
public indirect enum JSONValue: Sendable {
    case null
    case bool(Bool)
    case number(Double, String)
    case string(String)
    case array([JSONValue])
    case object([Member])

    public struct Member: Sendable {
        public var key: String
        public var value: JSONValue
    }

    /// Nejvyšší hloubka vnoření při čtení (ochrana zásobníku).
    static let maxDepth = 128

    public static func parse(_ text: String) throws(CoreError) -> JSONValue {
        var p = Reader(Array(text.utf8))
        p.space()
        let v = try p.value(0)
        p.space()
        guard p.i == p.src.count else { throw p.fail("unexpected data after top-level value") }
        return v
    }

    /// Kompaktní zápis (odsazení dělá `JSONFormatter`).
    public var compact: String {
        var out: [UInt8] = []
        write(&out)
        return String(decoding: out, as: UTF8.self)
    }

    func write(_ out: inout [UInt8]) {
        switch self {
        case .null: out.append(contentsOf: "null".utf8)
        case .bool(let b): out.append(contentsOf: (b ? "true" : "false").utf8)
        case .number(_, let s): out.append(contentsOf: s.utf8)
        case .string(let s): Self.quote(s, &out)
        case .array(let a):
            out.append(UInt8(ascii: "["))
            for (i, v) in a.enumerated() {
                if i > 0 { out.append(UInt8(ascii: ",")) }
                v.write(&out)
            }
            out.append(UInt8(ascii: "]"))
        case .object(let m):
            out.append(UInt8(ascii: "{"))
            for (i, e) in m.enumerated() {
                if i > 0 { out.append(UInt8(ascii: ",")) }
                Self.quote(e.key, &out)
                out.append(UInt8(ascii: ":"))
                e.value.write(&out)
            }
            out.append(UInt8(ascii: "}"))
        }
    }

    static func quote(_ s: String, _ out: inout [UInt8]) {
        out.append(UInt8(ascii: "\""))
        for c in s.utf8 {
            switch c {
            case UInt8(ascii: "\""): out.append(contentsOf: "\\\"".utf8)
            case UInt8(ascii: "\\"): out.append(contentsOf: "\\\\".utf8)
            case 0x0A: out.append(contentsOf: "\\n".utf8)
            case 0x0D: out.append(contentsOf: "\\r".utf8)
            case 0x09: out.append(contentsOf: "\\t".utf8)
            case ..<0x20: out.append(contentsOf: String(format: "\\u%04x", c).utf8)
            default: out.append(c)
            }
        }
        out.append(UInt8(ascii: "\""))
    }

    private struct Reader {
        let src: [UInt8]
        var i = 0

        init(_ src: [UInt8]) { self.src = src }

        mutating func value(_ depth: Int) throws(CoreError) -> JSONValue {
            guard depth < JSONValue.maxDepth else { throw fail("nesting too deep") }
            guard i < src.count else { throw fail("unexpected end of JSON input") }
            switch src[i] {
            case UInt8(ascii: "{"):
                i += 1
                var m: [Member] = []
                space()
                if peek(UInt8(ascii: "}")) { i += 1; return .object(m) }
                while true {
                    space()
                    guard peek(UInt8(ascii: "\"")) else { throw fail("expected object key") }
                    let k = try string()
                    space()
                    guard peek(UInt8(ascii: ":")) else { throw fail("expected ':' after object key") }
                    i += 1
                    space()
                    m.append(Member(key: k, value: try value(depth + 1)))
                    space()
                    if peek(UInt8(ascii: ",")) { i += 1; continue }
                    if peek(UInt8(ascii: "}")) { i += 1; return .object(m) }
                    throw fail("expected ',' or '}' in object")
                }
            case UInt8(ascii: "["):
                i += 1
                var a: [JSONValue] = []
                space()
                if peek(UInt8(ascii: "]")) { i += 1; return .array(a) }
                while true {
                    space()
                    a.append(try value(depth + 1))
                    space()
                    if peek(UInt8(ascii: ",")) { i += 1; continue }
                    if peek(UInt8(ascii: "]")) { i += 1; return .array(a) }
                    throw fail("expected ',' or ']' in array")
                }
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try number()
            default:
                for (word, v) in [("true", JSONValue.bool(true)), ("false", .bool(false)), ("null", .null)]
                where src[i...].starts(with: word.utf8) {
                    i += word.utf8.count
                    return v
                }
                throw fail("invalid character")
            }
        }

        mutating func string() throws(CoreError) -> String {
            i += 1
            var buf: [UInt8] = []
            while i < src.count {
                let c = src[i]
                i += 1
                switch c {
                case UInt8(ascii: "\""): return String(decoding: buf, as: UTF8.self)
                case UInt8(ascii: "\\"):
                    guard i < src.count else { break }
                    let e = src[i]
                    i += 1
                    switch e {
                    case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): buf.append(e)
                    case UInt8(ascii: "b"): buf.append(0x08)
                    case UInt8(ascii: "f"): buf.append(0x0C)
                    case UInt8(ascii: "n"): buf.append(0x0A)
                    case UInt8(ascii: "r"): buf.append(0x0D)
                    case UInt8(ascii: "t"): buf.append(0x09)
                    case UInt8(ascii: "u"):
                        var u = try hex4()
                        if (0xD800..<0xDC00).contains(u), src[i...].starts(with: "\\u".utf8) {
                            let save = i
                            i += 2
                            let lo = try hex4()
                            if (0xDC00..<0xE000).contains(lo) { u = 0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00) } else { i = save }
                        }
                        buf.append(contentsOf: String(Unicode.Scalar(u).map(Character.init) ?? "\u{FFFD}").utf8)
                    default: throw fail("invalid escape in string")
                    }
                case ..<0x20: throw fail("control character in string")
                default: buf.append(c)
                }
            }
            throw fail("unexpected end of JSON input")
        }

        mutating func hex4() throws(CoreError) -> UInt32 {
            guard i + 4 <= src.count, let v = UInt32(String(decoding: src[i..<i + 4], as: UTF8.self), radix: 16) else {
                throw fail("invalid \\u escape")
            }
            i += 4
            return v
        }

        mutating func number() throws(CoreError) -> JSONValue {
            let start = i
            func digits(_ i: inout Int) -> Int {
                let s = i
                while i < src.count, (48...57).contains(src[i]) { i += 1 }
                return i - s
            }
            if peek(UInt8(ascii: "-")) { i += 1 }
            if peek(UInt8(ascii: "0")) { i += 1 } else if digits(&i) == 0 { throw fail("invalid number") }
            if peek(UInt8(ascii: ".")) {
                i += 1
                guard digits(&i) > 0 else { throw fail("invalid number") }
            }
            if i < src.count, src[i] | 0x20 == UInt8(ascii: "e") {
                i += 1
                if i < src.count, src[i] == UInt8(ascii: "+") || src[i] == UInt8(ascii: "-") { i += 1 }
                guard digits(&i) > 0 else { throw fail("invalid number") }
            }
            let text = String(decoding: src[start..<i], as: UTF8.self)
            return .number(Double(text) ?? .nan, text)
        }

        func peek(_ c: UInt8) -> Bool { i < src.count && src[i] == c }

        mutating func space() {
            while i < src.count, src[i] == 0x20 || src[i] == 0x09 || src[i] == 0x0A || src[i] == 0x0D { i += 1 }
        }

        func fail(_ message: String) -> CoreError {
            let line = src[..<min(i, src.count)].reduce(1) { $1 == 0x0A ? $0 + 1 : $0 }
            return CoreError(.jsonInvalid, "\(line): \(message)")
        }
    }
}

extension JSONValue: Equatable {
    /// Rovnost dle RFC 9535: čísla hodnotou, objekty bez ohledu na pořadí klíčů.
    public static func == (a: JSONValue, b: JSONValue) -> Bool {
        switch (a, b) {
        case (.null, .null): true
        case let (.bool(x), .bool(y)): x == y
        case let (.number(x, _), .number(y, _)): x == y
        case let (.string(x), .string(y)): x.unicodeScalars.elementsEqual(y.unicodeScalars)
        case let (.array(x), .array(y)): x == y
        case let (.object(x), .object(y)):
            x.count == y.count && x.allSatisfy { m in y.contains { $0.key.unicodeScalars.elementsEqual(m.key.unicodeScalars) && $0.value == m.value } }
        default: false
        }
    }
}

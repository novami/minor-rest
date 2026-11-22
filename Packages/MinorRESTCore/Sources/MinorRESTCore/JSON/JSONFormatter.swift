/// Formátování JSON s odsazením 2 mezery (výstup jako Go `json.Indent`): zachová přesný text čísel,
/// řetězců a pořadí klíčů. Proměnné `{{…}}` (i `\{{…}}`) jsou povolené jako hodnota či klíč mimo řetězec
/// a uvnitř řetězců zůstanou beze změny. Chyba → `JSON_INVALID: <řádek>: <popis>`.
public enum JSONFormatter {
    public static func format(_ text: String) throws -> String {
        var p = Parser(Array(text.utf8), output: true)
        try p.run()
        return String(decoding: p.out, as: UTF8.self)
    }

    /// Jen kontrola syntaxe (varování v editoru těla).
    public static func validate(_ text: String) -> CoreError? {
        var p = Parser(Array(text.utf8), output: false)
        do { try p.run() } catch let e as CoreError { return e } catch { return CoreError(.jsonInvalid, "\(error)") }
        return nil
    }

    private struct Parser {
        let src: [UInt8]
        let output: Bool
        var i = 0
        var out: [UInt8] = []
        var stack: [UInt8] = [] // `{` nebo `[`

        enum Expect { case value, valueOrClose, key, keyOrClose, colon, after }

        init(_ src: [UInt8], output: Bool) {
            self.src = src
            self.output = output
            out.reserveCapacity(output ? src.count + src.count / 4 : 0)
        }

        mutating func run() throws {
            var expect = Expect.value
            var pendingOpen = false // za `{`/`[` čeká nový řádek, pokud nepřijde hned zavření
            skipSpace()
            while true {
                skipSpace()
                guard i < src.count else {
                    if expect == .after && stack.isEmpty { return }
                    throw fail("unexpected end of JSON input")
                }
                let c = src[i]
                if expect == .after && stack.isEmpty {
                    throw fail("invalid character \(quoted(c)) after top-level value")
                }
                func newlineIfPending() {
                    if pendingOpen { newline(stack.count); pendingOpen = false }
                }
                switch expect {
                case .colon:
                    guard c == UInt8(ascii: ":") else { throw fail("invalid character \(quoted(c)) after object key") }
                    i += 1
                    emit(": ")
                    expect = .value
                case .after:
                    let top = stack.last!
                    if c == UInt8(ascii: ",") {
                        i += 1
                        emit(",")
                        newline(stack.count)
                        expect = top == UInt8(ascii: "{") ? .key : .value
                    } else if c == closing(top) {
                        try close(c)
                        expect = .after
                    } else {
                        throw fail("invalid character \(quoted(c)) after \(top == UInt8(ascii: "{") ? "object key:value pair" : "array element")")
                    }
                case .keyOrClose, .valueOrClose:
                    let top = stack.last!
                    if c == closing(top) {
                        i += 1
                        emitByte(c)
                        stack.removeLast()
                        pendingOpen = false
                        expect = .after
                        continue
                    }
                    newlineIfPending()
                    expect = expect == .keyOrClose ? .key : .value
                    continue
                case .key:
                    newlineIfPending()
                    if c == UInt8(ascii: "\"") {
                        try string()
                    } else if try !variable() {
                        throw fail("invalid character \(quoted(c)) looking for beginning of object key string")
                    }
                    expect = .colon
                case .value:
                    newlineIfPending()
                    if try variable() {
                        expect = .after
                        continue
                    }
                    switch c {
                    case UInt8(ascii: "{"), UInt8(ascii: "["):
                        i += 1
                        emitByte(c)
                        stack.append(c)
                        pendingOpen = true
                        expect = c == UInt8(ascii: "{") ? .keyOrClose : .valueOrClose
                    case UInt8(ascii: "\""):
                        try string()
                        expect = .after
                    case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
                        try number()
                        expect = .after
                    case UInt8(ascii: "t"), UInt8(ascii: "f"), UInt8(ascii: "n"):
                        try literal()
                        expect = .after
                    default:
                        throw fail("invalid character \(quoted(c)) looking for beginning of value")
                    }
                }
                if expect == .after && stack.isEmpty {
                    // za hodnotou nejvyšší úrovně smí být jen bílé znaky – zachovají se (jako Go)
                    let rest = src[i...]
                    guard rest.allSatisfy(isSpace) else {
                        skipSpace()
                        throw fail("invalid character \(quoted(src[i])) after top-level value")
                    }
                    if output { out.append(contentsOf: rest) }
                    return
                }
            }
        }

        // MARK: tokeny

        private mutating func close(_ c: UInt8) throws {
            i += 1
            stack.removeLast()
            newline(stack.count)
            emitByte(c)
        }

        private mutating func string() throws {
            let start = i
            i += 1
            while i < src.count {
                let c = src[i]
                if c == UInt8(ascii: "\"") {
                    i += 1
                    emit(src[start..<i])
                    return
                }
                if c < 0x20 { throw fail("invalid character \(quoted(c)) in string literal") }
                if c == UInt8(ascii: "\\") {
                    guard i + 1 < src.count else { break }
                    let e = src[i + 1]
                    if variableLength(at: i + 1) > 0 { // `\{{…}}` uvnitř řetězce
                        i += 1 + variableLength(at: i + 1)
                        continue
                    }
                    switch e {
                    case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"), UInt8(ascii: "b"),
                         UInt8(ascii: "f"), UInt8(ascii: "n"), UInt8(ascii: "r"), UInt8(ascii: "t"):
                        i += 2
                    case UInt8(ascii: "u"):
                        guard i + 5 < src.count, src[i + 2...i + 5].allSatisfy(isHex) else {
                            i += 2
                            throw fail("invalid character in \\u hexadecimal character escape")
                        }
                        i += 6
                    default:
                        i += 1
                        throw fail("invalid character \(quoted(e)) in string escape code")
                    }
                    continue
                }
                i += 1
            }
            throw fail("unexpected end of JSON input")
        }

        private mutating func number() throws {
            let start = i
            func digits() -> Int {
                let s = i
                while i < src.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(src[i]) { i += 1 }
                return i - s
            }
            if src[i] == UInt8(ascii: "-") { i += 1 }
            guard i < src.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(src[i]) else {
                throw fail("invalid character in numeric literal")
            }
            if src[i] == UInt8(ascii: "0") { i += 1 } else { _ = digits() }
            if i < src.count, src[i] == UInt8(ascii: ".") {
                i += 1
                guard digits() > 0 else { throw fail("invalid character after decimal point in numeric literal") }
            }
            if i < src.count, src[i] == UInt8(ascii: "e") || src[i] == UInt8(ascii: "E") {
                i += 1
                if i < src.count, src[i] == UInt8(ascii: "+") || src[i] == UInt8(ascii: "-") { i += 1 }
                guard digits() > 0 else { throw fail("invalid character in exponent of numeric literal") }
            }
            emit(src[start..<i])
        }

        private mutating func literal() throws {
            for word in ["true", "false", "null"] {
                let w = Array(word.utf8)
                if src.count - i >= w.count, Array(src[i..<i + w.count]) == w {
                    i += w.count
                    emit(w[...])
                    return
                }
            }
            throw fail("invalid character \(quoted(src[i])) in literal")
        }

        /// `{{…}}` nebo `\{{…}}` (bez vnořených závorek) na aktuální pozici → zkopíruje a vrátí true.
        private mutating func variable() throws -> Bool {
            let n = variableLength(at: i)
            guard n > 0 else { return false }
            emit(src[i..<i + n])
            i += n
            return true
        }

        private func variableLength(at start: Int) -> Int {
            var j = start
            if j < src.count, src[j] == UInt8(ascii: "\\") { j += 1 }
            guard j + 1 < src.count, src[j] == UInt8(ascii: "{"), src[j + 1] == UInt8(ascii: "{") else { return 0 }
            j += 2
            while j < src.count, src[j] != UInt8(ascii: "{"), src[j] != UInt8(ascii: "}") { j += 1 }
            guard j + 1 < src.count, src[j] == UInt8(ascii: "}"), src[j + 1] == UInt8(ascii: "}") else { return 0 }
            return j + 2 - start
        }

        // MARK: výstup a pomocné

        private mutating func skipSpace() {
            while i < src.count, isSpace(src[i]) { i += 1 }
        }

        private func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D }
        private func isHex(_ c: UInt8) -> Bool { (48...57).contains(c) || (65...70).contains(c) || (97...102).contains(c) }
        private func closing(_ open: UInt8) -> UInt8 { open == UInt8(ascii: "{") ? UInt8(ascii: "}") : UInt8(ascii: "]") }

        private mutating func emit(_ s: String) { if output { out.append(contentsOf: s.utf8) } }
        private mutating func emit(_ bytes: ArraySlice<UInt8>) { if output { out.append(contentsOf: bytes) } }
        private mutating func emitByte(_ c: UInt8) { if output { out.append(c) } }

        private mutating func newline(_ depth: Int) {
            guard output else { return }
            out.append(0x0A)
            out.append(contentsOf: repeatElement(0x20, count: depth * 2))
        }

        private func quoted(_ c: UInt8) -> String {
            c < 0x80 ? "'\(Character(Unicode.Scalar(c)))'" : String(format: "0x%02X", c)
        }

        /// Chyba s číslem řádku pozice `i`.
        private func fail(_ message: String) -> CoreError {
            let line = src[..<min(i, src.count)].reduce(1) { $0 + ($1 == 0x0A ? 1 : 0) }
            return CoreError(.jsonInvalid, "\(line): \(message)")
        }
    }
}

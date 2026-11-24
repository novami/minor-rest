/// Formátování JSON s odsazením 2 mezery (výstup jako Go `json.Indent`): zachová přesný text čísel,
/// řetězců a pořadí klíčů. Proměnné `{{…}}` (i `\{{…}}`) jsou povolené jako hodnota či klíč mimo řetězec
/// a uvnitř řetězců zůstanou beze změny. Chyba → `JSON_INVALID: <řádek>: <popis>`.
nonisolated enum JSONFormatter {
    static func format(_ text: String) throws -> String {
        var par = Parser(Array(text.utf8), output: true)
        try par.run()
        return String(decoding: par.out, as: UTF8.self)
    }

    /// Jen kontrola syntaxe (varování v editoru těla).
    static func validate(_ text: String) -> CoreError? {
        var par = Parser(Array(text.utf8), output: false)
        do { try par.run() } catch let elem as CoreError { return elem } catch { return CoreError(.jsonInvalid, "\(error)") }
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
                let cur = src[i]
                if expect == .after && stack.isEmpty {
                    throw fail("invalid character \(quoted(cur)) after top-level value")
                }
                func newlineIfPending() {
                    if pendingOpen { newline(stack.count); pendingOpen = false }
                }
                switch expect {
                case .colon:
                    guard cur == UInt8(ascii: ":") else { throw fail("invalid character \(quoted(cur)) after object key") }
                    i += 1
                    emit(": ")
                    expect = .value
                case .after:
                    let top = stack.last!
                    if cur == UInt8(ascii: ",") {
                        i += 1
                        emit(",")
                        newline(stack.count)
                        expect = top == UInt8(ascii: "{") ? .key : .value
                    } else if cur == closing(top) {
                        try close(cur)
                        expect = .after
                    } else {
                        throw fail("invalid character \(quoted(cur)) after \(top == UInt8(ascii: "{") ? "object key:value pair" : "array element")")
                    }
                case .keyOrClose, .valueOrClose:
                    let top = stack.last!
                    if cur == closing(top) {
                        i += 1
                        emitByte(cur)
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
                    if cur == UInt8(ascii: "\"") {
                        try string()
                    } else if try !variable() {
                        throw fail("invalid character \(quoted(cur)) looking for beginning of object key string")
                    }
                    expect = .colon
                case .value:
                    newlineIfPending()
                    if try variable() {
                        expect = .after
                        continue
                    }
                    switch cur {
                    case UInt8(ascii: "{"), UInt8(ascii: "["):
                        i += 1
                        emitByte(cur)
                        stack.append(cur)
                        pendingOpen = true
                        expect = cur == UInt8(ascii: "{") ? .keyOrClose : .valueOrClose
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
                        throw fail("invalid character \(quoted(cur)) looking for beginning of value")
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

        private mutating func close(_ cur: UInt8) throws {
            i += 1
            stack.removeLast()
            newline(stack.count)
            emitByte(cur)
        }

        private mutating func string() throws {
            let start = i
            i += 1
            while i < src.count {
                let cur = src[i]
                if cur == UInt8(ascii: "\"") {
                    i += 1
                    emit(src[start..<i])
                    return
                }
                if cur < 0x20 { throw fail("invalid character \(quoted(cur)) in string literal") }
                if cur == UInt8(ascii: "\\") {
                    guard i + 1 < src.count else { break }
                    let elem = src[i + 1]
                    if variableLength(at: i + 1) > 0 { // `\{{…}}` uvnitř řetězce
                        i += 1 + variableLength(at: i + 1)
                        continue
                    }
                    switch elem {
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
                        throw fail("invalid character \(quoted(elem)) in string escape code")
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
                let str = i
                while i < src.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(src[i]) { i += 1 }
                return i - str
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
                let wrd = Array(word.utf8)
                if src.count - i >= wrd.count, Array(src[i..<i + wrd.count]) == wrd {
                    i += wrd.count
                    emit(wrd[...])
                    return
                }
            }
            throw fail("invalid character \(quoted(src[i])) in literal")
        }

        /// `{{…}}` nebo `\{{…}}` (bez vnořených závorek) na aktuální pozici → zkopíruje a vrátí true.
        private mutating func variable() throws -> Bool {
            let num = variableLength(at: i)
            guard num > 0 else { return false }
            emit(src[i..<i + num])
            i += num
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

        private func isSpace(_ cur: UInt8) -> Bool { cur == 0x20 || cur == 0x09 || cur == 0x0A || cur == 0x0D }
        private func isHex(_ cur: UInt8) -> Bool { (48...57).contains(cur) || (65...70).contains(cur) || (97...102).contains(cur) }
        private func closing(_ open: UInt8) -> UInt8 { open == UInt8(ascii: "{") ? UInt8(ascii: "}") : UInt8(ascii: "]") }

        private mutating func emit(_ str: String) { if output { out.append(contentsOf: str.utf8) } }
        private mutating func emit(_ bytes: ArraySlice<UInt8>) { if output { out.append(contentsOf: bytes) } }
        private mutating func emitByte(_ cur: UInt8) { if output { out.append(cur) } }

        private mutating func newline(_ depth: Int) {
            guard output else { return }
            out.append(0x0A)
            out.append(contentsOf: repeatElement(0x20, count: depth * 2))
        }

        private func quoted(_ cur: UInt8) -> String {
            cur < 0x80 ? "'\(Character(Unicode.Scalar(cur)))'" : String(format: "0x%02X", cur)
        }

        /// Chyba s číslem řádku pozice `i`.
        private func fail(_ message: String) -> CoreError {
            let line = src[..<min(i, src.count)].reduce(1) { $0 + ($1 == 0x0A ? 1 : 0) }
            return CoreError(.jsonInvalid, "\(line): \(message)")
        }
    }
}

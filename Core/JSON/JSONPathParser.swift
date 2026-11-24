import Foundation

// MARK: - Parser

nonisolated struct JSONPathParser {
    let str: [Unicode.Scalar]
    var i = 0

    init(_ text: String) { str = Array(text.unicodeScalars) }

    mutating func parse() throws(CoreError) -> Query {
        guard peek("$") else { throw fail("query must start with '$'") }
        let que = try query()
        guard i == str.count else { throw fail("unexpected character '\(str[i])'") }
        return que
    }

    /// `$` nebo `@` a segmenty.
    mutating func query() throws(CoreError) -> Query {
        let absolute = str[i] == "$"
        i += 1
        var segs: [Segment] = []
        while true {
            let save = i
            space()
            if peek("..") {
                i += 2
                if peek("[") {
                    segs.append(Segment(descendant: true, selectors: try bracket()))
                } else if peek("*") {
                    i += 1
                    segs.append(Segment(descendant: true, selectors: [.wildcard]))
                } else {
                    segs.append(Segment(descendant: true, selectors: [.name(try shorthand())]))
                }
            } else if peek(".") {
                i += 1
                if peek("*") {
                    i += 1
                    segs.append(Segment(descendant: false, selectors: [.wildcard]))
                } else {
                    segs.append(Segment(descendant: false, selectors: [.name(try shorthand())]))
                }
            } else if peek("[") {
                segs.append(Segment(descendant: false, selectors: try bracket()))
            } else {
                i = save
                return Query(absolute: absolute, segments: segs)
            }
        }
    }

    mutating func shorthand() throws(CoreError) -> String {
        func first(_ curVal: Unicode.Scalar) -> Bool {
            ("a"..."z").contains(curVal) || ("A"..."Z").contains(curVal) || curVal == "_" || curVal.value >= 0x80
        }
        guard i < str.count, first(str[i]) else { throw fail("expected member name") }
        let start = i
        while i < str.count, first(str[i]) || ("0"..."9").contains(str[i]) { i += 1 }
        return String(String.UnicodeScalarView(str[start..<i]))
    }

    mutating func bracket() throws(CoreError) -> [JSONSelector] {
        i += 1
        var sels: [JSONSelector] = []
        while true {
            space()
            sels.append(try selector())
            space()
            if peek(",") {
                i += 1
                continue
            }
            guard peek("]") else { throw fail("expected ',' or ']'") }
            i += 1
            return sels
        }
    }

    mutating func selector() throws(CoreError) -> JSONSelector {
        guard i < str.count else { throw fail("unexpected end of query") }
        switch str[i] {
        case "'", "\"": return .name(try string())
        case "*":
            i += 1
            return .wildcard
        case "?":
            i += 1
            space()
            return .filter(try orExpr())
        default:
            let start = peek(":") ? nil : try int()
            space()
            guard peek(":") else {
                guard let start else { throw fail("expected selector") }
                return .index(start)
            }
            i += 1
            space()
            let end = peekInt() ? try int() : nil
            space()
            var step: Int?
            if peek(":") {
                i += 1
                space()
                step = peekInt() ? try int() : nil
            }
            return .slice(start, end, step)
        }
    }

    func peekInt() -> Bool { i < str.count && (str[i] == "-" || ("0"..."9").contains(str[i])) }

    /// Celé číslo I-JSON bez úvodních nul, `-0` neplatné.
    mutating func int() throws(CoreError) -> Int {
        let start = i
        if peek("-") { i += 1 }
        let ds = i
        while i < str.count, ("0"..."9").contains(str[i]) { i += 1 }
        let text = String(String.UnicodeScalarView(str[start..<i]))
        guard i > ds, !(str[ds] == "0" && (i - ds > 1 || start != ds)) else {
            i = start
            throw fail("invalid integer")
        }
        guard let numVal = Int(text), abs(numVal) <= 9_007_199_254_740_991 else {
            i = start
            throw fail("integer out of range")
        }
        return numVal
    }

    /// Znak za `\` v řetězci (`i` ukazuje na něj).
    private mutating func escape(
        quote que: Unicode.Scalar, into out: inout String.UnicodeScalarView
    ) throws(CoreError) {
        let elem = str[i]
        i += 1
        switch elem {
        case "b": out.append("\u{08}")
        case "f": out.append("\u{0C}")
        case "n": out.append("\n")
        case "r": out.append("\r")
        case "t": out.append("\t")
        case "/", "\\": out.append(elem)
        case "u": out.append(try unicodeEscape())
        default:
            guard elem == que else {
                i -= 1
                throw fail("invalid escape")
            }
            out.append(elem)
        }
    }

    /// `\uXXXX` (včetně náhradního páru); `i` ukazuje za `u`.
    private mutating func unicodeEscape() throws(CoreError) -> Unicode.Scalar {
        var url = try hex4()
        if (0xD800..<0xDC00).contains(url) {
            guard peek("\\u") else { throw fail("lone surrogate") }
            i += 2
            let lo = try hex4()
            guard (0xDC00..<0xE000).contains(lo) else { throw fail("lone surrogate") }
            url = 0x10000 + ((url - 0xD800) << 10) + (lo - 0xDC00)
        }
        guard let sc = Unicode.Scalar(url) else { throw fail("lone surrogate") }
        return sc
    }

    mutating func string() throws(CoreError) -> String {
        let que = str[i]
        i += 1
        var out = String.UnicodeScalarView()
        while i < str.count {
            let curVal = str[i]
            i += 1
            if curVal == que { return String(out) }
            if curVal == "\\" {
                guard i < str.count else { break }
                try escape(quote: que, into: &out)
            } else {
                guard curVal.value >= 0x20 else {
                    i -= 1
                    throw fail("control character in string")
                }
                out.append(curVal)
            }
        }
        throw fail("unterminated string")
    }

    mutating func hex4() throws(CoreError) -> UInt32 {
        guard i + 4 <= str.count, let val = UInt32(String(String.UnicodeScalarView(str[i..<i + 4])), radix: 16) else {
            throw fail("invalid \\u escape")
        }
        i += 4
        return val
    }

    // MARK: Pomocné

    func peek(_ txt: String) -> Bool {
        var j = i
        for curVal in txt.unicodeScalars {
            guard j < str.count, str[j] == curVal else { return false }
            j += 1
        }
        return true
    }

    mutating func space() {
        while i < str.count, str[i] == " " || str[i] == "\t" || str[i] == "\n" || str[i] == "\r" { i += 1 }
    }

    func fail(_ message: String, at pos: Int? = nil) -> CoreError {
        CoreError(.jsonPathInvalid, "\((pos ?? i) + 1): \(message)")
    }
}

// MARK: - Filtry

nonisolated extension JSONPathParser {
    mutating func orExpr() throws(CoreError) -> Expr {
        var parts = [try andExpr()]
        while true {
            space()
            guard peek("||") else { break }
            i += 2
            space()
            parts.append(try andExpr())
        }
        return parts.count == 1 ? parts[0] : .or(parts)
    }

    mutating func andExpr() throws(CoreError) -> Expr {
        var parts = [try basicExpr()]
        while true {
            space()
            guard peek("&&") else { break }
            i += 2
            space()
            parts.append(try basicExpr())
        }
        return parts.count == 1 ? parts[0] : .and(parts)
    }

    mutating func basicExpr() throws(CoreError) -> Expr {
        guard i < str.count else { throw fail("unexpected end of query") }
        if peek("!"), !peek("!=") {
            i += 1
            space()
            if peek("(") { return .not(try paren()) }
            let start = i
            let opt = try operand()
            return .not(try test(opt, at: start))
        }
        if peek("(") { return try paren() }
        let start = i
        let left = try operand()
        let save = i
        space()
        guard let op = compareOp() else {
            i = save
            return try test(left, at: start)
        }
        space()
        let rs = i
        let right = try operand()
        try comparable(left, at: start)
        try comparable(right, at: rs)
        return .compare(left, op, right)
    }

    mutating func paren() throws(CoreError) -> Expr {
        i += 1
        space()
        let elem = try orExpr()
        space()
        guard peek(")") else { throw fail("expected ')'") }
        i += 1
        return elem
    }

    mutating func compareOp() -> CompareOp? {
        for op in [CompareOp.eq, .ne, .le, .ge, .lt, .gt] where peek(op.rawValue) {
            i += op.rawValue.unicodeScalars.count
            return op
        }
        return nil
    }

    /// Operand jako test existence / logická funkce.
    func test(_ opt: Operand, at pos: Int) throws(CoreError) -> Expr {
        switch opt {
        case .query(let que): return .test(que)
        case .fn(let fnVal) where fnVal.result == .logical: return .logicalFn(fnVal)
        case .fn(let fnVal): throw fail("\(fnVal.kind.rawValue)() must be compared", at: pos)
        case .literal: throw fail("literal must be compared", at: pos)
        }
    }

    func comparable(_ opt: Operand, at pos: Int) throws(CoreError) {
        switch opt {
        case .query(let que) where !que.singular: throw fail("query in comparison must be singular", at: pos)
        case .fn(let fnVal) where fnVal.result == .logical:
            throw fail("\(fnVal.kind.rawValue)() cannot be compared", at: pos)
        default: break
        }
    }

    mutating func operand() throws(CoreError) -> Operand {
        guard i < str.count else { throw fail("unexpected end of query") }
        let curVal = str[i]
        if curVal == "@" || curVal == "$" { return .query(try query()) }
        if curVal == "'" || curVal == "\"" { return .literal(.string(try string())) }
        if curVal == "-" || ("0"..."9").contains(curVal) { return .literal(try number()) }
        let words: [(String, JSONValue)] = [("true", .bool(true)), ("false", .bool(false)), ("null", .null)]
        for (wrd, val) in words where peekWord(wrd) {
            i += wrd.unicodeScalars.count
            return .literal(val)
        }
        if ("a"..."z").contains(curVal) { return .fn(try function()) }
        throw fail("unexpected character '\(curVal)'")
    }

    func peekWord(_ wrd: String) -> Bool {
        let numVal = wrd.unicodeScalars.count
        guard peek(wrd) else { return false }
        return i + numVal >= str.count
            || !(("a"..."z").contains(str[i + numVal]) || ("0"..."9").contains(str[i + numVal])
                || str[i + numVal] == "_")
    }

    mutating func number() throws(CoreError) -> JSONValue {
        let start = i
        if peek("-") { i += 1 }
        let ds = i
        while i < str.count, ("0"..."9").contains(str[i]) { i += 1 }
        guard i > ds, !(str[ds] == "0" && i - ds > 1) else {
            i = start
            throw fail("invalid number")
        }
        if peek(".") {
            i += 1
            let fnVal = i
            while i < str.count, ("0"..."9").contains(str[i]) { i += 1 }
            guard i > fnVal else { throw fail("invalid number") }
        }
        if i < str.count, str[i] == "e" || str[i] == "E" {
            i += 1
            if peek("+") || peek("-") { i += 1 }
            let elem = i
            while i < str.count, ("0"..."9").contains(str[i]) { i += 1 }
            guard i > elem else { throw fail("invalid number") }
        }
        let text = String(String.UnicodeScalarView(str[start..<i]))
        return .number(Double(text) ?? .nan, text)
    }

    mutating func function() throws(CoreError) -> JSONFunction {
        let start = i
        while i < str.count, ("a"..."z").contains(str[i]) || ("0"..."9").contains(str[i]) || str[i] == "_" { i += 1 }
        let name = String(String.UnicodeScalarView(str[start..<i]))
        guard peek("(") else {
            i = start
            throw fail("unexpected '\(name)'")
        }
        guard let kind = JSONFunction.Kind(rawValue: name) else { throw fail("unknown function \(name)()", at: start) }
        i += 1
        var args: [(Operand, Int)] = []
        space()
        if !peek(")") {
            while true {
                space()
                let par = i
                args.append((try operand(), par))
                space()
                if peek(",") {
                    i += 1
                    continue
                }
                break
            }
        }
        guard peek(")") else { throw fail("expected ')'") }
        i += 1
        let want = kind == .match || kind == .search ? 2 : 1
        guard args.count == want else {
            throw fail("\(name)() takes \(want) argument\(want == 1 ? "" : "s")", at: start)
        }
        try checkArguments(kind, name: name, args)
        return JSONFunction(kind: kind, args: args.map(\.0))
    }

    private func checkArguments(_ kind: JSONFunction.Kind, name: String, _ args: [(Operand, Int)]) throws(CoreError) {
        for (arg, par) in args {
            switch (kind, arg) {
            case (.count, .query), (.value, .query): break
            case (.count, _), (.value, _): throw fail("\(name)() argument must be a query", at: par)
            case (_, .query(let que)) where !que.singular:
                throw fail("\(name)() argument must be a singular query", at: par)
            case (_, .fn(let fnVal)) where fnVal.result == .logical:
                throw fail("\(fnVal.kind.rawValue)() is not a value", at: par)
            default: break
            }
        }
    }
}

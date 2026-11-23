import Foundation

/// JSONPath dle RFC 9535 (selektory, filtry, funkce length/count/match/search/value).
/// Chyba výrazu → `JSONPATH_INVALID: <pozice>: <popis>` (pozice od 1, ve znacích).
public struct JSONPath: Sendable {
    let query: Query

    public init(_ expr: String) throws(CoreError) {
        var p = Parser(expr.trimmingCharacters(in: .whitespacesAndNewlines))
        query = try p.parse()
    }

    /// Hodnoty vybraných uzlů v pořadí dokumentu.
    public func select(_ root: JSONValue) -> [JSONValue] {
        let ev = Evaluator(root: root)
        return ev.run(query, current: root)
    }

    /// Výsledek filtru nad textem JSON jako odsazené pole shod.
    public static func filter(json: String, _ expr: String) throws(CoreError) -> String {
        let path = try JSONPath(expr)
        let root = try JSONValue.parse(json)
        let compact = JSONValue.array(path.select(root)).compact
        return (try? JSONFormatter.format(compact)) ?? compact
    }
}

// MARK: - AST

struct Query: Sendable {
    var absolute: Bool
    var segments: [Segment]

    var singular: Bool {
        segments.allSatisfy { s in
            guard !s.descendant, s.selectors.count == 1 else { return false }
            switch s.selectors[0] { case .name, .index: return true; default: return false }
        }
    }
}

struct Segment: Sendable {
    var descendant: Bool
    var selectors: [Selector]
}

enum Selector: Sendable {
    case name(String)
    case wildcard
    case index(Int)
    case slice(Int?, Int?, Int?)
    case filter(Expr)
}

indirect enum Expr: Sendable {
    case or([Expr])
    case and([Expr])
    case not(Expr)
    case test(Query)
    case logicalFn(Fn)
    case compare(Operand, CompareOp, Operand)
}

enum CompareOp: String, Sendable { case eq = "==", ne = "!=", lt = "<", le = "<=", gt = ">", ge = ">=" }

indirect enum Operand: Sendable {
    case literal(JSONValue)
    case query(Query) // jen singulární
    case fn(Fn) // jen ValueType
}

struct Fn: Sendable {
    enum Kind: String, Sendable { case length, count, match, search, value }
    enum ResultType { case value, logical }
    var kind: Kind
    var args: [Operand]

    var result: ResultType { kind == .match || kind == .search ? .logical : .value }
}

// MARK: - Parser

private struct Parser {
    let s: [Unicode.Scalar]
    var i = 0

    init(_ text: String) { s = Array(text.unicodeScalars) }

    mutating func parse() throws(CoreError) -> Query {
        guard peek("$") else { throw fail("query must start with '$'") }
        let q = try query()
        guard i == s.count else { throw fail("unexpected character '\(s[i])'") }
        return q
    }

    /// `$` nebo `@` a segmenty.
    mutating func query() throws(CoreError) -> Query {
        let absolute = s[i] == "$"
        i += 1
        var segs: [Segment] = []
        while true {
            let save = i
            space()
            if peek("..") {
                i += 2
                if peek("[") { segs.append(Segment(descendant: true, selectors: try bracket())) } else if peek("*") {
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
        func first(_ c: Unicode.Scalar) -> Bool {
            ("a"..."z").contains(c) || ("A"..."Z").contains(c) || c == "_" || c.value >= 0x80
        }
        guard i < s.count, first(s[i]) else { throw fail("expected member name") }
        let start = i
        while i < s.count, first(s[i]) || ("0"..."9").contains(s[i]) { i += 1 }
        return String(String.UnicodeScalarView(s[start..<i]))
    }

    mutating func bracket() throws(CoreError) -> [Selector] {
        i += 1
        var sels: [Selector] = []
        while true {
            space()
            sels.append(try selector())
            space()
            if peek(",") { i += 1; continue }
            guard peek("]") else { throw fail("expected ',' or ']'") }
            i += 1
            return sels
        }
    }

    mutating func selector() throws(CoreError) -> Selector {
        guard i < s.count else { throw fail("unexpected end of query") }
        switch s[i] {
        case "'", "\"": return .name(try string())
        case "*": i += 1; return .wildcard
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

    func peekInt() -> Bool { i < s.count && (s[i] == "-" || ("0"..."9").contains(s[i])) }

    /// Celé číslo I-JSON bez úvodních nul, `-0` neplatné.
    mutating func int() throws(CoreError) -> Int {
        let start = i
        if peek("-") { i += 1 }
        let ds = i
        while i < s.count, ("0"..."9").contains(s[i]) { i += 1 }
        let text = String(String.UnicodeScalarView(s[start..<i]))
        guard i > ds, !(s[ds] == "0" && (i - ds > 1 || start != ds)) else { i = start; throw fail("invalid integer") }
        guard let n = Int(text), abs(n) <= 9_007_199_254_740_991 else { i = start; throw fail("integer out of range") }
        return n
    }

    mutating func string() throws(CoreError) -> String {
        let q = s[i]
        i += 1
        var out = String.UnicodeScalarView()
        while i < s.count {
            let c = s[i]
            i += 1
            if c == q { return String(out) }
            if c == "\\" {
                guard i < s.count else { break }
                let e = s[i]
                i += 1
                switch e {
                case "b": out.append("\u{08}")
                case "f": out.append("\u{0C}")
                case "n": out.append("\n")
                case "r": out.append("\r")
                case "t": out.append("\t")
                case "/", "\\": out.append(e)
                case "u":
                    var u = try hex4()
                    if (0xD800..<0xDC00).contains(u) {
                        guard peek("\\u") else { throw fail("lone surrogate") }
                        i += 2
                        let lo = try hex4()
                        guard (0xDC00..<0xE000).contains(lo) else { throw fail("lone surrogate") }
                        u = 0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00)
                    }
                    guard let sc = Unicode.Scalar(u) else { throw fail("lone surrogate") }
                    out.append(sc)
                default:
                    guard e == q else { i -= 1; throw fail("invalid escape") }
                    out.append(e)
                }
            } else {
                guard c.value >= 0x20 else { i -= 1; throw fail("control character in string") }
                out.append(c)
            }
        }
        throw fail("unterminated string")
    }

    mutating func hex4() throws(CoreError) -> UInt32 {
        guard i + 4 <= s.count, let v = UInt32(String(String.UnicodeScalarView(s[i..<i + 4])), radix: 16) else {
            throw fail("invalid \\u escape")
        }
        i += 4
        return v
    }

    // MARK: Filtry

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
        guard i < s.count else { throw fail("unexpected end of query") }
        if peek("!"), !peek("!=") {
            i += 1
            space()
            if peek("(") { return .not(try paren()) }
            let start = i
            let o = try operand()
            return .not(try test(o, at: start))
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
        let e = try orExpr()
        space()
        guard peek(")") else { throw fail("expected ')'") }
        i += 1
        return e
    }

    mutating func compareOp() -> CompareOp? {
        for op in [CompareOp.eq, .ne, .le, .ge, .lt, .gt] where peek(op.rawValue) {
            i += op.rawValue.unicodeScalars.count
            return op
        }
        return nil
    }

    /// Operand jako test existence / logická funkce.
    func test(_ o: Operand, at pos: Int) throws(CoreError) -> Expr {
        switch o {
        case .query(let q): return .test(q)
        case .fn(let f) where f.result == .logical: return .logicalFn(f)
        case .fn(let f): throw fail("\(f.kind.rawValue)() must be compared", at: pos)
        case .literal: throw fail("literal must be compared", at: pos)
        }
    }

    func comparable(_ o: Operand, at pos: Int) throws(CoreError) {
        switch o {
        case .query(let q) where !q.singular: throw fail("query in comparison must be singular", at: pos)
        case .fn(let f) where f.result == .logical: throw fail("\(f.kind.rawValue)() cannot be compared", at: pos)
        default: break
        }
    }

    mutating func operand() throws(CoreError) -> Operand {
        guard i < s.count else { throw fail("unexpected end of query") }
        let c = s[i]
        if c == "@" || c == "$" { return .query(try query()) }
        if c == "'" || c == "\"" { return .literal(.string(try string())) }
        if c == "-" || ("0"..."9").contains(c) { return .literal(try number()) }
        for (w, v) in [("true", JSONValue.bool(true)), ("false", .bool(false)), ("null", .null)] where peekWord(w) {
            i += w.unicodeScalars.count
            return .literal(v)
        }
        if ("a"..."z").contains(c) { return .fn(try function()) }
        throw fail("unexpected character '\(c)'")
    }

    func peekWord(_ w: String) -> Bool {
        let n = w.unicodeScalars.count
        guard peek(w) else { return false }
        return i + n >= s.count || !(("a"..."z").contains(s[i + n]) || ("0"..."9").contains(s[i + n]) || s[i + n] == "_")
    }

    mutating func number() throws(CoreError) -> JSONValue {
        let start = i
        if peek("-") { i += 1 }
        let ds = i
        while i < s.count, ("0"..."9").contains(s[i]) { i += 1 }
        guard i > ds, !(s[ds] == "0" && i - ds > 1) else { i = start; throw fail("invalid number") }
        if peek(".") {
            i += 1
            let f = i
            while i < s.count, ("0"..."9").contains(s[i]) { i += 1 }
            guard i > f else { throw fail("invalid number") }
        }
        if i < s.count, s[i] == "e" || s[i] == "E" {
            i += 1
            if peek("+") || peek("-") { i += 1 }
            let e = i
            while i < s.count, ("0"..."9").contains(s[i]) { i += 1 }
            guard i > e else { throw fail("invalid number") }
        }
        let text = String(String.UnicodeScalarView(s[start..<i]))
        return .number(Double(text) ?? .nan, text)
    }

    mutating func function() throws(CoreError) -> Fn {
        let start = i
        while i < s.count, ("a"..."z").contains(s[i]) || ("0"..."9").contains(s[i]) || s[i] == "_" { i += 1 }
        let name = String(String.UnicodeScalarView(s[start..<i]))
        guard peek("(") else { i = start; throw fail("unexpected '\(name)'") }
        guard let kind = Fn.Kind(rawValue: name) else { throw fail("unknown function \(name)()", at: start) }
        i += 1
        var args: [(Operand, Int)] = []
        space()
        if !peek(")") {
            while true {
                space()
                let p = i
                args.append((try operand(), p))
                space()
                if peek(",") { i += 1; continue }
                break
            }
        }
        guard peek(")") else { throw fail("expected ')'") }
        i += 1
        let want = kind == .match || kind == .search ? 2 : 1
        guard args.count == want else { throw fail("\(name)() takes \(want) argument\(want == 1 ? "" : "s")", at: start) }
        for (a, p) in args {
            switch (kind, a) {
            case (.count, .query), (.value, .query): break
            case (.count, _), (.value, _): throw fail("\(name)() argument must be a query", at: p)
            case (_, .query(let q)) where !q.singular: throw fail("\(name)() argument must be a singular query", at: p)
            case (_, .fn(let f)) where f.result == .logical: throw fail("\(f.kind.rawValue)() is not a value", at: p)
            default: break
            }
        }
        return Fn(kind: kind, args: args.map(\.0))
    }

    // MARK: Pomocné

    func peek(_ t: String) -> Bool {
        var j = i
        for c in t.unicodeScalars {
            guard j < s.count, s[j] == c else { return false }
            j += 1
        }
        return true
    }

    mutating func space() {
        while i < s.count, s[i] == " " || s[i] == "\t" || s[i] == "\n" || s[i] == "\r" { i += 1 }
    }

    func fail(_ message: String, at pos: Int? = nil) -> CoreError {
        CoreError(.jsonPathInvalid, "\((pos ?? i) + 1): \(message)")
    }
}

// MARK: - Vyhodnocení

private final class Evaluator {
    let root: JSONValue
    var regexes: [String: NSRegularExpression?] = [:]

    init(root: JSONValue) { self.root = root }

    func run(_ q: Query, current: JSONValue) -> [JSONValue] {
        var nodes = [q.absolute ? root : current]
        for seg in q.segments {
            var next: [JSONValue] = []
            for n in nodes {
                if seg.descendant { descend(n) { self.apply(seg.selectors, $0, &next) } } else { apply(seg.selectors, n, &next) }
            }
            nodes = next
            if nodes.isEmpty { break }
        }
        return nodes
    }

    func descend(_ v: JSONValue, _ visit: (JSONValue) -> Void) {
        visit(v)
        switch v {
        case .array(let a): for c in a { descend(c, visit) }
        case .object(let m): for e in m { descend(e.value, visit) }
        default: break
        }
    }

    func apply(_ sels: [Selector], _ v: JSONValue, _ out: inout [JSONValue]) {
        for sel in sels {
            switch (sel, v) {
            case let (.name(k), .object(m)):
                if let e = m.first(where: { $0.key.unicodeScalars.elementsEqual(k.unicodeScalars) }) { out.append(e.value) }
            case (.wildcard, .array(let a)): out.append(contentsOf: a)
            case (.wildcard, .object(let m)): out.append(contentsOf: m.map(\.value))
            case let (.index(n), .array(a)):
                let j = n < 0 ? a.count + n : n
                if a.indices.contains(j) { out.append(a[j]) }
            case let (.slice(start, end, step), .array(a)):
                for j in Self.slice(a.count, start, end, step) { out.append(a[j]) }
            case let (.filter(e), .array(a)): out.append(contentsOf: a.filter { test(e, $0) })
            case let (.filter(e), .object(m)): out.append(contentsOf: m.map(\.value).filter { test(e, $0) })
            default: break
            }
        }
    }

    static func slice(_ len: Int, _ start: Int?, _ end: Int?, _ step: Int?) -> [Int] {
        let step = step ?? 1
        guard step != 0, len > 0 else { return [] }
        func norm(_ i: Int) -> Int { i >= 0 ? i : len + i }
        var r: [Int] = []
        if step > 0 {
            let lower = min(max(norm(start ?? 0), 0), len), upper = min(max(norm(end ?? len), 0), len)
            var i = lower
            while i < upper { r.append(i); i += step }
        } else {
            let upper = min(max(norm(start ?? len - 1), -1), len - 1)
            let lower = min(max(end.map(norm) ?? -1, -1), len - 1)
            var i = upper
            while lower < i { r.append(i); i += step }
        }
        return r
    }

    func test(_ e: Expr, _ cur: JSONValue) -> Bool {
        switch e {
        case .or(let es): es.contains { test($0, cur) }
        case .and(let es): es.allSatisfy { test($0, cur) }
        case .not(let x): !test(x, cur)
        case .test(let q): !run(q, current: cur).isEmpty
        case .logicalFn(let f): logical(f, cur)
        case let .compare(l, op, r): compare(value(l, cur), op, value(r, cur))
        }
    }

    /// Hodnota operandu; nil = Nothing.
    func value(_ o: Operand, _ cur: JSONValue) -> JSONValue? {
        switch o {
        case .literal(let v): return v
        case .query(let q): return run(q, current: cur).first
        case .fn(let f):
            switch f.kind {
            case .length:
                switch value(f.args[0], cur) {
                case .string(let s): return Self.num(s.unicodeScalars.count)
                case .array(let a): return Self.num(a.count)
                case .object(let m): return Self.num(m.count)
                default: return nil
                }
            case .count: return Self.num(nodes(f.args[0], cur).count)
            case .value:
                let n = nodes(f.args[0], cur)
                return n.count == 1 ? n[0] : nil
            case .match, .search: return nil
            }
        }
    }

    func nodes(_ o: Operand, _ cur: JSONValue) -> [JSONValue] {
        if case .query(let q) = o { return run(q, current: cur) }
        return []
    }

    func logical(_ f: Fn, _ cur: JSONValue) -> Bool {
        guard case .string(let s)? = value(f.args[0], cur), case .string(let p)? = value(f.args[1], cur) else { return false }
        let pattern = f.kind == .match ? "\\A(?:\(p))\\z" : p
        let re: NSRegularExpression?
        if let c = regexes[pattern] { re = c } else {
            re = try? NSRegularExpression(pattern: pattern)
            regexes[pattern] = re
        }
        guard let re else { return false }
        return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    func compare(_ a: JSONValue?, _ op: CompareOp, _ b: JSONValue?) -> Bool {
        switch op {
        case .eq: return a == b
        case .ne: return a != b
        case .lt: return less(a, b)
        case .le: return less(a, b) || a == b
        case .gt: return less(b, a)
        case .ge: return less(b, a) || a == b
        }
    }

    func less(_ a: JSONValue?, _ b: JSONValue?) -> Bool {
        switch (a, b) {
        case let (.number(x, _)?, .number(y, _)?): x < y
        case let (.string(x)?, .string(y)?): x.unicodeScalars.lexicographicallyPrecedes(y.unicodeScalars)
        default: false
        }
    }

    static func num(_ n: Int) -> JSONValue { .number(Double(n), String(n)) }
}

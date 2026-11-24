import Foundation

/// JSONPath dle RFC 9535 (selektory, filtry, funkce length/count/match/search/value).
/// Chyba výrazu → `JSONPATH_INVALID: <pozice>: <popis>` (pozice od 1, ve znacích).
nonisolated struct JSONPath: Sendable {
    let query: Query

    init(_ expr: String) throws(CoreError) {
        var par = JSONPathParser(expr.trimmingCharacters(in: .whitespacesAndNewlines))
        query = try par.parse()
    }

    /// Hodnoty vybraných uzlů v pořadí dokumentu.
    func select(_ root: JSONValue) -> [JSONValue] {
        let ev = JSONPathEvaluator(root: root)
        return ev.run(query, current: root)
    }

    /// Výsledek filtru nad textem JSON jako odsazené pole shod.
    static func filter(json: String, _ expr: String) throws(CoreError) -> String {
        let path = try JSONPath(expr)
        let root = try JSONValue.parse(json)
        let compact = JSONValue.array(path.select(root)).compact
        return (try? JSONFormatter.format(compact)) ?? compact
    }
}

// MARK: - AST

nonisolated struct Query: Sendable {
    var absolute: Bool
    var segments: [Segment]

    var singular: Bool {
        segments.allSatisfy { str in
            guard !str.descendant, str.selectors.count == 1 else { return false }
            switch str.selectors[0] {
            case .name, .index: return true
            default: return false
            }
        }
    }
}

nonisolated struct Segment: Sendable {
    var descendant: Bool
    var selectors: [JSONSelector]
}

nonisolated enum JSONSelector: Sendable {
    case name(String)
    case wildcard
    case index(Int)
    case slice(Int?, Int?, Int?)
    case filter(Expr)
}

nonisolated indirect enum Expr: Sendable {
    case or([Expr])
    case and([Expr])
    case not(Expr)
    case test(Query)
    case logicalFn(JSONFunction)
    case compare(Operand, CompareOp, Operand)
}

nonisolated enum CompareOp: String, Sendable {
    case eq = "=="
    case ne = "!="
    case lt = "<"
    case le = "<="
    case gt = ">"
    case ge = ">="
}

nonisolated indirect enum Operand: Sendable {
    case literal(JSONValue)
    case query(Query)  // jen singulární
    case fn(JSONFunction)  // jen ValueType
}

nonisolated struct JSONFunction: Sendable {
    enum Kind: String, Sendable { case length, count, match, search, value }
    enum ResultType { case value, logical }
    var kind: Kind
    var args: [Operand]

    var result: ResultType { kind == .match || kind == .search ? .logical : .value }
}

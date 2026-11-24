import Foundation

// MARK: - Vyhodnocení

nonisolated final class JSONPathEvaluator {
    let root: JSONValue
    var regexes: [String: NSRegularExpression?] = [:]

    init(root: JSONValue) { self.root = root }

    func run(_ que: Query, current: JSONValue) -> [JSONValue] {
        var nodes = [que.absolute ? root : current]
        for seg in que.segments {
            var next: [JSONValue] = []
            for numVal in nodes {
                if seg.descendant {
                    descend(numVal) { self.apply(seg.selectors, $0, &next) }
                } else {
                    apply(seg.selectors, numVal, &next)
                }
            }
            nodes = next
            if nodes.isEmpty { break }
        }
        return nodes
    }

    func descend(_ val: JSONValue, _ visit: (JSONValue) -> Void) {
        visit(val)
        switch val {
        case .array(let arg): for curVal in arg { descend(curVal, visit) }
        case .object(let map): for elem in map { descend(elem.value, visit) }
        default: break
        }
    }

    func apply(_ sels: [JSONSelector], _ val: JSONValue, _ out: inout [JSONValue]) {
        for sel in sels {
            switch (sel, val) {
            case (.name(let key), .object(let map)): out.append(contentsOf: Self.member(map, key))
            case (.wildcard, .array(let arg)): out.append(contentsOf: arg)
            case (.wildcard, .object(let map)): out.append(contentsOf: map.map(\.value))
            case (.index(let numVal), .array(let arg)): out.append(contentsOf: Self.element(arg, at: numVal))
            case (.slice(let start, let end, let step), .array(let arg)):
                for j in Self.slice(arg.count, start, end, step) { out.append(arg[j]) }
            case (.filter(let elem), .array(let arg)): out.append(contentsOf: arg.filter { test(elem, $0) })
            case (.filter(let elem), .object(let map)):
                out.append(contentsOf: map.map(\.value).filter { test(elem, $0) })
            default: break
            }
        }
    }

    private static func member(_ map: [JSONValue.Member], _ key: String) -> [JSONValue] {
        map.first { $0.key.unicodeScalars.elementsEqual(key.unicodeScalars) }.map { [$0.value] } ?? []
    }

    private static func element(_ arg: [JSONValue], at numVal: Int) -> [JSONValue] {
        let j = numVal < 0 ? arg.count + numVal : numVal
        return arg.indices.contains(j) ? [arg[j]] : []
    }

    static func slice(_ len: Int, _ start: Int?, _ end: Int?, _ step: Int?) -> [Int] {
        let step = step ?? 1
        guard step != 0, len > 0 else { return [] }
        func norm(_ i: Int) -> Int { i >= 0 ? i : len + i }
        var res: [Int] = []
        if step > 0 {
            let lower = min(max(norm(start ?? 0), 0), len)
            let upper = min(max(norm(end ?? len), 0), len)
            var i = lower
            while i < upper {
                res.append(i)
                i += step
            }
        } else {
            let upper = min(max(norm(start ?? len - 1), -1), len - 1)
            let lower = min(max(end.map(norm) ?? -1, -1), len - 1)
            var i = upper
            while lower < i {
                res.append(i)
                i += step
            }
        }
        return res
    }

    func test(_ elem: Expr, _ cur: JSONValue) -> Bool {
        switch elem {
        case .or(let es): es.contains { test($0, cur) }
        case .and(let es): es.allSatisfy { test($0, cur) }
        case .not(let x): !test(x, cur)
        case .test(let que): !run(que, current: cur).isEmpty
        case .logicalFn(let fnVal): logical(fnVal, cur)
        case .compare(let lst, let op, let res): compare(value(lst, cur), op, value(res, cur))
        }
    }

    /// Hodnota operandu; nil = Nothing.
    func value(_ opt: Operand, _ cur: JSONValue) -> JSONValue? {
        switch opt {
        case .literal(let val): return val
        case .query(let que): return run(que, current: cur).first
        case .fn(let fnVal): return functionValue(fnVal, cur)
        }
    }

    private func functionValue(_ fnVal: JSONFunction, _ cur: JSONValue) -> JSONValue? {
        switch fnVal.kind {
        case .length:
            switch value(fnVal.args[0], cur) {
            case .string(let str): return Self.num(str.unicodeScalars.count)
            case .array(let arg): return Self.num(arg.count)
            case .object(let map): return Self.num(map.count)
            default: return nil
            }
        case .count: return Self.num(nodes(fnVal.args[0], cur).count)
        case .value:
            let numVal = nodes(fnVal.args[0], cur)
            return numVal.count == 1 ? numVal[0] : nil
        case .match, .search: return nil
        }
    }

    func nodes(_ opt: Operand, _ cur: JSONValue) -> [JSONValue] {
        if case .query(let que) = opt { return run(que, current: cur) }
        return []
    }

    func logical(_ fnVal: JSONFunction, _ cur: JSONValue) -> Bool {
        guard case .string(let str)? = value(fnVal.args[0], cur), case .string(let par)? = value(fnVal.args[1], cur)
        else { return false }
        let pattern = fnVal.kind == .match ? "\\A(?:\(par))\\z" : par
        let re: NSRegularExpression?
        if let curVal = regexes[pattern] {
            re = curVal
        } else {
            re = try? NSRegularExpression(pattern: pattern)
            regexes[pattern] = re
        }
        guard let re else { return false }
        return re.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)) != nil
    }

    func compare(_ arg: JSONValue?, _ op: CompareOp, _ buf: JSONValue?) -> Bool {
        switch op {
        case .eq: return arg == buf
        case .ne: return arg != buf
        case .lt: return less(arg, buf)
        case .le: return less(arg, buf) || arg == buf
        case .gt: return less(buf, arg)
        case .ge: return less(buf, arg) || arg == buf
        }
    }

    func less(_ arg: JSONValue?, _ buf: JSONValue?) -> Bool {
        switch (arg, buf) {
        case (.number(let x, _)?, .number(let y, _)?): x < y
        case (.string(let x)?, .string(let y)?): x.unicodeScalars.lexicographicallyPrecedes(y.unicodeScalars)
        default: false
        }
    }

    static func num(_ numVal: Int) -> JSONValue { .number(Double(numVal), String(numVal)) }
}

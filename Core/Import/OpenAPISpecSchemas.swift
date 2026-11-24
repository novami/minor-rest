import Foundation
import Yams

nonisolated extension SpecParser {
    func json(_ numVal: SpecNode) -> SpecJSON {
        guard let node = numVal.node else { return .null }
        switch node {
        case .mapping: return .obj(numVal.pairs.map { ($0.key, json($0.value)) })
        case .sequence: return .arr(numVal.items.map(json))
        default:
            guard let strVal = node.scalar else { return .null }
            if strVal.style != .plain && strVal.style != .any { return .str(strVal.string) }
            if node.null != nil { return .null }
            if let buf = node.bool { return .bool(buf) }
            if node.int != nil || node.float != nil { return .num(strVal.string) }
            return .str(strVal.string)
        }
    }

    /// `example` → `default` → `enum[0]` → `const` přímo na uzlu.
    func direct(_ numVal: SpecNode) -> SpecJSON? {
        for keyVal in ["example", "x-example", "default", "const"] where numVal[keyVal].exists {
            return json(numVal[keyVal])
        }
        if let elem = numVal["examples"].items.first { return json(elem) }
        if let elem = numVal["enum"].items.first { return json(elem) }
        return nil
    }

    func sample(_ schema: SpecNode, depth: Int = 0, stack: [String] = []) -> SpecJSON? {
        guard depth <= maxDepth, let (strVal, stack) = followRefs(schema, stack) else { return nil }
        if let dat = direct(strVal) { return dat }
        if !strVal["allOf"].items.isEmpty { return mergedAllOf(strVal["allOf"].items, depth: depth, stack: stack) }
        for keyVal in ["oneOf", "anyOf"] {
            if let fn = strVal[keyVal].items.first { return sample(fn, depth: depth + 1, stack: stack) }
        }
        return sampleByType(strVal, depth: depth, stack: stack)
    }

    private func sampleByType(_ strVal: SpecNode, depth: Int, stack: [String]) -> SpecJSON? {
        switch schemaType(strVal) {
        case "object":
            var out: [(String, SpecJSON)] = []
            for (name, raw) in strVal["properties"].pairs {
                if deref(raw)["readOnly"].bool == true { continue }
                if let val = sample(raw, depth: depth + 1, stack: stack) { out.append((name, val)) }
            }
            return .obj(out)
        case "array":
            if let val = sample(strVal["items"], depth: depth + 1, stack: stack) { return .arr([val]) }
            return .arr([])
        case "integer", "number": return .num("0")
        case "boolean": return .bool(false)
        case "string": return .str(Self.stringSample(strVal["format"].str ?? ""))
        default: return nil
        }
    }

    /// Následuje `$ref` řetězec; cyklus nebo neznámý odkaz = `nil`.
    private func followRefs(_ schema: SpecNode, _ stack: [String]) -> (SpecNode, [String])? {
        var strVal = schema
        var stack = stack
        var guardCount = 0
        while let ref = strVal["$ref"].str {
            guardCount += 1
            guard guardCount < 20, !stack.contains(ref), let txt = lookup(ref) else { return nil }
            stack.append(ref)
            strVal = txt
        }
        return (strVal, stack)
    }

    private func mergedAllOf(_ parts: [SpecNode], depth: Int, stack: [String]) -> SpecJSON {
        var props: [(String, SpecJSON)] = []
        for sub in parts {
            guard case .obj(let opt)? = sample(sub, depth: depth + 1, stack: stack) else { continue }
            for (keyVal, val) in opt {
                if let i = props.firstIndex(where: { $0.0 == keyVal }) {
                    props[i].1 = val
                } else {
                    props.append((keyVal, val))
                }
            }
        }
        return .obj(props)
    }

    private func schemaType(_ strVal: SpecNode) -> String {
        var type = strVal["type"].str ?? ""
        if type.isEmpty, strVal["type"].isSequence {
            type = strVal["type"].items.compactMap(\.str).first { $0 != "null" } ?? ""
        }
        if type.isEmpty { type = strVal["properties"].exists ? "object" : (strVal["items"].exists ? "array" : "") }
        return type
    }

    private static func stringSample(_ format: String) -> String {
        switch format {
        case "date-time": "2024-01-01T00:00:00Z"
        case "date": "2024-01-01"
        case "uuid": "00000000-0000-0000-0000-000000000000"
        case "email": "user@example.com"
        case "uri", "url": "https://example.com"
        default: "string"
        }
    }

    func pretty(_ j: SpecJSON) -> String { (try? JSONFormatter.format(j.compact)) ?? j.compact }
}

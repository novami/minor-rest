import Foundation
import Yams

nonisolated extension SpecParser {
    // MARK: Operace

    /// Parametry cesty a operace; operace přepíše parametr se stejným `in` a názvem.
    private func mergedParameters(_ item: SpecNode, _ opNode: SpecNode) -> [SpecNode] {
        func key(_ par: SpecNode) -> String { (par["in"].str ?? "") + "|" + (par["name"].str ?? "") }
        var params = item["parameters"].items.map { deref($0) }
        for raw in opNode["parameters"].items {
            let par = deref(raw)
            if let i = params.firstIndex(where: { key($0) == key(par) }) { params[i] = par } else { params.append(par) }
        }
        return params
    }

    mutating func operation(_ method: String, _ rawPath: String, _ item: SpecNode, _ opNode: SpecNode) -> APIOperation {
        var op = APIOperation()
        op.method = method
        op.path = Self.colonPath(rawPath)
        op.tag = opNode["tags"].items.first?.str ?? ""
        op.summary = opNode["summary"].str ?? ""
        op.operationId = opNode["operationId"].str ?? ""
        op.description = opNode["description"].str ?? ""

        let params = mergedParameters(item, opNode)
        var declaredPath: [String: PathParam] = [:]
        var formParams: [SpecNode] = []
        var bodyParam: SpecNode?
        for par in params {
            let name = par["name"].str ?? ""
            let desc = par["description"].str ?? ""
            let value = paramValue(par)
            let row = KeyValue(name: name, value: value, enabled: par["required"].bool == true, description: desc)
            switch par["in"].str ?? "" {
            case "query": op.query.append(row)
            case "header": op.headers.append(row)
            case "path": declaredPath[name] = PathParam(name: name, value: value, description: desc)
            case "formData": formParams.append(par)
            case "body": bodyParam = par
            default: break
            }
        }
        op.pathParams = PathParams.names("{{baseUrl}}" + op.path).map { declaredPath[$0] ?? PathParam(name: $0) }

        if v2 {
            op.body = bodyV2(opNode, bodyParam, formParams)
        } else {
            op.body = bodyV3(deref(opNode["requestBody"]))
        }
        return op
    }

    static func colonPath(_ path: String) -> String {
        var out = ""
        var name: String?
        for ch in path {
            if ch == "{" {
                name = ""
            } else if ch == "}", let numVal = name {
                out += ":" + numVal
                name = nil
            } else if name != nil {
                name?.append(ch)
            } else {
                out.append(ch)
            }
        }
        if let numVal = name { out += "{" + numVal }
        return out
    }

    func paramValue(_ par: SpecNode) -> String {
        if let dat = direct(par) { return dat.text }
        if let ex = par["examples"].pairs.first, let val = Optional(deref(ex.value)["value"]), val.exists {
            return json(val).text
        }
        if let dat = direct(deref(par["schema"])) { return dat.text }
        if par["type"].str == "array", let dat = direct(par["items"]) { return dat.text }
        return ""
    }

    // MARK: Těla

    func bodyV3(_ rb: SpecNode) -> Body? {
        let content = rb["content"].pairs
        guard
            let pick = content.first(where: { $0.key == "application/json" })
                ?? content.first(where: { $0.key.contains("json") }) ?? content.first
        else { return nil }
        let media = pick.value
        let schema = media["schema"]
        let ct = pick.key.lowercased()

        func example() -> SpecJSON? {
            if media["example"].exists { return json(media["example"]) }
            if let ex = media["examples"].pairs.first {
                let val = deref(ex.value)["value"]
                if val.exists { return json(val) }
            }
            return nil
        }

        if ct.contains("json") {
            let j = example() ?? sample(schema) ?? .obj([])
            return Body(type: BodyType.json, raw: pretty(j))
        }
        if ct.contains("x-www-form-urlencoded") || ct.contains("multipart") {
            return formBody(schema, multipart: ct.contains("multipart"))
        }
        let raw = example().map(\.text) ?? ""
        if ct.contains("xml") { return Body(type: BodyType.xml, raw: raw) }
        if ct.contains("html") { return Body(type: BodyType.html, raw: raw) }
        if ct.hasPrefix("text/") { return Body(type: BodyType.text, raw: raw) }
        return Body(type: BodyType.binary)
    }

    func formBody(_ schema: SpecNode, multipart: Bool) -> Body {
        var strVal = deref(schema)
        if !strVal["allOf"].items.isEmpty {
            strVal = strVal["allOf"].items.map(deref).first { $0["properties"].exists } ?? strVal
        }
        var kv: [KeyValue] = []
        var parts: [MultipartPart] = []
        for (name, raw) in strVal["properties"].pairs {
            let par = deref(raw)
            let isFile = par["format"].str == "binary" || par["type"].str == "file"
            let val = isFile ? "" : (sample(par, stack: []) ?? .str("")).text
            kv.append(KeyValue(name: name, value: val))
            parts.append(MultipartPart(name: name, kind: isFile ? "file" : "text", value: val))
        }
        return multipart ? Body(type: BodyType.multipart, multipart: parts) : Body(type: BodyType.form, form: kv)
    }

    func bodyV2(_ op: SpecNode, _ bodyParam: SpecNode?, _ form: [SpecNode]) -> Body? {
        let consumes = (op["consumes"].exists ? op["consumes"] : root["consumes"]).items.compactMap(\.str)
        if let bp = bodyParam {
            let j = direct(bp) ?? sample(bp["schema"]) ?? .obj([])
            if consumes.isEmpty || consumes.contains(where: { $0.contains("json") }) {
                return Body(type: BodyType.json, raw: pretty(j))
            }
            let curVal = consumes[0]
            return Body(
                type: curVal.contains("xml") ? BodyType.xml : (curVal.contains("html") ? BodyType.html : BodyType.text),
                raw: "")
        }
        guard !form.isEmpty else { return nil }
        let multi = consumes.contains { $0.contains("multipart") } || form.contains { $0["type"].str == "file" }
        var kv: [KeyValue] = []
        var parts: [MultipartPart] = []
        for par in form {
            let name = par["name"].str ?? ""
            let isFile = par["type"].str == "file"
            let val = isFile ? "" : paramValue(par)
            kv.append(KeyValue(name: name, value: val, description: par["description"].str ?? ""))
            parts.append(MultipartPart(name: name, kind: isFile ? "file" : "text", value: val))
        }
        return multi ? Body(type: BodyType.multipart, multipart: parts) : Body(type: BodyType.form, form: kv)
    }
}

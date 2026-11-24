import Foundation
import Yams

/// Neutrální podoba specifikace (Swagger 2.0 i OpenAPI 3.x) – vstup generátoru (kap. 7).
nonisolated struct APISpec: Sendable, Equatable {
    var title = ""
    var description = ""
    var servers: [APIServer] = []
    /// Globální autentizace (první požadavek `security`); `nil` = žádná.
    var auth: Auth?
    /// Názvy proměnných použitých v autentizaci (`username`, `token` …), které se založí prázdné.
    var variables: [String] = []
    var operations: [APIOperation] = []
    var warnings: [String] = []
}

nonisolated struct APIServer: Sendable, Equatable {
    var url: String
    var description: String
}

nonisolated struct APIOperation: Sendable, Equatable {
    var method = ""
    /// Cesta s parametry ve tvaru `:id`.
    var path = ""
    var tag = ""
    var summary = ""
    var operationId = ""
    var description = ""
    var query: [KeyValue] = []
    var headers: [KeyValue] = []
    var pathParams: [PathParam] = []
    var body: Body?
    /// `nil` = zdědit; `none` při `security: []`; jinak vlastní schéma operace.
    var auth: Auth?

    /// Název requestu: `summary` → `operationId` → `METHOD /path`.
    var title: String {
        if !summary.isEmpty { return summary }
        if !operationId.isEmpty { return operationId }
        let shown = path.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.hasPrefix(":") ? "{\($0.dropFirst())}" : String($0) }.joined(separator: "/")
        return "\(method) \(shown)"
    }
}

// MARK: - Parser

nonisolated enum OpenAPIParser {
    static func parse(_ text: String) throws -> APISpec {
        let root: Node
        do {
            guard let numVal = try Yams.compose(yaml: text) else { throw CoreError(.importInvalid, "empty") }
            root = numVal
        } catch let elem as CoreError {
            throw elem
        } catch {
            throw CoreError(.importInvalid, "\(error)")
        }
        guard root.mapping != nil else { throw CoreError(.importInvalid, "not an object") }
        var par = SpecParser(root: SpecNode(root))
        guard par.v2 || par.v3 else { throw CoreError(.importInvalid, "swagger/openapi") }
        return par.run()
    }
}

/// Tenký obal nad `Node` (bez výjimek; chybějící klíč = prázdný uzel).
nonisolated private struct SpecNode {
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
nonisolated private indirect enum SpecJSON {
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

nonisolated private struct SpecParser {
    let root: SpecNode
    var warnings: [String] = []
    var vars: [String] = []
    var schemes: [String: Auth] = [:]
    let v2: Bool
    let v3: Bool
    let maxDepth = 6

    init(root: SpecNode) {
        self.root = root
        v2 = root["swagger"].str?.hasPrefix("2") ?? false
        v3 = root["openapi"].str?.hasPrefix("3") ?? false
    }

    mutating func warn(_ strVal: String) { if !warnings.contains(strVal) { warnings.append(strVal) } }
    mutating func need(_ name: String) { if !vars.contains(name) { vars.append(name) } }

    mutating func run() -> APISpec {
        var spec = APISpec()
        spec.title = root["info"]["title"].str ?? ""
        spec.description = root["info"]["description"].str ?? ""
        spec.servers = servers()
        loadSchemes()
        let global = authFor(root["security"])
        spec.auth = global
        for (path, raw) in root["paths"].pairs {
            let item = deref(raw)
            for (key, opNode) in item.pairs {
                let mapVal = key.uppercased()
                if key.lowercased() == "trace" {
                    warn("TRACE \(path)")
                    continue
                }
                guard HTTPMethod.all.contains(mapVal) else { continue }
                var op = operation(mapVal, path, item, opNode)
                if opNode["security"].exists {
                    let arg = authFor(opNode["security"]) ?? Auth(type: AuthType.none)
                    if arg != global { op.auth = arg }
                }
                spec.operations.append(op)
            }
        }
        spec.variables = vars
        spec.warnings = warnings
        return spec
    }

    // MARK: Servery

    func servers() -> [APIServer] {
        if v2 {
            let host = root["host"].str ?? ""
            var base = root["basePath"].str ?? ""
            if base == "/" { base = "" }
            if host.isEmpty { return base.isEmpty ? [] : [APIServer(url: base, description: "")] }
            let schemes = root["schemes"].items.compactMap(\.str)
            let scheme = schemes.contains("https") ? "https" : (schemes.first ?? "https")
            return [APIServer(url: "\(scheme)://\(host)\(base)", description: "")]
        }
        return root["servers"].items.compactMap { strVal in
            guard var url = strVal["url"].str else { return nil }
            for (name, val) in strVal["variables"].pairs {
                url = url.replacingOccurrences(
                    of: "{\(name)}", with: val["default"].str ?? val["enum"].items.first?.str ?? "")
            }
            return APIServer(url: url, description: strVal["description"].str ?? "")
        }
    }

    // MARK: Autentizace

    mutating func loadSchemes() {
        let defs = v2 ? root["securityDefinitions"] : root["components"]["securitySchemes"]
        for (name, raw) in defs.pairs {
            let strVal = deref(raw)
            let type = strVal["type"].str ?? ""
            switch type {
            case "basic":
                need("username")
                need("password")
                schemes[name] = Auth(
                    type: AuthType.basic, basic: BasicAuth(username: "{{username}}", password: "{{password}}"))
            case "http":
                switch (strVal["scheme"].str ?? "").lowercased() {
                case "basic":
                    need("username")
                    need("password")
                    schemes[name] = Auth(
                        type: AuthType.basic, basic: BasicAuth(username: "{{username}}", password: "{{password}}"))
                case "bearer":
                    need("token")
                    schemes[name] = Auth(type: AuthType.bearer, bearer: BearerAuth(token: "{{token}}"))
                default: warn("security: \(name)")
                }
            case "apiKey":
                let loc = strVal["in"].str ?? ""
                guard loc == "header" || loc == "query" else {
                    warn("security: \(name)")
                    continue
                }
                need("apiKey")
                schemes[name] = Auth(
                    type: AuthType.apiKey,
                    apiKey: APIKeyAuth(key: strVal["name"].str ?? "", value: "{{apiKey}}", location: loc))
            case "oauth2":
                if let arg = oauth(strVal) { schemes[name] = arg } else { warn("security: \(name)") }
            default:
                warn("security: \(name)")
            }
        }
    }

    mutating func oauth(_ strVal: SpecNode) -> Auth? {
        var opt = OAuth2Auth()
        var flow = SpecNode(nil)
        var grant = ""
        func url(_ urlVal: String?) -> String {
            (urlVal ?? "").hasPrefix("/") ? "{{baseUrl}}" + (urlVal ?? "") : (urlVal ?? "")
        }
        if v2 {
            flow = strVal
            switch strVal["flow"].str ?? "" {
            case "application": grant = "client_credentials"
            case "password": grant = "password"
            case "accessCode": grant = "authorization_code"
            default: return nil
            }
            opt.authURL = url(flow["authorizationUrl"].str)
        } else {
            let map = [
                "clientCredentials": "client_credentials", "password": "password",
                "authorizationCode": "authorization_code"
            ]
            guard let fn = strVal["flows"].pairs.first(where: { map[$0.key] != nil }) else { return nil }
            flow = fn.value
            grant = map[fn.key] ?? ""
            opt.authURL = url(flow["authorizationUrl"].str)
        }
        opt.grantType = grant
        opt.tokenURL = url(flow["tokenUrl"].str)
        opt.scope = flow["scopes"].pairs.map(\.key).joined(separator: " ")
        opt.clientID = "{{clientId}}"
        opt.clientSecret = "{{clientSecret}}"
        need("clientId")
        need("clientSecret")
        opt.usePKCE = grant == "authorization_code"
        opt.clientAuth = "header"
        opt.tokenPlacement = "header"
        opt.autoRefresh = true
        if grant == "password" {
            opt.username = "{{username}}"
            opt.password = "{{password}}"
            need("username")
            need("password")
        }
        return Auth(type: AuthType.oauth2, oauth2: opt)
    }

    /// První neprázdná alternativa požadavku `security` → schéma; prázdné pole → `nil`.
    func authFor(_ sec: SpecNode) -> Auth? {
        for alt in sec.items {
            if let name = alt.pairs.first?.key, let arg = schemes[name] { return arg }
        }
        return nil
    }

    // MARK: $ref

    func lookup(_ ref: String) -> SpecNode? {
        guard ref.hasPrefix("#/") else { return nil }
        var cur = root
        for part in ref.dropFirst(2).split(separator: "/", omittingEmptySubsequences: false) {
            let key = (String(part).removingPercentEncoding ?? String(part))
                .replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            if cur.isSequence {
                let items = cur.items
                guard let i = Int(key), i < items.count else { return nil }
                cur = items[i]
            } else {
                cur = cur[key]
            }
            if !cur.exists { return nil }
        }
        return cur
    }

    /// Následuje řetěz `$ref`; neplatný / externí odkaz nebo cyklus → prázdný uzel.
    func deref(_ numVal: SpecNode) -> SpecNode {
        var cur = numVal
        var seen: Set<String> = []
        while let ref = cur["$ref"].str {
            guard seen.insert(ref).inserted, let txt = lookup(ref) else { return SpecNode(nil) }
            cur = txt
        }
        return cur
    }

    // MARK: Ukázkové hodnoty

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
        guard depth <= maxDepth else { return nil }
        var strVal = schema
        var stack = stack
        var guardCount = 0
        while let ref = strVal["$ref"].str {
            guardCount += 1
            guard guardCount < 20, !stack.contains(ref), let txt = lookup(ref) else { return nil }
            stack.append(ref)
            strVal = txt
        }
        if let dat = direct(strVal) { return dat }
        if !strVal["allOf"].items.isEmpty {
            var props: [(String, SpecJSON)] = []
            for sub in strVal["allOf"].items {
                if case .obj(let opt)? = sample(sub, depth: depth + 1, stack: stack) {
                    for (keyVal, val) in opt {
                        if let i = props.firstIndex(where: { $0.0 == keyVal }) {
                            props[i].1 = val
                        } else {
                            props.append((keyVal, val))
                        }
                    }
                }
            }
            return .obj(props)
        }
        for keyVal in ["oneOf", "anyOf"] {
            if let fn = strVal[keyVal].items.first { return sample(fn, depth: depth + 1, stack: stack) }
        }
        var type = strVal["type"].str ?? ""
        if type.isEmpty, strVal["type"].isSequence {
            type = strVal["type"].items.compactMap(\.str).first { $0 != "null" } ?? ""
        }
        if type.isEmpty { type = strVal["properties"].exists ? "object" : (strVal["items"].exists ? "array" : "") }
        switch type {
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
        case "string":
            switch strVal["format"].str ?? "" {
            case "date-time": return .str("2024-01-01T00:00:00Z")
            case "date": return .str("2024-01-01")
            case "uuid": return .str("00000000-0000-0000-0000-000000000000")
            case "email": return .str("user@example.com")
            case "uri", "url": return .str("https://example.com")
            default: return .str("string")
            }
        default: return nil
        }
    }

    func pretty(_ j: SpecJSON) -> String { (try? JSONFormatter.format(j.compact)) ?? j.compact }

    // MARK: Operace

    mutating func operation(_ method: String, _ rawPath: String, _ item: SpecNode, _ opNode: SpecNode) -> APIOperation {
        var op = APIOperation()
        op.method = method
        op.path = Self.colonPath(rawPath)
        op.tag = opNode["tags"].items.first?.str ?? ""
        op.summary = opNode["summary"].str ?? ""
        op.operationId = opNode["operationId"].str ?? ""
        op.description = opNode["description"].str ?? ""

        var params: [SpecNode] = []
        func key(_ par: SpecNode) -> String { (par["in"].str ?? "") + "|" + (par["name"].str ?? "") }
        for raw in item["parameters"].items { params.append(deref(raw)) }
        for raw in opNode["parameters"].items {
            let par = deref(raw)
            if let i = params.firstIndex(where: { key($0) == key(par) }) { params[i] = par } else { params.append(par) }
        }

        var declaredPath: [String: PathParam] = [:]
        var formParams: [SpecNode] = []
        var bodyParam: SpecNode?
        for par in params {
            let name = par["name"].str ?? ""
            let desc = par["description"].str ?? ""
            let value = paramValue(par)
            switch par["in"].str ?? "" {
            case "query":
                op.query.append(
                    KeyValue(name: name, value: value, enabled: par["required"].bool == true, description: desc))
            case "header":
                op.headers.append(
                    KeyValue(name: name, value: value, enabled: par["required"].bool == true, description: desc))
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

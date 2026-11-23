import Foundation
import Yams

/// Neutrální podoba specifikace (Swagger 2.0 i OpenAPI 3.x) – vstup generátoru (kap. 7).
public struct APISpec: Sendable, Equatable {
    public var title = ""
    public var description = ""
    public var servers: [APIServer] = []
    /// Globální autentizace (první požadavek `security`); `nil` = žádná.
    public var auth: Auth?
    /// Názvy proměnných použitých v autentizaci (`username`, `token` …), které se založí prázdné.
    public var variables: [String] = []
    public var operations: [APIOperation] = []
    public var warnings: [String] = []
}

public struct APIServer: Sendable, Equatable {
    public var url: String
    public var description: String
}

public struct APIOperation: Sendable, Equatable {
    public var method = ""
    /// Cesta s parametry ve tvaru `:id`.
    public var path = ""
    public var tag = ""
    public var summary = ""
    public var operationId = ""
    public var description = ""
    public var query: [KV] = []
    public var headers: [KV] = []
    public var pathParams: [PathParam] = []
    public var body: Body?
    /// `nil` = zdědit; `none` při `security: []`; jinak vlastní schéma operace.
    public var auth: Auth?

    /// Název requestu: `summary` → `operationId` → `METHOD /path`.
    public var title: String {
        if !summary.isEmpty { return summary }
        if !operationId.isEmpty { return operationId }
        let shown = path.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.hasPrefix(":") ? "{\($0.dropFirst())}" : String($0) }.joined(separator: "/")
        return "\(method) \(shown)"
    }
}

// MARK: - Parser

enum OpenAPIParser {
    static func parse(_ text: String) throws -> APISpec {
        let root: Node
        do {
            guard let n = try Yams.compose(yaml: text) else { throw CoreError(.importInvalid, "empty") }
            root = n
        } catch let e as CoreError {
            throw e
        } catch {
            throw CoreError(.importInvalid, "\(error)")
        }
        guard root.mapping != nil else { throw CoreError(.importInvalid, "not an object") }
        var p = P(root: N(root))
        guard p.v2 || p.v3 else { throw CoreError(.importInvalid, "swagger/openapi") }
        return p.run()
    }
}

/// Tenký obal nad `Node` (bez výjimek; chybějící klíč = prázdný uzel).
private struct N {
    var node: Node?
    init(_ n: Node?) { node = n }
    subscript(_ k: String) -> N { N(node?.mapping != nil ? node?[k] : nil) }
    var exists: Bool { node != nil }
    var str: String? { node?.scalar?.string }
    var bool: Bool? { node?.scalar != nil ? node?.bool : nil }
    var items: [N] { node?.sequence?.map { N($0) } ?? [] }
    var pairs: [(key: String, value: N)] { node?.mapping?.map { ($0.key.string ?? "", N($0.value)) } ?? [] }
    var isMapping: Bool { node?.mapping != nil }
    var isSequence: Bool { node?.sequence != nil }
}

/// Ordered JSON pro ukázková těla.
private indirect enum J {
    case null, bool(Bool), num(String), str(String), arr([J]), obj([(String, J)])

    var compact: String {
        switch self {
        case .null: "null"
        case let .bool(b): b ? "true" : "false"
        case let .num(s): s
        case let .str(s): Self.quote(s)
        case let .arr(a): "[" + a.map(\.compact).joined(separator: ",") + "]"
        case let .obj(o): "{" + o.map { Self.quote($0.0) + ":" + $0.1.compact }.joined(separator: ",") + "}"
        }
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }

    /// Řetězec pro hodnotu parametru / pole formuláře.
    var text: String {
        switch self {
        case let .str(s): s
        case let .num(s): s
        case let .bool(b): b ? "true" : "false"
        case .null: ""
        default: compact
        }
    }
}

private struct P {
    let root: N
    var warnings: [String] = []
    var vars: [String] = []
    var schemes: [String: Auth] = [:]
    let v2: Bool
    let v3: Bool
    let maxDepth = 6

    init(root: N) {
        self.root = root
        v2 = root["swagger"].str?.hasPrefix("2") ?? false
        v3 = root["openapi"].str?.hasPrefix("3") ?? false
    }

    mutating func warn(_ s: String) { if !warnings.contains(s) { warnings.append(s) } }
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
                let m = key.uppercased()
                if key.lowercased() == "trace" { warn("TRACE \(path)"); continue }
                guard HTTPMethod.all.contains(m) else { continue }
                var op = operation(m, path, item, opNode)
                if opNode["security"].exists {
                    let a = authFor(opNode["security"]) ?? Auth(type: AuthType.none)
                    if a != global { op.auth = a }
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
        return root["servers"].items.compactMap { s in
            guard var url = s["url"].str else { return nil }
            for (name, v) in s["variables"].pairs {
                url = url.replacingOccurrences(of: "{\(name)}", with: v["default"].str ?? v["enum"].items.first?.str ?? "")
            }
            return APIServer(url: url, description: s["description"].str ?? "")
        }
    }

    // MARK: Autentizace

    mutating func loadSchemes() {
        let defs = v2 ? root["securityDefinitions"] : root["components"]["securitySchemes"]
        for (name, raw) in defs.pairs {
            let s = deref(raw)
            let type = s["type"].str ?? ""
            switch type {
            case "basic":
                need("username"); need("password")
                schemes[name] = Auth(type: AuthType.basic, basic: BasicAuth(username: "{{username}}", password: "{{password}}"))
            case "http":
                switch (s["scheme"].str ?? "").lowercased() {
                case "basic":
                    need("username"); need("password")
                    schemes[name] = Auth(type: AuthType.basic, basic: BasicAuth(username: "{{username}}", password: "{{password}}"))
                case "bearer":
                    need("token")
                    schemes[name] = Auth(type: AuthType.bearer, bearer: BearerAuth(token: "{{token}}"))
                default: warn("security: \(name)")
                }
            case "apiKey":
                let loc = s["in"].str ?? ""
                guard loc == "header" || loc == "query" else { warn("security: \(name)"); continue }
                need("apiKey")
                schemes[name] = Auth(type: AuthType.apiKey, apiKey: APIKeyAuth(key: s["name"].str ?? "", value: "{{apiKey}}", location: loc))
            case "oauth2":
                if let a = oauth(s) { schemes[name] = a } else { warn("security: \(name)") }
            default:
                warn("security: \(name)")
            }
        }
    }

    mutating func oauth(_ s: N) -> Auth? {
        var o = OAuth2Auth()
        var flow = N(nil), grant = ""
        func url(_ u: String?) -> String { (u ?? "").hasPrefix("/") ? "{{baseUrl}}" + (u ?? "") : (u ?? "") }
        if v2 {
            flow = s
            switch s["flow"].str ?? "" {
            case "application": grant = "client_credentials"
            case "password": grant = "password"
            case "accessCode": grant = "authorization_code"
            default: return nil
            }
            o.authURL = url(flow["authorizationUrl"].str)
        } else {
            let map = ["clientCredentials": "client_credentials", "password": "password", "authorizationCode": "authorization_code"]
            guard let f = s["flows"].pairs.first(where: { map[$0.key] != nil }) else { return nil }
            flow = f.value
            grant = map[f.key] ?? ""
            o.authURL = url(flow["authorizationUrl"].str)
        }
        o.grantType = grant
        o.tokenURL = url(flow["tokenUrl"].str)
        o.scope = flow["scopes"].pairs.map(\.key).joined(separator: " ")
        o.clientID = "{{clientId}}"
        o.clientSecret = "{{clientSecret}}"
        need("clientId"); need("clientSecret")
        o.usePKCE = grant == "authorization_code"
        o.clientAuth = "header"
        o.tokenPlacement = "header"
        o.autoRefresh = true
        if grant == "password" { o.username = "{{username}}"; o.password = "{{password}}"; need("username"); need("password") }
        return Auth(type: AuthType.oauth2, oauth2: o)
    }

    /// První neprázdná alternativa požadavku `security` → schéma; prázdné pole → `nil`.
    func authFor(_ sec: N) -> Auth? {
        for alt in sec.items {
            if let name = alt.pairs.first?.key, let a = schemes[name] { return a }
        }
        return nil
    }

    // MARK: $ref

    func lookup(_ ref: String) -> N? {
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
    func deref(_ n: N) -> N {
        var cur = n
        var seen: Set<String> = []
        while let ref = cur["$ref"].str {
            guard seen.insert(ref).inserted, let t = lookup(ref) else { return N(nil) }
            cur = t
        }
        return cur
    }

    // MARK: Ukázkové hodnoty

    func json(_ n: N) -> J {
        guard let node = n.node else { return .null }
        switch node {
        case .mapping: return .obj(n.pairs.map { ($0.key, json($0.value)) })
        case .sequence: return .arr(n.items.map(json))
        default:
            guard let s = node.scalar else { return .null }
            if s.style != .plain && s.style != .any { return .str(s.string) }
            if node.null != nil { return .null }
            if let b = node.bool { return .bool(b) }
            if node.int != nil || node.float != nil { return .num(s.string) }
            return .str(s.string)
        }
    }

    /// `example` → `default` → `enum[0]` → `const` přímo na uzlu.
    func direct(_ n: N) -> J? {
        for k in ["example", "x-example", "default", "const"] where n[k].exists { return json(n[k]) }
        if let e = n["examples"].items.first { return json(e) }
        if let e = n["enum"].items.first { return json(e) }
        return nil
    }

    func sample(_ schema: N, depth: Int = 0, stack: [String] = []) -> J? {
        guard depth <= maxDepth else { return nil }
        var s = schema, stack = stack
        var guardCount = 0
        while let ref = s["$ref"].str {
            guardCount += 1
            guard guardCount < 20, !stack.contains(ref), let t = lookup(ref) else { return nil }
            stack.append(ref)
            s = t
        }
        if let d = direct(s) { return d }
        if !s["allOf"].items.isEmpty {
            var props: [(String, J)] = []
            for sub in s["allOf"].items {
                if case let .obj(o)? = sample(sub, depth: depth + 1, stack: stack) {
                    for (k, v) in o { if let i = props.firstIndex(where: { $0.0 == k }) { props[i].1 = v } else { props.append((k, v)) } }
                }
            }
            return .obj(props)
        }
        for k in ["oneOf", "anyOf"] {
            if let f = s[k].items.first { return sample(f, depth: depth + 1, stack: stack) }
        }
        var type = s["type"].str ?? ""
        if type.isEmpty, s["type"].isSequence { type = s["type"].items.compactMap(\.str).first { $0 != "null" } ?? "" }
        if type.isEmpty { type = s["properties"].exists ? "object" : (s["items"].exists ? "array" : "") }
        switch type {
        case "object":
            var out: [(String, J)] = []
            for (name, raw) in s["properties"].pairs {
                if deref(raw)["readOnly"].bool == true { continue }
                if let v = sample(raw, depth: depth + 1, stack: stack) { out.append((name, v)) }
            }
            return .obj(out)
        case "array":
            if let v = sample(s["items"], depth: depth + 1, stack: stack) { return .arr([v]) }
            return .arr([])
        case "integer", "number": return .num("0")
        case "boolean": return .bool(false)
        case "string":
            switch s["format"].str ?? "" {
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

    func pretty(_ j: J) -> String { (try? JSONFormatter.format(j.compact)) ?? j.compact }

    // MARK: Operace

    mutating func operation(_ method: String, _ rawPath: String, _ item: N, _ opNode: N) -> APIOperation {
        var op = APIOperation()
        op.method = method
        op.path = Self.colonPath(rawPath)
        op.tag = opNode["tags"].items.first?.str ?? ""
        op.summary = opNode["summary"].str ?? ""
        op.operationId = opNode["operationId"].str ?? ""
        op.description = opNode["description"].str ?? ""

        var params: [N] = []
        func key(_ p: N) -> String { (p["in"].str ?? "") + "|" + (p["name"].str ?? "") }
        for raw in item["parameters"].items { params.append(deref(raw)) }
        for raw in opNode["parameters"].items {
            let p = deref(raw)
            if let i = params.firstIndex(where: { key($0) == key(p) }) { params[i] = p } else { params.append(p) }
        }

        var declaredPath: [String: PathParam] = [:]
        var formParams: [N] = []
        var bodyParam: N?
        for p in params {
            let name = p["name"].str ?? ""
            let desc = p["description"].str ?? ""
            let value = paramValue(p)
            switch p["in"].str ?? "" {
            case "query": op.query.append(KV(name: name, value: value, enabled: p["required"].bool == true, description: desc))
            case "header": op.headers.append(KV(name: name, value: value, enabled: p["required"].bool == true, description: desc))
            case "path": declaredPath[name] = PathParam(name: name, value: value, description: desc)
            case "formData": formParams.append(p)
            case "body": bodyParam = p
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
        var out = "", name: String?
        for ch in path {
            if ch == "{" { name = "" } else if ch == "}", let n = name { out += ":" + n; name = nil } else if name != nil { name?.append(ch) } else { out.append(ch) }
        }
        if let n = name { out += "{" + n }
        return out
    }

    func paramValue(_ p: N) -> String {
        if let d = direct(p) { return d.text }
        if let ex = p["examples"].pairs.first, let v = Optional(deref(ex.value)["value"]), v.exists { return json(v).text }
        if let d = direct(deref(p["schema"])) { return d.text }
        if p["type"].str == "array", let d = direct(p["items"]) { return d.text }
        return ""
    }

    // MARK: Těla

    func bodyV3(_ rb: N) -> Body? {
        let content = rb["content"].pairs
        guard let pick = content.first(where: { $0.key == "application/json" })
            ?? content.first(where: { $0.key.contains("json") }) ?? content.first else { return nil }
        let media = pick.value
        let schema = media["schema"]
        let ct = pick.key.lowercased()

        func example() -> J? {
            if media["example"].exists { return json(media["example"]) }
            if let ex = media["examples"].pairs.first {
                let v = deref(ex.value)["value"]
                if v.exists { return json(v) }
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

    func formBody(_ schema: N, multipart: Bool) -> Body {
        var s = deref(schema)
        if !s["allOf"].items.isEmpty { s = s["allOf"].items.map(deref).first { $0["properties"].exists } ?? s }
        var kv: [KV] = [], parts: [MultipartPart] = []
        for (name, raw) in s["properties"].pairs {
            let p = deref(raw)
            let isFile = p["format"].str == "binary" || p["type"].str == "file"
            let v = isFile ? "" : (sample(p, stack: []) ?? .str("")).text
            kv.append(KV(name: name, value: v))
            parts.append(MultipartPart(name: name, kind: isFile ? "file" : "text", value: v))
        }
        return multipart ? Body(type: BodyType.multipart, multipart: parts) : Body(type: BodyType.form, form: kv)
    }

    func bodyV2(_ op: N, _ bodyParam: N?, _ form: [N]) -> Body? {
        let consumes = (op["consumes"].exists ? op["consumes"] : root["consumes"]).items.compactMap(\.str)
        if let bp = bodyParam {
            let j = direct(bp) ?? sample(bp["schema"]) ?? .obj([])
            if consumes.isEmpty || consumes.contains(where: { $0.contains("json") }) {
                return Body(type: BodyType.json, raw: pretty(j))
            }
            let c = consumes[0]
            return Body(type: c.contains("xml") ? BodyType.xml : (c.contains("html") ? BodyType.html : BodyType.text), raw: "")
        }
        guard !form.isEmpty else { return nil }
        let multi = consumes.contains { $0.contains("multipart") } || form.contains { $0["type"].str == "file" }
        var kv: [KV] = [], parts: [MultipartPart] = []
        for p in form {
            let name = p["name"].str ?? ""
            let isFile = p["type"].str == "file"
            let v = isFile ? "" : paramValue(p)
            kv.append(KV(name: name, value: v, description: p["description"].str ?? ""))
            parts.append(MultipartPart(name: name, kind: isFile ? "file" : "text", value: v))
        }
        return multi ? Body(type: BodyType.multipart, multipart: parts) : Body(type: BodyType.form, form: kv)
    }
}

import Foundation
import Yams

nonisolated struct SpecParser {
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
            if let auth = makeScheme(deref(raw)) { schemes[name] = auth } else { warn("security: \(name)") }
        }
    }

    private mutating func basicScheme() -> Auth {
        need("username")
        need("password")
        return Auth(type: AuthType.basic, basic: BasicAuth(username: "{{username}}", password: "{{password}}"))
    }

    /// Schéma zabezpečení → auth s proměnnými; `nil` = nepodporované.
    private mutating func makeScheme(_ strVal: SpecNode) -> Auth? {
        switch strVal["type"].str ?? "" {
        case "basic": return basicScheme()
        case "http":
            switch (strVal["scheme"].str ?? "").lowercased() {
            case "basic": return basicScheme()
            case "bearer":
                need("token")
                return Auth(type: AuthType.bearer, bearer: BearerAuth(token: "{{token}}"))
            default: return nil
            }
        case "apiKey":
            let loc = strVal["in"].str ?? ""
            guard loc == "header" || loc == "query" else { return nil }
            need("apiKey")
            return Auth(
                type: AuthType.apiKey,
                apiKey: APIKeyAuth(key: strVal["name"].str ?? "", value: "{{apiKey}}", location: loc))
        case "oauth2": return oauth(strVal)
        default: return nil
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
}

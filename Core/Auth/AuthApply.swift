import Foundation

/// Dědění a použití autorizace (PLAN kap. 5). OAuth2 přibude ve F7/2–3.
nonisolated enum AuthApply {
    /// Zdroj auth pro UI a `Prepared.authSource`.
    static let sourceRequest = "request", sourceProject = "project", folderPrefix = "folder:"

    /// Platná auth: request → složky (nejbližší první) → projekt, první ne-`inherit` vyhrává;
    /// prázdný typ = `inherit`, projekt s `inherit` = `none`. Vrací i zdroj (`request`, `folder:<rel>`, `project`).
    static func effective(_ auth: Auth, folders: [PrepareFolder], project: Auth) -> (auth: Auth, source: String) {
        if !isInherit(auth) { return (auth, sourceRequest) }
        for fn in folders.reversed() where !isInherit(fn.config.auth) {
            return (fn.config.auth, folderPrefix + fn.rel)
        }
        return (isInherit(project) ? Auth(type: AuthType.none) : project, sourceProject)
    }

    static func isInherit(_ arg: Auth) -> Bool { arg.type.isEmpty || arg.type == AuthType.inherit }

    /// Hodnota zapsaná přímo (ne jen přes `{{…}}`) – v UI varování u hesla, tokenu a hodnoty API klíče.
    static func isLiteral(_ str: String) -> Bool {
        let txt = str.trimmingCharacters(in: .whitespaces)
        guard !txt.isEmpty else { return false }
        let rest = txt.replacingOccurrences(of: #"\{\{[^{}]*\}\}"#, with: "", options: .regularExpression)
        return !rest.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Přidá auth do hlaviček (vyhodnotí proměnné); API klíč v query vrátí jako `query` (připojí volající).
    /// Ručně zadaná hlavička (`Authorization`, název API klíče) nebo zapnutý query parametr se stejným
    /// názvem (`queryNames`) má přednost. `secrets` = hodnoty k maskování (API klíč).
    static func apply(
        _ auth: Auth, headers: inout [KV], queryNames: Set<String>,
        _ resVal: Resolver
    ) throws -> (query: KV?, secrets: [String]) {
        func res(_ str: String) throws -> String { try resVal.resolve(str).value }
        func hasHeader(_ name: String) -> Bool {
            headers.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
        switch auth.type {
        case AuthType.basic:
            let buf = auth.basic ?? BasicAuth()
            let user = try res(buf.username)
            let pass = try res(buf.password)
            guard !(user.isEmpty && pass.isEmpty), !hasHeader("Authorization") else { return (nil, []) }
            headers.append(
                KV(name: "Authorization", value: "Basic " + Data((user + ":" + pass).utf8).base64EncodedString()))
        case AuthType.bearer:
            let buf = auth.bearer ?? BearerAuth()
            let token = try res(buf.token)
            guard !token.isEmpty, !hasHeader("Authorization") else { return (nil, []) }
            let prefix = try res(buf.prefix).trimmingCharacters(in: .whitespaces)
            headers.append(KV(name: "Authorization", value: (prefix.isEmpty ? "Bearer" : prefix) + " " + token))
        case AuthType.apiKey:
            let keyVal = auth.apiKey ?? APIKeyAuth()
            let key = try res(keyVal.key).trimmingCharacters(in: .whitespaces)
            let value = try res(keyVal.value)
            guard !key.isEmpty else { return (nil, []) }
            let secrets = value.isEmpty ? [] : [value]
            if keyVal.location == "query" {
                return queryNames.contains(key) ? (nil, []) : (KV(name: key, value: value), secrets)
            }
            guard !hasHeader(key) else { return (nil, []) }
            headers.append(KV(name: key, value: value))
            return (nil, secrets)
        default:
            break
        }
        return (nil, [])
    }

    /// OAuth2: token z cache / refresh / nový; přidá ho jako hlavičku (`headerPrefix`) nebo query `access_token`.
    /// Ručně zadaná `Authorization` či query `access_token` má přednost (token se ani nezískává).
    static func applyOAuth(
        _ arg: OAuth2Auth, client: OAuthClient, options: HTTPEngine.Options,
        headers: inout [KV], queryNames: Set<String>,
        _ resVal: Resolver
    ) async throws -> (query: KV?, secrets: [String]) {
        let par = try OAuthParams(arg) { try resVal.resolve($0).value }
        guard !par.tokenURL.isEmpty else { return (nil, []) }
        let inHeader = par.tokenPlacement == "header"
        if inHeader {
            guard !headers.contains(where: { $0.name.caseInsensitiveCompare("Authorization") == .orderedSame })
            else { return (nil, []) }
        } else if queryNames.contains("access_token") {
            return (nil, [])
        }
        let token = try await client.accessToken(par, options: options)
        if inHeader {
            headers.append(KV(name: "Authorization", value: par.headerPrefix + " " + token))
            return (nil, [token])
        }
        return (KV(name: "access_token", value: token), [token])
    }
}

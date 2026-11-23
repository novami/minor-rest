import Foundation

/// Dědění a použití autorizace (PLAN kap. 5). OAuth2 přibude ve F7/2–3.
public enum AuthApply {
    /// Zdroj auth pro UI a `Prepared.authSource`.
    public static let sourceRequest = "request", sourceProject = "project", folderPrefix = "folder:"

    /// Platná auth: request → složky (nejbližší první) → projekt, první ne-`inherit` vyhrává;
    /// prázdný typ = `inherit`, projekt s `inherit` = `none`. Vrací i zdroj (`request`, `folder:<rel>`, `project`).
    public static func effective(_ auth: Auth, folders: [PrepareFolder], project: Auth) -> (auth: Auth, source: String) {
        if !isInherit(auth) { return (auth, sourceRequest) }
        for f in folders.reversed() where !isInherit(f.config.auth) {
            return (f.config.auth, folderPrefix + f.rel)
        }
        return (isInherit(project) ? Auth(type: AuthType.none) : project, sourceProject)
    }

    public static func isInherit(_ a: Auth) -> Bool { a.type.isEmpty || a.type == AuthType.inherit }

    /// Hodnota zapsaná přímo (ne jen přes `{{…}}`) – v UI varování u hesla, tokenu a hodnoty API klíče.
    public static func isLiteral(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        let rest = t.replacingOccurrences(of: #"\{\{[^{}]*\}\}"#, with: "", options: .regularExpression)
        return !rest.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Přidá auth do hlaviček (vyhodnotí proměnné); API klíč v query vrátí jako `query` (připojí volající).
    /// Ručně zadaná hlavička (`Authorization`, název API klíče) nebo zapnutý query parametr se stejným
    /// názvem (`queryNames`) má přednost. `secrets` = hodnoty k maskování (API klíč).
    static func apply(_ auth: Auth, headers: inout [KV], queryNames: Set<String>,
                      _ r: Resolver) throws -> (query: KV?, secrets: [String]) {
        func res(_ s: String) throws -> String { try r.resolve(s).value }
        func hasHeader(_ name: String) -> Bool { headers.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
        switch auth.type {
        case AuthType.basic:
            let b = auth.basic ?? BasicAuth()
            let user = try res(b.username), pass = try res(b.password)
            guard !(user.isEmpty && pass.isEmpty), !hasHeader("Authorization") else { return (nil, []) }
            headers.append(KV(name: "Authorization", value: "Basic " + Data((user + ":" + pass).utf8).base64EncodedString()))
        case AuthType.bearer:
            let b = auth.bearer ?? BearerAuth()
            let token = try res(b.token)
            guard !token.isEmpty, !hasHeader("Authorization") else { return (nil, []) }
            let prefix = try res(b.prefix).trimmingCharacters(in: .whitespaces)
            headers.append(KV(name: "Authorization", value: (prefix.isEmpty ? "Bearer" : prefix) + " " + token))
        case AuthType.apiKey:
            let k = auth.apiKey ?? APIKeyAuth()
            let key = try res(k.key).trimmingCharacters(in: .whitespaces), value = try res(k.value)
            guard !key.isEmpty else { return (nil, []) }
            let secrets = value.isEmpty ? [] : [value]
            if k.location == "query" {
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
}

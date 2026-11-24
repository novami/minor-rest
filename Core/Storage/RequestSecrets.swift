import Foundation

/// Citlivé hodnoty requestů (hesla, tokeny, API klíče, Authorization/Cookie) žijí v Keychainu.
/// V YAML zůstává jen `{{keychain}}`; účet = `<vlastník>/<pole>`, vlastník `req/<id>` nebo `proj/<id>`.
nonisolated enum RequestSecrets {
    static let marker = "{{keychain}}"
    private static let sensitiveHeaders: Set<String> = ["authorization", "proxy-authorization", "cookie"]

    /// Literál = neprázdná hodnota bez proměnných; ty zůstávají v YAML.
    static func isLiteral(_ value: String) -> Bool { !value.isEmpty && !value.contains("{{") }

    /// Projde všechna citlivá pole (název pole, hodnota).
    private static func visit(_ auth: inout Auth, _ headers: inout [KV], _ body: (String, inout String) throws -> Void)
        rethrows {
        if auth.basic != nil { try body("basic.password", &auth.basic!.password) }
        if auth.bearer != nil { try body("bearer.token", &auth.bearer!.token) }
        if auth.apiKey != nil { try body("apikey.value", &auth.apiKey!.value) }
        if auth.oauth2 != nil {
            try body("oauth2.clientSecret", &auth.oauth2!.clientSecret)
            try body("oauth2.password", &auth.oauth2!.password)
        }
        for i in headers.indices where sensitiveHeaders.contains(headers[i].name.lowercased()) {
            try body("header.\(i)", &headers[i].value)
        }
    }

    /// Literály přesune do Keychainu a v YAML je nahradí značkou; ostatní pole smaže ze starých položek.
    static func store(owner: String, auth: inout Auth, headers: inout [KV], secrets: SecretStore) throws {
        try visit(&auth, &headers) { slot, value in
            let account = "\(owner)/\(slot)"
            if isLiteral(value) {
                try secrets.set(account: account, value: value)
                value = marker
            } else if value != marker {
                try secrets.delete(account: account)
            }
        }
    }

    /// Nahradí značky hodnotami z Keychainu (chybějící položka = prázdná hodnota).
    static func fill(owner: String, auth: inout Auth, headers: inout [KV], secrets: SecretStore) throws {
        try visit(&auth, &headers) { slot, value in
            if value == marker { value = try secrets.get(account: "\(owner)/\(slot)") ?? "" }
        }
    }

    /// Smaže všechny položky vlastníka (po smazání requestu).
    static func deleteAll(owner: String, secrets: SecretStore) {
        let slots =
            ["basic.password", "bearer.token", "apikey.value", "oauth2.clientSecret", "oauth2.password"]
            + (0..<32).map { "header.\($0)" }
        for slot in slots { try? secrets.delete(account: "\(owner)/\(slot)") }
    }
}

nonisolated extension Request {
    /// Kopie s literály nahrazenými značkou; hodnoty zapíše do Keychainu.
    func storingSecrets(_ secrets: SecretStore) throws -> Request {
        var res = self
        try RequestSecrets.store(owner: "req/\(id)", auth: &res.auth, headers: &res.headers, secrets: secrets)
        return res
    }

    func fillingSecrets(_ secrets: SecretStore) throws -> Request {
        var res = self
        try RequestSecrets.fill(owner: "req/\(id)", auth: &res.auth, headers: &res.headers, secrets: secrets)
        return res
    }
}

nonisolated extension ProjectConfig {
    func storingSecrets(_ secrets: SecretStore) throws -> ProjectConfig {
        var cur = self
        try RequestSecrets.store(owner: "proj/\(id)", auth: &cur.auth, headers: &cur.headers, secrets: secrets)
        return cur
    }

    func fillingSecrets(_ secrets: SecretStore) throws -> ProjectConfig {
        var cur = self
        try RequestSecrets.fill(owner: "proj/\(id)", auth: &cur.auth, headers: &cur.headers, secrets: secrets)
        return cur
    }
}

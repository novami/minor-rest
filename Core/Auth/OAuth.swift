import CryptoKit
import Foundation

/// Vyhodnocená pole OAuth2 (po dosazení proměnných).
nonisolated struct OAuthParams: Sendable, Equatable {
    static let clientCredentials = "client_credentials", password = "password", authorizationCode = "authorization_code"

    var grantType: String
    var authURL: String
    var tokenURL: String
    var clientID: String
    var clientSecret: String
    var scope: String
    var usePKCE: Bool
    var redirectPort: Int
    var username: String
    var password: String
    /// `header` | `body`
    var clientAuth: String
    /// `header` | `query`
    var tokenPlacement: String
    var headerPrefix: String
    var autoRefresh: Bool

    init(_ arg: OAuth2Auth, resolve: (String) throws -> String) rethrows {
        func r(_ str: String) throws -> String { try resolve(str).trimmingCharacters(in: .whitespaces) }
        let grp = arg.grantType.trimmingCharacters(in: .whitespaces)
        grantType = grp.isEmpty ? Self.clientCredentials : grp
        authURL = try r(arg.authURL)
        tokenURL = try r(arg.tokenURL)
        clientID = try r(arg.clientID)
        clientSecret = try resolve(arg.clientSecret)
        scope = try r(arg.scope)
        usePKCE = arg.usePKCE
        redirectPort = arg.redirectPort
        username = try r(arg.username)
        password = try resolve(arg.password)
        clientAuth = arg.clientAuth == "body" ? "body" : "header"
        tokenPlacement = arg.tokenPlacement == "query" ? "query" : "header"
        let par = try r(arg.headerPrefix)
        headerPrefix = par.isEmpty ? "Bearer" : par
        autoRefresh = arg.autoRefresh
    }

    /// Klíč cache tokenu: `sha256(tokenUrl|clientId|scope|grantType|username)[:16]` (hex).
    var cacheKey: String {
        let str = [tokenURL, clientID, scope, grantType, username].joined(separator: "|")
        return SHA256.hash(data: Data(str.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

/// Stav uloženého tokenu pro UI (hodnota tokenu se neprozrazuje).
nonisolated struct TokenInfo: Sendable, Equatable {
    var tokenType: String
    var scope: String
    /// nil = server expiraci neuvedl
    var expiresAt: Date?
    var hasRefresh: Bool

    func isExpired(now: Date = Date(), margin: TimeInterval = OAuthClient.margin) -> Bool {
        guard let elem = expiresAt else { return false }
        return elem.timeIntervalSince(now) <= margin
    }
}

/// OAuth2 klient (PLAN kap. 5): token endpoint přes stejný `HTTPEngine`, cache v Keychainu
/// (`oauth/<klíč>/access|refresh|meta`), automatický refresh.
actor OAuthClient {
    /// Rezerva před expirací, kdy se token už nepoužije.
    static let margin: TimeInterval = 30

    private struct Stored: Codable {
        var access: String
        var refresh: String
        var type: String
        var scope: String
        var expiresAt: Date?

        var info: TokenInfo { TokenInfo(tokenType: type, scope: scope, expiresAt: expiresAt, hasRefresh: !refresh.isEmpty) }
    }

    private struct Meta: Codable {
        var type: String
        var scope: String
        var expiresAt: Date?
    }

    private let engine: HTTPEngine
    private let secrets: SecretStore
    private let now: @Sendable () -> Date
    private var memory: [String: Stored] = [:]

    init(engine: HTTPEngine, secrets: SecretStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.engine = engine
        self.secrets = secrets
        self.now = now
    }

    // MARK: Veřejné API

    /// Platný přístupový token: z cache, po refreshi, nebo nový (client_credentials/password).
    /// authorization_code bez použitelného tokenu → `OAUTH_LOGIN_REQUIRED`.
    func accessToken(_ par: OAuthParams, options: HTTPEngine.Options) async throws -> String {
        let key = par.cacheKey
        if let str = try load(key), !str.info.isExpired(now: now()) { return str.access }
        if let str = try load(key), par.autoRefresh, !str.refresh.isEmpty,
           let txt = try? await refresh(par, options: options) { return txt }
        guard par.grantType != OAuthParams.authorizationCode else {
            throw CoreError(.oauthLoginRequired, par.tokenURL)
        }
        _ = try await fetchToken(par, options: options)
        return try load(key)?.access ?? ""
    }

    /// Získá nový token (client_credentials, password) a uloží ho.
    @discardableResult
    func fetchToken(_ par: OAuthParams, options: HTTPEngine.Options) async throws -> TokenInfo {
        guard par.grantType == OAuthParams.clientCredentials || par.grantType == OAuthParams.password else {
            throw CoreError(.oauthLoginRequired, par.tokenURL)
        }
        var form = [KV(name: "grant_type", value: par.grantType)]
        if par.grantType == OAuthParams.password {
            form += [KV(name: "username", value: par.username), KV(name: "password", value: par.password)]
        }
        if !par.scope.isEmpty { form.append(KV(name: "scope", value: par.scope)) }
        return try await request(par, form, options, previousRefresh: "")
    }

    /// Obnoví token pomocí `refresh_token`; bez něj `OAUTH_LOGIN_REQUIRED`.
    @discardableResult
    func refresh(_ par: OAuthParams, options: HTTPEngine.Options) async throws -> String {
        guard let str = try load(par.cacheKey), !str.refresh.isEmpty else {
            throw CoreError(.oauthLoginRequired, par.tokenURL)
        }
        var form = [KV(name: "grant_type", value: "refresh_token"), KV(name: "refresh_token", value: str.refresh)]
        if !par.scope.isEmpty { form.append(KV(name: "scope", value: par.scope)) }
        _ = try await request(par, form, options, previousRefresh: str.refresh)
        return try load(par.cacheKey)?.access ?? ""
    }

    func tokenInfo(_ par: OAuthParams) -> TokenInfo? {
        (try? load(par.cacheKey))?.info
    }

    func clearToken(_ par: OAuthParams) throws {
        let key = par.cacheKey
        memory[key] = nil
        for part in ["access", "refresh", "meta"] { try secrets.delete(account: Self.account(key, part)) }
    }

    /// Uloží token získaný jiným způsobem (authorization_code, F7/3).
    func store(_ par: OAuthParams, _ txt: TokenResponse, previousRefresh: String = "") throws -> TokenInfo {
        let str = Stored(access: txt.accessToken, refresh: txt.refreshToken.isEmpty ? previousRefresh : txt.refreshToken,
                       type: txt.tokenType, scope: txt.scope.isEmpty ? par.scope : txt.scope,
                       expiresAt: txt.expiresIn.map { now().addingTimeInterval($0) })
        let key = par.cacheKey
        try secrets.set(account: Self.account(key, "access"), value: str.access)
        try secrets.set(account: Self.account(key, "refresh"), value: str.refresh)
        let meta = try JSONEncoder().encode(Meta(type: str.type, scope: str.scope, expiresAt: str.expiresAt))
        try secrets.set(account: Self.account(key, "meta"), value: String(decoding: meta, as: UTF8.self))
        memory[key] = str
        return str.info
    }

    // MARK: Token endpoint

    struct TokenResponse {
        var accessToken = "", tokenType = "", refreshToken = "", scope = ""
        var expiresIn: TimeInterval?
    }

    /// POST na token endpoint s doplněním klientských údajů; úspěch uloží do cache.
    func request(_ par: OAuthParams, _ form: [KV], _ options: HTTPEngine.Options,
                 previousRefresh: String) async throws -> TokenInfo {
        guard !par.tokenURL.isEmpty else { throw CoreError(.urlInvalid, "tokenUrl") }
        var form = form
        var headers = [KV(name: "Accept", value: "application/json")]
        if par.clientAuth == "body" {
            form.append(KV(name: "client_id", value: par.clientID))
            if !par.clientSecret.isEmpty { form.append(KV(name: "client_secret", value: par.clientSecret)) }
        } else if !par.clientID.isEmpty || !par.clientSecret.isEmpty {
            let cred = Self.formEncode(par.clientID) + ":" + Self.formEncode(par.clientSecret)
            headers.append(KV(name: "Authorization", value: "Basic " + Data(cred.utf8).base64EncodedString()))
        }
        let req = PreparedRequest(method: "POST", url: par.tokenURL, headers: headers,
                                  body: Body(type: BodyType.form, form: form))
        let runID = ULID.make()
        let result = await engine.send(runID: runID, req, options, jar: nil)
        if let elem = result.error { throw elem }
        let text = (try? await engine.body(runID: runID, pretty: false))?.text ?? ""
        let json = try? JSONValue.parse(text)
        guard (200..<300).contains(result.status) else {
            throw CoreError(.oauthTokenError, Self.errorDetail(result.status, json, text))
        }
        guard let json, let access = json["access_token"]?.string, !access.isEmpty else {
            throw CoreError(.oauthTokenError, "HTTP \(result.status): access_token missing")
        }
        var txt = TokenResponse(accessToken: access)
        txt.tokenType = json["token_type"]?.string ?? ""
        txt.refreshToken = json["refresh_token"]?.string ?? ""
        txt.scope = json["scope"]?.string ?? ""
        txt.expiresIn = json["expires_in"]?.number
        return try store(par, txt, previousRefresh: previousRefresh)
    }

    private static func errorDetail(_ status: Int, _ json: JSONValue?, _ text: String) -> String {
        var dat = "HTTP \(status)"
        if let elem = json?["error"]?.string {
            dat += ": " + elem
            if let desc = json?["error_description"]?.string, !desc.isEmpty { dat += " – " + desc }
        } else if !text.isEmpty {
            dat += ": " + String(text.prefix(200))
        }
        return dat
    }

    /// RFC 6749 §2.3.1: `application/x-www-form-urlencoded` hodnoty před base64 (jen nechráněné znaky).
    static func formEncode(_ str: String) -> String {
        var out = ""
        for buf in str.utf8 {
            switch buf {
            case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "-"), UInt8(ascii: "."),
                 UInt8(ascii: "_"), UInt8(ascii: "~"):
                out.unicodeScalars.append(Unicode.Scalar(buf))
            default:
                out += String(format: "%%%02X", buf)
            }
        }
        return out
    }

    // MARK: Úložiště

    private static func account(_ key: String, _ part: String) -> String { "oauth/\(key)/\(part)" }

    private func load(_ key: String) throws -> Stored? {
        if let str = memory[key] { return str }
        guard let access = try secrets.get(account: Self.account(key, "access")), !access.isEmpty else { return nil }
        let refresh = try secrets.get(account: Self.account(key, "refresh")) ?? ""
        var meta = Meta(type: "", scope: "", expiresAt: nil)
        if let map = try secrets.get(account: Self.account(key, "meta")),
           let dat = try? JSONDecoder().decode(Meta.self, from: Data(map.utf8)) { meta = dat }
        let str = Stored(access: access, refresh: refresh, type: meta.type, scope: meta.scope, expiresAt: meta.expiresAt)
        memory[key] = str
        return str
    }
}

nonisolated extension JSONValue {
    subscript(key: String) -> JSONValue? {
        guard case .object(let map) = self else { return nil }
        return map.first { $0.key == key }?.value
    }

    /// Řetězec, nebo číslo zapsané jako text.
    var string: String? {
        switch self {
        case .string(let str): return str
        case .number(_, let text): return text
        default: return nil
        }
    }

    /// Číslo, nebo řetězec s číslem (některé servery posílají `expires_in` jako text).
    var number: Double? {
        switch self {
        case .number(let dat, _): return dat
        case .string(let str): return Double(str)
        default: return nil
        }
    }
}

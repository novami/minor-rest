import CryptoKit
import Foundation

/// Vyhodnocená pole OAuth2 (po dosazení proměnných).
public struct OAuthParams: Sendable, Equatable {
    public static let clientCredentials = "client_credentials", password = "password", authorizationCode = "authorization_code"

    public var grantType: String
    public var authURL: String
    public var tokenURL: String
    public var clientID: String
    public var clientSecret: String
    public var scope: String
    public var usePKCE: Bool
    public var redirectPort: Int
    public var username: String
    public var password: String
    /// `header` | `body`
    public var clientAuth: String
    /// `header` | `query`
    public var tokenPlacement: String
    public var headerPrefix: String
    public var autoRefresh: Bool

    public init(_ a: OAuth2Auth, resolve: (String) throws -> String) rethrows {
        func r(_ s: String) throws -> String { try resolve(s).trimmingCharacters(in: .whitespaces) }
        let g = a.grantType.trimmingCharacters(in: .whitespaces)
        grantType = g.isEmpty ? Self.clientCredentials : g
        authURL = try r(a.authURL)
        tokenURL = try r(a.tokenURL)
        clientID = try r(a.clientID)
        clientSecret = try resolve(a.clientSecret)
        scope = try r(a.scope)
        usePKCE = a.usePKCE
        redirectPort = a.redirectPort
        username = try r(a.username)
        password = try resolve(a.password)
        clientAuth = a.clientAuth == "body" ? "body" : "header"
        tokenPlacement = a.tokenPlacement == "query" ? "query" : "header"
        let p = try r(a.headerPrefix)
        headerPrefix = p.isEmpty ? "Bearer" : p
        autoRefresh = a.autoRefresh
    }

    /// Klíč cache tokenu: `sha256(tokenUrl|clientId|scope|grantType|username)[:16]` (hex).
    public var cacheKey: String {
        let s = [tokenURL, clientID, scope, grantType, username].joined(separator: "|")
        return SHA256.hash(data: Data(s.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

/// Stav uloženého tokenu pro UI (hodnota tokenu se neprozrazuje).
public struct TokenInfo: Sendable, Equatable {
    public var tokenType: String
    public var scope: String
    /// nil = server expiraci neuvedl
    public var expiresAt: Date?
    public var hasRefresh: Bool

    public func isExpired(now: Date = Date(), margin: TimeInterval = OAuthClient.margin) -> Bool {
        guard let e = expiresAt else { return false }
        return e.timeIntervalSince(now) <= margin
    }
}

/// OAuth2 klient (PLAN kap. 5): token endpoint přes stejný `HTTPEngine`, cache v Keychainu
/// (`oauth/<klíč>/access|refresh|meta`), automatický refresh.
public actor OAuthClient {
    /// Rezerva před expirací, kdy se token už nepoužije.
    public static let margin: TimeInterval = 30

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
    var loginTask: Task<TokenInfo, any Error>?

    public init(engine: HTTPEngine, secrets: SecretStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.engine = engine
        self.secrets = secrets
        self.now = now
    }

    // MARK: Veřejné API

    /// Platný přístupový token: z cache, po refreshi, nebo nový (client_credentials/password).
    /// authorization_code bez použitelného tokenu → `OAUTH_LOGIN_REQUIRED`.
    public func accessToken(_ p: OAuthParams, options: HTTPEngine.Options) async throws -> String {
        let key = p.cacheKey
        if let s = try load(key), !s.info.isExpired(now: now()) { return s.access }
        if let s = try load(key), p.autoRefresh, !s.refresh.isEmpty,
           let t = try? await refresh(p, options: options) { return t }
        guard p.grantType != OAuthParams.authorizationCode else {
            throw CoreError(.oauthLoginRequired, p.tokenURL)
        }
        _ = try await fetchToken(p, options: options)
        return try load(key)?.access ?? ""
    }

    /// Získá nový token (client_credentials, password) a uloží ho.
    @discardableResult
    public func fetchToken(_ p: OAuthParams, options: HTTPEngine.Options) async throws -> TokenInfo {
        guard p.grantType == OAuthParams.clientCredentials || p.grantType == OAuthParams.password else {
            throw CoreError(.oauthLoginRequired, p.tokenURL)
        }
        var form = [KV(name: "grant_type", value: p.grantType)]
        if p.grantType == OAuthParams.password {
            form += [KV(name: "username", value: p.username), KV(name: "password", value: p.password)]
        }
        if !p.scope.isEmpty { form.append(KV(name: "scope", value: p.scope)) }
        return try await request(p, form, options, previousRefresh: "")
    }

    /// Obnoví token pomocí `refresh_token`; bez něj `OAUTH_LOGIN_REQUIRED`.
    @discardableResult
    public func refresh(_ p: OAuthParams, options: HTTPEngine.Options) async throws -> String {
        guard let s = try load(p.cacheKey), !s.refresh.isEmpty else {
            throw CoreError(.oauthLoginRequired, p.tokenURL)
        }
        var form = [KV(name: "grant_type", value: "refresh_token"), KV(name: "refresh_token", value: s.refresh)]
        if !p.scope.isEmpty { form.append(KV(name: "scope", value: p.scope)) }
        _ = try await request(p, form, options, previousRefresh: s.refresh)
        return try load(p.cacheKey)?.access ?? ""
    }

    public func tokenInfo(_ p: OAuthParams) -> TokenInfo? {
        (try? load(p.cacheKey))?.info
    }

    public func clearToken(_ p: OAuthParams) throws {
        let key = p.cacheKey
        memory[key] = nil
        for part in ["access", "refresh", "meta"] { try secrets.delete(account: Self.account(key, part)) }
    }

    /// Uloží token získaný jiným způsobem (authorization_code, F7/3).
    func store(_ p: OAuthParams, _ t: TokenResponse, previousRefresh: String = "") throws -> TokenInfo {
        let s = Stored(access: t.accessToken, refresh: t.refreshToken.isEmpty ? previousRefresh : t.refreshToken,
                       type: t.tokenType, scope: t.scope.isEmpty ? p.scope : t.scope,
                       expiresAt: t.expiresIn.map { now().addingTimeInterval($0) })
        let key = p.cacheKey
        try secrets.set(account: Self.account(key, "access"), value: s.access)
        try secrets.set(account: Self.account(key, "refresh"), value: s.refresh)
        let meta = try JSONEncoder().encode(Meta(type: s.type, scope: s.scope, expiresAt: s.expiresAt))
        try secrets.set(account: Self.account(key, "meta"), value: String(decoding: meta, as: UTF8.self))
        memory[key] = s
        return s.info
    }

    // MARK: Token endpoint

    struct TokenResponse {
        var accessToken = "", tokenType = "", refreshToken = "", scope = ""
        var expiresIn: TimeInterval?
    }

    /// POST na token endpoint s doplněním klientských údajů; úspěch uloží do cache.
    func request(_ p: OAuthParams, _ form: [KV], _ options: HTTPEngine.Options,
                 previousRefresh: String) async throws -> TokenInfo {
        guard !p.tokenURL.isEmpty else { throw CoreError(.urlInvalid, "tokenUrl") }
        var form = form
        var headers = [KV(name: "Accept", value: "application/json")]
        if p.clientAuth == "body" {
            form.append(KV(name: "client_id", value: p.clientID))
            if !p.clientSecret.isEmpty { form.append(KV(name: "client_secret", value: p.clientSecret)) }
        } else if !p.clientID.isEmpty || !p.clientSecret.isEmpty {
            let cred = Self.formEncode(p.clientID) + ":" + Self.formEncode(p.clientSecret)
            headers.append(KV(name: "Authorization", value: "Basic " + Data(cred.utf8).base64EncodedString()))
        }
        let req = PreparedRequest(method: "POST", url: p.tokenURL, headers: headers,
                                  body: Body(type: BodyType.form, form: form))
        let runID = ULID.make()
        let result = await engine.send(runID: runID, req, options, jar: nil)
        if let e = result.error { throw e }
        let text = (try? await engine.body(runID: runID, pretty: false))?.text ?? ""
        let json = try? JSONValue.parse(text)
        guard (200..<300).contains(result.status) else {
            throw CoreError(.oauthTokenError, Self.errorDetail(result.status, json, text))
        }
        guard let json, let access = json["access_token"]?.string, !access.isEmpty else {
            throw CoreError(.oauthTokenError, "HTTP \(result.status): access_token missing")
        }
        var t = TokenResponse(accessToken: access)
        t.tokenType = json["token_type"]?.string ?? ""
        t.refreshToken = json["refresh_token"]?.string ?? ""
        t.scope = json["scope"]?.string ?? ""
        t.expiresIn = json["expires_in"]?.number
        return try store(p, t, previousRefresh: previousRefresh)
    }

    private static func errorDetail(_ status: Int, _ json: JSONValue?, _ text: String) -> String {
        var d = "HTTP \(status)"
        if let e = json?["error"]?.string {
            d += ": " + e
            if let desc = json?["error_description"]?.string, !desc.isEmpty { d += " – " + desc }
        } else if !text.isEmpty {
            d += ": " + String(text.prefix(200))
        }
        return d
    }

    /// RFC 6749 §2.3.1: `application/x-www-form-urlencoded` hodnoty před base64 (jen nechráněné znaky).
    static func formEncode(_ s: String) -> String {
        var out = ""
        for b in s.utf8 {
            switch b {
            case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "-"), UInt8(ascii: "."),
                 UInt8(ascii: "_"), UInt8(ascii: "~"):
                out.unicodeScalars.append(Unicode.Scalar(b))
            default:
                out += String(format: "%%%02X", b)
            }
        }
        return out
    }

    // MARK: Úložiště

    private static func account(_ key: String, _ part: String) -> String { "oauth/\(key)/\(part)" }

    private func load(_ key: String) throws -> Stored? {
        if let s = memory[key] { return s }
        guard let access = try secrets.get(account: Self.account(key, "access")), !access.isEmpty else { return nil }
        let refresh = try secrets.get(account: Self.account(key, "refresh")) ?? ""
        var meta = Meta(type: "", scope: "", expiresAt: nil)
        if let m = try secrets.get(account: Self.account(key, "meta")),
           let d = try? JSONDecoder().decode(Meta.self, from: Data(m.utf8)) { meta = d }
        let s = Stored(access: access, refresh: refresh, type: meta.type, scope: meta.scope, expiresAt: meta.expiresAt)
        memory[key] = s
        return s
    }
}

extension JSONValue {
    subscript(key: String) -> JSONValue? {
        guard case .object(let m) = self else { return nil }
        return m.first { $0.key == key }?.value
    }

    /// Řetězec, nebo číslo zapsané jako text.
    var string: String? {
        switch self {
        case .string(let s): return s
        case .number(_, let text): return text
        default: return nil
        }
    }

    /// Číslo, nebo řetězec s číslem (některé servery posílají `expires_in` jako text).
    var number: Double? {
        switch self {
        case .number(let d, _): return d
        case .string(let s): return Double(s)
        default: return nil
        }
    }
}

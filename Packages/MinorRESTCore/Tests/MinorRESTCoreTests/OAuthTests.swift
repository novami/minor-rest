import Foundation
import Synchronization
import Testing
@testable import MinorRESTCore

/// Token server: počítá volání, vrací `access-N`, refresh_token a expires_in.
private final class TokenServer: Sendable {
    let calls = Mutex<[TestRequest]>([])
    let status = Mutex(200)
    let expiresIn = Mutex(3600)
    func response(_ r: TestRequest) -> TestResponse {
        let n = calls.withLock { $0.append(r); return $0.count }
        let st = status.withLock { $0 }
        let json = st == 200
            ? #"{"access_token":"access-\#(n)","token_type":"bearer","refresh_token":"ref-\#(n)","expires_in":\#(expiresIn.withLock { $0 })}"#
            : #"{"error":"invalid_client","error_description":"bad"}"#
        return TestResponse(status: st, headers: [("Content-Type", "application/json")], body: Data(json.utf8))
    }
}

private func oauth(_ url: String, grant: String = "client_credentials") -> OAuth2Auth {
    var a = OAuth2Auth()
    a.grantType = grant
    a.tokenURL = url
    a.clientID = "id é"
    a.clientSecret = "s:3"
    a.scope = "read write"
    a.username = "jan"
    a.password = "pw"
    a.autoRefresh = true
    return a
}

private func bodyString(_ r: TestRequest) -> String { String(decoding: r.body, as: UTF8.self) }

@Test func oauthClientCredentialsAndCache() async throws {
    let ts = TokenServer()
    let srv = try await TestHTTPServer { ts.response($0) }
    defer { srv.stop() }
    let client = OAuthClient(engine: HTTPEngine(), secrets: MemorySecrets())
    let input = PrepareInput(request: Request(method: "GET", url: "x.test/a", auth: Auth(type: AuthType.oauth2, oauth2: oauth(srv.url + "/token"))),
                             oauth: client)
    var p = try await Prepare.prepare(input)
    #expect(p.request.headers == [KV(name: "Authorization", value: "Bearer access-1")])
    #expect(p.secrets.contains("access-1"))
    let call = ts.calls.withLock { $0[0] }
    #expect(call.header("Authorization") == "Basic " + Data("id%20%C3%A9:s%3A3".utf8).base64EncodedString())
    #expect(bodyString(call) == "grant_type=client_credentials&scope=read+write")

    p = try await Prepare.prepare(input)           // z cache, bez dalšího volání
    #expect(p.request.headers.first?.value == "Bearer access-1")
    #expect(ts.calls.withLock { $0.count } == 1)
}

@Test func oauthPasswordBodyAuthQueryPlacement() async throws {
    let ts = TokenServer()
    let srv = try await TestHTTPServer { ts.response($0) }
    defer { srv.stop() }
    var a = oauth(srv.url + "/token", grant: "password")
    a.clientAuth = "body"
    a.tokenPlacement = "query"
    let client = OAuthClient(engine: HTTPEngine(), secrets: MemorySecrets())
    let p = try await Prepare.prepare(PrepareInput(
        request: Request(method: "GET", url: "x.test/a", auth: Auth(type: AuthType.oauth2, oauth2: a)), oauth: client))
    #expect(p.request.url == "http://x.test/a?access_token=access-1")
    let call = ts.calls.withLock { $0[0] }
    #expect(call.header("Authorization") == nil)
    #expect(bodyString(call) == "grant_type=password&username=jan&password=pw&scope=read+write&client_id=id+%C3%A9&client_secret=s%3A3")
}

/// Expirovaný token se obnoví refresh tokenem; selhání refreshe → nový token; chyba serveru → OAUTH_TOKEN_ERROR.
@Test func oauthRefreshAndErrors() async throws {
    let ts = TokenServer()
    ts.expiresIn.withLock { $0 = 10 }              // kratší než rezerva 30 s → vždy „expirovaný“
    let srv = try await TestHTTPServer { ts.response($0) }
    defer { srv.stop() }
    let client = OAuthClient(engine: HTTPEngine(), secrets: MemorySecrets())
    let params = OAuthParams(oauth(srv.url + "/token")) { $0 }
    let o = HTTPEngine.Options()
    #expect(try await client.accessToken(params, options: o) == "access-1")
    #expect(try await client.accessToken(params, options: o) == "access-2")
    #expect(bodyString(ts.calls.withLock { $0[1] }) == "grant_type=refresh_token&refresh_token=ref-1&scope=read+write")
    #expect(await client.tokenInfo(params)?.hasRefresh == true)

    ts.status.withLock { $0 = 401 }
    await #expect(throws: CoreError.self) { try await client.accessToken(params, options: o) }
    do { _ = try await client.fetchToken(params, options: o) } catch let e as CoreError {
        #expect(e.code == .oauthTokenError)
        #expect(e.detail == "HTTP 401: invalid_client – bad")
    }

    try await client.clearToken(params)
    #expect(await client.tokenInfo(params) == nil)
    let code = OAuthParams(oauth(srv.url + "/token", grant: "authorization_code")) { $0 }
    do { _ = try await client.accessToken(code, options: o); Issue.record("má selhat") } catch let e as CoreError {
        #expect(e.code == .oauthLoginRequired)
    }
}

@Test func oauthTokenPersistsInSecrets() async throws {
    let ts = TokenServer()
    let srv = try await TestHTTPServer { ts.response($0) }
    defer { srv.stop() }
    let secrets = MemorySecrets()
    let params = OAuthParams(oauth(srv.url + "/token")) { $0 }
    _ = try await OAuthClient(engine: HTTPEngine(), secrets: secrets).fetchToken(params, options: HTTPEngine.Options())
    let again = OAuthClient(engine: HTTPEngine(), secrets: secrets)    // nová instance = po restartu
    #expect(try await again.accessToken(params, options: HTTPEngine.Options()) == "access-1")
    #expect(ts.calls.withLock { $0.count } == 1)
    #expect(secrets.all.keys.sorted() == ["access", "meta", "refresh"].map { "oauth/\(params.cacheKey)/\($0)" })
}

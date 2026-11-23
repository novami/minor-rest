import Foundation
import Testing
@testable import MinorRESTCore

private let basic = Auth(type: AuthType.basic, basic: BasicAuth(username: "{{user}}", password: "pá:ss"))
private let bearer = Auth(type: AuthType.bearer, bearer: BearerAuth(token: "{{token}}", prefix: ""))
private let keyHeader = Auth(type: AuthType.apiKey, apiKey: APIKeyAuth(key: "X-API-Key", value: "{{token}}", location: "header"))
private let keyQuery = Auth(type: AuthType.apiKey, apiKey: APIKeyAuth(key: "api key", value: "a&b", location: "query"))

private func prepare(_ auth: Auth, headers: [KV] = [], folders: [PrepareFolder] = [],
                     project: Auth = Auth()) async throws -> Prepared {
    try await Prepare.prepare(PrepareInput(
        request: Request(method: "GET", url: "x.test/a?q=1", headers: headers, auth: auth),
        project: ProjectConfig(vars: [Var(name: "user", value: "jan"), Var(name: "token", value: "t0k")], auth: project),
        folders: folders))
}

@Test(arguments: [
    (basic, "Authorization", "Basic " + Data("jan:pá:ss".utf8).base64EncodedString(), "http://x.test/a?q=1"),
    (bearer, "Authorization", "Bearer t0k", "http://x.test/a?q=1"),
    (keyHeader, "X-API-Key", "t0k", "http://x.test/a?q=1"),
    (keyQuery, nil, nil, "http://x.test/a?q=1&api%20key=a%26b"),
])
func authApplies(auth: Auth, header: String?, value: String?, url: String) async throws {
    let p = try await prepare(auth)
    #expect(p.request.headers == (header.map { [KV(name: $0, value: value!)] } ?? []))
    #expect(p.request.url == url)
    #expect(p.authSource == AuthApply.sourceRequest)
}

/// Dědění: nejbližší složka s vlastní auth vyhrává; ruční hlavička `Authorization` má přednost.
@Test func authInheritsAndManualWins() async throws {
    let folders = [PrepareFolder(rel: "api", config: FolderConfig(auth: bearer)),
                   PrepareFolder(rel: "api/users", config: FolderConfig(auth: Auth(type: AuthType.inherit)))]
    var p = try await prepare(Auth(type: AuthType.inherit), folders: folders, project: basic)
    #expect(p.request.headers == [KV(name: "Authorization", value: "Bearer t0k")])
    #expect(p.authSource == "folder:api")

    p = try await prepare(Auth(), project: Auth(type: AuthType.inherit))
    #expect(p.request.headers.isEmpty)
    #expect(p.authSource == AuthApply.sourceProject)

    p = try await prepare(keyHeader, headers: [KV(name: "x-api-key", value: "own")])
    #expect(p.request.headers == [KV(name: "x-api-key", value: "own")])
    #expect(p.secrets.isEmpty)

    p = try await prepare(basic, headers: [KV(name: "authorization", value: "Token x")])
    #expect(p.request.headers == [KV(name: "authorization", value: "Token x")])
}

@Test(arguments: [("", false), ("{{token}}", false), (" {{a}}{{b}} ", false), ("abc", true), ("x{{token}}", true)])
func authLiteral(value: String, literal: Bool) {
    #expect(AuthApply.isLiteral(value) == literal)
}

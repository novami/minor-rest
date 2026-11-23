import Foundation
import Testing
@testable import MinorRESTCore

private func kv(_ n: String, _ v: String, _ on: Bool = true) -> KV { KV(name: n, value: v, enabled: on) }
private func v(_ n: String, _ val: String) -> Var { Var(name: n, value: val) }

@Test func prepareMergesLevels() async throws {
    let input = PrepareInput(
        request: Request(
            method: "post", url: "{{host}}/users/:id",
            params: Params(query: [kv("q", "{{who}}"), kv("off", "x", false)],
                           path: [PathParam(name: "id", value: "{{id}}")]),
            headers: [kv("X-Project", "", false), kv("User-Agent", "", false), kv("X-Req", "{{missing}}")],
            body: Body(type: BodyType.form, form: [kv("a", "{{id}}"), kv("b", "x", false)]),
            vars: [v("id", "42")],
            settings: HTTPSettings(timeoutMs: 1000)),
        project: ProjectConfig(vars: [v("host", "api.test"), v("who", "project")],
                               headers: [kv("X-Project", "1"), kv("x-team", "p"), kv("Accept", "", false)],
                               settings: HTTPSettings(maxRedirects: 3, timeoutMs: 5000)),
        folders: [
            PrepareFolder(rel: "api", config: FolderConfig(vars: [v("who", "api")], headers: [kv("X-Team", "{{who}}")])),
            PrepareFolder(rel: "api/users", config: FolderConfig(vars: [v("who", "users")])),
        ],
        userAgent: "MinorREST/test")
    let p = try await Prepare.prepare(input)
    #expect(p.request.method == "POST")
    #expect(p.request.url == "http://api.test/users/42?q=users")
    #expect(p.request.headers == [kv("X-Team", "users"), kv("X-Req", "{{missing}}")])
    #expect(p.request.noAuto == ["User-Agent", "Accept"])
    #expect(p.request.body.form == [kv("a", "42")])
    #expect(p.options == HTTPEngine.Options(followRedirects: true, maxRedirects: 3, timeoutMs: 1000,
                                            verifyTLS: true, userAgent: "MinorREST/test"))
    #expect(p.unresolved == ["missing"])
}

@Test(arguments: [("{{host}}/x", ErrorCode.varUnresolvedHost), ("http://[::1", .urlInvalid)])
func prepareErrors(url: String, code: ErrorCode) async {
    await #expect(throws: CoreError.self) {
        do { _ = try await Prepare.prepare(PrepareInput(request: Request(method: "GET", url: url))) } catch let e as CoreError {
            #expect(e.code == code)
            throw e
        }
    }
}

/// Zapnutý řádek na nižší úrovni zruší vypnutí z vyšší; prázdný typ těla = none.
@Test func prepareReenablesAuto() async throws {
    let p = try await Prepare.prepare(PrepareInput(
        request: Request(method: "GET", url: "x.test", headers: [kv("accept", "text/plain")], body: Body(type: "", raw: "x")),
        project: ProjectConfig(headers: [kv("Accept", "", false)])))
    #expect(p.request.noAuto.isEmpty)
    #expect(p.request.headers == [kv("accept", "text/plain")])
    #expect(p.request.body == Body(type: BodyType.none))
}

@Test func projectFolderChain() throws {
    let tmp = TempDir()
    let p = try Project.create(name: "P", in: tmp.url) { _ in }
    let a = try p.createFolder(parent: "", name: "a")
    let b = try p.createFolder(parent: a.rel, name: "b")
    try p.saveFolderConfig(b.rel, FolderConfig(name: "b", vars: [v("x", "1")]))
    let r = try p.createRequest(parent: b.rel, name: "r")
    let chain = try p.folderChain(r.rel)
    #expect(chain.map(\.rel) == ["a", "a/b"])
    #expect(chain.last?.config.vars == [v("x", "1")])
    #expect(try p.folderChain("top.yaml").isEmpty)
}

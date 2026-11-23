import Foundation
import Testing
@testable import MinorRESTCore

private func tempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appending(path: "minorrest-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

@Test func setCookieSplit() {
    let merged = "a=1; Path=/; HttpOnly, b=2; Expires=Wed, 21 Oct 2035 07:28:00 GMT, c=3"
    #expect(SetCookie.split(merged) == ["a=1; Path=/; HttpOnly", "b=2; Expires=Wed, 21 Oct 2035 07:28:00 GMT", "c=3"])
}

@Test func cookieJarMatching() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = CookieJar.file(projectID: "P1", in: dir)
    let jar = CookieJar(file: file)
    let login = URL(string: "https://api.example.com/auth/login")!
    jar.store(SetCookie.parse(["sid=1; Path=/", "dom=2; Domain=example.com; Path=/", "sec=3; Secure; Path=/",
                               "deep=4", "evil=5; Domain=other.com"], for: login))
    #expect(jar.cookies.map(\.name) == ["sid", "dom", "sec", "deep"])  // cizí Domain zahozena
    #expect(jar.header(for: URL(string: "https://api.example.com/auth/x")!) == "deep=4; sid=1; dom=2; sec=3")
    #expect(jar.header(for: URL(string: "http://api.example.com/")!) == "sid=1; dom=2")   // Secure jen https
    #expect(jar.header(for: URL(string: "https://www.example.com/")!) == "dom=2")           // host-only
    #expect(jar.header(for: URL(string: "https://api.example.com/authx")!) == "sid=1; dom=2; sec=3")
    jar.store(SetCookie.parse(["sid=; Max-Age=0; Path=/"], for: login))                       // smazání
    #expect(!jar.cookies.contains { $0.name == "sid" })

    try jar.save()
    #expect(CookieJar(file: file).cookies == jar.cookies)
}

@Test func cookiesThroughRedirect() async throws {
    let srv = try await TestHTTPServer { r in
        if r.target == "/login" {
            return TestResponse(status: 302, headers: [("Location", "/me"), ("Set-Cookie", "sid=abc; Path=/; HttpOnly"),
                                                       ("Set-Cookie", "x=1; Expires=Wed, 21 Oct 2035 07:28:00 GMT")])
        }
        return echo(r)
    }
    defer { srv.stop() }
    let jar = CookieJar(file: nil)
    let req = PreparedRequest(method: "GET", url: srv.url + "/login", headers: [KV(name: "Cookie", value: "u=0")])
    let res = await HTTPEngine().send(runID: "r", req, HTTPEngine.Options(timeoutMs: 5000), jar: jar)
    #expect(res.error == nil && res.status == 200)
    #expect(res.headers.first { $0.name == "Echo-Cookie" }?.value == "u=0; sid=abc; x=1")
    #expect(res.cookies.map(\.name) == ["sid", "x"] && res.cookies[0].httpOnly)
    #expect(jar.cookies.count == 2)

    // Bez jaru: jen uživatelská hlavička; opakované Set-Cookie jako samostatné řádky.
    var o = HTTPEngine.Options(timeoutMs: 5000, cookieJar: false)
    o.followRedirects = false
    let off = await HTTPEngine().send(runID: "r", req, o, jar: jar)
    #expect(off.status == 302 && off.headers.filter { $0.name == "Set-Cookie" }.count == 2)
    #expect(off.sent.headers.first { $0.name == "Cookie" }?.value == "u=0")
}

/// URLSession `Authorization` při redirectu zahodí vždy; engine ji vrátí jen pro původní host.
@Test func authorizationAfterRedirect() async throws {
    let box = PortBox()
    let srv = try await TestHTTPServer { r in
        switch r.target {
        case "/same": TestResponse(status: 302, headers: [("Location", "/me")])
        case "/other": TestResponse(status: 302, headers: [("Location", "http://localhost:\(box.port)/me")])
        default: echo(r)
        }
    }
    defer { srv.stop() }
    box.port = srv.port
    let auth = [KV(name: "Authorization", value: "Bearer t")]
    let same = await HTTPEngine().send(runID: "r", PreparedRequest(method: "GET", url: srv.url + "/same", headers: auth), HTTPEngine.Options(timeoutMs: 5000))
    #expect(same.headers.first { $0.name == "Echo-Authorization" }?.value == "Bearer t")
    let other = await HTTPEngine().send(runID: "r", PreparedRequest(method: "GET", url: srv.url + "/other", headers: auth), HTTPEngine.Options(timeoutMs: 5000))
    #expect(other.status == 200 && !other.headers.contains { $0.name == "Echo-Authorization" })
}

private final class PortBox: @unchecked Sendable { var port: UInt16 = 0 }

@Test func manualProxy() async throws {
    let srv = try await TestHTTPServer(echo)
    defer { srv.stop() }
    let o = HTTPEngine.Options(timeoutMs: 5000, proxy: .manual(host: "127.0.0.1", port: Int(srv.port)))
    let res = await HTTPEngine().send(runID: "r", PreparedRequest(method: "GET", url: "http://proxy-test.invalid/a?b=1"), o)
    #expect(res.error == nil && res.headers.first { $0.name == "X-Target" }?.value == "http://proxy-test.invalid/a?b=1")
}

@Test func historyAddListMask() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let h = History(dir: dir, limit: 2)
    var r = RunResult(runID: "r")
    r.status = 200
    r.headers = [KV(name: "Set-Cookie", value: "sid=1"), KV(name: "X-Token", value: "tajne123")]
    r.sent.headers = [KV(name: "Authorization", value: "Bearer tajne123"), KV(name: "Cookie", value: "sid=1")]
    r.timing.totalMs = 12.5
    r.redirects = [Redirect(status: 302, method: "GET", url: "http://a/?k=tajne123", location: "/b")]
    let p = PreparedRequest(method: "GET", url: "http://a/?k=tajne123")
    var e = SavedResponse(r, request: p, secrets: ["tajne123"])
    e.projectID = "P"
    e.requestID = "R"

    let first = try h.add(e, body: Data(repeating: 65, count: History.maxBody + 10))
    try h.add(e, body: Data("x".utf8))
    let last = try h.add(e, body: nil)
    #expect(h.list().map(\.id).count == 2 && h.list().first?.id == last.id)
    #expect((try? h.entry(first.id)) == nil)

    let saved = try h.entry(last.id)
    #expect(saved.request.url == "http://a/?k=***" && saved.response.redirects[0].url == "http://a/?k=***")
    #expect(saved.request.headers.map(\.value) == ["Bearer ***", "***"])
    #expect(saved.response.headers.map(\.value) == ["***", "***"])
    var expected = e
    expected.id = last.id
    #expect(saved == expected)
    #expect(try h.body(last.id) == nil)

    let big = try h.add(e, body: Data(repeating: 65, count: History.maxBody + 10))
    #expect(try h.entry(big.id).truncated && h.body(big.id)?.count == History.maxBody)
    try h.clear()
    #expect(h.list().isEmpty)
}

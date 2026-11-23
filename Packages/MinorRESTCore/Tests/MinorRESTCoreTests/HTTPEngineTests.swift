import Foundation
import Testing
@testable import MinorRESTCore

private let defOpts = HTTPEngine.Options(timeoutMs: 5000, userAgent: "MinorREST/test")

private extension RunResult {
    func header(_ name: String) -> String? {
        let v = headers.filter { $0.name.lowercased() == name.lowercased() }.map(\.value)
        return v.isEmpty ? nil : v.joined(separator: ",")
    }
}

private func send(_ r: PreparedRequest, _ o: HTTPEngine.Options = defOpts, engine: HTTPEngine = HTTPEngine()) async -> (RunResult, String) {
    let res = await engine.send(runID: "r", r, o)
    let body = (try? await engine.data(runID: "r")).map { String(decoding: $0, as: UTF8.self) } ?? ""
    return (res, body)
}

@Test(arguments: HTTPMethod.all)
func httpMethods(method: String) async throws {
    let srv = try await TestHTTPServer(echo)
    defer { srv.stop() }
    let body = method == HTTPMethod.get || method == HTTPMethod.head ? Body() : Body(type: BodyType.text, raw: "x")
    let (res, text) = await send(PreparedRequest(method: method.lowercased(), url: srv.url + "/a?b=1", body: body))
    #expect(res.error == nil)
    #expect(res.status == 200 && res.statusText == "OK" && res.proto == "HTTP/1.1")
    #expect(res.header("X-Method") == method && res.header("X-Target") == "/a?b=1")
    #expect(text == (body.type.isEmpty ? "" : "x"))
}

/// Ověření z PLAN 4.1: tělo u GET.
@Test func httpGetWithBody() async throws {
    let srv = try await TestHTTPServer(echo)
    defer { srv.stop() }
    let (res, text) = await send(PreparedRequest(method: "GET", url: srv.url, body: Body(type: BodyType.text, raw: "x")))
    #expect(res.error?.code == .bodyNotAllowed && text == "")
    let (empty, _) = await send(PreparedRequest(method: "GET", url: srv.url, body: Body(type: BodyType.text)))
    #expect(empty.error == nil && empty.header("Echo-Content-Type") == nil)
}

@Test func httpHeaders() async throws {
    let srv = try await TestHTTPServer(echo)
    defer { srv.stop() }
    let h = [
        KV(name: "X-A", value: "1"), KV(name: "x-a", value: "2"), KV(name: "X-Off", value: "1", enabled: false),
        KV(name: "Host", value: "example.test"), KV(name: "Content-Length", value: "999"),
        KV(name: "Accept", value: "application/json"), KV(name: "Authorization", value: "Bearer t"),
    ]
    let (res, _) = await send(PreparedRequest(method: "GET", url: srv.url, headers: h))
    #expect(res.error == nil)
    #expect(res.header("Echo-X-A") == "1,2")
    #expect(res.header("Echo-X-Off") == nil)
    #expect(res.header("Echo-Host") == "127.0.0.1:\(srv.port)")
    #expect(res.header("Echo-Content-Length") == nil)
    #expect(res.header("Echo-Accept") == "application/json")
    #expect(res.header("Echo-User-Agent") == "MinorREST/test")
    #expect(res.header("Echo-Authorization") == "Bearer t")

    // Vypnuté automatické hlavičky: systém nesmí doplnit vlastní User-Agent.
    let (off, _) = await send(PreparedRequest(method: "GET", url: srv.url, noAuto: ["user-agent", "Accept"]))
    #expect(off.header("Echo-User-Agent") ?? "" == "")
    #expect(off.header("Echo-Accept") ?? "" == "")
}

@Test func httpBodies() async throws {
    let srv = try await TestHTTPServer(echo)
    defer { srv.stop() }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data("PNG".utf8).write(to: dir.appendingPathComponent("žluťoučký.png"))
    func post(_ b: Body, _ h: [KV] = []) async -> (RunResult, String) {
        await send(PreparedRequest(method: "POST", url: srv.url, headers: h, body: b, baseDir: dir.path))
    }

    var (res, text) = await post(Body(type: BodyType.json, raw: #"{"a":1}"#))
    #expect(res.header("Echo-Content-Type") == "application/json; charset=utf-8" && text == #"{"a":1}"#)
    #expect(res.header("Echo-Content-Length") == "7")

    (res, _) = await post(Body(type: BodyType.json, raw: "{}"), [KV(name: "content-type", value: "application/vnd.api+json")])
    #expect(res.header("Echo-Content-Type") == "application/vnd.api+json")

    (res, text) = await post(Body(type: BodyType.form, form: [
        KV(name: "z", value: "a b&c"), KV(name: "off", value: "x", enabled: false), KV(name: "a", value: "ř"),
    ]))
    #expect(text == "z=a+b%26c&a=%C5%99" && res.header("Echo-Content-Type") == "application/x-www-form-urlencoded")

    (res, text) = await post(Body(type: BodyType.multipart, multipart: [
        MultipartPart(name: "t", value: "hodnota"),
        MultipartPart(name: "f", kind: "file", path: "žluťoučký.png"),
    ]), [KV(name: "Content-Type", value: "multipart/form-data")])
    let ct = res.header("Echo-Content-Type") ?? ""
    let boundary = ct.components(separatedBy: "boundary=").last ?? ""
    #expect(ct.hasPrefix("multipart/form-data; boundary=") && !boundary.isEmpty)
    #expect(text == """
        --\(boundary)\r
        Content-Disposition: form-data; name="t"\r
        \r
        hodnota\r
        --\(boundary)\r
        Content-Disposition: form-data; name="f"; filename="žluťoučký.png"\r
        Content-Type: image/png\r
        \r
        PNG\r
        --\(boundary)--\r

        """)

    (res, text) = await post(Body(type: BodyType.binary, binaryPath: "žluťoučký.png"))
    #expect(text == "PNG" && res.header("Echo-Content-Type") == "image/png" && res.header("Echo-Content-Length") == "3")

    (res, _) = await post(Body(type: BodyType.binary, binaryPath: "nic.bin"))
    #expect(res.error?.code == .fileNotFound)
    (res, _) = await post(Body(type: BodyType.multipart, multipart: [MultipartPart(name: "f", kind: "file", path: "nic")]))
    #expect(res.error?.code == .fileNotFound)
}

@Test(arguments: [
    (false, 10, 302, 0, nil),
    (true, 10, 200, 3, nil),
    (true, 3, 200, 3, nil),
    (true, 2, 0, 3, ErrorCode.redirectLimit),
] as [(Bool, Int, Int, Int, ErrorCode?)])
func httpRedirects(follow: Bool, max: Int, status: Int, hops: Int, err: ErrorCode?) async throws {
    let srv = try await TestHTTPServer(redirector)
    defer { srv.stop() }
    let o = HTTPEngine.Options(followRedirects: follow, maxRedirects: max, timeoutMs: 5000)
    let (res, _) = await send(PreparedRequest(method: "GET", url: srv.url + "/r/3"), o)
    #expect(res.error?.code == err)
    #expect(res.status == status && res.redirects.count == hops)
}

/// 307 pošle metodu a tělo znovu (i ze souboru), 303 přepne POST na GET.
@Test func httpRedirectBody() async throws {
    let srv = try await TestHTTPServer(redirector)
    defer { srv.stop() }
    var (res, text) = await send(PreparedRequest(method: "POST", url: srv.url + "/r/2", body: Body(type: BodyType.text, raw: "data")))
    #expect(res.error == nil && text == "data" && res.header("X-Method") == "POST")
    #expect(res.redirects.first == Redirect(status: 307, method: "POST", url: srv.url + "/r/2", location: "/r/1"))

    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
    try Data("soubor".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    (res, text) = await send(PreparedRequest(method: "POST", url: srv.url + "/r/2", body: Body(type: BodyType.binary, binaryPath: file.path)))
    #expect(res.error == nil && text == "soubor")

    (res, text) = await send(PreparedRequest(method: "POST", url: srv.url + "/see", body: Body(type: BodyType.text, raw: "data")))
    #expect(res.error == nil && res.header("X-Method") == "GET" && text == "")
    #expect(res.sent.method == "GET" && res.sent.bodySize == 0 && res.redirects.first?.status == 303)
}

/// `/r/<n>`: n > 0 přesměruje na `/r/<n-1>` (POST 307, jinak 302), `/r/0` = echo, `/see` = 303 na `/r/0`.
@Sendable private func redirector(_ r: TestRequest) -> TestResponse {
    if r.target == "/see" { return TestResponse(status: 303, headers: [("Location", "/r/0")]) }
    let n = Int(r.target.split(separator: "/").last ?? "") ?? 0
    if n == 0 { return echo(r) }
    return TestResponse(status: r.method == "POST" ? 307 : 302, headers: [("Location", "/r/\(n - 1)")])
}

@Test func httpTimeoutCancel() async throws {
    let srv = try await TestHTTPServer { _ in TestResponse(delay: .seconds(3)) }
    defer { srv.stop() }
    let start = ContinuousClock.now
    var o = defOpts
    o.timeoutMs = 100
    let (res, _) = await send(PreparedRequest(method: "GET", url: srv.url), o)
    #expect(res.error?.code == .netTimeout)
    #expect(ContinuousClock.now - start < .seconds(2))

    let engine = HTTPEngine()
    Task {
        try await Task.sleep(for: .milliseconds(100))
        await engine.cancel(runID: "r")
    }
    let (canceled, _) = await send(PreparedRequest(method: "GET", url: srv.url), engine: engine)
    #expect(canceled.error?.code == .canceled)
}

@Test func httpErrors() async throws {
    let srv = try await TestHTTPServer(echo)
    let closed = srv.url
    srv.stop()
    try await Task.sleep(for: .milliseconds(50))
    let cases: [(String, String, ErrorCode)] = [
        ("GET", closed, .netRefused),
        ("GET", "http://neexistuje.invalid", .netDNS),
        ("GET", "ftp://example.com", .urlInvalid),
        ("GET", "/jen/cesta", .urlInvalid),
        ("BAD METHOD", "http://x.test", .methodInvalid),
    ]
    for (m, u, code) in cases {
        let (res, _) = await send(PreparedRequest(method: m, url: u))
        #expect(res.error?.code == code, "\(u): \(String(describing: res.error))")
    }
}

/// TLS proti veřejnému serveru s neplatným certifikátem – jen s `MINORREST_NET=1`.
@Test(.enabled(if: ProcessInfo.processInfo.environment["MINORREST_NET"] == "1"))
func httpTLSPublic() async {
    let r = PreparedRequest(method: "GET", url: "https://self-signed.badssl.com/")
    let (verified, _) = await send(r)
    #expect(verified.error?.code == .tlsVerify)
    var o = defOpts
    o.verifyTLS = false
    let (insecure, _) = await send(r, o)
    #expect(insecure.error == nil && insecure.status == 200)
    let tls = insecure.tls
    #expect(tls?.version.hasPrefix("TLS 1.") == true && tls?.cipher.hasPrefix("TLS_") == true, "\(String(describing: tls))")
    #expect(tls?.serverName == "self-signed.badssl.com" && tls?.subject.contains("CN=") == true && tls?.notAfter.isEmpty == false)
    #expect(insecure.timing.tlsMs > 0)
    let (h2, _) = await send(PreparedRequest(method: "GET", url: "https://www.google.com/"))
    #expect(h2.proto == "HTTP/2" || h2.proto == "HTTP/3")
}

import Foundation
import Testing
@testable import MinorRESTCore

private func req(_ method: String = "GET", _ url: String = "http://a/x", headers: [KV] = [], body: Body = Body()) -> PreparedRequest {
    PreparedRequest(method: method, url: url, headers: headers, body: body, baseDir: "/proj")
}

private let opts = HTTPEngine.Options(followRedirects: true, maxRedirects: 10, timeoutMs: 30_000, verifyTLS: true)

@Test(arguments: [
    (req(), "curl 'http://a/x' \\\n  -L --max-redirs 10 \\\n  --max-time 30 \\\n  --compressed"),
    (req("HEAD"), "curl --head 'http://a/x' \\\n  -L --max-redirs 10 \\\n  --max-time 30 \\\n  --compressed"),
    (req("POST", headers: [KV(name: "X-A", value: "it's $HOME!\\ ůž")], body: Body(type: BodyType.json, raw: "{\n \"k\": \"Příliš žluťoučký\"\n}")),
     "curl -X POST 'http://a/x' \\\n  -L --max-redirs 10 \\\n  --max-time 30 \\\n  --compressed \\\n  -H 'X-A: it'\\''s $HOME!\\ ůž' \\\n  -H 'Content-Type: application/json; charset=utf-8' \\\n  --data-raw '{\n \"k\": \"Příliš žluťoučký\"\n}'"),
    (req("POST", body: Body(type: BodyType.form, form: [KV(name: "q", value: "kůň & co"), KV(name: "off", value: "1", enabled: false)])),
     "curl -X POST 'http://a/x' \\\n  -L --max-redirs 10 \\\n  --max-time 30 \\\n  --compressed \\\n  --data-urlencode 'q=kůň & co'"),
    (req("PUT", body: Body(type: BodyType.multipart, multipart: [MultipartPart(name: "t", value: "@x;y"), MultipartPart(name: "f", kind: "file", path: "d/a.txt")])),
     "curl -X PUT 'http://a/x' \\\n  -L --max-redirs 10 \\\n  --max-time 30 \\\n  --compressed \\\n  --form-string 't=@x;y' \\\n  -F 'f=@/proj/d/a.txt;type=text/plain'"),
] as [(PreparedRequest, String)])
func curlGolden(_ p: PreparedRequest, _ expected: String) {
    #expect(Export.curl(p, options: opts) == expected)
}

@Test func curlOptionsAndMask() {
    var o = opts
    o.followRedirects = false
    o.verifyTLS = false
    o.timeoutMs = 1500
    let p = req("GET", "http://a/x?k=sekret", headers: [KV(name: "Authorization", value: "Bearer sekret"), KV(name: "X-Off", value: "1", enabled: false)])
    #expect(Export.curl(p, options: o, multiline: false)
            == "curl 'http://a/x?k=sekret' -k --max-time 1.5 --compressed -H 'Authorization: Bearer sekret'")
    #expect(Export.curl(p, options: o, multiline: false, mask: true, secrets: ["sekret"])
            == "curl 'http://a/x?k=***' -k --max-time 1.5 --compressed -H 'Authorization: Bearer ***'")
}

@Test func curlFromSaved() {
    var e = SavedResponse()
    e.request.method = "POST"
    e.request.url = "http://a/x"
    e.request.headers = [KV(name: "User-Agent", value: "MinorREST/1"), KV(name: "Content-Type", value: "application/json"), KV(name: "Authorization", value: "Bearer ***")]
    e.request.body = "{}"
    #expect(Export.curl(e, options: .init(followRedirects: false, timeoutMs: 0), multiline: false)
            == "curl -X POST 'http://a/x' --compressed -H 'Content-Type: application/json' -H 'Authorization: Bearer ***' --data-raw '{}'")
}

/// Zkopírovaný příkaz spuštěný v zsh i bash doručí stejné tělo a Content-Type jako aplikace.
@Test(arguments: ["/bin/zsh", "/bin/bash"], [true, false])
func curlRoundtrip(shell: String, multiline: Bool) async throws {
    let srv = try await TestHTTPServer(echo)
    defer { srv.stop() }
    let json = "{\n  \"k\": \"Příliš žluťoučký kůň úpěl ďábelské ódy\",\n  \"q\": \"it's $HOME ! \\\\ \\\"x\\\"\"\n}"
    let p = PreparedRequest(method: "POST", url: srv.url + "/r?a=1&b=č",
                            headers: [KV(name: "X-Custom", value: "a '$x' !")], body: Body(type: BodyType.json, raw: json))
    let o = HTTPEngine.Options(timeoutMs: 5000)
    let engine = HTTPEngine()
    let res = await engine.send(runID: "r", p, o)
    let appBody = try await engine.rawBody(runID: "r", limit: 1 << 20)

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: shell)
    // Příkaz jde přes stdin: argumenty `Process` Foundation převádí do NFD, terminál posílá NFC.
    proc.arguments = ["-s"]
    let inp = Pipe(), out = Pipe(), err = Pipe()
    proc.standardInput = inp
    proc.standardOutput = out
    proc.standardError = err
    try proc.run()
    inp.fileHandleForWriting.write(Data((Export.curl(p, options: o, multiline: multiline) + " -s -D /dev/stderr\n").utf8))
    try inp.fileHandleForWriting.close()
    let shellBody = out.fileHandleForReading.readDataToEndOfFile()
    let shellHead = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    proc.waitUntilExit()

    #expect(res.error == nil && shellBody == appBody && appBody == Data(json.utf8))
    for name in ["Echo-Content-Type", "Echo-X-Custom"] {
        let app = res.headers.first { $0.name == name }?.value
        let line = shellHead.split(separator: "\r\n").first { $0.lowercased().hasPrefix(name.lowercased() + ":") }
        #expect(app != nil && line?.dropFirst(name.count + 1).trimmingCharacters(in: .whitespaces) == app)
    }
}

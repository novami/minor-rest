import Foundation
import Synchronization
import Testing
@testable import MinorRESTCore

private let opts = HTTPEngine.Options(timeoutMs: 5000, userAgent: "MinorREST/test")
private let plain = "Příliš žluťoučký kůň úpěl ďábelské ódy. Příliš žluťoučký kůň úpěl ďábelské ódy."

/// gzip = hlavička + raw deflate + CRC32 + délka.
private func gzip(_ s: String) throws -> Data {
    let raw = Data(s.utf8)
    var out = Data([0x1F, 0x8B, 0x08, 0, 0, 0, 0, 0, 0, 0x03])
    out.append(try (raw as NSData).compressed(using: .zlib) as Data)
    var crc: UInt32 = 0xFFFF_FFFF
    for b in raw {
        crc ^= UInt32(b)
        for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
    }
    for v in [~crc, UInt32(raw.count)] { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
    return out
}

@Test func httpGzipSizes() async throws {
    let z = try gzip(plain)
    let srv = try await TestHTTPServer { _ in
        TestResponse(headers: [("Content-Encoding", "gzip"), ("Content-Type", "text/plain; charset=utf-8")], body: z)
    }
    defer { srv.stop() }
    let e = HTTPEngine()
    let res = await e.send(runID: "r", PreparedRequest(method: "GET", url: srv.url), opts)
    #expect(res.error == nil)
    #expect(try await e.body(runID: "r", pretty: false).text == plain)
    #expect(res.sizes.bodyWire == Int64(z.count) && res.sizes.bodyDecoded == Int64(plain.utf8.count))
}

@Test(arguments: [
    ("text/plain; charset=windows-1250", plain.data(using: .windowsCP1250)!, "text/plain", "windows-1250", false),
    ("text/html; charset=ISO-8859-2", Data("<p>x</p>".utf8), "text/html", "iso-8859-2", false),
    ("text/html", Data("<meta charset=\"windows-1250\"><p>".utf8) + plain.data(using: .windowsCP1250)!, "text/html", "windows-1250", false),
    ("application/json", Data(#"{"a":"ž"}"#.utf8), "application/json", "utf-8", false),
    ("", Data("ahoj ž".utf8), "", "utf-8", false),
    ("image/png", Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0]), "image/png", "", true),
    ("", Data([0, 1, 2]), "", "", true),
])
func httpCharset(ct: String, body: Data, mediaType: String, charset: String, binary: Bool) async throws {
    let srv = try await TestHTTPServer { _ in TestResponse(headers: ct.isEmpty ? [] : [("Content-Type", ct)], body: body) }
    defer { srv.stop() }
    let e = HTTPEngine()
    let res = await e.send(runID: "r", PreparedRequest(method: "GET", url: srv.url), opts)
    #expect(res.contentType == mediaType && res.charset == charset && res.isBinary == binary)
    let v = try await e.body(runID: "r", pretty: false)
    if charset == "windows-1250" { #expect(v.text.hasSuffix(plain)) }
    if mediaType == "application/json" { #expect(try await e.body(runID: "r", pretty: true).text == "{\n  \"a\": \"ž\"\n}") }
    if binary { #expect(v.text == "" && (v.image != nil) == mediaType.hasPrefix("image/")) }
}

@Test func httpSentTimingSizes() async throws {
    let got = Mutex<[String]>([])
    let srv = try await TestHTTPServer { r in
        got.withLock { $0 = r.headers.map { "\($0.name.lowercased()): \($0.value)" } }
        return echo(r)
    }
    defer { srv.stop() }
    let e = HTTPEngine()
    let url = "http://localhost:\(srv.port)/a?b=1"  // projde DNS
    let res = await e.send(runID: "r", PreparedRequest(method: "POST", url: url, headers: [KV(name: "X-Z", value: "1")],
                                                       body: Body(type: BodyType.json, raw: #"{"a":1}"#)), opts)
    #expect(res.error == nil)
    #expect(res.sent.method == "POST" && res.sent.url == url && res.sent.bodySize == 7)
    let sent = Set(res.sent.headers.map { "\($0.name.lowercased()): \($0.value)" })
    #expect(sent.isSuperset(of: got.withLock { $0 }), "odesláno \(sent), přijato \(got.withLock { $0 })")
    #expect(res.sent.headers.first { $0.name == "Host" }?.value == "localhost:\(srv.port)")
    #expect(res.sizes.reqBody == 7 && res.sizes.reqHeaders > 50 && res.sizes.headers > 50)
    #expect(!res.remoteAddr.isEmpty && !res.localAddr.isEmpty && res.remoteAddr.hasSuffix(":\(srv.port)"))
    let t = res.timing
    #expect(t.totalMs > 0 && t.totalMs >= t.ttfbMs + t.downloadMs && !t.reused && res.tls == nil, "\(t)")
}

@Test func httpBodyLimits() async throws {
    let big = Data(repeating: 0x61, count: ResponseBody.memLimit + 100)
    let srv = try await TestHTTPServer { _ in TestResponse(body: big) }
    defer { srv.stop() }
    let e = HTTPEngine()
    let res = await e.send(runID: "big", PreparedRequest(method: "GET", url: srv.url), opts)
    let path = try #require(try await e.stored("big").body.path)
    #expect(res.error == nil && !res.truncated && res.sizes.bodyDecoded == Int64(big.count))
    #expect(try await e.data(runID: "big") == big)
    let v = try await e.body(runID: "big", pretty: false)
    #expect(v.partial && v.text.utf8.count == BodyView.headView && v.size == Int64(big.count))
    let out = FileManager.default.temporaryDirectory.appending(path: "minorrest-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: out) }
    try await e.saveBody(runID: "big", to: out)
    #expect(try Data(contentsOf: out) == big)

    var o = opts
    o.maxBodyBytes = 5
    let small = await e.send(runID: "small", PreparedRequest(method: "GET", url: srv.url), o)
    #expect(small.error == nil && small.truncated && small.status == 200)
    #expect(try await e.data(runID: "small") == Data("aaaaa".utf8))

    // LRU: po 20 dalších výsledcích je první vyřazen a jeho temp soubor smazán.
    for i in 0..<HTTPEngine.keepResults {
        await e.keep("\(i)", .init(body: .data(Data()), contentType: "", charset: "", isBinary: false))
    }
    await #expect(throws: CoreError.self) { try await e.data(runID: "big") }
    #expect(!FileManager.default.fileExists(atPath: path.path))
    await e.close()
    await #expect(throws: CoreError.self) { try await e.data(runID: "0") }
}

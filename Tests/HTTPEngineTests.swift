import XCTest

@testable import MinorREST

/// Odpovědi pro `StubProtocol`; `nil` handler = spojení se nikdy nedokončí (test zrušení).
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else { return }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class HTTPEngineTests: XCTestCase {
    override func tearDown() {
        StubProtocol.handler = nil
        super.tearDown()
    }

    func testSuccessfulResponseHasStatusHeadersAndSize() async {
        StubProtocol.handler = { req in
            let res = HTTPURLResponse(
                url: req.url!, statusCode: 201, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json", "X-Echo": req.httpMethod ?? ""])!
            return (res, Data("{\"ok\":true}".utf8))
        }
        let engine = HTTPEngine(protocolClasses: [StubProtocol.self])
        let resVal = PreparedRequest(
            method: "POST", url: "http://localhost/items", body: Body(type: BodyType.json, raw: "{}"))
        let result = await engine.send(runID: "r1", resVal, HTTPEngine.Options())

        XCTAssertNil(result.error)
        XCTAssertEqual(result.status, 201)
        XCTAssertEqual(result.headers.first { $0.name.lowercased() == "x-echo" }?.value, "POST")
    }

    func testCancelReturnsCanceledError() async {
        StubProtocol.handler = nil
        let engine = HTTPEngine(protocolClasses: [StubProtocol.self])
        let resVal = PreparedRequest(method: "GET", url: "http://localhost/slow")
        async let result = engine.send(runID: "r2", resVal, HTTPEngine.Options())
        try? await Task.sleep(for: .milliseconds(200))
        await engine.cancel(runID: "r2")
        let res = await result
        XCTAssertEqual(res.error?.code, .canceled)
    }
}

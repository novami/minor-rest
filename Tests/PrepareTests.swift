import XCTest

@testable import MinorREST

final class PrepareTests: XCTestCase {
    func testBuildsRequestWithVariablesQueryHeadersAndBody() async throws {
        let request = Request(
            method: "POST", url: "{{base}}/users/:id",
            params: Params(query: [KV(name: "q", value: "a b")], path: [PathParam(name: "id", value: "42")]),
            headers: [KV(name: "X-Trace", value: "{{trace}}"), KV(name: "X-Off", value: "no", enabled: false)],
            body: Body(type: BodyType.json, raw: "{\"n\":1}"))
        let input = PrepareInput(
            request: request,
            environment: [
                Var(name: "base", value: "http://localhost:8080"),
                Var(name: "trace", value: "t-1")
            ])
        let out = try await Prepare.prepare(input)

        XCTAssertEqual(out.request.method, "POST")
        XCTAssertTrue(out.request.url.hasPrefix("http://localhost:8080/users/42?q=a"), out.request.url)
        XCTAssertEqual(out.request.headers.first { $0.name == "X-Trace" }?.value, "t-1")
        XCTAssertNil(out.request.headers.first { $0.name == "X-Off" })
        XCTAssertEqual(out.request.body.raw, "{\"n\":1}")
        XCTAssertTrue(out.unresolved.isEmpty)
    }

    func testReportsUnresolvedVariable() async throws {
        let input = PrepareInput(request: Request(method: "GET", url: "http://localhost/{{missing}}"))
        let out = try await Prepare.prepare(input)
        XCTAssertEqual(out.unresolved, ["missing"])
    }
}

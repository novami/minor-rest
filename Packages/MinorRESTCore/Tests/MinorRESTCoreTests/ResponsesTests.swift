import Foundation
import Testing
@testable import MinorRESTCore

@Test func savedResponsesVersions() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "mr-resp-\(ULID.make())/R1")
    defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
    let s = Responses(dir: dir)
    var r = RunResult(runID: "r")
    r.status = 201
    let e = SavedResponse(r, request: PreparedRequest(method: "POST", url: "http://a/"), secrets: [])

    #expect(s.list().isEmpty)
    let v1 = try s.save(e, body: Data("{\"a\":1}".utf8))
    let v2 = try s.save(e, body: nil, label: "po opravě")
    let v3 = try s.save(e, body: Data("x".utf8))
    #expect([v1.version, v2.version, v3.version] as [Int] == [1, 2, 3])
    #expect(s.list().map(\.version) == [3, 2, 1])
    #expect(s.list()[2].bodySize == 7 && s.list()[1].label == "po opravě" && s.list()[0].status == 201)
    #expect(try s.body(1) == Data("{\"a\":1}".utf8))

    try s.setLabel(1, "první")
    #expect(try s.get(1).label == "první" && s.get(1).version == 1)
    try s.delete(2)
    #expect(s.list().map(\.version) == [3, 1])
    #expect((try? s.get(2)) == nil)
    #expect(try s.save(e, body: nil).version == 4)
}

@Test(arguments: [
    (["a", "b", "c"], ["a", "x", "c", "d"], "  a\n- b\n+ x\n  c\n+ d"),
    (["a"], ["a"], "@@ 1 @@"),
    ([], ["n"], "+ n"),
    (["1", "2", "3", "4", "5", "6", "7", "8", "9"], ["1", "2", "3", "4", "5", "6", "7", "8", "X"], "@@ 5 @@\n  6\n  7\n  8\n- 9\n+ X"),
])
func lineDiff(_ a: [String], _ b: [String], _ expected: String) {
    #expect(LineDiff.render(LineDiff.diff(a, b)) == expected)
}

@Test func extractorRules() {
    let rules = [
        Extract(name: "token", from: "body", path: "$.data.token"),
        Extract(name: "id", from: "body", path: "$.data.id"),
        Extract(name: "obj", from: "body", path: "$.data.o"),
        Extract(name: "loc", from: "header", path: "location"),
        Extract(name: "miss", from: "body", path: "$.nope"),
        Extract(name: "off", from: "body", path: "$.data.id", enabled: false),
    ]
    let out = Extractor.run(rules, body: #"{"data":{"token":"abc","id":7,"o":{"a":1}}}"#, headers: [KV(name: "Location", value: "/x")])
    #expect(out.values.map(\.name) == ["token", "id", "obj", "loc"])
    #expect(out.values.map(\.value) == ["abc", "7", #"{"a":1}"#, "/x"])
    #expect(out.warnings.count == 1 && out.warnings[0].hasPrefix("miss"))
    #expect(Extractor.run([rules[0]], body: "není json", headers: []).warnings.count == 1)
}

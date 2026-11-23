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

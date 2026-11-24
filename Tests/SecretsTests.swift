import XCTest

@testable import MinorREST

final class SecretsTests: XCTestCase {
    func testTokenIsStoredInKeychainNotInRequestFile() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "minorrest-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MemorySecrets()
        let project = try Project.create(name: "Demo", in: dir)
        project.secrets = store
        let node = try project.createRequest(parent: "", name: "Login")

        var request = try project.loadRequest(node.rel)
        request.auth = Auth(type: AuthType.bearer, bearer: BearerAuth(token: "s3cr3t-token"))
        request.headers = [KV(name: "Authorization", value: "Bearer abc123"), KV(name: "Accept", value: "*/*")]
        try project.saveRequest(node.rel, request)

        let files = try FileManager.default.subpathsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".req.yaml") }
        let yaml = try files.map { try String(contentsOf: dir.appending(path: $0), encoding: .utf8) }.joined()
        XCTAssertFalse(yaml.contains("s3cr3t-token"))
        XCTAssertFalse(yaml.contains("abc123"))
        XCTAssertTrue(yaml.contains(RequestSecrets.marker))
        XCTAssertEqual(store.all.count, 2)

        let loaded = try project.loadRequest(node.rel)
        XCTAssertEqual(loaded.auth.bearer?.token, "s3cr3t-token")
        XCTAssertEqual(loaded.headers.first?.value, "Bearer abc123")
    }

    func testLegacyPlaintextIsMigrated() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "minorrest-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MemorySecrets()
        let project = try Project.create(name: "Demo", in: dir)
        project.secrets = MemorySecrets()
        let node = try project.createRequest(parent: "", name: "Old")
        var request = try project.loadRequest(node.rel)
        request.auth = Auth(type: AuthType.basic, basic: BasicAuth(username: "u", password: "plain-pass"))
        let file = try XCTUnwrap(
            FileManager.default.subpathsOfDirectory(atPath: dir.path)
                .first { $0.hasSuffix(".req.yaml") })
        try FileIO.writeYAML(request, to: dir.appending(path: file))

        project.secrets = store
        project.migrateSecrets()

        XCTAssertFalse(try String(contentsOf: dir.appending(path: file), encoding: .utf8).contains("plain-pass"))
        XCTAssertEqual(try project.loadRequest(node.rel).auth.basic?.password, "plain-pass")
    }
}

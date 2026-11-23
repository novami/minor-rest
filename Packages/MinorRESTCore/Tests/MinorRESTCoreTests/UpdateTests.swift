import CryptoKit
import Foundation
import Testing
@testable import MinorRESTCore

@Test(arguments: [("1.2.3", true), ("0.0.0", true), ("v1.2.3", false), ("1.2", false), ("1.2.3-beta", false), ("1.x.3", false)] as [(String, Bool)])
func versionParsing(_ s: String, _ valid: Bool) {
    #expect((AppVersion(s) != nil) == valid)
}

@Test func versionOrdering() {
    #expect(AppVersion("0.10.0")! > AppVersion("0.9.9")!)
    #expect(AppVersion("0.0.0")!.isDevelopment)
}

private struct FakeLoader: DataLoader {
    var responses: [String: (Int, Data, [String: String])]
    func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        guard let r = responses[url.lastPathComponent] ?? responses[url.absoluteString] else { throw URLError(.notConnectedToInternet) }
        return (r.1, HTTPURLResponse(url: url, statusCode: r.0, httpVersion: nil, headerFields: r.2)!)
    }
}

private func feed(_ version: String, url: String = "https://github.com/o/r/z.zip") -> Data {
    Data(#"{"version":"\#(version)","url":"\#(url)","sha256":"ab","signature":"cw==","notes":"n"}"#.utf8)
}

@Test func checkerFindsNewerOnly() async throws {
    func check(_ data: Data, current: String) async throws -> UpdateInfo? {
        let loader = FakeLoader(responses: ["appcast.json": (200, data, [:])])
        return try await UpdateChecker(feedURL: URL(string: "https://x/appcast.json")!, current: AppVersion(current)!, loader: loader).check()
    }
    #expect(try await check(feed("1.2.0"), current: "1.1.9")?.version == AppVersion(1, 2, 0))
    #expect(try await check(feed("1.2.0"), current: "1.2.0") == nil)
    await #expect(throws: CoreError.self) { try await check(feed("1.2.0", url: "http://x/z.zip"), current: "1.0.0") }
    await #expect(throws: CoreError.self) { try await check(Data("{}".utf8), current: "1.0.0") }
}

@Test func verifyChecksHashAndSignedMessage() throws {
    let key = Curve25519.Signing.PrivateKey()
    let installer = try UpdateInstaller(publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString(),
                                        bundleID: "app.test", workDir: FileManager.default.temporaryDirectory)
    let zip = Data("zip-bytes".utf8)
    let hex = SHA256.hash(data: zip).map { String(format: "%02x", $0) }.joined()
    func info(version: String = "1.0.1", sha: String = hex, signedFor app: String = "app.test") throws -> UpdateInfo {
        let msg = UpdateInstaller.signedMessage(appID: app, version: version, sha256: hex)
        return UpdateInfo(version: AppVersion(version)!, notes: "", url: URL(string: "https://x/z.zip")!, sha256: sha,
                          signature: try key.signature(for: msg).base64EncodedString())
    }
    try installer.verify(zip: zip, info: info())
    #expect(throws: CoreError.self) { try installer.verify(zip: Data("tampered".utf8), info: info()) }       // otisk nesedí
    #expect(throws: CoreError.self) { try installer.verify(zip: zip, info: info(signedFor: "other.app")) }   // podpis pro jinou aplikaci
    var wrongVersion = try info()
    wrongVersion.version = AppVersion(9, 9, 9)
    #expect(throws: CoreError.self) { try installer.verify(zip: zip, info: wrongVersion) }                   // downgrade/záměna verze
    #expect(throws: CoreError.self) { try UpdateInstaller(publicKeyBase64: "", bundleID: "x", workDir: .temporaryDirectory) }
}

@Test func swapReplacesAndRollsBack() throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: dir) }
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let cur = dir.appendingPathComponent("A.app"), new = dir.appendingPathComponent("new.app")
    try "old".write(to: cur, atomically: true, encoding: .utf8)
    try "new".write(to: new, atomically: true, encoding: .utf8)
    try UpdateInstaller.swap(current: cur, with: new)
    #expect(try String(contentsOf: cur, encoding: .utf8) == "new")
    #expect(!fm.fileExists(atPath: cur.path + ".old"))
    // chybějící nový bundle → původní zůstane
    #expect(throws: CoreError.self) { try UpdateInstaller.swap(current: cur, with: dir.appendingPathComponent("missing.app")) }
    #expect(try String(contentsOf: cur, encoding: .utf8) == "new")
}

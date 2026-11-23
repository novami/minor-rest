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

private func release(_ tag: String, prerelease: Bool = false, assets: Bool = true) -> Data {
    let a = assets ? """
    [{"name":"MinorREST-\(tag)-macos-arm64.zip","browser_download_url":"https://github.com/o/r/z.zip","size":10},
     {"name":"MinorREST-\(tag)-macos-arm64.zip.sig","browser_download_url":"https://github.com/o/r/z.sig","size":10}]
    """ : "[]"
    return Data("""
    {"tag_name":"\(tag)","draft":false,"prerelease":\(prerelease),"body":"n","html_url":"https://github.com/o/r/releases/1","assets":\(a)}
    """.utf8)
}

@Test func checkerFindsNewerOnly() async throws {
    func check(_ data: Data, current: String) async throws -> UpdateInfo? {
        let loader = FakeLoader(responses: ["latest": (200, data, ["ETag": "x"])])
        return try await UpdateChecker(repo: "o/r", current: AppVersion(current)!, loader: loader).check()
    }
    #expect(try await check(release("1.2.0"), current: "1.1.9")?.version == AppVersion(1, 2, 0))
    #expect(try await check(release("1.2.0"), current: "1.2.0") == nil)
    #expect(try await check(release("1.2.0", prerelease: true), current: "1.0.0") == nil)
    await #expect(throws: CoreError.self) { try await check(release("1.2.0", assets: false), current: "1.0.0") }
}

@Test func signatureVerification() throws {
    let key = Curve25519.Signing.PrivateKey()
    let installer = try UpdateInstaller(publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString(),
                                        bundleID: "x", workDir: FileManager.default.temporaryDirectory)
    let zip = Data("zip-bytes".utf8)
    let sig = try key.signature(for: zip).base64EncodedString()
    try installer.verify(zip: zip, signatureBase64: sig + "\n")
    #expect(throws: CoreError.self) { try installer.verify(zip: Data("tampered".utf8), signatureBase64: sig) }
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

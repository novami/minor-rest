import XCTest

@testable import MinorREST

final class AppSettingsTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "minorrest-settings-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testMissingFileGivesDefaultsAndRoundTrips() throws {
        let dir = tempDir()
        XCTAssertEqual(try AppSettings.load(from: dir), AppSettings())
        var set = AppSettings()
        set.general.language = "en"
        set.requests.timeoutMs = 5_000
        set.responses.historyLimit = 50
        set.copy.maskSecrets = true
        try set.save(to: dir)
        XCTAssertEqual(try AppSettings.load(from: dir), set)
        XCTAssertEqual(set.requests.http.timeoutMs, 5_000)
    }

    func testPartialFileKeepsDefaultsAndInvalidValuesAreReplaced() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let text = "general:\n  language: xx\nrequests:\n  verifyTLS: false\nresponses:\n  historyLimit: 0\n"
        try text.write(to: dir.appending(path: AppSettings.file), atomically: true, encoding: .utf8)
        let set = try AppSettings.load(from: dir)
        XCTAssertEqual(set.general.language, "auto")
        XCTAssertFalse(set.requests.verifyTLS)
        XCTAssertEqual(set.requests.timeoutMs, 30_000)
        XCTAssertEqual(set.responses.historyLimit, 200)
    }

    func testProjectsDirectory() {
        var set = AppSettings()
        XCTAssertEqual(set.general.projectsDirectory, Workspace.defaultProjectsDirectory)
        set.general.projectsDir = "/tmp/projects"
        XCTAssertEqual(set.general.projectsDirectory.path, "/tmp/projects")
    }
}

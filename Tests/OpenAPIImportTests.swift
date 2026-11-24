import XCTest

@testable import MinorREST

final class OpenAPIImportTests: XCTestCase {
    private func spec(_ name: String) async throws -> APISpec {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = dir.appending(path: "Fixtures/OpenAPI/\(name)")
        return try await OpenAPIImport.load(source: url)
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "minorrest-import-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func requestFiles(_ project: ProjectInfo) -> Int {
        let files = FileManager.default.enumerator(atPath: project.path)?.allObjects as? [String] ?? []
        return files.filter { $0.hasSuffix(".req.yaml") }.count
    }

    func testPetstoreProjectHasFoldersAndBaseUrl() async throws {
        for name in ["petstore2.json", "petstore3.yaml"] {
            let spec = try await spec(name)
            let result = try OpenAPIImport.importProject(spec, in: try tempDir(), secrets: MemorySecrets())
            XCTAssertGreaterThan(result.requestCount, 0, name)
            XCTAssertEqual(requestFiles(result.project), result.requestCount, name)
            let project = try Project.open(URL(fileURLWithPath: result.project.path))
            let env = try project.listEnvironments().first { $0.id == result.environmentID }
            XCTAssertEqual(env?.name, "Default", name)
            XCTAssertFalse(env?.vars.first { $0.name == "baseUrl" }?.value.isEmpty ?? true, name)
        }
    }

    func testImportIntoExistingProjectCreatesFolder() async throws {
        let spec = try await spec("petstore3.yaml")
        let project = try Project.create(name: "Existing", in: try tempDir())
        let result = try OpenAPIImport.importFolder(spec, into: project)
        XCTAssertEqual(requestFiles(project.info), result.requestCount)
    }

    func testCyclicSchemaDoesNotHang() async throws {
        let spec = try await spec("cycle31.yaml")
        XCTAssertFalse(spec.operations.isEmpty)
    }
}

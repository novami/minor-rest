import XCTest

@testable import MinorREST

@MainActor
final class ImportSessionTests: XCTestCase {
    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/OpenAPI/\(name)")
    }

    func testLoadFileShowsPreview() async throws {
        let session = ImportSession()
        await session.load(fixture("petstore3.yaml"))
        XCTAssertEqual(session.step, .preview)
        XCTAssertNil(session.error)
        let preview = try XCTUnwrap(session.preview)
        XCTAssertGreaterThan(preview.requestCount, 0)
        XCTAssertEqual(session.name, preview.title)
        session.grouping = .pathSegment
        XCTAssertNotEqual(session.preview?.folders, preview.folders)
    }

    func testInvalidSourceKeepsSourceStep() async {
        let session = ImportSession()
        await session.load(fixture("missing.yaml"))
        XCTAssertEqual(session.step, .source)
        XCTAssertNotNil(session.error)
        session.urlText = "not a url"
        await session.loadURLText()
        XCTAssertNotNil(session.error)
    }
}

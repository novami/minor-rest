import Foundation
import Testing
@testable import MinorRESTCore

@Test(arguments: [
    ("/p/a/b.req.yaml", "a/b.req.yaml"),
    ("/p/a", "a"),
    ("/p", nil),
    ("/p/", nil),
    ("/other/x", nil),
    ("/px/a", nil),
    ("/p/.git/HEAD", nil),
    ("/p/.responses/x/1.yaml", nil),
    ("/p/a/.tmp-123", nil),
] as [(String, String?)])
func watcherRelativePath(path: String, want: String?) {
    #expect(ProjectWatcher.relativePath(root: "/p", path: path) == want)
}

/// Sběr hlášení z watcheru.
private final class Changes: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [[String]?] = []
    func append(_ rels: [String]?) { lock.withLock { items.append(rels) } }
    var all: [[String]?] { lock.withLock { items } }

    /// Počká na první hlášení (nejdéle `seconds`).
    func first(within seconds: Double) async -> [String]?? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let item = all.first { return item }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }
}

private func watch(_ tmp: TempDir, ignoreSelf: Bool) async -> (ProjectWatcher, Changes) {
    let changes = Changes()
    let watcher = ProjectWatcher(ignoreSelf: ignoreSelf) { _, rels in changes.append(rels) }
    watcher.add(id: "p", root: tmp.url)
    try? await Task.sleep(for: .milliseconds(200)) // stream se rozbíhá
    return (watcher, changes)
}

@Test func watcherReportsChanges() async throws {
    let tmp = TempDir()
    let (watcher, changes) = await watch(tmp, ignoreSelf: false)
    try Data("x".utf8).write(to: tmp.url.appending(path: ".tmp-1"))
    try Data("x".utf8).write(to: tmp.url.appending(path: "a.req.yaml"))
    let rels = await changes.first(within: 3)
    #expect(rels == .some(["a.req.yaml"]))
    watcher.remove(id: "p")
}

@Test func watcherIgnoresSelf() async throws {
    let tmp = TempDir()
    let (watcher, changes) = await watch(tmp, ignoreSelf: true)
    try Data("x".utf8).write(to: tmp.url.appending(path: "a.req.yaml"))
    #expect(await changes.first(within: 1) == nil)
    watcher.remove(id: "p")
}

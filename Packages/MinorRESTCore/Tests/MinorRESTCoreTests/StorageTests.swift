import Foundation
import Testing
@testable import MinorRESTCore

/// Dočasný adresář smazaný po testu.
final class TempDir: @unchecked Sendable {
    let url: URL
    init() {
        url = FileManager.default.temporaryDirectory.appending(path: "minorrest-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
    func sub(_ name: String) -> URL {
        let u = url.appending(path: name)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}

/// Projekt v dočasném adresáři; Koš nahrazuje přesun do `trash/`.
private func newProject(_ tmp: TempDir) throws -> Project {
    let trash = tmp.sub("trash")
    return try Project.create(name: "Můj projekt", in: tmp.sub("projects")) { url in
        try FileManager.default.moveItem(at: url, to: trash.appending(path: UUID().uuidString + "-" + url.lastPathComponent))
    }
}

private func names(_ nodes: [TreeNode]) -> String { nodes.map(\.name).joined(separator: ",") }

private func code(_ body: () throws -> Void) -> ErrorCode? {
    do { try body() } catch let e as CoreError { return e.code } catch { return nil }
    return nil
}

private func write(_ text: String, to url: URL) throws {
    try Data(text.utf8).write(to: url)
}

@Suite struct StorageTests {
    @Test func createAndTree() throws {
        let tmp = TempDir()
        let p = try newProject(tmp)
        #expect(p.root.lastPathComponent == "muj-projekt")
        #expect(try String(contentsOf: p.root.appending(path: ".gitignore"), encoding: .utf8) == ".responses/\n")

        let f = try p.createFolder(parent: "", name: "Uživatelé")
        _ = try p.createFolder(parent: f.rel, name: "Detail")
        let r = try p.createRequest(parent: f.rel, name: "Seznam")
        _ = try p.createRequest(parent: f.rel, name: "Seznam") // kolize → seznam-2
        _ = try p.createRequest(parent: "", name: "Kořenový")
        try FileManager.default.createDirectory(at: p.root.appending(path: "bez-configu"), withIntermediateDirectories: false)
        try write("name: [x", to: p.root.appending(path: "rozbity.req.yaml"))

        #expect(r.rel == "uzivatele/seznam.req.yaml" && !r.id.isEmpty && r.method == "GET")
        var req = try p.loadRequest(r.rel)
        req.url = "{{base}}/users"
        try p.saveRequest(r.rel, req)

        let tree = try p.loadTree()
        #expect(names(tree.children) == "Uživatelé,Kořenový,rozbity")
        #expect(tree.children[2].error == "YAML_INVALID")
        let u = tree.children[0]
        #expect(names(u.children) == "Detail,Seznam,Seznam")
        #expect(u.children[2].rel == "uzivatele/seznam-2.req.yaml" && u.children[1].url == "{{base}}/users")

        let q = try Project.open(p.root)
        #expect(q.info.id == p.info.id && !q.readOnly)
    }

    @Test func renameMoveDuplicateDelete() throws {
        let tmp = TempDir()
        let p = try newProject(tmp)
        let a = try p.createFolder(parent: "", name: "A")
        var b = try p.createFolder(parent: "", name: "B")
        var r1 = try p.createRequest(parent: a.rel, name: "Jedna")
        _ = try p.createRequest(parent: b.rel, name: "Dva")
        _ = try p.createRequest(parent: b.rel, name: "Tři")

        r1 = try p.rename(r1.rel, to: "Příliš žluťoučký kůň")
        #expect(r1.rel == "a/prilis-zlutoucky-kun.req.yaml" && r1.name == "Příliš žluťoučký kůň")
        b = try p.rename(b.rel, to: "Béčko")
        #expect(b.rel == "becko" && b.children.count == 2)

        r1 = try p.move(r1.rel, to: b.rel, index: 0)
        #expect(r1.rel == "becko/prilis-zlutoucky-kun.req.yaml")
        let kids = try p.loadTree().children[1].children
        #expect(names(kids) == "Příliš žluťoučký kůň,Dva,Tři")
        #expect(kids.map(\.seq) == [1, 2, 3])
        _ = try p.move(r1.rel, to: b.rel, index: 99)
        #expect(names(try p.loadTree().children[1].children) == "Dva,Tři,Příliš žluťoučký kůň")
        #expect(code { _ = try p.move(b.rel, to: b.rel, index: 0) } == .moveIntoSelf)

        let d = try p.duplicate(a.rel)
        #expect(d.name == "A kopie" && d.rel == "a-kopie")
        let dup = try p.duplicate("becko/dva.req.yaml", copySuffix: " copy")
        let tree = try p.loadTree()
        #expect(names(tree.children) == "A,A kopie,Béčko")
        #expect(names(tree.children[2].children) == "Dva,Dva copy,Tři,Příliš žluťoučký kůň")
        let orig = try p.loadRequest("becko/dva.req.yaml")
        #expect(!dup.id.isEmpty && dup.id != orig.id)

        // request se stejným ID (kopie z Finderu): smazáním jednoho se odpovědi nesmažou
        let finderCopy = try p.createRequest(parent: a.rel, name: "Kopie z Finderu")
        var fc = try p.loadRequest(finderCopy.rel)
        fc.id = orig.id
        try FileIO.writeYAML(fc, to: p.root.appending(path: finderCopy.rel))
        let resp = p.root.appending(path: ".responses/\(orig.id)")
        try FileManager.default.createDirectory(at: resp, withIntermediateDirectories: true)
        try p.delete("becko/dva.req.yaml")
        #expect(FileIO.exists(resp))
        try p.delete(finderCopy.rel)

        let tri = try p.loadRequest("becko/tri.req.yaml")
        let triResp = p.root.appending(path: ".responses/\(tri.id)")
        try FileManager.default.createDirectory(at: triResp, withIntermediateDirectories: true)
        try p.delete("becko")
        #expect(!FileIO.exists(p.root.appending(path: "becko")) && !FileIO.exists(triResp))
    }

    @Test func duplicatedFolderGetsNewRequestIDs() throws {
        let tmp = TempDir()
        let p = try newProject(tmp)
        let a = try p.createFolder(parent: "", name: "A")
        let r = try p.createRequest(parent: a.rel, name: "R")
        let d = try p.duplicate(a.rel)
        let copy = try p.loadRequest("\(d.rel)/r.req.yaml")
        #expect(copy.id != r.id && !copy.id.isEmpty && copy.name == "R")
        #expect(try p.loadFolderConfig(d.rel).name == "A kopie")
    }

    @Test func saveRequestAndGuards() throws {
        let tmp = TempDir()
        let p = try newProject(tmp)
        let n = try p.createRequest(parent: "", name: "X")
        var r = try p.loadRequest(n.rel)
        let id = r.id
        r.url = "{{baseUrl}}/a"
        r.id = "JINE"
        r.name = "Zastaralý název z tabu"
        r.seq = 9 // identitu drží strom
        try p.saveRequest(n.rel, r)
        let got = try p.loadRequest(n.rel)
        #expect(got.url == r.url && got.id == id && got.name == "X" && got.seq == 1)

        for rel in ["../venku.req.yaml", "/abs.req.yaml", "a/../b.req.yaml", "a//b.req.yaml"] {
            #expect(code { _ = try p.loadRequest(rel) } == .pathInvalid, "\(rel)")
        }
        #expect(code { try p.saveRequest("neni.req.yaml", r) } == .notFound)
        #expect(code { _ = try p.createFolder(parent: "", name: "  ") } == .nameEmpty)
        #expect(try p.createFolder(parent: "", name: "Environments").rel == "environments-2")

        var cfg = p.config
        cfg.formatVersion = ProjectFormat.version + 1
        try FileIO.writeYAML(cfg, to: p.root.appending(path: ProjectFormat.projectFile))
        let q = try Project.open(p.root)
        #expect(q.readOnly)
        #expect(code { _ = try q.createRequest(parent: "", name: "Y") } == .projectReadOnly)

        cfg.ignoreResponsesInGit = false
        try p.saveConfig(cfg)
        #expect(try String(contentsOf: p.root.appending(path: ".gitignore"), encoding: .utf8).isEmpty)
        #expect(p.config.formatVersion == ProjectFormat.version) // formatVersion se nepřepíše
    }

    @Test func registry() async throws {
        let tmp = TempDir()
        let p = try newProject(tmp)
        let reg = ProjectRegistry()
        let a = try await reg.open(p.root)
        let b = try await reg.open(URL(fileURLWithPath: p.root.path + "/"))
        let count = await reg.list().count
        #expect(a === b && count == 1)
        do { _ = try await reg.open(tmp.sub("prazdny")); Issue.record("non-project opened") } catch let e as CoreError {
            #expect(e.code == .projectInvalid)
        }
        let id = a.info.id
        try await reg.close(id)
        let paths = await reg.paths()
        #expect(paths.isEmpty)
        do { _ = try await reg.project(id); Issue.record("closed project found") } catch let e as CoreError {
            #expect(e.code == .notFound)
        }
    }

    @Test func initProject() throws {
        let tmp = TempDir()
        let dir = tmp.sub("existing")
        try write("x", to: dir.appending(path: "readme.txt"))
        let p = try Project.initProject(at: dir, name: "Stávající")
        #expect(Project.isProjectDir(dir) && p.info.name == "Stávající")
        #expect(code { _ = try Project.initProject(at: dir, name: "Znovu") } == .projectInvalid)
    }

    @Test func duplicateIDFixedOnLoad() throws {
        let tmp = TempDir()
        let p = try newProject(tmp)
        let r = try p.createRequest(parent: "", name: "A")
        let data = try Data(contentsOf: p.root.appending(path: r.rel))
        Thread.sleep(forTimeInterval: 0.02)
        try data.write(to: p.root.appending(path: "kopie.req.yaml")) // kopie z Finderu

        let ids = Dictionary(uniqueKeysWithValues: try p.loadTree().children.map { ($0.rel, $0.id) })
        #expect(ids[r.rel] == r.id)
        #expect(ids["kopie.req.yaml"] != r.id && ids["kopie.req.yaml"]?.isEmpty == false)
        #expect(try p.loadRequest("kopie.req.yaml").id == ids["kopie.req.yaml"])
    }

    @Test func fileRef() throws {
        let tmp = TempDir()
        let p = try newProject(tmp)
        let outside = tmp.url.appending(path: "x.bin").path
        #expect(p.fileRef(p.root.appending(path: "data/foto.jpg").path) == "data/foto.jpg")
        #expect(p.fileRef(outside) == outside)
        #expect(p.fileRef(p.root.path + "-jiny/a.txt") == p.root.path + "-jiny/a.txt")
        // /var → /private/var: symlink v cestě nesmí rozbít relativní odkaz
        let viaSymlink = p.root.path.replacingOccurrences(of: "/private/var/", with: "/var/")
        #expect(p.fileRef(viaSymlink + "/data/a.txt") == "data/a.txt")
    }

    @Test func workspaceRoundtrip() throws {
        let tmp = TempDir()
        #expect(try Workspace.load(from: tmp.url) == Workspace())
        var w = Workspace()
        w.projects = ["/a/Projekt č. 1", "/b"]
        w.activeProject = "P1"
        w.expanded = ["P1": ["uzivatele", "uzivatele/detail"], "P2": []]
        w.tabs = ["P1": ["R1", "R2"]]
        w.activeTab = ["P1": "R2"]
        w.sidebarHidden = true
        w.sidebarWidth = 300
        try w.save(to: tmp.url)
        #expect(try Workspace.load(from: tmp.url) == w)
        try write("sidebarWidth: 0\n", to: tmp.url.appending(path: Workspace.file))
        #expect(try Workspace.load(from: tmp.url).sidebarWidth == Workspace.defaultSidebarWidth)
    }
}

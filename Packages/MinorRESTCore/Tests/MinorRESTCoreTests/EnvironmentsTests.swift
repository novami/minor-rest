import Foundation
import Testing
@testable import MinorRESTCore

private func newProject(_ tmp: TempDir) throws -> Project {
    let trash = tmp.sub("trash")
    return try Project.create(name: "P", in: tmp.sub("projects")) { url in
        try FileManager.default.moveItem(at: url, to: trash.appending(path: UUID().uuidString + "-" + url.lastPathComponent))
    }
}

private func files(_ dir: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
}

@Suite struct EnvironmentsTests {
    @Test func crudWithSecrets() throws {
        let tmp = TempDir()
        let p = try newProject(tmp)
        let store = MemorySecrets()
        let dir = p.root.appending(path: "environments")

        var env = try p.saveEnvironment(EnvironmentConfig(name: "Vývoj", vars: [
            Var(name: "baseUrl", value: "http://localhost:8080"),
            Var(name: "apiKey", value: "tajne-123", secret: true),
        ]), secrets: store)
        let pid = p.info.id
        #expect(!env.id.isEmpty)
        #expect(files(dir) == ["vyvoj.yaml"])
        let yaml = try String(contentsOf: dir.appending(path: "vyvoj.yaml"), encoding: .utf8)
        #expect(!yaml.contains("tajne-123"))
        #expect(yaml.contains("secret: true"))
        #expect(store.all == ["\(pid)/\(env.id)/apiKey": "tajne-123"])

        let listed = try p.listEnvironments()
        #expect(listed.map(\.name) == ["Vývoj"])
        #expect(listed[0].vars[1].value == "")
        #expect(try store.fill(listed[0].vars, account: p.secretAccount(envID: env.id)) == env.vars)

        // přejmenování prostředí i tajné proměnné
        env.name = "Produkce"
        env.vars[1].name = "token"
        try p.saveEnvironment(env, secrets: store)
        #expect(files(dir) == ["produkce.yaml"])
        #expect(store.all == ["\(pid)/\(env.id)/token": "tajne-123"])
        #expect(try p.listEnvironments().map(\.id) == [env.id])

        // druhé prostředí se stejným slugem, řazení podle názvu
        try p.saveEnvironment(EnvironmentConfig(name: "Produkce!"), secrets: store)
        try p.saveEnvironment(EnvironmentConfig(name: "Alfa"), secrets: store)
        #expect(files(dir) == ["alfa.yaml", "produkce-2.yaml", "produkce.yaml"])
        #expect(try p.listEnvironments().map(\.name) == ["Alfa", "Produkce", "Produkce!"])

        try p.deleteEnvironment(id: env.id, secrets: store)
        #expect(files(dir) == ["alfa.yaml", "produkce-2.yaml"])
        #expect(store.all.isEmpty)
        #expect(throws: CoreError.self) { try p.deleteEnvironment(id: env.id, secrets: store) }
    }

    @Test func copiedFileGetsNewID() throws {
        let tmp = TempDir()
        let p = try newProject(tmp)
        let env = try p.saveEnvironment(EnvironmentConfig(name: "A"), secrets: MemorySecrets())
        let dir = p.root.appending(path: "environments")
        try FileManager.default.copyItem(at: dir.appending(path: "a.yaml"), to: dir.appending(path: "b.yaml"))
        try Data("name: Bez ID\n".utf8).write(to: dir.appending(path: "c.yaml"))
        try Data("vars: [".utf8).write(to: dir.appending(path: "d.yaml"))
        let ids = try p.listEnvironments().map(\.id)
        #expect(ids.count == 3 && ids.first == env.id && Set(ids).count == 3)
        #expect(try p.listEnvironments().map(\.id) == ids)   // nová ID jsou zapsaná
    }

    @Test func globals() throws {
        let tmp = TempDir()
        let store = MemorySecrets()
        #expect(try Globals.load(from: tmp.url).isEmpty)
        try Globals.save([Var(name: "user", value: "jan"), Var(name: "pass", value: "heslo", secret: true)],
                         to: tmp.url, secrets: store)
        #expect(store.all == ["global/pass": "heslo"])
        let vars = try Globals.load(from: tmp.url)
        #expect(vars.map(\.value) == ["jan", ""])
        #expect(try store.fill(vars, account: Secrets.globalAccount).map(\.value) == ["jan", "heslo"])
        try Globals.save([Var(name: "user", value: "jan")], to: tmp.url, secrets: store)
        #expect(store.all.isEmpty)
    }

    /// Skutečný Keychain jen s `MINORREST_KEYCHAIN=1` (v CI může být zamčený).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MINORREST_KEYCHAIN"] == "1"))
    func keychain() throws {
        let s = Secrets(service: "MinorREST-test")
        let account = "test/\(UUID().uuidString)/žluťoučký"
        defer { try? s.delete(account: account) }
        #expect(try s.get(account: account) == nil)
        try s.set(account: account, value: "kůň 1")
        try s.set(account: account, value: "kůň 2")
        #expect(try s.get(account: account) == "kůň 2")
        try s.delete(account: account)
        try s.delete(account: account)
        #expect(try s.get(account: account) == nil)
    }
}

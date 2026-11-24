import Foundation

/// Prostředí `environments/<slug>.yaml` (PLAN 2.7); hodnoty tajných proměnných jsou v `SecretStore`.
nonisolated extension Project {
    var environmentsURL: URL { root.appending(path: ProjectFormat.environmentDir) }

    /// Účet Keychain tajné proměnné prostředí.
    func secretAccount(envID: String) -> (String) -> String {
        Self.account(locked { cfg.id }, envID)
    }

    static func account(_ projectID: String, _ envID: String) -> (String) -> String {
        { Secrets.account(projectID: projectID, envID: envID, name: $0) }
    }

    /// Prostředí seřazená podle názvu, bez hodnot z Keychain (`SecretStore.fill`). Nečitelné soubory se
    /// vynechají; chybějící nebo duplicitní ID (kopie souboru) se doplní a zapíše – ne v read-only projektu.
    func listEnvironments() throws -> [EnvironmentConfig] {
        try locked {
            try environmentFiles().map(\.env).sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    /// Uloží prostředí (prázdné `id` = nové). Tajné hodnoty jdou do `secrets` (před zápisem YAML),
    /// položky odebraných či přejmenovaných tajných proměnných se smažou. Změna názvu přejmenuje soubor.
    @discardableResult
    func saveEnvironment(_ env: EnvironmentConfig, secrets: SecretStore) throws -> EnvironmentConfig {
        try locked {
            try writable()
            var env = env
            env.name = try Self.cleanName(env.name)
            let files = try environmentFiles()
            let existing = env.id.isEmpty ? nil : files.first { $0.env.id == env.id }
            if env.id.isEmpty { env.id = ULID.make() }
            try secrets.sync(old: existing?.env.vars ?? [], new: env.vars, account: Self.account(cfg.id, env.id))

            try FileIO.createDirectory(environmentsURL, intermediate: true)
            let own = existing.map { $0.file.lastPathComponent.lowercased() }
            let taken = Set(try FileIO.fm.contentsOfDirectory(atPath: environmentsURL.path).map { $0.lowercased() })
                .subtracting(own.map { [$0] } ?? [])
            let name = Slug.unique(Slug.make(env.name)) { taken.contains($0 + ".yaml") } + ".yaml"
            let target = environmentsURL.appending(path: name)
            var stored = env
            stored.vars = env.vars.withoutSecretValues
            try FileIO.writeYAML(stored, to: target)
            if let old = existing?.file, old.lastPathComponent != name { try? FileIO.fm.removeItem(at: old) }
            return env
        }
    }

    /// Přesune soubor prostředí do Koše a smaže jeho tajné hodnoty.
    func deleteEnvironment(id: String, secrets: SecretStore) throws {
        try locked {
            try writable()
            guard let elem = try environmentFiles().first(where: { $0.env.id == id }) else {
                throw CoreError(.notFound, id)
            }
            do { try trash(elem.file) } catch { throw CoreError(.trashFailed, error.localizedDescription) }
            try secrets.deleteAll(elem.env.vars, account: Self.account(cfg.id, id))
        }
    }

    /// Soubory prostředí podle názvu souboru (volat se zámkem).
    func environmentFiles() throws -> [(file: URL, env: EnvironmentConfig)] {
        let dir = environmentsURL
        guard FileIO.isDirectory(dir) else { return [] }
        let names: [String]
        do { names = try FileIO.fm.contentsOfDirectory(atPath: dir.path) } catch { throw FileIO.error(error) }
        var seen: Set<String> = []
        var out: [(file: URL, env: EnvironmentConfig)] = []
        for name in names.sorted() where name.hasSuffix(".yaml") && !name.hasPrefix(".") {
            let file = dir.appending(path: name)
            guard var env = try? FileIO.readYAML(EnvironmentConfig.self, from: file) else { continue }
            if env.id.isEmpty || seen.contains(env.id) {
                env.id = ULID.make()
                if !readOnly { try FileIO.writeYAML(env, to: file) }
            }
            seen.insert(env.id)
            out.append((file, env))
        }
        return out
    }
}

/// Globální proměnné `globals.yaml` v adresáři aplikace (formát jako prostředí, jen `vars`).
nonisolated enum Globals {
    static let file = "globals.yaml"

    /// Chybějící soubor = žádné proměnné; tajné hodnoty se doplní přes `SecretStore.fill`.
    static func load(from dir: URL) throws -> [Var] {
        let url = dir.appending(path: file)
        guard FileIO.exists(url) else { return [] }
        return try FileIO.readYAML(GlobalsFile.self, from: url).vars
    }

    static func save(_ vars: [Var], to dir: URL, secrets: SecretStore) throws {
        let old = try load(from: dir)
        try secrets.sync(old: old, new: vars, account: Secrets.globalAccount)
        try FileIO.createDirectory(dir, intermediate: true)
        try FileIO.writeYAML(GlobalsFile(vars: vars.withoutSecretValues), to: dir.appending(path: file))
    }
}

nonisolated struct GlobalsFile: YAMLCodable {
    var vars: [Var]

    var yaml: YNode {
        var map = YMap()
        map.add("vars", .seq(vars.map(\.yaml)))
        return map.node
    }

    init(vars: [Var]) { self.vars = vars }

    init(yaml opt: YAMLObject) throws { vars = try opt.list("vars") }
}

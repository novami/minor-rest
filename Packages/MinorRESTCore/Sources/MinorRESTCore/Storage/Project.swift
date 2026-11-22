import Foundation

/// Otevřený projekt na disku. Operace jsou serializované zámkem; adresace přes `rel` (PLAN 2.2).
public final class Project: @unchecked Sendable {
    public typealias Trash = @Sendable (URL) throws -> Void

    /// Přesun do Koše (testy ho nahrazují přesunem do dočasného adresáře).
    public static let systemTrash: Trash = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    static let gitignoreResponses = ProjectFormat.responsesDir + "/"
    public static let defaultCopySuffix = " kopie"

    public let root: URL
    let trash: Trash
    let lock = NSLock()
    var cfg: ProjectConfig
    public let readOnly: Bool

    init(root: URL, config: ProjectConfig, trash: @escaping Trash) {
        self.root = root.standardizedFileURL
        self.cfg = config
        self.trash = trash
        self.readOnly = config.formatVersion > ProjectFormat.version
    }

    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: - Založení a otevření

    /// Založí projekt v novém podadresáři `parentDir/<slug názvu>`.
    public static func create(name: String, in parentDir: URL, trash: @escaping Trash = systemTrash) throws -> Project {
        let name = try cleanName(name)
        try FileIO.createDirectory(parentDir, intermediate: true)
        let taken = try FileIO.takenNames(in: parentDir)
        let root = parentDir.appending(path: Slug.unique(Slug.make(name)) { taken.contains($0) })
        try FileIO.createDirectory(root)
        return try initProject(at: root, name: name, trash: trash)
    }

    /// Založí projekt v existujícím adresáři.
    public static func initProject(at root: URL, name: String, trash: @escaping Trash = systemTrash) throws -> Project {
        let name = try cleanName(name)
        let file = root.appending(path: ProjectFormat.projectFile)
        if FileIO.exists(file) { throw CoreError(.projectInvalid, "already exists: \(root.path)") }
        let cfg = ProjectConfig(formatVersion: ProjectFormat.version, id: ULID.make(), name: name,
                                auth: Auth(type: AuthType.none), ignoreResponsesInGit: true)
        try FileIO.writeYAML(cfg, to: file)
        try syncGitignore(root: root, ignore: true)
        return Project(root: root, config: cfg, trash: trash)
    }

    public static func isProjectDir(_ root: URL) -> Bool {
        FileIO.exists(root.appending(path: ProjectFormat.projectFile))
    }

    public static func open(_ root: URL, trash: @escaping Trash = systemTrash) throws -> Project {
        let cfg: ProjectConfig
        do {
            cfg = try FileIO.readYAML(from: root.appending(path: ProjectFormat.projectFile))
        } catch let e as CoreError where e.code == .notFound {
            throw CoreError(.projectInvalid, e.detail)
        }
        if cfg.id.isEmpty { throw CoreError(.projectInvalid, "missing id") }
        return Project(root: root, config: cfg, trash: trash)
    }

    // MARK: - Konfigurace

    public var info: ProjectInfo {
        locked { ProjectInfo(id: cfg.id, name: cfg.name, path: root.path, readOnly: readOnly) }
    }

    public var config: ProjectConfig { locked { cfg } }

    /// Uloží konfiguraci (ID a formatVersion zůstanou) a srovná `.gitignore`.
    public func saveConfig(_ config: ProjectConfig) throws {
        try locked {
            try writable()
            var config = config
            config.id = cfg.id
            config.formatVersion = cfg.formatVersion
            try FileIO.writeYAML(config, to: root.appending(path: ProjectFormat.projectFile))
            cfg = try FileIO.readYAML(from: root.appending(path: ProjectFormat.projectFile))
            try Self.syncGitignore(root: root, ignore: config.ignoreResponsesInGit)
        }
    }

    /// Znovu načte `minorrest.yaml` (změna zvenku); ID se nemění.
    public func reloadConfig() throws {
        try locked {
            var fresh: ProjectConfig = try FileIO.readYAML(from: root.appending(path: ProjectFormat.projectFile))
            fresh.id = cfg.id
            cfg = fresh
        }
    }

    // MARK: - Cesty

    func url(_ rel: String) throws -> URL {
        guard RelPath.isValid(rel) else { throw CoreError(.pathInvalid, rel) }
        return rel.isEmpty ? root : root.appending(path: rel)
    }

    /// Absolutní cesta položky.
    public func absoluteURL(_ rel: String) throws -> URL { try url(rel) }

    /// Odkaz na soubor pro YAML: uvnitř projektu relativní (s `/`), jinak absolutní; symlinky se rozvinou.
    public func fileRef(_ path: String) -> String {
        let path = path.nfc
        let base = FileIO.realPath(root.path), target = FileIO.realPath(path)
        guard target.hasPrefix(base + "/") else { return path }
        return String(target.dropFirst(base.count + 1))
    }

    func writable() throws {
        if readOnly { throw CoreError(.projectReadOnly, root.path) }
    }

    static func cleanName(_ name: String) throws -> String {
        let name = name.nfc.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw CoreError(.nameEmpty) }
        return name
    }

    /// Přidá nebo odebere řádek `.responses/` v `.gitignore` projektu.
    static func syncGitignore(root: URL, ignore: Bool) throws {
        let file = root.appending(path: ".gitignore")
        var text = ""
        if FileIO.exists(file) {
            do { text = try String(contentsOf: file, encoding: .utf8) } catch { throw FileIO.error(error) }
        }
        var lines = text.isEmpty ? [] : text.trimmingTrailingNewlines().components(separatedBy: "\n")
        let found = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == gitignoreResponses }
        switch (ignore, found) {
        case (true, nil): lines.append(gitignoreResponses)
        case (false, let i?): lines.remove(at: i)
        default: return
        }
        try FileIO.writeAtomic(Data((lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").utf8), to: file)
    }
}

extension String {
    func trimmingTrailingNewlines() -> String {
        var s = self
        while s.hasSuffix("\n") { s.removeLast() }
        return s
    }
}

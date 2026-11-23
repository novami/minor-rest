import Foundation

public struct ImportOptions: Sendable, Equatable {
    public enum Grouping: String, Sendable { case tag, pathSegment }
    public var grouping: Grouping
    /// Složka pro operace bez tagu / segmentu (lokalizuje UI).
    public var otherFolder: String

    public init(grouping: Grouping = .tag, otherFolder: String = "Ostatní") {
        self.grouping = grouping
        self.otherFolder = otherFolder
    }
}

public struct ImportPreview: Sendable, Equatable {
    public struct Folder: Sendable, Equatable { public var name: String; public var count: Int }
    public var title: String
    public var folders: [Folder]
    public var requestCount: Int
    public var serverCount: Int
    public var warnings: [String]
}

public struct ImportResult: Sendable, Equatable {
    public var project: ProjectInfo
    /// Prostředí „Default“ (první server), které má UI aktivovat.
    public var environmentID: String?
    public var requestCount: Int
}

/// Import OpenAPI / Swagger (kap. 7): zdroj → `APISpec` → projekt / složka.
public enum OpenAPIImport {
    public static func parse(_ text: String) throws -> APISpec { try OpenAPIParser.parse(text) }

    /// Načte soubor nebo `http(s)` URL a rozparsuje ho.
    public static func load(source: URL) async throws -> APISpec {
        let data: Data
        do {
            if source.isFileURL {
                data = try Data(contentsOf: source)
            } else {
                let (d, resp) = try await URLSession.shared.data(from: source)
                if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
                    throw CoreError(.importFetch, "HTTP \(h.statusCode)")
                }
                data = d
            }
        } catch let e as CoreError {
            throw e
        } catch {
            throw CoreError(.importFetch, error.localizedDescription)
        }
        guard let text = String(data: data, encoding: .utf8) else { throw CoreError(.importInvalid, "UTF-8") }
        return try parse(text)
    }

    public static func preview(_ spec: APISpec, options: ImportOptions = ImportOptions()) -> ImportPreview {
        let groups = group(spec, options)
        return ImportPreview(title: spec.title, folders: groups.map { .init(name: $0.name, count: $0.ops.count) },
                             requestCount: spec.operations.count, serverCount: spec.servers.count, warnings: spec.warnings)
    }

    /// Nový projekt `name` (výchozí `info.title`) v `parentDir`.
    public static func importProject(_ spec: APISpec, name: String? = nil, in parentDir: URL, options: ImportOptions = ImportOptions(),
                                     secrets: SecretStore, trash: @escaping Project.Trash = Project.systemTrash) throws -> ImportResult {
        let title = (name ?? spec.title).trimmingCharacters(in: .whitespacesAndNewlines)
        let project = try Project.create(name: title.isEmpty ? "API" : title, in: parentDir, trash: trash)
        var cfg = project.config
        cfg.description = spec.description
        cfg.auth = spec.auth ?? cfg.auth
        merge(&cfg.vars, names: spec.variables)
        if spec.servers.isEmpty { merge(&cfg.vars, [Var(name: "baseUrl")]) }
        try project.saveConfig(cfg)

        var firstEnv: String?
        var used: [String] = []
        for (i, s) in spec.servers.enumerated() {
            var envName = i == 0 ? "Default" : (s.description.isEmpty ? s.url : s.description)
            while used.contains(envName.lowercased()) { envName += " 2" }
            used.append(envName.lowercased())
            let env = try project.saveEnvironment(EnvironmentConfig(name: envName, vars: [Var(name: "baseUrl", value: trimSlash(s.url))]),
                                                  secrets: secrets)
            if i == 0 { firstEnv = env.id }
        }
        let n = try populate(project, parent: "", spec, options)
        return ImportResult(project: project.info, environmentID: firstEnv, requestCount: n)
    }

    /// Import do existujícího projektu jako nová složka (první server → proměnná `baseUrl` složky).
    public static func importFolder(_ spec: APISpec, into project: Project, options: ImportOptions = ImportOptions()) throws -> ImportResult {
        let title = spec.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let node = try project.createFolder(parent: "", name: title.isEmpty ? "API" : title)
        var fc = try project.loadFolderConfig(node.rel)
        if let s = spec.servers.first { merge(&fc.vars, [Var(name: "baseUrl", value: trimSlash(s.url))]) } else { merge(&fc.vars, [Var(name: "baseUrl")]) }
        merge(&fc.vars, names: spec.variables)
        fc.auth = spec.auth ?? fc.auth
        try project.saveFolderConfig(node.rel, fc)
        let n = try populate(project, parent: node.rel, spec, options)
        return ImportResult(project: project.info, environmentID: nil, requestCount: n)
    }

    // MARK: - Interní

    private static let secretVars: Set<String> = ["password", "token", "apiKey", "clientSecret"]

    private static func trimSlash(_ u: String) -> String { u.hasSuffix("/") ? String(u.dropLast()) : u }

    private static func merge(_ vars: inout [Var], names: [String]) {
        merge(&vars, names.map { Var(name: $0, secret: secretVars.contains($0)) })
    }

    private static func merge(_ vars: inout [Var], _ add: [Var]) {
        for v in add {
            if let i = vars.firstIndex(where: { $0.name == v.name }) { if vars[i].value.isEmpty { vars[i].value = v.value } } else { vars.append(v) }
        }
    }

    private struct Group { var name: String; var ops: [APIOperation] }

    private static func group(_ spec: APISpec, _ o: ImportOptions) -> [Group] {
        var groups: [Group] = []
        for op in spec.operations {
            var name: String
            switch o.grouping {
            case .tag: name = op.tag
            case .pathSegment: name = op.path.split(separator: "/").first { !$0.hasPrefix(":") }.map(String.init) ?? ""
            }
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { name = o.otherFolder }
            if let i = groups.firstIndex(where: { $0.name == name }) { groups[i].ops.append(op) } else { groups.append(Group(name: name, ops: [op])) }
        }
        return groups
    }

    private static func populate(_ project: Project, parent: String, _ spec: APISpec, _ o: ImportOptions) throws -> Int {
        var count = 0
        for g in group(spec, o) {
            let folder = try project.createFolder(parent: parent, name: g.name)
            for op in g.ops {
                let node = try project.createRequest(parent: folder.rel, name: op.title)
                var r = try project.loadRequest(node.rel)
                r.method = op.method
                r.url = "{{baseUrl}}" + op.path
                r.params = Params(query: op.query, path: op.pathParams)
                r.headers = op.headers
                if let a = op.auth { r.auth = a }
                if let b = op.body { r.body = b }
                r.docs = op.description
                try project.saveRequest(node.rel, r)
                count += 1
            }
        }
        return count
    }
}

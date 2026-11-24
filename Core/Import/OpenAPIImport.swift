import Foundation

nonisolated struct ImportOptions: Sendable, Equatable {
    enum Grouping: String, Sendable { case tag, pathSegment }
    var grouping: Grouping
    /// Složka pro operace bez tagu / segmentu (lokalizuje UI).
    var otherFolder: String

    init(grouping: Grouping = .tag, otherFolder: String = "Ostatní") {
        self.grouping = grouping
        self.otherFolder = otherFolder
    }
}

nonisolated struct ImportPreview: Sendable, Equatable {
    struct Folder: Sendable, Equatable { var name: String; var count: Int }
    var title: String
    var folders: [Folder]
    var requestCount: Int
    var serverCount: Int
    var warnings: [String]
}

nonisolated struct ImportResult: Sendable, Equatable {
    var project: ProjectInfo
    /// Prostředí „Default“ (první server), které má UI aktivovat.
    var environmentID: String?
    var requestCount: Int
}

/// Import OpenAPI / Swagger (kap. 7): zdroj → `APISpec` → projekt / složka.
nonisolated enum OpenAPIImport {
    static func parse(_ text: String) throws -> APISpec { try OpenAPIParser.parse(text) }

    /// Načte soubor nebo `http(s)` URL a rozparsuje ho.
    static func load(source: URL) async throws -> APISpec {
        let data: Data
        do {
            if source.isFileURL {
                data = try Data(contentsOf: source)
            } else {
                let (dat, resp) = try await URLSession.shared.data(from: source)
                if let hdr = resp as? HTTPURLResponse, !(200..<300).contains(hdr.statusCode) {
                    throw CoreError(.importFetch, "HTTP \(hdr.statusCode)")
                }
                data = dat
            }
        } catch let elem as CoreError {
            throw elem
        } catch {
            throw CoreError(.importFetch, error.localizedDescription)
        }
        guard let text = String(data: data, encoding: .utf8) else { throw CoreError(.importInvalid, "UTF-8") }
        return try parse(text)
    }

    static func preview(_ spec: APISpec, options: ImportOptions = ImportOptions()) -> ImportPreview {
        let groups = group(spec, options)
        return ImportPreview(title: spec.title, folders: groups.map { .init(name: $0.name, count: $0.ops.count) },
                             requestCount: spec.operations.count, serverCount: spec.servers.count, warnings: spec.warnings)
    }

    /// Nový projekt `name` (výchozí `info.title`) v `parentDir`.
    static func importProject(_ spec: APISpec, name: String? = nil, in parentDir: URL, options: ImportOptions = ImportOptions(),
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
        for (i, str) in spec.servers.enumerated() {
            var envName = i == 0 ? "Default" : (str.description.isEmpty ? str.url : str.description)
            while used.contains(envName.lowercased()) { envName += " 2" }
            used.append(envName.lowercased())
            let env = try project.saveEnvironment(EnvironmentConfig(name: envName, vars: [Var(name: "baseUrl", value: trimSlash(str.url))]),
                                                  secrets: secrets)
            if i == 0 { firstEnv = env.id }
        }
        let num = try populate(project, parent: "", spec, options)
        return ImportResult(project: project.info, environmentID: firstEnv, requestCount: num)
    }

    /// Import do existujícího projektu jako nová složka (první server → proměnná `baseUrl` složky).
    static func importFolder(_ spec: APISpec, into project: Project, options: ImportOptions = ImportOptions()) throws -> ImportResult {
        let title = spec.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let node = try project.createFolder(parent: "", name: title.isEmpty ? "API" : title)
        var fc = try project.loadFolderConfig(node.rel)
        if let str = spec.servers.first { merge(&fc.vars, [Var(name: "baseUrl", value: trimSlash(str.url))]) } else { merge(&fc.vars, [Var(name: "baseUrl")]) }
        merge(&fc.vars, names: spec.variables)
        fc.auth = spec.auth ?? fc.auth
        try project.saveFolderConfig(node.rel, fc)
        let num = try populate(project, parent: node.rel, spec, options)
        return ImportResult(project: project.info, environmentID: nil, requestCount: num)
    }

    // MARK: - Interní

    private static let secretVars: Set<String> = ["password", "token", "apiKey", "clientSecret"]

    private static func trimSlash(_ url: String) -> String { url.hasSuffix("/") ? String(url.dropLast()) : url }

    private static func merge(_ vars: inout [Var], names: [String]) {
        merge(&vars, names.map { Var(name: $0, secret: secretVars.contains($0)) })
    }

    private static func merge(_ vars: inout [Var], _ add: [Var]) {
        for val in add {
            if let i = vars.firstIndex(where: { $0.name == val.name }) { if vars[i].value.isEmpty { vars[i].value = val.value } } else { vars.append(val) }
        }
    }

    private struct Group { var name: String; var ops: [APIOperation] }

    private static func group(_ spec: APISpec, _ opt: ImportOptions) -> [Group] {
        var groups: [Group] = []
        for op in spec.operations {
            var name: String
            switch opt.grouping {
            case .tag: name = op.tag
            case .pathSegment: name = op.path.split(separator: "/").first { !$0.hasPrefix(":") }.map(String.init) ?? ""
            }
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { name = opt.otherFolder }
            if let i = groups.firstIndex(where: { $0.name == name }) { groups[i].ops.append(op) } else { groups.append(Group(name: name, ops: [op])) }
        }
        return groups
    }

    private static func populate(_ project: Project, parent: String, _ spec: APISpec, _ opt: ImportOptions) throws -> Int {
        var count = 0
        for grp in group(spec, opt) {
            let folder = try project.createFolder(parent: parent, name: grp.name)
            for op in grp.ops {
                let node = try project.createRequest(parent: folder.rel, name: op.title)
                var res = try project.loadRequest(node.rel)
                res.method = op.method
                res.url = "{{baseUrl}}" + op.path
                res.params = Params(query: op.query, path: op.pathParams)
                res.headers = op.headers
                if let arg = op.auth { res.auth = arg }
                if let buf = op.body { res.body = buf }
                res.docs = op.description
                try project.saveRequest(node.rel, res)
                count += 1
            }
        }
        return count
    }
}

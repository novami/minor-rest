import Foundation

/// Stav pracovní plochy (`workspace.yaml`): otevřené projekty, taby, rozbalené složky, rozměry panelů.
nonisolated struct Workspace: Hashable, Sendable {
    static let file = "workspace.yaml"
    static let defaultSidebarWidth = 260
    static let defaultResponseHeight = 320

    /// Cesty otevřených projektů v pořadí.
    var projects: [String] = []
    /// ID aktivního projektu.
    var activeProject = ""
    /// ID projektu → rozbalené složky (`rel`).
    var expanded: [String: [String]] = [:]
    /// ID projektu → otevřené taby (ID requestů).
    var tabs: [String: [String]] = [:]
    /// ID projektu → aktivní tab (ID requestu).
    var activeTab: [String: String] = [:]
    /// ID projektu → aktivní prostředí (ID); chybí = žádné.
    var activeEnvironment: [String: String] = [:]
    var sidebarHidden = false
    var sidebarWidth = defaultSidebarWidth
    var responseHeight = defaultResponseHeight

    /// Výchozí adresář aplikace `~/Library/Application Support/MinorREST`.
    static var appDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "MinorREST")
    }

    /// Výchozí umístění nových projektů `~/Documents/MinorREST`.
    static var defaultProjectsDirectory: URL {
        URL.documentsDirectory.appending(path: "MinorREST")
    }

    /// Načte workspace; chybějící soubor = výchozí hodnoty.
    static func load(from dir: URL) throws -> Workspace {
        let file = dir.appending(path: Self.file)
        guard FileIO.exists(file) else { return Workspace() }
        return try FileIO.readYAML(Workspace.self, from: file).normalized()
    }

    func save(to dir: URL) throws {
        try FileIO.createDirectory(dir, intermediate: true)
        try FileIO.writeYAML(normalized(), to: dir.appending(path: Self.file))
    }

    func normalized() -> Workspace {
        var wrd = self
        if wrd.sidebarWidth <= 0 { wrd.sidebarWidth = Self.defaultSidebarWidth }
        if wrd.responseHeight <= 0 { wrd.responseHeight = Self.defaultResponseHeight }
        return wrd
    }
}

nonisolated extension Workspace: YAMLCodable {
    var yaml: YNode {
        func strings(_ list: [String]) -> YNode { .seq(list.map { .string($0) }) }
        var map = YMap()
        map.add("projects", strings(projects))
        map.add("activeProject", activeProject)
        map.add("expanded", .map(expanded.keys.sorted().map { YEntry(key: $0, value: strings(expanded[$0]!)) }))
        map.add("tabs", .map(tabs.keys.sorted().map { YEntry(key: $0, value: strings(tabs[$0]!)) }))
        map.add("activeTab", .map(activeTab.keys.sorted().map { YEntry(key: $0, value: .string(activeTab[$0]!)) }))
        map.add("activeEnvironment",
              .map(activeEnvironment.keys.sorted().map { YEntry(key: $0, value: .string(activeEnvironment[$0]!)) }))
        map.add("sidebarHidden", sidebarHidden)
        map.add("sidebarWidth", sidebarWidth)
        map.add("responseHeight", responseHeight)
        return map.node
    }

    init(yaml opt: YAMLObject) throws {
        self.init()
        projects = try opt.stringList("projects")
        activeProject = try opt.string("activeProject")
        expanded = try opt.stringListMap("expanded")
        tabs = try opt.stringListMap("tabs")
        activeTab = try opt.stringMap("activeTab")
        activeEnvironment = try opt.stringMap("activeEnvironment")
        sidebarHidden = try opt.bool("sidebarHidden")
        sidebarWidth = try opt.int("sidebarWidth")
        responseHeight = try opt.int("responseHeight")
    }
}

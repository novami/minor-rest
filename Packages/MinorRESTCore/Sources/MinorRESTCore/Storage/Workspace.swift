import Foundation

/// Stav pracovní plochy (`workspace.yaml`): otevřené projekty, taby, rozbalené složky, rozměry panelů.
public struct Workspace: Hashable, Sendable {
    public static let file = "workspace.yaml"
    public static let defaultSidebarWidth = 260
    public static let defaultResponseHeight = 320

    /// Cesty otevřených projektů v pořadí.
    public var projects: [String] = []
    /// ID aktivního projektu.
    public var activeProject = ""
    /// ID projektu → rozbalené složky (`rel`).
    public var expanded: [String: [String]] = [:]
    /// ID projektu → otevřené taby (ID requestů).
    public var tabs: [String: [String]] = [:]
    /// ID projektu → aktivní tab (ID requestu).
    public var activeTab: [String: String] = [:]
    /// ID projektu → aktivní prostředí (ID); chybí = žádné.
    public var activeEnvironment: [String: String] = [:]
    public var sidebarHidden = false
    public var sidebarWidth = defaultSidebarWidth
    public var responseHeight = defaultResponseHeight

    public init() {}

    /// Výchozí adresář aplikace `~/Library/Application Support/MinorREST`.
    public static var appDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "MinorREST")
    }

    /// Výchozí umístění nových projektů `~/Documents/MinorREST`.
    public static var defaultProjectsDirectory: URL {
        URL.documentsDirectory.appending(path: "MinorREST")
    }

    /// Načte workspace; chybějící soubor = výchozí hodnoty.
    public static func load(from dir: URL) throws -> Workspace {
        let file = dir.appending(path: Self.file)
        guard FileIO.exists(file) else { return Workspace() }
        return try FileIO.readYAML(Workspace.self, from: file).normalized()
    }

    public func save(to dir: URL) throws {
        try FileIO.createDirectory(dir, intermediate: true)
        try FileIO.writeYAML(normalized(), to: dir.appending(path: Self.file))
    }

    func normalized() -> Workspace {
        var w = self
        if w.sidebarWidth <= 0 { w.sidebarWidth = Self.defaultSidebarWidth }
        if w.responseHeight <= 0 { w.responseHeight = Self.defaultResponseHeight }
        return w
    }
}

extension Workspace: YAMLCodable {
    public var yaml: YNode {
        func strings(_ list: [String]) -> YNode { .seq(list.map { .string($0) }) }
        var m = YMap()
        m.add("projects", strings(projects))
        m.add("activeProject", activeProject)
        m.add("expanded", .map(expanded.keys.sorted().map { YEntry(key: $0, value: strings(expanded[$0]!)) }))
        m.add("tabs", .map(tabs.keys.sorted().map { YEntry(key: $0, value: strings(tabs[$0]!)) }))
        m.add("activeTab", .map(activeTab.keys.sorted().map { YEntry(key: $0, value: .string(activeTab[$0]!)) }))
        m.add("activeEnvironment",
              .map(activeEnvironment.keys.sorted().map { YEntry(key: $0, value: .string(activeEnvironment[$0]!)) }))
        m.add("sidebarHidden", sidebarHidden)
        m.add("sidebarWidth", sidebarWidth)
        m.add("responseHeight", responseHeight)
        return m.node
    }

    public init(yaml o: YAMLObject) throws {
        self.init()
        projects = try o.stringList("projects")
        activeProject = try o.string("activeProject")
        expanded = try o.stringListMap("expanded")
        tabs = try o.stringListMap("tabs")
        activeTab = try o.stringMap("activeTab")
        activeEnvironment = try o.stringMap("activeEnvironment")
        sidebarHidden = try o.bool("sidebarHidden")
        sidebarWidth = try o.int("sidebarWidth")
        responseHeight = try o.int("responseHeight")
    }
}

import Foundation

/// Otevřené projekty (jeden výskyt na ID).
public actor ProjectRegistry {
    private var projects: [Project] = []
    private let trash: Project.Trash

    public init(trash: @escaping Project.Trash = Project.systemTrash) {
        self.trash = trash
    }

    /// Otevře projekt; už otevřený (stejné ID) vrátí beze změny.
    @discardableResult
    public func open(_ root: URL) throws -> Project {
        add(try Project.open(root.standardizedFileURL, trash: trash))
    }

    @discardableResult
    public func add(_ project: Project) -> Project {
        let id = project.info.id
        if let existing = projects.first(where: { $0.info.id == id }) { return existing }
        projects.append(project)
        return project
    }

    public func project(_ id: String) throws -> Project {
        guard let p = projects.first(where: { $0.info.id == id }) else { throw CoreError(.notFound, "project \(id)") }
        return p
    }

    public func close(_ id: String) throws {
        guard let i = projects.firstIndex(where: { $0.info.id == id }) else { throw CoreError(.notFound, "project \(id)") }
        projects.remove(at: i)
    }

    public func list() -> [ProjectInfo] { projects.map(\.info) }

    public func paths() -> [String] { projects.map(\.root.path) }
}

import Foundation

/// Otevřené projekty (jeden výskyt na ID).
actor ProjectRegistry {
    private var projects: [Project] = []
    private let trash: Project.Trash

    init(trash: @escaping Project.Trash = Project.systemTrash) {
        self.trash = trash
    }

    /// Otevře projekt; už otevřený (stejné ID) vrátí beze změny.
    @discardableResult
    func open(_ root: URL) throws -> Project {
        let project = try Project.open(root.standardizedFileURL, trash: trash)
        project.migrateSecrets()
        return add(project)
    }

    @discardableResult
    func add(_ project: Project) -> Project {
        let id = project.info.id
        if let existing = projects.first(where: { $0.info.id == id }) { return existing }
        projects.append(project)
        return project
    }

    func project(_ id: String) throws -> Project {
        guard let par = projects.first(where: { $0.info.id == id }) else { throw CoreError(.notFound, "project \(id)") }
        return par
    }

    func close(_ id: String) throws {
        guard let i = projects.firstIndex(where: { $0.info.id == id }) else {
            throw CoreError(.notFound, "project \(id)")
        }
        projects.remove(at: i)
    }

    func list() -> [ProjectInfo] { projects.map(\.info) }

    func paths() -> [String] { projects.map(\.root.path) }
}

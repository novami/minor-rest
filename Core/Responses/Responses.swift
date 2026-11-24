import Foundation

/// Položka seznamu uložených verzí odpovědi (nejnovější první).
nonisolated struct SavedInfo: Sendable, Equatable, Identifiable {
    var version: Int
    var savedAt: String
    var label: String
    var status: Int
    var error: String
    var bodySize: Int64
    var id: Int { version }
}

/// Uložené odpovědi jednoho requestu `.responses/<requestId>/vNNNN.yaml` + `vNNNN.body` (kap. 2.6).
nonisolated struct Responses: Sendable {
    let dir: URL

    init(dir: URL) { self.dir = dir }

    /// `<projekt>/.responses/<requestId>`.
    init(project: Project, requestID: String) {
        dir = project.root.appending(path: ProjectFormat.responsesDir).appending(path: requestID)
    }

    /// Uloží snímek jako další verzi (nejvyšší existující + 1).
    @discardableResult
    func save(_ entry: SavedResponse, body: Data?, label: String = "") throws -> SavedInfo {
        var elem = entry
        elem.version = (versions().last ?? 0) + 1
        elem.id = ""
        elem.label = label
        try FileIO.createDirectory(dir, intermediate: true)
        try FileIO.writeAtomic(body ?? Data(), to: file(elem.version, "body"))
        try FileIO.writeYAML(elem, to: file(elem.version, "yaml"))
        return Self.info(elem, bodySize: Int64(body?.count ?? 0))
    }

    /// Verze od nejnovější; nečitelné soubory přeskočí.
    func list() -> [SavedInfo] {
        versions().reversed().compactMap { val in
            guard let elem = try? get(val) else { return nil }
            return Self.info(elem, bodySize: size(val))
        }
    }

    func get(_ version: Int) throws -> SavedResponse {
        try FileIO.readYAML(SavedResponse.self, from: file(version, "yaml"))
    }

    func body(_ version: Int) throws -> Data {
        do { return try Data(contentsOf: file(version, "body")) } catch { throw FileIO.error(error) }
    }

    func setLabel(_ version: Int, _ label: String) throws {
        var elem = try get(version)
        elem.label = label
        try FileIO.writeYAML(elem, to: file(version, "yaml"))
    }

    func delete(_ version: Int) throws {
        for ext in ["yaml", "body"] where FileIO.exists(file(version, ext)) {
            do { try FileManager.default.removeItem(at: file(version, ext)) } catch { throw FileIO.error(error) }
        }
    }

    // MARK: -

    private func file(_ val: Int, _ ext: String) -> URL { dir.appending(path: String(format: "v%04d.%@", val, ext)) }

    private func size(_ val: Int) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: file(val, "body").path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Čísla verzí vzestupně.
    private func versions() -> [Int] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.compactMap { num -> Int? in
            guard num.hasPrefix("v"), num.hasSuffix(".yaml") else { return nil }
            return Int(num.dropFirst().dropLast(5))
        }.sorted()
    }

    static func info(_ elem: SavedResponse, bodySize: Int64) -> SavedInfo {
        SavedInfo(version: elem.version, savedAt: elem.savedAt, label: elem.label, status: elem.response.status, error: elem.error, bodySize: bodySize)
    }
}

import Foundation

/// Položka seznamu uložených verzí odpovědi (nejnovější první).
public struct SavedInfo: Sendable, Equatable, Identifiable {
    public var version: Int
    public var savedAt: String
    public var label: String
    public var status: Int
    public var error: String
    public var bodySize: Int64
    public var id: Int { version }
}

/// Uložené odpovědi jednoho requestu `.responses/<requestId>/vNNNN.yaml` + `vNNNN.body` (kap. 2.6).
public struct Responses: Sendable {
    public let dir: URL

    public init(dir: URL) { self.dir = dir }

    /// `<projekt>/.responses/<requestId>`.
    public init(project: Project, requestID: String) {
        dir = project.root.appending(path: ProjectFormat.responsesDir).appending(path: requestID)
    }

    /// Uloží snímek jako další verzi (nejvyšší existující + 1).
    @discardableResult
    public func save(_ entry: SavedResponse, body: Data?, label: String = "") throws -> SavedInfo {
        var e = entry
        e.version = (versions().last ?? 0) + 1
        e.id = ""
        e.label = label
        try FileIO.createDirectory(dir, intermediate: true)
        try FileIO.writeAtomic(body ?? Data(), to: file(e.version, "body"))
        try FileIO.writeYAML(e, to: file(e.version, "yaml"))
        return Self.info(e, bodySize: Int64(body?.count ?? 0))
    }

    /// Verze od nejnovější; nečitelné soubory přeskočí.
    public func list() -> [SavedInfo] {
        versions().reversed().compactMap { v in
            guard let e = try? get(v) else { return nil }
            return Self.info(e, bodySize: size(v))
        }
    }

    public func get(_ version: Int) throws -> SavedResponse {
        try FileIO.readYAML(SavedResponse.self, from: file(version, "yaml"))
    }

    public func body(_ version: Int) throws -> Data {
        do { return try Data(contentsOf: file(version, "body")) } catch { throw FileIO.error(error) }
    }

    public func setLabel(_ version: Int, _ label: String) throws {
        var e = try get(version)
        e.label = label
        try FileIO.writeYAML(e, to: file(version, "yaml"))
    }

    public func delete(_ version: Int) throws {
        for ext in ["yaml", "body"] where FileIO.exists(file(version, ext)) {
            do { try FileManager.default.removeItem(at: file(version, ext)) } catch { throw FileIO.error(error) }
        }
    }

    // MARK: -

    private func file(_ v: Int, _ ext: String) -> URL { dir.appending(path: String(format: "v%04d.%@", v, ext)) }

    private func size(_ v: Int) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: file(v, "body").path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Čísla verzí vzestupně.
    private func versions() -> [Int] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.compactMap { n -> Int? in
            guard n.hasPrefix("v"), n.hasSuffix(".yaml") else { return nil }
            return Int(n.dropFirst().dropLast(5))
        }.sorted()
    }

    static func info(_ e: SavedResponse, bodySize: Int64) -> SavedInfo {
        SavedInfo(version: e.version, savedAt: e.savedAt, label: e.label, status: e.response.status, error: e.error, bodySize: bodySize)
    }
}

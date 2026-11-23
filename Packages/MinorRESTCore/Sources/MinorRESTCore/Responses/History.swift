import Foundation

/// Položka seznamu historie (nejnovější první).
public struct HistoryItem: Sendable, Equatable, Identifiable {
    public var id: String
    public var savedAt: String
    public var method: String
    public var url: String
    public var status: Int
    public var error: String
    public var projectID: String
    public var requestID: String
    public var requestName: String
}

/// Historie odeslání `history/<ULID>.yaml` + `<ULID>.body` (kap. 2.1): posledních `limit`, tělo max 1 MB.
public struct History: Sendable {
    public static let maxBody = 1 << 20

    public let dir: URL
    public let limit: Int

    public init(dir: URL, limit: Int = 200) {
        self.dir = dir
        self.limit = limit
    }

    /// Zapíše záznam (přidělí ID) a smaže nejstarší nad limit. `body` delší než `maxBody` se ořízne.
    @discardableResult
    public func add(_ entry: SavedResponse, body: Data?) throws -> HistoryItem {
        var e = entry
        e.id = ULID.make()
        e.version = 0
        try FileIO.createDirectory(dir, intermediate: true)
        if let body {
            if body.count > Self.maxBody { e.truncated = true }
            try FileIO.writeAtomic(body.count > Self.maxBody ? body.prefix(Self.maxBody) : body, to: file(e.id, "body"))
        }
        try FileIO.writeYAML(e, to: file(e.id, "yaml"))
        try prune()
        return Self.item(e)
    }

    /// Záznamy od nejnovějšího; nečitelné soubory přeskočí.
    public func list() -> [HistoryItem] {
        ids().reversed().compactMap { try? entry($0) }.map(Self.item)
    }

    public func entry(_ id: String) throws -> SavedResponse {
        try FileIO.readYAML(SavedResponse.self, from: file(id, "yaml"))
    }

    /// Uložené tělo; nil = záznam bez těla.
    public func body(_ id: String) throws -> Data? {
        let f = file(id, "body")
        guard FileIO.exists(f) else { return nil }
        do { return try Data(contentsOf: f) } catch { throw FileIO.error(error) }
    }

    public func clear() throws {
        for id in ids() { try remove(id) }
    }

    // MARK: -

    private func file(_ id: String, _ ext: String) -> URL { dir.appending(path: "\(id).\(ext)") }

    /// ID seřazená vzestupně (ULID = čas).
    private func ids() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasSuffix(".yaml") && !$0.hasPrefix(".") }.map { String($0.dropLast(5)) }.sorted()
    }

    private func prune() throws {
        let all = ids()
        for id in all.dropLast(max(limit, 0)) { try remove(id) }
    }

    private func remove(_ id: String) throws {
        for ext in ["yaml", "body"] where FileIO.exists(file(id, ext)) {
            do { try FileManager.default.removeItem(at: file(id, ext)) } catch { throw FileIO.error(error) }
        }
    }

    static func item(_ e: SavedResponse) -> HistoryItem {
        HistoryItem(id: e.id, savedAt: e.savedAt, method: e.request.method, url: e.request.url, status: e.response.status,
                    error: e.error, projectID: e.projectID, requestID: e.requestID, requestName: e.requestName)
    }
}

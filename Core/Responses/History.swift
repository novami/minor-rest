import Foundation

/// Položka seznamu historie (nejnovější první).
nonisolated struct HistoryItem: Sendable, Equatable, Identifiable {
    var id: String
    var savedAt: String
    var method: String
    var url: String
    var status: Int
    var error: String
    var projectID: String
    var requestID: String
    var requestName: String
}

/// Historie odeslání `history/<ULID>.yaml` + `<ULID>.body` (kap. 2.1): posledních `limit`, tělo max 1 MB.
nonisolated struct History: Sendable {
    static let maxBody = 1 << 20

    let dir: URL
    let limit: Int

    init(dir: URL, limit: Int = 200) {
        self.dir = dir
        self.limit = limit
    }

    /// Zapíše záznam (přidělí ID) a smaže nejstarší nad limit. `body` delší než `maxBody` se ořízne.
    @discardableResult
    func add(_ entry: SavedResponse, body: Data?) throws -> HistoryItem {
        var elem = entry
        elem.id = ULID.make()
        elem.version = 0
        try FileIO.createDirectory(dir, intermediate: true)
        if let body {
            if body.count > Self.maxBody { elem.truncated = true }
            try FileIO.writeAtomic(body.count > Self.maxBody ? body.prefix(Self.maxBody) : body, to: file(elem.id, "body"))
        }
        try FileIO.writeYAML(elem, to: file(elem.id, "yaml"))
        try prune()
        return Self.item(elem)
    }

    /// Záznamy od nejnovějšího; nečitelné soubory přeskočí.
    func list() -> [HistoryItem] {
        ids().reversed().compactMap { try? entry($0) }.map(Self.item)
    }

    func entry(_ id: String) throws -> SavedResponse {
        try FileIO.readYAML(SavedResponse.self, from: file(id, "yaml"))
    }

    /// Uložené tělo; nil = záznam bez těla.
    func body(_ id: String) throws -> Data? {
        let fn = file(id, "body")
        guard FileIO.exists(fn) else { return nil }
        do { return try Data(contentsOf: fn) } catch { throw FileIO.error(error) }
    }

    func clear() throws {
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

    static func item(_ elem: SavedResponse) -> HistoryItem {
        HistoryItem(id: elem.id, savedAt: elem.savedAt, method: elem.request.method, url: elem.request.url, status: elem.response.status,
                    error: elem.error, projectID: elem.projectID, requestID: elem.requestID, requestName: elem.requestName)
    }
}

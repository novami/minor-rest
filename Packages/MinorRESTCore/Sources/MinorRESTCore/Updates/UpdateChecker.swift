import Foundation

/// Dostupná aktualizace z podepsaného feedu `appcast.json` (formát sdílený aplikacemi Minor*).
public struct UpdateInfo: Sendable, Equatable {
    public var version: AppVersion
    public var notes: String
    public var url: URL
    public var sha256: String
    public var signature: String
}

/// Načtení dat po síti (v testech nahrazeno).
public protocol DataLoader: Sendable {
    func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: DataLoader {
    public func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CoreError(.updateFeed, "no http response") }
        return (data, http)
    }
}

/// Čte feed `appcast.json` posledního releasu. Jen HTTPS.
public actor UpdateChecker {
    private let feedURL: URL
    private let current: AppVersion
    private let loader: DataLoader

    public init(feedURL: URL, current: AppVersion, loader: DataLoader = URLSession(configuration: .ephemeral)) {
        self.feedURL = feedURL
        self.current = current
        self.loader = loader
    }

    /// `nil` = aktuální verze je nejnovější. Nikdy nenabídne stejnou ani nižší verzi.
    public func check() async throws -> UpdateInfo? {
        guard feedURL.scheme == "https" else { throw CoreError(.updateFeed, "https") }
        var req = URLRequest(url: feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("MinorREST/\(current)", forHTTPHeaderField: "User-Agent")
        let data: Data, http: HTTPURLResponse
        do { (data, http) = try await loader.load(req) } catch { throw CoreError(.updateFeed, "\(error)") }
        guard http.statusCode == 200 else { throw CoreError(.updateFeed, "HTTP \(http.statusCode)") }
        return try Self.parse(data, current: current)
    }

    struct Feed: Decodable {
        var version: String
        var url: URL
        var sha256: String
        var signature: String
        var notes: String?
    }

    static func parse(_ data: Data, current: AppVersion) throws -> UpdateInfo? {
        let feed: Feed
        do { feed = try JSONDecoder().decode(Feed.self, from: data) } catch { throw CoreError(.updateFeed, "json") }
        guard let version = AppVersion(feed.version) else { throw CoreError(.updateFeed, "version") }
        guard version > current else { return nil }
        guard feed.url.scheme == "https" else { throw CoreError(.updateFeed, "https") }
        return UpdateInfo(version: version, notes: feed.notes ?? "", url: feed.url, sha256: feed.sha256, signature: feed.signature)
    }
}

import Foundation

/// Dostupná aktualizace nalezená v GitHub Releases.
public struct UpdateInfo: Sendable, Equatable {
    public var version: AppVersion
    public var notes: String
    public var pageURL: URL
    public var zipURL: URL
    public var signatureURL: URL
    public var size: Int64
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

/// Zjišťuje poslední release repozitáře. Jen HTTPS; ETag drží v paměti.
public actor UpdateChecker {
    private let repo: String
    private let current: AppVersion
    private let loader: DataLoader
    private var etag: String?
    private var cached: UpdateInfo?

    public init(repo: String, current: AppVersion, loader: DataLoader = URLSession(configuration: .ephemeral)) {
        self.repo = repo
        self.current = current
        self.loader = loader
    }

    /// `nil` = aktuální verze je nejnovější. Nikdy nenabídne stejnou ani nižší verzi.
    public func check() async throws -> UpdateInfo? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            throw CoreError(.updateFeed, "url")
        }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("MinorREST/\(current)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let data: Data, http: HTTPURLResponse
        do { (data, http) = try await loader.load(req) } catch { throw CoreError(.updateFeed, "\(error)") }
        if http.statusCode == 304 { return cached }
        guard http.statusCode == 200 else { throw CoreError(.updateFeed, "HTTP \(http.statusCode)") }
        let info = try Self.parse(data, current: current)
        etag = http.value(forHTTPHeaderField: "ETag")
        cached = info
        return info
    }

    struct Release: Decodable {
        struct Asset: Decodable { var name: String; var browser_download_url: URL; var size: Int64 }
        var tag_name: String
        var draft: Bool
        var prerelease: Bool
        var body: String?
        var html_url: URL
        var assets: [Asset]
    }

    static func parse(_ data: Data, current: AppVersion) throws -> UpdateInfo? {
        let release: Release
        do { release = try JSONDecoder().decode(Release.self, from: data) } catch { throw CoreError(.updateFeed, "json") }
        guard !release.draft, !release.prerelease, let version = AppVersion(release.tag_name), version > current else { return nil }
        let zipName = "MinorREST-\(version)-macos-arm64.zip"
        guard let zip = release.assets.first(where: { $0.name == zipName }),
              let sig = release.assets.first(where: { $0.name == zipName + ".sig" }),
              zip.browser_download_url.scheme == "https", sig.browser_download_url.scheme == "https"
        else { throw CoreError(.updateFeed, "assets") }
        return UpdateInfo(version: version, notes: release.body ?? "", pageURL: release.html_url,
                          zipURL: zip.browser_download_url, signatureURL: sig.browser_download_url, size: zip.size)
    }
}

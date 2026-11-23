import Foundation
import Synchronization

/// Cookie jar projektu (kap. 4): cookies z odpovědí včetně skoků redirectu, perzistence do JSON.
public final class CookieJar: Sendable {
    private struct State {
        var cookies: [Cookie] = []
        var changed = false
    }

    /// `cookies/<projectId>.json`; nil = jen v paměti.
    public let file: URL?
    private let state: Mutex<State>

    /// Načte soubor; chybějící nebo poškozený = prázdný jar (přepíše ho další uložení).
    public init(file: URL?) {
        self.file = file
        var s = State()
        if let file, let d = try? Data(contentsOf: file), let c = try? JSONDecoder().decode([Cookie].self, from: d) {
            s.cookies = c
        }
        state = Mutex(s)
    }

    public static func file(projectID: String, in appDir: URL) -> URL {
        appDir.appending(path: "cookies/\(projectID).json")
    }

    public var cookies: [Cookie] { state.withLock { $0.cookies } }

    public func clear() {
        state.withLock { s in
            s.changed = s.changed || !s.cookies.isEmpty
            s.cookies = []
        }
    }

    /// Hodnota hlavičky `Cookie` pro URL (delší cesta dřív); prázdná, když nic nepasuje.
    public func header(for url: URL, now: Date = Date()) -> String {
        guard let host = url.host(percentEncoded: false)?.lowercased() else { return "" }
        let path = url.path(percentEncoded: true).isEmpty ? "/" : url.path(percentEncoded: true)
        let secure = Self.isSecure(url)
        return state.withLock { s in
            s.cookies
                .filter { Self.domainMatch(host, $0.domain) && Self.pathMatch(path, $0.path) && (secure || !$0.secure) && !Self.expired($0, now) }
                .sorted { $0.path.count > $1.path.count }
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")
        }
    }

    /// Uloží cookies odpovědi (stejný název+doména+cesta nahradí, prošlé smaže).
    public func store(_ received: [Cookie], now: Date = Date()) {
        guard !received.isEmpty else { return }
        state.withLock { s in
            for c in received {
                s.cookies.removeAll { $0.name == c.name && $0.domain.lowercased() == c.domain.lowercased() && $0.path == c.path }
                if !Self.expired(c, now) { s.cookies.append(c) }
            }
            s.cookies.removeAll { Self.expired($0, now) }
            s.changed = true
        }
    }

    /// Zapíše soubor, pokud se od načtení/uložení změnil.
    public func save() throws {
        guard let file else { return }
        let data = try state.withLock { s -> Data? in
            guard s.changed else { return nil }
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let d = try enc.encode(s.cookies)
            s.changed = false
            return d
        }
        guard let data else { return }
        do {
            try FileIO.createDirectory(file.deletingLastPathComponent(), intermediate: true)
            try FileIO.writeAtomic(data, to: file)
        } catch {
            state.withLock { $0.changed = true }
            throw error
        }
    }

    // MARK: - Pravidla RFC 6265

    static func isSecure(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" || ["localhost", "127.0.0.1", "::1"].contains(url.host(percentEncoded: false)?.lowercased() ?? "")
    }

    static func domainMatch(_ host: String, _ domain: String) -> Bool {
        let d = domain.lowercased()
        guard d.hasPrefix(".") else { return host == d }
        return host == d.dropFirst() || host.hasSuffix(d)
    }

    static func pathMatch(_ path: String, _ cookiePath: String) -> Bool {
        let cp = cookiePath.isEmpty ? "/" : cookiePath
        guard path.hasPrefix(cp) else { return false }
        return path.count == cp.count || cp.hasSuffix("/") || path.dropFirst(cp.count).hasPrefix("/")
    }

    static func expired(_ c: Cookie, _ now: Date) -> Bool {
        guard !c.expires.isEmpty, let d = ISO8601DateFormatter().date(from: c.expires) else { return false }
        return d <= now
    }
}

/// Hlavičky `Set-Cookie` (URLSession je slučuje čárkou do jedné hodnoty).
enum SetCookie {
    /// Rozdělí sloučenou hodnotu na jednotlivé hlavičky (čárka v `Expires` zůstane).
    static func split(_ merged: String) -> [String] {
        merged.split(separator: /,\s*(?=[^;,=\s]+=)/).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Cookies z hlaviček odpovědi na `url`; `Domain` mimo host se zahodí.
    static func parse(_ lines: [String], for url: URL) -> [Cookie] {
        guard let host = url.host(percentEncoded: false)?.lowercased() else { return [] }
        let f = ISO8601DateFormatter()
        return lines.flatMap { HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": $0], for: url) }
            .filter { CookieJar.domainMatch(host, $0.domain) }
            .map { c in
                Cookie(name: c.name, value: c.value, domain: c.domain, path: c.path, expires: c.expiresDate.map(f.string) ?? "",
                       secure: c.isSecure, httpOnly: c.isHTTPOnly, sameSite: c.sameSitePolicy?.rawValue ?? "")
            }
    }
}

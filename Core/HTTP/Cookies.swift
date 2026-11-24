import Foundation
import Synchronization

/// Cookie jar projektu (kap. 4): cookies z odpovědí včetně skoků redirectu, perzistence do JSON.
nonisolated final class CookieJar: Sendable {
    private struct State {
        var cookies: [Cookie] = []
        var changed = false
    }

    /// `cookies/<projectId>.json`; nil = jen v paměti.
    let file: URL?
    private let state: Mutex<State>

    /// Načte soubor; chybějící nebo poškozený = prázdný jar (přepíše ho další uložení).
    init(file: URL?) {
        self.file = file
        var str = State()
        if let file, let dat = try? Data(contentsOf: file), let cur = try? JSONDecoder().decode([Cookie].self, from: dat) {
            str.cookies = cur
        }
        state = Mutex(str)
    }

    static func file(projectID: String, in appDir: URL) -> URL {
        appDir.appending(path: "cookies/\(projectID).json")
    }

    var cookies: [Cookie] { state.withLock { $0.cookies } }

    func clear() {
        state.withLock { str in
            str.changed = str.changed || !str.cookies.isEmpty
            str.cookies = []
        }
    }

    /// Hodnota hlavičky `Cookie` pro URL (delší cesta dřív); prázdná, když nic nepasuje.
    func header(for url: URL, now: Date = Date()) -> String {
        guard let host = url.host(percentEncoded: false)?.lowercased() else { return "" }
        let path = url.path(percentEncoded: true).isEmpty ? "/" : url.path(percentEncoded: true)
        let secure = Self.isSecure(url)
        return state.withLock { str in
            str.cookies
                .filter { Self.domainMatch(host, $0.domain) && Self.pathMatch(path, $0.path) && (secure || !$0.secure) && !Self.expired($0, now) }
                .sorted { $0.path.count > $1.path.count }
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")
        }
    }

    /// Uloží cookies odpovědi (stejný název+doména+cesta nahradí, prošlé smaže).
    func store(_ received: [Cookie], now: Date = Date()) {
        guard !received.isEmpty else { return }
        state.withLock { str in
            for cur in received {
                str.cookies.removeAll { $0.name == cur.name && $0.domain.lowercased() == cur.domain.lowercased() && $0.path == cur.path }
                if !Self.expired(cur, now) { str.cookies.append(cur) }
            }
            str.cookies.removeAll { Self.expired($0, now) }
            str.changed = true
        }
    }

    /// Zapíše soubor, pokud se od načtení/uložení změnil.
    func save() throws {
        guard let file else { return }
        let data = try state.withLock { str -> Data? in
            guard str.changed else { return nil }
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let dat = try enc.encode(str.cookies)
            str.changed = false
            return dat
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
        let dat = domain.lowercased()
        guard dat.hasPrefix(".") else { return host == dat }
        return host == dat.dropFirst() || host.hasSuffix(dat)
    }

    static func pathMatch(_ path: String, _ cookiePath: String) -> Bool {
        let cp = cookiePath.isEmpty ? "/" : cookiePath
        guard path.hasPrefix(cp) else { return false }
        return path.count == cp.count || cp.hasSuffix("/") || path.dropFirst(cp.count).hasPrefix("/")
    }

    static func expired(_ cur: Cookie, _ now: Date) -> Bool {
        guard !cur.expires.isEmpty, let dat = ISO8601DateFormatter().date(from: cur.expires) else { return false }
        return dat <= now
    }
}

/// Hlavičky `Set-Cookie` (URLSession je slučuje čárkou do jedné hodnoty).
nonisolated enum SetCookie {
    /// Rozdělí sloučenou hodnotu na jednotlivé hlavičky (čárka v `Expires` zůstane).
    static func split(_ merged: String) -> [String] {
        merged.split(separator: /,\s*(?=[^;,=\s]+=)/).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Cookies z hlaviček odpovědi na `url`; `Domain` mimo host se zahodí.
    static func parse(_ lines: [String], for url: URL) -> [Cookie] {
        guard let host = url.host(percentEncoded: false)?.lowercased() else { return [] }
        let fn = ISO8601DateFormatter()
        return lines.flatMap { HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": $0], for: url) }
            .filter { CookieJar.domainMatch(host, $0.domain) }
            .map { cur in
                Cookie(name: cur.name, value: cur.value, domain: cur.domain, path: cur.path, expires: cur.expiresDate.map(fn.string) ?? "",
                       secure: cur.isSecure, httpOnly: cur.isHTTPOnly, sameSite: cur.sameSitePolicy?.rawValue ?? "")
            }
    }
}

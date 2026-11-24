import Foundation

/// Request s vyhodnocenými proměnnými a sestavenou URL (vstup `HTTPEngine.send`).
nonisolated struct PreparedRequest: Sendable, Equatable {
    var method: String
    var url: String
    /// Odešlou se jen zapnuté, v zadaném pořadí.
    var headers: [KV]
    var body: Body
    /// Kořen projektu pro relativní cesty souborů.
    var baseDir: String
    /// Automatické hlavičky vypnuté uživatelem (`User-Agent`, `Accept`, `Content-Type`).
    var noAuto: [String]

    init(
        method: String, url: String, headers: [KV] = [], body: Body = Body(), baseDir: String = "",
        noAuto: [String] = []
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.baseDir = baseDir
        self.noAuto = noAuto
    }
}

/// Redirect jednoho skoku.
nonisolated struct Redirect: Sendable, Equatable {
    var status: Int
    var method: String
    var url: String
    var location: String
}

nonisolated struct TLSInfo: Sendable, Equatable {
    var version = ""
    var cipher = ""
    var serverName = ""
    var subject = ""
    var issuer = ""
    /// RFC 3339
    var notAfter = ""
}

/// Velikosti v bajtech.
nonisolated struct Sizes: Sendable, Equatable {
    var reqHeaders: Int64 = 0
    var reqBody: Int64 = 0
    var headers: Int64 = 0
    var bodyWire: Int64 = 0
    var bodyDecoded: Int64 = 0
}

/// Časy posledního skoku v ms.
nonisolated struct Timing: Sendable, Equatable {
    var dnsMs: Double = 0
    var connectMs: Double = 0
    var tlsMs: Double = 0
    var ttfbMs: Double = 0
    var downloadMs: Double = 0
    var totalMs: Double = 0
    var reused = false
}

/// Skutečně odeslaný request posledního skoku.
nonisolated struct SentRequest: Sendable, Equatable {
    var method = ""
    var url = ""
    var headers: [KV] = []
    var bodyPreview = ""
    var bodySize: Int64 = 0
}

/// Cookie z `Set-Cookie`; `domain` s tečkou na začátku = i subdomény, bez ní jen daný host.
nonisolated struct Cookie: Codable, Sendable, Equatable {
    var name: String
    var value: String
    var domain: String
    var path: String
    /// RFC 3339; prázdné = do konce relace (v jaru zůstává do smazání).
    var expires: String
    var secure: Bool
    var httpOnly: Bool
    var sameSite: String

    init(
        name: String, value: String, domain: String = "", path: String = "/", expires: String = "",
        secure: Bool = false, httpOnly: Bool = false, sameSite: String = ""
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expires = expires
        self.secure = secure
        self.httpOnly = httpOnly
        self.sameSite = sameSite
    }
}

/// Výsledek odeslání; tělo si UI vyžádá zvlášť (`HTTPEngine.body`).
nonisolated struct RunResult: Sendable, Equatable {
    let runID: String
    /// Při chybě jsou vyplněné jen `sent`, `timing` a `redirects` (pokud jsou).
    var error: CoreError?
    var status = 0
    var statusText = ""
    var proto = ""
    var remoteAddr = ""
    var localAddr = ""
    var tls: TLSInfo?
    /// Seřazené podle názvu (pořadí serveru URLSession nedává).
    var headers: [KV] = []
    var cookies: [Cookie] = []
    var sizes = Sizes()
    var timing = Timing()
    var redirects: [Redirect] = []
    var sent = SentRequest()
    var contentType = ""
    var charset = ""
    var isBinary = false
    var truncated = false
    var unresolved: [String] = []
    var extracted: [KV] = []
    var authSource = ""

    init(runID: String) { self.runID = runID }
}

nonisolated extension HTTPEngine {
    /// Výsledná (zděděná) nastavení odeslání.
    struct Options: Sendable, Equatable {
        var followRedirects = true
        var maxRedirects = 10
        /// 0 = bez limitu
        var timeoutMs = 30_000
        var verifyTLS = true
        var userAgent = ""
        var maxBodyBytes: Int64 = 100 << 20
        /// Použít cookie jar předaný do `send` (posílat i ukládat cookies).
        var cookieJar = true
        var proxy = Proxy.system

        init(
            followRedirects: Bool = true, maxRedirects: Int = 10, timeoutMs: Int = 30_000,
            verifyTLS: Bool = true, userAgent: String = "", cookieJar: Bool = true, proxy: Proxy = .system
        ) {
            self.followRedirects = followRedirects
            self.maxRedirects = maxRedirects
            self.timeoutMs = timeoutMs
            self.verifyTLS = verifyTLS
            self.userAgent = userAgent
            self.cookieJar = cookieJar
            self.proxy = proxy
        }

        /// Z nastavení složeného přes `over(.builtin)` (chybějící položky = výchozí hodnoty).
        init(_ str: HTTPSettings, userAgent: String) {
            self.init(
                followRedirects: str.followRedirects ?? true, maxRedirects: str.maxRedirects ?? 10,
                timeoutMs: str.timeoutMs ?? 30_000, verifyTLS: str.verifyTLS ?? true, userAgent: userAgent,
                cookieJar: str.cookieJar ?? true)
        }
    }

    /// Proxy odeslání (globální nastavení, kap. 9).
    enum Proxy: Sendable, Equatable {
        /// Systémové nastavení včetně PAC.
        case system
        case none
        /// HTTP proxy pro http i https (CONNECT).
        case manual(host: String, port: Int)

        /// `connectionProxyDictionary`; nil = systémové.
        var dictionary: [AnyHashable: Any]? {
            switch self {
            case .system: return nil
            case .none: return [:]
            case .manual(let host, let port):
                return [
                    kCFNetworkProxiesHTTPEnable: 1, kCFNetworkProxiesHTTPProxy: host, kCFNetworkProxiesHTTPPort: port,
                    kCFNetworkProxiesHTTPSEnable: 1, kCFNetworkProxiesHTTPSProxy: host, kCFNetworkProxiesHTTPSPort: port
                ]
            }
        }
    }
}

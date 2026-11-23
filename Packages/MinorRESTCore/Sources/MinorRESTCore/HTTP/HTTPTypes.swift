import Foundation

/// Request s vyhodnocenými proměnnými a sestavenou URL (vstup `HTTPEngine.send`).
public struct PreparedRequest: Sendable, Equatable {
    public var method: String
    public var url: String
    /// Odešlou se jen zapnuté, v zadaném pořadí.
    public var headers: [KV]
    public var body: Body
    /// Kořen projektu pro relativní cesty souborů.
    public var baseDir: String
    /// Automatické hlavičky vypnuté uživatelem (`User-Agent`, `Accept`, `Content-Type`).
    public var noAuto: [String]

    public init(method: String, url: String, headers: [KV] = [], body: Body = Body(), baseDir: String = "", noAuto: [String] = []) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.baseDir = baseDir
        self.noAuto = noAuto
    }
}

/// Redirect jednoho skoku.
public struct Redirect: Sendable, Equatable {
    public var status: Int
    public var method: String
    public var url: String
    public var location: String

    public init(status: Int, method: String, url: String, location: String) {
        self.status = status
        self.method = method
        self.url = url
        self.location = location
    }
}

public struct TLSInfo: Sendable, Equatable {
    public var version = ""
    public var cipher = ""
    public var serverName = ""
    public var subject = ""
    public var issuer = ""
    /// RFC 3339
    public var notAfter = ""
    public init() {}
}

/// Velikosti v bajtech.
public struct Sizes: Sendable, Equatable {
    public var reqHeaders: Int64 = 0
    public var reqBody: Int64 = 0
    public var headers: Int64 = 0
    public var bodyWire: Int64 = 0
    public var bodyDecoded: Int64 = 0
    public init() {}
}

/// Časy posledního skoku v ms.
public struct Timing: Sendable, Equatable {
    public var dnsMs: Double = 0
    public var connectMs: Double = 0
    public var tlsMs: Double = 0
    public var ttfbMs: Double = 0
    public var downloadMs: Double = 0
    public var totalMs: Double = 0
    public var reused = false
    public init() {}
}

/// Skutečně odeslaný request posledního skoku.
public struct SentRequest: Sendable, Equatable {
    public var method = ""
    public var url = ""
    public var headers: [KV] = []
    public var bodyPreview = ""
    public var bodySize: Int64 = 0
    public init() {}
}

/// Cookie z `Set-Cookie`; `domain` s tečkou na začátku = i subdomény, bez ní jen daný host.
public struct Cookie: Codable, Sendable, Equatable {
    public var name: String
    public var value: String
    public var domain: String
    public var path: String
    /// RFC 3339; prázdné = do konce relace (v jaru zůstává do smazání).
    public var expires: String
    public var secure: Bool
    public var httpOnly: Bool
    public var sameSite: String

    public init(name: String, value: String, domain: String = "", path: String = "/", expires: String = "",
                secure: Bool = false, httpOnly: Bool = false, sameSite: String = "") {
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
public struct RunResult: Sendable, Equatable {
    public let runID: String
    /// Při chybě jsou vyplněné jen `sent`, `timing` a `redirects` (pokud jsou).
    public var error: CoreError?
    public var status = 0
    public var statusText = ""
    public var proto = ""
    public var remoteAddr = ""
    public var localAddr = ""
    public var tls: TLSInfo?
    /// Seřazené podle názvu (pořadí serveru URLSession nedává).
    public var headers: [KV] = []
    public var cookies: [Cookie] = []
    public var sizes = Sizes()
    public var timing = Timing()
    public var redirects: [Redirect] = []
    public var sent = SentRequest()
    public var contentType = ""
    public var charset = ""
    public var isBinary = false
    public var truncated = false
    public var unresolved: [String] = []
    public var extracted: [KV] = []
    public var authSource = ""

    public init(runID: String) { self.runID = runID }
}

extension HTTPEngine {
    /// Výsledná (zděděná) nastavení odeslání.
    public struct Options: Sendable, Equatable {
        public var followRedirects = true
        public var maxRedirects = 10
        /// 0 = bez limitu
        public var timeoutMs = 30_000
        public var verifyTLS = true
        public var userAgent = ""
        public var maxBodyBytes: Int64 = 100 << 20
        /// Použít cookie jar předaný do `send` (posílat i ukládat cookies).
        public var cookieJar = true
        public var proxy = Proxy.system

        public init(followRedirects: Bool = true, maxRedirects: Int = 10, timeoutMs: Int = 30_000,
                    verifyTLS: Bool = true, userAgent: String = "", cookieJar: Bool = true, proxy: Proxy = .system) {
            self.followRedirects = followRedirects
            self.maxRedirects = maxRedirects
            self.timeoutMs = timeoutMs
            self.verifyTLS = verifyTLS
            self.userAgent = userAgent
            self.cookieJar = cookieJar
            self.proxy = proxy
        }

        /// Z nastavení složeného přes `over(.builtin)` (chybějící položky = výchozí hodnoty).
        public init(_ s: HTTPSettings, userAgent: String) {
            self.init(followRedirects: s.followRedirects ?? true, maxRedirects: s.maxRedirects ?? 10,
                      timeoutMs: s.timeoutMs ?? 30_000, verifyTLS: s.verifyTLS ?? true, userAgent: userAgent,
                      cookieJar: s.cookieJar ?? true)
        }
    }

    /// Proxy odeslání (globální nastavení, kap. 9).
    public enum Proxy: Sendable, Equatable {
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
                return [kCFNetworkProxiesHTTPEnable: 1, kCFNetworkProxiesHTTPProxy: host, kCFNetworkProxiesHTTPPort: port,
                        kCFNetworkProxiesHTTPSEnable: 1, kCFNetworkProxiesHTTPSProxy: host, kCFNetworkProxiesHTTPSPort: port]
            }
        }
    }
}

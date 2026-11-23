import Foundation
import Synchronization

/// Odesílá připravené requesty přes URLSession (kap. 4 plánu); každé odeslání má vlastní session.
public actor HTTPEngine {
    static let keepResults = 20

    /// Tělo posledních výsledků s údaji potřebnými pro zobrazení.
    struct Stored: Sendable {
        var body: ResponseBody
        var contentType: String
        var charset: String
        var isBinary: Bool
    }

    private var runs: [String: RunDelegate] = [:]
    private var results: [String: Stored] = [:]
    private var order: [String] = []

    public init() {}

    deinit {
        for s in results.values { s.body.remove() }
    }

    /// Zahodí všechny výsledky a smaže jejich temp soubory (ukončení aplikace).
    public func close() {
        for s in results.values { s.body.remove() }
        results = [:]
        order = []
    }

    /// Zruší běžící odeslání (výsledek `CANCELED`); neznámé runID ignoruje.
    public func cancel(runID: String) {
        runs[runID]?.cancel(CoreError(.canceled))
    }

    /// Odešle request; chyby jsou v `RunResult.error` (s částečným výsledkem).
    /// `jar` se použije jen při `o.cookieJar` (doplní `Cookie`, uloží `Set-Cookie` i ze skoků redirectu; na disk ne).
    public func send(runID: String, _ r: PreparedRequest, _ o: Options, jar: CookieJar? = nil) async -> RunResult {
        var res = RunResult(runID: runID)
        var req: URLRequest, payload: Payload
        do { (req, payload) = try Self.makeRequest(r, o) } catch { res.error = error; return res }
        res.sent.bodySize = payload.size
        res.sent.bodyPreview = payload.preview
        let jar = o.cookieJar ? jar : nil
        let userCookie = req.value(forHTTPHeaderField: "Cookie")
        if let jar, let u = req.url { req.setValue(Self.cookieHeader(userCookie, jar.header(for: u)), forHTTPHeaderField: "Cookie") }

        let d = RunDelegate(options: o, payload: payload, jar: jar, userCookie: userCookie)
        runs[runID] = d
        defer { if runs[runID] === d { runs[runID] = nil } }
        let timeout: Task<Void, Never>? = o.timeoutMs > 0 ? Task { [d] in
            try? await Task.sleep(for: .milliseconds(o.timeoutMs))
            if !Task.isCancelled { d.cancel(CoreError(.netTimeout, "\(o.timeoutMs) ms")) }
        } : nil
        let out = await withTaskCancellationHandler {
            await d.run(req)
        } onCancel: {
            d.cancel(CoreError(.canceled))
        }
        timeout?.cancel()

        res.redirects = out.redirects
        res.sent.method = out.sentMethod
        res.sent.url = out.sentURL
        res.sent.headers = out.sentHeaders
        res.timing = out.timing
        res.sizes = out.sizes
        res.remoteAddr = out.remoteAddr
        res.localAddr = out.localAddr
        if !out.redirects.isEmpty, out.sentMethod != req.httpMethod, out.sentMethod == HTTPMethod.get {
            res.sent.bodySize = 0  // po 301–303 se tělo zahodí
            res.sent.bodyPreview = ""
        }
        if let e = out.error {
            res.error = e
            return res
        }
        res.status = out.status
        res.statusText = HTTPStatus.text(out.status)
        res.proto = out.proto
        res.tls = out.tls
        res.headers = out.headers
        res.cookies = out.cookies
        res.truncated = out.truncated

        let ct = out.headers.first { $0.name.lowercased() == "content-type" }?.value ?? ""
        let sample: Data
        do { sample = try out.body.read(limit: ResponseBody.sniffLen) } catch {
            out.body.remove()
            res.error = error
            return res
        }
        (res.contentType, res.charset, res.isBinary) = ContentSniff.sniff(ct, sample)
        keep(runID, Stored(body: out.body, contentType: res.contentType, charset: res.charset, isBinary: res.isBinary))
        return res
    }

    /// Tělo pro zobrazení v UTF-8; `pretty` odsadí JSON (nevalidní nechá beze změny).
    public func body(runID: String, pretty: Bool) throws(CoreError) -> BodyView {
        let s = try stored(runID)
        var v = BodyView()
        v.lang = BodyView.lang(s.contentType)
        v.size = s.body.size
        if s.isBinary {
            if s.contentType.hasPrefix("image/") { v.image = try s.body.read() }
            return v
        }
        let b = try s.body.read(limit: BodyView.maxView)
        v.partial = v.size > Int64(b.count)
        v.text = ContentSniff.toUTF8(b, s.charset)
        if pretty, v.lang == "json", !v.partial, let f = try? JSONFormatter.format(v.text) { v.text = f }
        return v
    }

    /// Surové (dekomprimované) tělo odpovědi držené v posledních výsledcích.
    func data(runID: String) throws(CoreError) -> Data {
        try stored(runID).body.read()
    }

    /// Začátek surového těla (historie, uložení odpovědi).
    public func rawBody(runID: String, limit: Int) throws(CoreError) -> Data {
        try stored(runID).body.read(limit: limit)
    }

    func stored(_ runID: String) throws(CoreError) -> Stored {
        guard let s = results[runID] else { throw CoreError(.runNotFound, runID) }
        return s
    }

    func keep(_ runID: String, _ s: Stored) {
        if let old = results[runID], old.body != s.body { old.body.remove() }
        order.removeAll { $0 == runID }
        results[runID] = s
        order.append(runID)
        while order.count > Self.keepResults {
            results.removeValue(forKey: order.removeFirst())?.body.remove()
        }
    }

    // MARK: - Sestavení URLRequest

    /// Uživatelská hlavička `Cookie` + cookies z jaru; nil = žádná.
    static func cookieHeader(_ user: String?, _ jar: String) -> String? {
        let parts = [user ?? "", jar].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    private static let tokenChars = Set("!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    static func makeRequest(_ r: PreparedRequest, _ o: Options) throws(CoreError) -> (URLRequest, Payload) {
        let method = r.method.uppercased()
        guard !method.isEmpty, method.allSatisfy({ tokenChars.contains($0) }) else { throw CoreError(.methodInvalid, r.method) }
        guard let u = URL(string: r.url), let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = u.host(), !host.isEmpty else { throw CoreError(.urlInvalid, r.url) }
        var payload = try Payload.build(r.body, baseDir: r.baseDir)
        // URLSession tělo u GET/HEAD odmítne (NSURLErrorDataLengthExceedsMaximum), ani jako stream.
        if method == HTTPMethod.get || method == HTTPMethod.head {
            if payload.size > 0 { throw CoreError(.bodyNotAllowed, method) }
            payload = Payload()
        }

        var req = URLRequest(url: u)
        req.httpMethod = method
        var has = Set<String>()
        for h in r.headers where h.enabled {
            let name = h.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            has.insert(key)
            if key == "host" || key == "content-length" { continue }  // určuje URLSession
            req.addValue(h.value, forHTTPHeaderField: name)
        }
        let off = Set(r.noAuto.map { $0.lowercased() })
        func auto(_ name: String, _ value: String) {
            let key = name.lowercased()
            if !has.contains(key), !off.contains(key), !value.isEmpty { req.setValue(value, forHTTPHeaderField: name) }
        }
        auto("User-Agent", o.userAgent)
        auto("Accept", "*/*")
        if !payload.isEmpty {
            auto("Content-Type", payload.contentType)
            fixBoundary(&req, payload.contentType)
        }
        // Prázdná hodnota = neposlat; jinak by systém doplnil vlastní.
        if !has.contains("user-agent"), off.contains("user-agent") || o.userAgent.isEmpty { req.setValue("", forHTTPHeaderField: "User-Agent") }
        if !has.contains("accept"), off.contains("accept") { req.setValue("", forHTTPHeaderField: "Accept") }

        switch payload.source {
        case .none: break
        case .data(let d): req.httpBody = d
        case .file:
            req.httpBodyStream = payload.stream()
            req.setValue(String(payload.size), forHTTPHeaderField: "Content-Length")
        }
        return (req, payload)
    }

    /// Doplní boundary do uživatelského multipart Content-Type bez něj.
    private static func fixBoundary(_ req: inout URLRequest, _ autoCT: String) {
        guard let ct = req.value(forHTTPHeaderField: "Content-Type"), let b = autoCT.range(of: "boundary=") else { return }
        let lower = ct.lowercased()
        if lower.hasPrefix("multipart/"), !lower.contains("boundary=") {
            req.setValue(ct + "; " + autoCT[b.lowerBound...], forHTTPHeaderField: "Content-Type")
        }
    }
}

// MARK: - Delegát jednoho odeslání

/// Výsledek z delegáta (jen Sendable hodnoty).
struct RunOutcome: Sendable {
    var error: CoreError?
    var status = 0
    var proto = ""
    var headers: [KV] = []
    /// Přijaté cookies celého běhu (i ze skoků redirectu).
    var cookies: [Cookie] = []
    var body = ResponseBody.data(Data())
    var truncated = false
    var redirects: [Redirect] = []
    var sentMethod = ""
    var sentURL = ""
    var sentHeaders: [KV] = []
    var timing = Timing()
    var sizes = Sizes()
    var remoteAddr = ""
    var localAddr = ""
    var tls: TLSInfo?
}

final class RunDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<RunOutcome, Never>?
        var task: URLSessionTask?
        var cause: CoreError?
        var sink: BodySink
        var redirects: [Redirect] = []
        var cookies: [Cookie] = []
        /// `Authorization` původního requestu a jeho host (URLSession ji při redirectu zahodí vždy).
        var authorization: (host: String, value: String)?
        var proto = ""
        var metrics = RunOutcome()
        /// Leaf certifikát podle hostu (subjekt, vydavatel, expirace).
        var certs: [String: TLSInfo] = [:]
    }

    private let state: Mutex<State>
    private let options: HTTPEngine.Options
    private let payload: Payload
    private let jar: CookieJar?
    private let userCookie: String?

    init(options: HTTPEngine.Options, payload: Payload, jar: CookieJar? = nil, userCookie: String? = nil) {
        self.options = options
        self.payload = payload
        self.jar = jar
        self.userCookie = userCookie
        state = Mutex(State(sink: BodySink(max: options.maxBodyBytes)))
    }

    func run(_ req: URLRequest) async -> RunOutcome {
        await withCheckedContinuation { (c: CheckedContinuation<RunOutcome, Never>) in
            let cfg = URLSessionConfiguration.ephemeral
            cfg.urlCache = nil
            cfg.httpCookieStorage = nil
            cfg.httpShouldSetCookies = false
            cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            // Celkový limit hlídá engine; tohle je jen limit nečinnosti.
            cfg.timeoutIntervalForRequest = options.timeoutMs > 0 ? Double(options.timeoutMs) / 1000 + 5 : 7 * 86400
            cfg.timeoutIntervalForResource = 7 * 86400
            if let p = options.proxy.dictionary { cfg.connectionProxyDictionary = p }
            let session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
            let task = session.dataTask(with: req)
            let canceled = state.withLock { s in
                if let v = req.value(forHTTPHeaderField: "Authorization"), let h = req.url?.host()?.lowercased() {
                    s.authorization = (h, v)
                }
                s.continuation = c
                s.task = task
                return s.cause != nil
            }
            task.resume()
            if canceled { task.cancel() }
        }
    }

    /// Zruší task s příčinou (první příčina vyhrává).
    func cancel(_ cause: CoreError) {
        let task = state.withLock { s -> URLSessionTask? in
            if s.cause == nil { s.cause = cause }
            return s.task
        }
        task?.cancel()
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = space.serverTrust,
           let c = TLSNames.certificate(trust) {
            var info = TLSInfo()
            (info.subject, info.issuer, info.notAfter) = c
            state.withLock { $0.certs[space.host.lowercased()] = info }
        }
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           !options.verifyTLS, let trust = space.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    /// Cookies z odpovědi: do výsledku běhu a do jaru.
    private func receiveCookies(_ r: HTTPURLResponse) {
        guard let v = r.value(forHTTPHeaderField: "Set-Cookie"), let u = r.url else { return }
        let got = SetCookie.parse(SetCookie.split(v), for: u)
        guard !got.isEmpty else { return }
        jar?.store(got)
        state.withLock { s in
            for c in got {
                s.cookies.removeAll { $0.name == c.name && $0.domain == c.domain && $0.path == c.path }
                s.cookies.append(c)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        receiveCookies(response)
        guard options.followRedirects else { return completionHandler(nil) }
        let prev = task.currentRequest
        let hop = Redirect(status: response.statusCode, method: prev?.httpMethod ?? "",
                           url: prev?.url?.absoluteString ?? "",
                           location: response.value(forHTTPHeaderField: "Location") ?? request.url?.absoluteString ?? "")
        let count = state.withLock { s in
            s.redirects.append(hop)
            return s.redirects.count
        }
        if count > options.maxRedirects {
            cancel(CoreError(.redirectLimit, String(options.maxRedirects)))
            return completionHandler(nil)
        }
        var next = request
        // Jen na původní host (při změně hostu se neposílá).
        let auth = state.withLock { $0.authorization }
        next.setValue(auth.flatMap { $0.host == request.url?.host()?.lowercased() ? $0.value : nil }, forHTTPHeaderField: "Authorization")
        if let jar, let u = request.url { next.setValue(HTTPEngine.cookieHeader(userCookie, jar.header(for: u)), forHTTPHeaderField: "Cookie") }
        completionHandler(next)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping @Sendable (InputStream?) -> Void) {
        completionHandler(payload.stream())
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let r = state.withLock { s -> Result<Bool, CoreError> in
            do throws(CoreError) { return .success(try s.sink.append(data)) } catch { return .failure(error) }
        }
        switch r {
        case .success(true): break
        case .success(false): dataTask.cancel()  // limit maxBodyBytes → truncated, odpověď platí
        case .failure(let e): cancel(e)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let t = metrics.transactionMetrics.last else { return }
        var m = RunOutcome()
        func ms(_ a: Date?, _ b: Date?) -> Double {
            guard let a, let b else { return 0 }
            return max(0, b.timeIntervalSince(a) * 1000)
        }
        m.timing.dnsMs = ms(t.domainLookupStartDate, t.domainLookupEndDate)
        m.timing.connectMs = ms(t.connectStartDate, t.secureConnectionStartDate ?? t.connectEndDate)
        m.timing.tlsMs = ms(t.secureConnectionStartDate, t.secureConnectionEndDate)
        m.timing.ttfbMs = ms(t.requestEndDate, t.responseStartDate)
        m.timing.downloadMs = ms(t.responseStartDate, t.responseEndDate)
        m.timing.totalMs = metrics.taskInterval.duration * 1000
        m.timing.reused = t.isReusedConnection
        m.remoteAddr = Self.address(t.remoteAddress, t.remotePort)
        m.localAddr = Self.address(t.localAddress, t.localPort)
        m.sizes.reqHeaders = t.countOfRequestHeaderBytesSent
        m.sizes.reqBody = t.countOfRequestBodyBytesSent
        m.sizes.headers = t.countOfResponseHeaderBytesReceived
        m.sizes.bodyWire = t.countOfResponseBodyBytesReceived
        m.sizes.bodyDecoded = t.countOfResponseBodyBytesAfterDecoding
        if let v = t.negotiatedTLSProtocolVersion {
            var info = TLSInfo()
            info.version = TLSNames.version(v.rawValue)
            info.cipher = t.negotiatedTLSCipherSuite.map { TLSNames.cipher($0.rawValue) } ?? ""
            info.serverName = t.request.url?.host() ?? ""
            m.tls = info
        }
        let proto = t.networkProtocolName ?? ""
        state.withLock { s in
            s.metrics = m
            s.proto = proto
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        session.finishTasksAndInvalidate()
        if let r = task.response as? HTTPURLResponse { receiveCookies(r) }
        let sent = task.currentRequest
        let c = state.withLock { s -> (CheckedContinuation<RunOutcome, Never>?, RunOutcome) in
            var out = s.metrics
            out.redirects = s.redirects
            out.cookies = s.cookies
            out.proto = HTTPStatus.proto(s.proto)
            if let cause = s.cause {
                out.error = cause
            } else if let error, !s.sink.truncated {
                out.error = Self.classify(error)
            }
            if out.tls != nil, let cert = s.certs[out.tls!.serverName.lowercased()] {
                (out.tls!.subject, out.tls!.issuer, out.tls!.notAfter) = (cert.subject, cert.issuer, cert.notAfter)
            }
            if out.error == nil {
                out.truncated = s.sink.truncated
                out.body = s.sink.finish()
            } else {
                s.sink.discard()
            }
            defer { s.continuation = nil; s.task = nil }
            return (s.continuation, out)
        }
        var out = c.1
        out.sentMethod = sent?.httpMethod ?? ""
        out.sentURL = sent?.url?.absoluteString ?? ""
        out.sentHeaders = Self.sentHeaders(sent, proto: out.proto)
        if out.error == nil, let r = task.response as? HTTPURLResponse {
            out.status = r.statusCode
            out.headers = Self.rows(r.allHeaderFields.reduce(into: [String: String]()) { $0["\($1.key)"] = "\($1.value)" })
        } else if out.error == nil {
            out.body.remove()
            out.body = .data(Data())
            out.error = CoreError(.netError, "no response")
        }
        c.0?.resume(returning: out)
    }

    /// Řádky seřazené podle názvu; sloučené `Set-Cookie` rozdělí na samostatné řádky.
    static func rows(_ h: [String: String]) -> [KV] {
        h.sorted { $0.key.lowercased() < $1.key.lowercased() }.flatMap { k, v in
            k.lowercased() == "set-cookie" ? SetCookie.split(v).map { KV(name: k, value: $0) } : [KV(name: k, value: v)]
        }
    }

    /// Hlavičky z `currentRequest` (bez prázdných – ty se neodešlou) + odvozené `Host`, `Connection`, `Cache-Control`.
    static func sentHeaders(_ r: URLRequest?, proto: String) -> [KV] {
        var h = (r?.allHTTPHeaderFields ?? [:]).filter { !$0.value.isEmpty }
        let has = Set(h.keys.map { $0.lowercased() })
        if !has.contains("host"), let u = r?.url, let host = u.host(percentEncoded: false) {
            let name = host.contains(":") ? "[\(host)]" : host
            h["Host"] = u.port.map { "\(name):\($0)" } ?? name
        }
        if proto == "HTTP/1.1", !has.contains("connection") { h["Connection"] = "keep-alive" }
        // Doplní URLSession kvůli `reloadIgnoringLocalAndRemoteCacheData`.
        if !has.contains("cache-control") { h["Cache-Control"] = "no-cache" }
        return rows(h)
    }

    static func address(_ ip: String?, _ port: Int?) -> String {
        guard let ip, !ip.isEmpty else { return "" }
        let host = ip.contains(":") ? "[\(ip)]" : ip
        return port.map { "\(host):\($0)" } ?? host
    }

    /// Převod chyby URLSession na kód (kap. 4).
    static func classify(_ error: any Error) -> CoreError {
        let ns = error as NSError
        let detail = ns.localizedDescription
        guard ns.domain == NSURLErrorDomain else { return CoreError(.netError, detail) }
        switch URLError.Code(rawValue: ns.code) {
        case .cannotFindHost, .dnsLookupFailed: return CoreError(.netDNS, detail)
        case .cannotConnectToHost: return CoreError(.netRefused, detail)
        case .timedOut: return CoreError(.netTimeout, detail)
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .clientCertificateRejected, .clientCertificateRequired:
            return CoreError(.tlsVerify, detail)
        case .secureConnectionFailed: return CoreError(.tlsError, detail)
        case .cancelled: return CoreError(.canceled)
        case .httpTooManyRedirects: return CoreError(.redirectLimit, detail)
        case .badURL, .unsupportedURL: return CoreError(.urlInvalid, detail)
        default: return CoreError(.netError, detail)
        }
    }
}

enum HTTPStatus {
    /// `http/1.1` → `HTTP/1.1`, `h2` → `HTTP/2`, `h3` → `HTTP/3`.
    static func proto(_ name: String) -> String {
        switch name.lowercased() {
        case "h2": "HTTP/2"
        case "h3", "h3-29": "HTTP/3"
        case "": ""
        default: name.uppercased()
        }
    }

    /// Standardní text stavu (skutečný reason phrase URLSession nedává).
    static func text(_ code: Int) -> String { texts[code] ?? "" }

    private static let texts: [Int: String] = [
        100: "Continue", 101: "Switching Protocols", 102: "Processing", 103: "Early Hints",
        200: "OK", 201: "Created", 202: "Accepted", 203: "Non-Authoritative Information", 204: "No Content",
        205: "Reset Content", 206: "Partial Content", 207: "Multi-Status", 208: "Already Reported", 226: "IM Used",
        300: "Multiple Choices", 301: "Moved Permanently", 302: "Found", 303: "See Other", 304: "Not Modified",
        305: "Use Proxy", 307: "Temporary Redirect", 308: "Permanent Redirect",
        400: "Bad Request", 401: "Unauthorized", 402: "Payment Required", 403: "Forbidden", 404: "Not Found",
        405: "Method Not Allowed", 406: "Not Acceptable", 407: "Proxy Authentication Required", 408: "Request Timeout",
        409: "Conflict", 410: "Gone", 411: "Length Required", 412: "Precondition Failed", 413: "Content Too Large",
        414: "URI Too Long", 415: "Unsupported Media Type", 416: "Range Not Satisfiable", 417: "Expectation Failed",
        418: "I'm a teapot", 421: "Misdirected Request", 422: "Unprocessable Content", 423: "Locked",
        424: "Failed Dependency", 425: "Too Early", 426: "Upgrade Required", 428: "Precondition Required",
        429: "Too Many Requests", 431: "Request Header Fields Too Large", 451: "Unavailable For Legal Reasons",
        500: "Internal Server Error", 501: "Not Implemented", 502: "Bad Gateway", 503: "Service Unavailable",
        504: "Gateway Timeout", 505: "HTTP Version Not Supported", 506: "Variant Also Negotiates",
        507: "Insufficient Storage", 508: "Loop Detected", 510: "Not Extended", 511: "Network Authentication Required",
    ]
}

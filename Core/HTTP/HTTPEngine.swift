import Foundation
import Synchronization

/// Odesílá připravené requesty přes URLSession (kap. 4 plánu); každé odeslání má vlastní session.
actor HTTPEngine {
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

    /// Vlastní `URLProtocol` třídy (testy bez sítě); v aplikaci prázdné.
    private nonisolated(unsafe) let protocolClasses: [AnyClass]

    init(protocolClasses: [AnyClass] = []) {
        self.protocolClasses = protocolClasses
    }

    deinit {
        for str in results.values { str.body.remove() }
    }

    /// Zahodí všechny výsledky a smaže jejich temp soubory (ukončení aplikace).
    func close() {
        for str in results.values { str.body.remove() }
        results = [:]
        order = []
    }

    /// Zruší běžící odeslání (výsledek `CANCELED`); neznámé runID ignoruje.
    func cancel(runID: String) {
        runs[runID]?.cancel(CoreError(.canceled))
    }

    /// Odešle request; chyby jsou v `RunResult.error` (s částečným výsledkem).
    /// `jar` se použije jen při `o.cookieJar` (doplní `Cookie`, uloží `Set-Cookie` i ze skoků redirectu; na disk ne).
    func send(runID: String, _ resVal: PreparedRequest, _ opt: Options, jar: CookieJar? = nil) async -> RunResult {
        var res = RunResult(runID: runID)
        var req: URLRequest
        var payload: Payload
        do { (req, payload) = try Self.makeRequest(resVal, opt) } catch {
            res.error = error
            return res
        }
        res.sent.bodySize = payload.size
        res.sent.bodyPreview = payload.preview
        let jar = opt.cookieJar ? jar : nil
        let userCookie = req.value(forHTTPHeaderField: "Cookie")
        if let jar, let urlVal = req.url {
            req.setValue(Self.cookieHeader(userCookie, jar.header(for: urlVal)), forHTTPHeaderField: "Cookie")
        }

        let dat = RunDelegate(
            options: opt, payload: payload, jar: jar, userCookie: userCookie, protocolClasses: protocolClasses)
        runs[runID] = dat
        defer { if runs[runID] === dat { runs[runID] = nil } }
        let timeout: Task<Void, Never>? =
            opt.timeoutMs > 0
            ? Task { [dat] in
                try? await Task.sleep(for: .milliseconds(opt.timeoutMs))
                if !Task.isCancelled { dat.cancel(CoreError(.netTimeout, "\(opt.timeoutMs) ms")) }
            } : nil
        let out = await withTaskCancellationHandler {
            await dat.run(req)
        } onCancel: {
            dat.cancel(CoreError(.canceled))
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
        if let elem = out.error {
            res.error = elem
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

    /// Tělo pro zobrazení v UTF-8; `pretty` odsadí JSON (nevalidní nechá beze změny), XML a HTML – jen celé tělo.
    func body(runID: String, pretty: Bool) throws(CoreError) -> BodyView {
        let str = try stored(runID)
        var val = BodyView()
        val.lang = BodyView.lang(str.contentType)
        val.size = str.body.size
        if str.isBinary {
            if str.contentType.hasPrefix("image/"), val.size <= BodyView.maxImage { val.image = try str.body.read() }
            return val
        }
        val.partial = val.size > BodyView.maxView
        let buf = try str.body.read(limit: val.partial ? BodyView.headView : nil)
        val.text = ContentSniff.toUTF8(buf, str.charset)
        guard pretty, !val.partial else { return val }
        switch val.lang {
        case "json": if let fn = try? JSONFormatter.format(val.text) { val.text = fn }
        case "xml", "html": val.text = MarkupFormatter.format(val.text, html: val.lang == "html")
        default: break
        }
        return val
    }

    /// JSONPath filtr nad celým tělem (do `BodyView.maxView`); výsledek = odsazené pole shod.
    func filter(runID: String, jsonPath: String) throws(CoreError) -> String {
        let str = try stored(runID)
        guard !str.isBinary, str.body.size <= BodyView.maxView else {
            throw CoreError(.jsonInvalid, "body not available")
        }
        return try JSONPath.filter(json: ContentSniff.toUTF8(try str.body.read(), str.charset), jsonPath)
    }

    /// Uložení surového (dekomprimovaného) těla do souboru.
    func saveBody(runID: String, to url: URL) throws(CoreError) {
        try stored(runID).body.save(to: url)
    }

    /// Surové (dekomprimované) tělo odpovědi držené v posledních výsledcích.
    func data(runID: String) throws(CoreError) -> Data {
        try stored(runID).body.read()
    }

    /// Začátek surového těla (historie, uložení odpovědi).
    func rawBody(runID: String, limit: Int) throws(CoreError) -> Data {
        try stored(runID).body.read(limit: limit)
    }

    func stored(_ runID: String) throws(CoreError) -> Stored {
        guard let str = results[runID] else { throw CoreError(.runNotFound, runID) }
        return str
    }

    func keep(_ runID: String, _ str: Stored) {
        if let old = results[runID], old.body != str.body { old.body.remove() }
        order.removeAll { $0 == runID }
        results[runID] = str
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

    static func makeRequest(_ resVal: PreparedRequest, _ opt: Options) throws(CoreError) -> (URLRequest, Payload) {
        let method = resVal.method.uppercased()
        guard !method.isEmpty, method.allSatisfy({ tokenChars.contains($0) }) else {
            throw CoreError(.methodInvalid, resVal.method)
        }
        guard let urlVal = URL(string: resVal.url), let scheme = urlVal.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = urlVal.host(), !host.isEmpty
        else { throw CoreError(.urlInvalid, resVal.url) }
        var payload = try Payload.build(resVal.body, baseDir: resVal.baseDir)
        // URLSession tělo u GET/HEAD odmítne (NSURLErrorDataLengthExceedsMaximum), ani jako stream.
        if method == HTTPMethod.get || method == HTTPMethod.head {
            if payload.size > 0 { throw CoreError(.bodyNotAllowed, method) }
            payload = Payload()
        }

        var req = URLRequest(url: urlVal)
        req.httpMethod = method
        var has = Set<String>()
        for hdr in resVal.headers where hdr.enabled {
            let name = hdr.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            has.insert(key)
            if key == "host" || key == "content-length" { continue }  // určuje URLSession
            req.addValue(hdr.value, forHTTPHeaderField: name)
        }
        let off = Set(resVal.noAuto.map { $0.lowercased() })
        func auto(_ name: String, _ value: String) {
            let key = name.lowercased()
            if !has.contains(key), !off.contains(key), !value.isEmpty { req.setValue(value, forHTTPHeaderField: name) }
        }
        auto("User-Agent", opt.userAgent)
        auto("Accept", "*/*")
        if !payload.isEmpty {
            auto("Content-Type", payload.contentType)
            fixBoundary(&req, payload.contentType)
        }
        // Prázdná hodnota = neposlat; jinak by systém doplnil vlastní.
        if !has.contains("user-agent"), off.contains("user-agent") || opt.userAgent.isEmpty {
            req.setValue("", forHTTPHeaderField: "User-Agent")
        }
        if !has.contains("accept"), off.contains("accept") { req.setValue("", forHTTPHeaderField: "Accept") }

        switch payload.source {
        case .none: break
        case .data(let dat): req.httpBody = dat
        case .file:
            req.httpBodyStream = payload.stream()
            req.setValue(String(payload.size), forHTTPHeaderField: "Content-Length")
        }
        return (req, payload)
    }

    /// Doplní boundary do uživatelského multipart Content-Type bez něj.
    private static func fixBoundary(_ req: inout URLRequest, _ autoCT: String) {
        guard let ct = req.value(forHTTPHeaderField: "Content-Type"), let buf = autoCT.range(of: "boundary=") else {
            return
        }
        let lower = ct.lowercased()
        if lower.hasPrefix("multipart/"), !lower.contains("boundary=") {
            req.setValue(ct + "; " + autoCT[buf.lowerBound...], forHTTPHeaderField: "Content-Type")
        }
    }
}

// MARK: - Delegát jednoho odeslání

/// Výsledek z delegáta (jen Sendable hodnoty).
nonisolated struct RunOutcome: Sendable {
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

nonisolated final class RunDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
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

    private nonisolated(unsafe) let protocolClasses: [AnyClass]

    init(
        options: HTTPEngine.Options, payload: Payload, jar: CookieJar? = nil, userCookie: String? = nil,
        protocolClasses: [AnyClass] = []
    ) {
        self.protocolClasses = protocolClasses
        self.options = options
        self.payload = payload
        self.jar = jar
        self.userCookie = userCookie
        state = Mutex(State(sink: BodySink(max: options.maxBodyBytes)))
    }

    func run(_ req: URLRequest) async -> RunOutcome {
        await withCheckedContinuation { (cur: CheckedContinuation<RunOutcome, Never>) in
            let cfg = URLSessionConfiguration.ephemeral
            cfg.urlCache = nil
            if !protocolClasses.isEmpty { cfg.protocolClasses = protocolClasses }
            cfg.httpCookieStorage = nil
            cfg.httpShouldSetCookies = false
            cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            // Celkový limit hlídá engine; tohle je jen limit nečinnosti.
            cfg.timeoutIntervalForRequest = options.timeoutMs > 0 ? Double(options.timeoutMs) / 1000 + 5 : 7 * 86400
            cfg.timeoutIntervalForResource = 7 * 86400
            if let par = options.proxy.dictionary { cfg.connectionProxyDictionary = par }
            let session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
            let task = session.dataTask(with: req)
            let canceled = state.withLock { str in
                if let val = req.value(forHTTPHeaderField: "Authorization"), let hdr = req.url?.host()?.lowercased() {
                    str.authorization = (hdr, val)
                }
                str.continuation = cur
                str.task = task
                return str.cause != nil
            }
            task.resume()
            if canceled { task.cancel() }
        }
    }

    /// Zruší task s příčinou (první příčina vyhrává).
    func cancel(_ cause: CoreError) {
        let task = state.withLock { str -> URLSessionTask? in
            if str.cause == nil { str.cause = cause }
            return str.task
        }
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = space.serverTrust,
            let cur = TLSNames.certificate(trust) {
            var info = TLSInfo()
            (info.subject, info.issuer, info.notAfter) = cur
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
    private func receiveCookies(_ resVal: HTTPURLResponse) {
        guard let val = resVal.value(forHTTPHeaderField: "Set-Cookie"), let urlVal = resVal.url else { return }
        let got = SetCookie.parse(SetCookie.split(val), for: urlVal)
        guard !got.isEmpty else { return }
        jar?.store(got)
        state.withLock { str in
            for cur in got {
                str.cookies.removeAll { $0.name == cur.name && $0.domain == cur.domain && $0.path == cur.path }
                str.cookies.append(cur)
            }
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        receiveCookies(response)
        guard options.followRedirects else { return completionHandler(nil) }
        let prev = task.currentRequest
        let hop = Redirect(
            status: response.statusCode, method: prev?.httpMethod ?? "",
            url: prev?.url?.absoluteString ?? "",
            location: response.value(forHTTPHeaderField: "Location") ?? request.url?.absoluteString ?? "")
        let count = state.withLock { str in
            str.redirects.append(hop)
            return str.redirects.count
        }
        if count > options.maxRedirects {
            cancel(CoreError(.redirectLimit, String(options.maxRedirects)))
            return completionHandler(nil)
        }
        var next = request
        // Jen na původní host (při změně hostu se neposílá).
        let auth = state.withLock { $0.authorization }
        next.setValue(
            auth.flatMap { $0.host == request.url?.host()?.lowercased() ? $0.value : nil },
            forHTTPHeaderField: "Authorization")
        if let jar, let urlVal = request.url {
            next.setValue(HTTPEngine.cookieHeader(userCookie, jar.header(for: urlVal)), forHTTPHeaderField: "Cookie")
        }
        completionHandler(next)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        needNewBodyStream completionHandler: @escaping @Sendable (InputStream?) -> Void
    ) {
        completionHandler(payload.stream())
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let resVal = state.withLock { str -> Result<Bool, CoreError> in
            do throws(CoreError) { return .success(try str.sink.append(data)) } catch { return .failure(error) }
        }
        switch resVal {
        case .success(true): break
        case .success(false): dataTask.cancel()  // limit maxBodyBytes → truncated, odpověď platí
        case .failure(let elem): cancel(elem)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let txt = metrics.transactionMetrics.last else { return }
        var map = RunOutcome()
        func ms(_ arg: Date?, _ buf: Date?) -> Double {
            guard let arg, let buf else { return 0 }
            return max(0, buf.timeIntervalSince(arg) * 1000)
        }
        map.timing.dnsMs = ms(txt.domainLookupStartDate, txt.domainLookupEndDate)
        map.timing.connectMs = ms(txt.connectStartDate, txt.secureConnectionStartDate ?? txt.connectEndDate)
        map.timing.tlsMs = ms(txt.secureConnectionStartDate, txt.secureConnectionEndDate)
        map.timing.ttfbMs = ms(txt.requestEndDate, txt.responseStartDate)
        map.timing.downloadMs = ms(txt.responseStartDate, txt.responseEndDate)
        map.timing.totalMs = metrics.taskInterval.duration * 1000
        map.timing.reused = txt.isReusedConnection
        map.remoteAddr = Self.address(txt.remoteAddress, txt.remotePort)
        map.localAddr = Self.address(txt.localAddress, txt.localPort)
        map.sizes.reqHeaders = txt.countOfRequestHeaderBytesSent
        map.sizes.reqBody = txt.countOfRequestBodyBytesSent
        map.sizes.headers = txt.countOfResponseHeaderBytesReceived
        map.sizes.bodyWire = txt.countOfResponseBodyBytesReceived
        map.sizes.bodyDecoded = txt.countOfResponseBodyBytesAfterDecoding
        if let val = txt.negotiatedTLSProtocolVersion {
            var info = TLSInfo()
            info.version = TLSNames.version(val.rawValue)
            info.cipher = txt.negotiatedTLSCipherSuite.map { TLSNames.cipher($0.rawValue) } ?? ""
            info.serverName = txt.request.url?.host() ?? ""
            map.tls = info
        }
        let proto = txt.networkProtocolName ?? ""
        state.withLock { str in
            str.metrics = map
            str.proto = proto
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        session.finishTasksAndInvalidate()
        if let resVal = task.response as? HTTPURLResponse { receiveCookies(resVal) }
        let sent = task.currentRequest
        let cur = state.withLock { str -> (CheckedContinuation<RunOutcome, Never>?, RunOutcome) in
            var out = str.metrics
            out.redirects = str.redirects
            out.cookies = str.cookies
            out.proto = HTTPStatus.proto(str.proto)
            if let cause = str.cause {
                out.error = cause
            } else if let error, !str.sink.truncated {
                out.error = Self.classify(error)
            }
            if out.tls != nil, let cert = str.certs[out.tls!.serverName.lowercased()] {
                (out.tls!.subject, out.tls!.issuer, out.tls!.notAfter) = (cert.subject, cert.issuer, cert.notAfter)
            }
            if out.error == nil {
                out.truncated = str.sink.truncated
                out.body = str.sink.finish()
            } else {
                str.sink.discard()
            }
            defer {
                str.continuation = nil
                str.task = nil
            }
            return (str.continuation, out)
        }
        var out = cur.1
        out.sentMethod = sent?.httpMethod ?? ""
        out.sentURL = sent?.url?.absoluteString ?? ""
        out.sentHeaders = Self.sentHeaders(sent, proto: out.proto)
        if out.error == nil, let resVal = task.response as? HTTPURLResponse {
            out.status = resVal.statusCode
            out.headers = Self.rows(
                resVal.allHeaderFields.reduce(into: [String: String]()) { $0["\($1.key)"] = "\($1.value)" })
        } else if out.error == nil {
            out.body.remove()
            out.body = .data(Data())
            out.error = CoreError(.netError, "no response")
        }
        cur.0?.resume(returning: out)
    }

    /// Řádky seřazené podle názvu; sloučené `Set-Cookie` rozdělí na samostatné řádky.
    static func rows(_ hdr: [String: String]) -> [KV] {
        hdr.sorted { $0.key.lowercased() < $1.key.lowercased() }.flatMap { keyVal, val in
            keyVal.lowercased() == "set-cookie"
                ? SetCookie.split(val).map { KV(name: keyVal, value: $0) } : [KV(name: keyVal, value: val)]
        }
    }

    /// Hlavičky z `currentRequest` (bez prázdných – ty se neodešlou) + odvozené `Host`, `Connection`, `Cache-Control`.
    static func sentHeaders(_ resVal: URLRequest?, proto: String) -> [KV] {
        var hdr = (resVal?.allHTTPHeaderFields ?? [:]).filter { !$0.value.isEmpty }
        let has = Set(hdr.keys.map { $0.lowercased() })
        if !has.contains("host"), let urlVal = resVal?.url, let host = urlVal.host(percentEncoded: false) {
            let name = host.contains(":") ? "[\(host)]" : host
            hdr["Host"] = urlVal.port.map { "\(name):\($0)" } ?? name
        }
        if proto == "HTTP/1.1", !has.contains("connection") { hdr["Connection"] = "keep-alive" }
        // Doplní URLSession kvůli `reloadIgnoringLocalAndRemoteCacheData`.
        if !has.contains("cache-control") { hdr["Cache-Control"] = "no-cache" }
        return rows(hdr)
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

nonisolated enum HTTPStatus {
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
        507: "Insufficient Storage", 508: "Loop Detected", 510: "Not Extended", 511: "Network Authentication Required"
    ]
}

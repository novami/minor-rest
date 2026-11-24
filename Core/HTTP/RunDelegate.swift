import Foundation
import Synchronization

// MARK: - Delegát jednoho odeslání

/// Výsledek z delegáta (jen Sendable hodnoty).
nonisolated struct RunOutcome: Sendable {
    var error: CoreError?
    var status = 0
    var proto = ""
    var headers: [KeyValue] = []
    /// Přijaté cookies celého běhu (i ze skoků redirectu).
    var cookies: [Cookie] = []
    var body = ResponseBody.data(Data())
    var truncated = false
    var redirects: [Redirect] = []
    var sentMethod = ""
    var sentURL = ""
    var sentHeaders: [KeyValue] = []
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
            (info.subject, info.issuer, info.notAfter) = (cur.subject, cur.issuer, cur.notAfter)
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
            if var tls = out.tls, let cert = str.certs[tls.serverName.lowercased()] {
                (tls.subject, tls.issuer, tls.notAfter) = (cert.subject, cert.issuer, cert.notAfter)
                out.tls = tls
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
    static func rows(_ hdr: [String: String]) -> [KeyValue] {
        hdr.sorted { $0.key.lowercased() < $1.key.lowercased() }.flatMap { keyVal, val in
            keyVal.lowercased() == "set-cookie"
                ? SetCookie.split(val).map { KeyValue(name: keyVal, value: $0) } : [KeyValue(name: keyVal, value: val)]
        }
    }

    /// Hlavičky z `currentRequest` (bez prázdných – ty se neodešlou) + odvozené `Host`, `Connection`, `Cache-Control`.
    static func sentHeaders(_ resVal: URLRequest?, proto: String) -> [KeyValue] {
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

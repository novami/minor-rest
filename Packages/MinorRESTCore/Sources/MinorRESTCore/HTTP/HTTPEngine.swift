import Foundation
import Synchronization

/// Odesílá připravené requesty přes URLSession (kap. 4 plánu); každé odeslání má vlastní session.
public actor HTTPEngine {
    static let keepResults = 20

    private var runs: [String: RunDelegate] = [:]
    private var bodies: [String: Data] = [:]
    private var order: [String] = []

    public init() {}

    /// Zruší běžící odeslání (výsledek `CANCELED`); neznámé runID ignoruje.
    public func cancel(runID: String) {
        runs[runID]?.cancel(CoreError(.canceled))
    }

    /// Odešle request; chyby jsou v `RunResult.error` (s částečným výsledkem).
    public func send(runID: String, _ r: PreparedRequest, _ o: Options) async -> RunResult {
        var res = RunResult(runID: runID)
        let req: URLRequest, payload: Payload
        do { (req, payload) = try Self.makeRequest(r, o) } catch { res.error = error; return res }
        res.sent.bodySize = payload.size
        res.sent.bodyPreview = payload.preview

        let d = RunDelegate(options: o, payload: payload)
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
        res.headers = out.headers
        keep(runID, out.data)
        return res
    }

    /// Surové (dekomprimované) tělo odpovědi držené v posledních výsledcích.
    func data(runID: String) throws(CoreError) -> Data {
        guard let d = bodies[runID] else { throw CoreError(.runNotFound, runID) }
        return d
    }

    private func keep(_ runID: String, _ data: Data) {
        order.removeAll { $0 == runID }
        bodies[runID] = data
        order.append(runID)
        while order.count > Self.keepResults { bodies[order.removeFirst()] = nil }
    }

    // MARK: - Sestavení URLRequest

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
    var data = Data()
    var redirects: [Redirect] = []
    var sentMethod = ""
    var sentURL = ""
    var sentHeaders: [KV] = []
}

final class RunDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<RunOutcome, Never>?
        var task: URLSessionTask?
        var cause: CoreError?
        var data = Data()
        var redirects: [Redirect] = []
        var proto = ""
    }

    private let state = Mutex(State())
    private let options: HTTPEngine.Options
    private let payload: Payload

    init(options: HTTPEngine.Options, payload: Payload) {
        self.options = options
        self.payload = payload
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
            let session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
            let task = session.dataTask(with: req)
            let canceled = state.withLock { s in
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
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           !options.verifyTLS, let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
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
        if prev?.url?.host() != request.url?.host() { next.setValue(nil, forHTTPHeaderField: "Authorization") }
        completionHandler(next)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping @Sendable (InputStream?) -> Void) {
        completionHandler(payload.stream())
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        state.withLock { $0.data.append(data) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let proto = metrics.transactionMetrics.last?.networkProtocolName ?? ""
        state.withLock { $0.proto = proto }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        session.finishTasksAndInvalidate()
        var out = RunOutcome()
        let sent = task.currentRequest
        out.sentMethod = sent?.httpMethod ?? ""
        out.sentURL = sent?.url?.absoluteString ?? ""
        out.sentHeaders = Self.rows(sent?.allHTTPHeaderFields ?? [:])
        let c = state.withLock { s -> CheckedContinuation<RunOutcome, Never>? in
            out.redirects = s.redirects
            out.proto = HTTPStatus.proto(s.proto)
            out.data = s.data
            if let cause = s.cause {
                out.error = cause
            } else if let error {
                out.error = Self.classify(error)
            }
            defer { s.continuation = nil; s.task = nil }
            return s.continuation
        }
        if out.error == nil, let r = task.response as? HTTPURLResponse {
            out.status = r.statusCode
            out.headers = Self.rows(r.allHeaderFields.reduce(into: [String: String]()) { $0["\($1.key)"] = "\($1.value)" })
        } else if out.error == nil {
            out.error = CoreError(.netError, "no response")
        }
        if out.error != nil { out.data = Data() }
        c?.resume(returning: out)
    }

    static func rows(_ h: [String: String]) -> [KV] {
        h.sorted { $0.key.lowercased() < $1.key.lowercased() }.map { KV(name: $0.key, value: $0.value) }
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

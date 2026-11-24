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
    private let protocolClasses: [AnyClass]

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

        Self.applyTransport(out, to: &res, requestMethod: req.httpMethod)
        if let elem = out.error {
            res.error = elem
            return res
        }
        Self.applyResponse(out, to: &res)

        let ct = out.headers.first { $0.name.lowercased() == "content-type" }?.value ?? ""
        let sample: Data
        do { sample = try out.body.read(limit: ResponseBody.sniffLen) } catch {
            out.body.remove()
            res.error = error
            return res
        }
        let sniffed = ContentSniff.sniff(ct, sample)
        (res.contentType, res.charset, res.isBinary) = (sniffed.mediaType, sniffed.charset, sniffed.binary)
        keep(runID, Stored(body: out.body, contentType: res.contentType, charset: res.charset, isBinary: res.isBinary))
        return res
    }

    private static func applyTransport(_ out: RunOutcome, to res: inout RunResult, requestMethod: String?) {
        res.redirects = out.redirects
        res.sent.method = out.sentMethod
        res.sent.url = out.sentURL
        res.sent.headers = out.sentHeaders
        res.timing = out.timing
        res.sizes = out.sizes
        res.remoteAddr = out.remoteAddr
        res.localAddr = out.localAddr
        if !out.redirects.isEmpty, out.sentMethod != requestMethod, out.sentMethod == HTTPMethod.get {
            res.sent.bodySize = 0  // po 301–303 se tělo zahodí
            res.sent.bodyPreview = ""
        }
    }

    private static func applyResponse(_ out: RunOutcome, to res: inout RunResult) {
        res.status = out.status
        res.statusText = HTTPStatus.text(out.status)
        res.proto = out.proto
        res.tls = out.tls
        res.headers = out.headers
        res.cookies = out.cookies
        res.truncated = out.truncated
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
        configureHeaders(&req, resVal, opt, payload)

        switch payload.source {
        case .none: break
        case .data(let dat): req.httpBody = dat
        case .file:
            req.httpBodyStream = payload.stream()
            req.setValue(String(payload.size), forHTTPHeaderField: "Content-Length")
        }
        return (req, payload)
    }

    private static func configureHeaders(
        _ req: inout URLRequest, _ resVal: PreparedRequest, _ opt: Options, _ payload: Payload
    ) {
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

import Foundation

/// Uložená odpověď (kap. 2.6) – formát `.responses/<requestId>/vNNNN.yaml` i historie (`history/<ULID>.yaml`).
public struct SavedResponse: Sendable, Equatable {
    /// Číslo verze (uložené odpovědi); v historii 0.
    public var version = 0
    /// ULID záznamu historie; u uložených odpovědí prázdné.
    public var id = ""
    /// RFC 3339 s místní zónou.
    public var savedAt = ""
    public var label = ""
    /// Jen historie: odkud request je (pro „Otevřít request“).
    public var projectID = ""
    public var requestID = ""
    public var requestName = ""
    /// Kód chyby odeslání (`NET_REFUSED` …) a detail; pak `response` obsahuje jen timing a redirecty.
    public var error = ""
    public var errorDetail = ""
    /// Tělo v `.body` je oříznuté (limit historie nebo `maxBodyBytes`).
    public var truncated = false
    public var request = Request()
    public var response = Response()

    public struct Request: Sendable, Equatable {
        public var method = ""
        public var url = ""
        public var headers: [KV] = []
        public var bodySize: Int64 = 0
        /// Jen textové tělo do 256 kB (celé), jinak prázdné.
        public var body = ""
        public init() {}
    }

    public struct Response: Sendable, Equatable {
        public var status = 0
        public var statusText = ""
        public var proto = ""
        public var remoteAddr = ""
        public var localAddr = ""
        public var tls: TLSInfo?
        public var headers: [KV] = []
        public var sizes = Sizes()
        public var timing = Timing()
        public var redirects: [Redirect] = []
        public var contentType = ""
        public var charset = ""
        public init() {}
    }

    public init() {}

    static let maxRequestBody: Int64 = 256 << 10

    /// Snímek běhu s maskováním (kap. 2.8); `request` = připravený request (URL před redirecty).
    public init(_ r: RunResult, request p: PreparedRequest, secrets: [String], now: Date = Date()) {
        let m = Mask(secrets: secrets)
        savedAt = Self.timestamp(now)
        request.method = p.method
        request.url = m.text(p.url)
        request.headers = m.headers(r.sent.headers.isEmpty ? p.headers.filter(\.enabled) : r.sent.headers)
        request.bodySize = r.sent.bodySize
        if r.sent.bodySize <= Self.maxRequestBody, Int64(r.sent.bodyPreview.utf8.count) == r.sent.bodySize {
            request.body = m.text(r.sent.bodyPreview)
        }
        if let e = r.error {
            error = e.code.rawValue
            errorDetail = m.text(e.detail)
        }
        truncated = r.truncated
        response.status = r.status
        response.statusText = r.statusText
        response.proto = r.proto
        response.remoteAddr = r.remoteAddr
        response.localAddr = r.localAddr
        response.tls = r.tls
        response.headers = m.headers(r.headers)
        response.sizes = r.sizes
        response.timing = r.timing
        response.redirects = r.redirects.map { Redirect(status: $0.status, method: $0.method, url: m.text($0.url), location: m.text($0.location)) }
        response.contentType = r.contentType
        response.charset = r.charset
    }

    static func timestamp(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        return f.string(from: d)
    }
}

/// Maskování tajných hodnot (kap. 2.8).
struct Mask {
    let secrets: [String]

    static let headers: Set<String> = ["authorization", "proxy-authorization", "cookie", "set-cookie"]

    func text(_ s: String) -> String {
        secrets.reduce(s) { $0.replacingOccurrences(of: $1, with: Resolver.masked) }
    }

    /// `Authorization: Bearer x` → `Bearer ***`; ostatní citlivé hlavičky → `***`.
    func headers(_ rows: [KV]) -> [KV] {
        rows.map { h in
            var h = h
            let key = h.name.lowercased()
            if key.hasSuffix("authorization"), let sp = h.value.firstIndex(of: " ") {
                h.value = h.value[..<sp] + " " + Resolver.masked
            } else if Self.headers.contains(key) {
                h.value = Resolver.masked
            } else {
                h.value = text(h.value)
            }
            return h
        }
    }
}

extension SavedResponse: YAMLCodable {
    public var yaml: YNode {
        var m = YMap()
        if version > 0 { m.add("version", version) }
        m.addIfNotEmpty("id", id)
        m.add("savedAt", savedAt)
        if id.isEmpty { m.add("label", label) }
        m.addIfNotEmpty("projectId", projectID)
        m.addIfNotEmpty("requestId", requestID)
        m.addIfNotEmpty("requestName", requestName)
        m.addIfNotEmpty("error", error)
        m.addIfNotEmpty("errorDetail", errorDetail)
        m.addIfTrue("truncated", truncated)

        var q = YMap()
        q.add("method", request.method)
        q.add("url", request.url)
        q.add("headers", .seq(request.headers.map(\.header)))
        q.add("bodySize", Int(request.bodySize))
        q.addIfNotEmpty("body", request.body)
        m.add("request", q.node)

        let r = response
        var s = YMap()
        s.add("status", r.status)
        s.add("statusText", r.statusText)
        s.add("proto", r.proto)
        s.add("remoteAddr", r.remoteAddr)
        s.add("localAddr", r.localAddr)
        if let t = r.tls {
            var tm = YMap()
            tm.add("version", t.version)
            tm.add("cipher", t.cipher)
            tm.add("serverName", t.serverName)
            tm.add("certSubject", t.subject)
            tm.add("certIssuer", t.issuer)
            tm.add("certExpires", t.notAfter)
            s.add("tls", tm.node)
        }
        s.add("headers", .seq(r.headers.map(\.header)))
        var sz = YMap()
        sz.add("reqHeaders", Int(r.sizes.reqHeaders))
        sz.add("reqBody", Int(r.sizes.reqBody))
        sz.add("headers", Int(r.sizes.headers))
        sz.add("bodyWire", Int(r.sizes.bodyWire))
        sz.add("bodyDecoded", Int(r.sizes.bodyDecoded))
        s.add("sizes", sz.node)
        var tm = YMap()
        tm.add("dnsMs", r.timing.dnsMs)
        tm.add("connectMs", r.timing.connectMs)
        tm.add("tlsMs", r.timing.tlsMs)
        tm.add("ttfbMs", r.timing.ttfbMs)
        tm.add("downloadMs", r.timing.downloadMs)
        tm.add("totalMs", r.timing.totalMs)
        tm.addIfTrue("reused", r.timing.reused)
        s.add("timing", tm.node)
        s.add("redirects", .seq(r.redirects.map { h in
            var x = YMap()
            x.add("status", h.status)
            x.add("method", h.method)
            x.add("url", h.url)
            x.add("location", h.location)
            return x.node
        }))
        s.add("contentType", r.contentType)
        s.add("charset", r.charset)
        m.add("response", s.node)
        return m.node
    }

    public init(yaml o: YAMLObject) throws {
        version = try o.int("version")
        id = try o.string("id")
        savedAt = try o.string("savedAt")
        label = try o.string("label")
        projectID = try o.string("projectId")
        requestID = try o.string("requestId")
        requestName = try o.string("requestName")
        error = try o.string("error")
        errorDetail = try o.string("errorDetail")
        truncated = try o.bool("truncated")
        if let q: SavedRequestYAML = try o.object("request") { request = q.value }
        if let s: SavedResponseYAML = try o.object("response") { response = s.value }
    }
}

private extension KV {
    /// Hlavička uložené odpovědi: jen název a hodnota.
    var header: YNode {
        var m = YMap()
        m.add("name", name)
        m.add("value", value)
        return m.node
    }
}

private struct HeaderYAML: YAMLDecodable {
    let value: KV
    init(yaml o: YAMLObject) throws { value = KV(name: try o.string("name"), value: try o.string("value")) }
}

private struct SavedRequestYAML: YAMLDecodable {
    var value = SavedResponse.Request()
    init(yaml o: YAMLObject) throws {
        value.method = try o.string("method")
        value.url = try o.string("url")
        value.headers = try (o.list("headers") as [HeaderYAML]).map(\.value)
        value.bodySize = Int64(try o.int("bodySize"))
        value.body = try o.string("body")
    }
}

private struct TLSYAML: YAMLDecodable {
    var value = TLSInfo()
    init(yaml o: YAMLObject) throws {
        value.version = try o.string("version")
        value.cipher = try o.string("cipher")
        value.serverName = try o.string("serverName")
        value.subject = try o.string("certSubject")
        value.issuer = try o.string("certIssuer")
        value.notAfter = try o.string("certExpires")
    }
}

private struct SizesYAML: YAMLDecodable {
    var value = Sizes()
    init(yaml o: YAMLObject) throws {
        value.reqHeaders = Int64(try o.int("reqHeaders"))
        value.reqBody = Int64(try o.int("reqBody"))
        value.headers = Int64(try o.int("headers"))
        value.bodyWire = Int64(try o.int("bodyWire"))
        value.bodyDecoded = Int64(try o.int("bodyDecoded"))
    }
}

private struct TimingYAML: YAMLDecodable {
    var value = Timing()
    init(yaml o: YAMLObject) throws {
        value.dnsMs = try o.double("dnsMs")
        value.connectMs = try o.double("connectMs")
        value.tlsMs = try o.double("tlsMs")
        value.ttfbMs = try o.double("ttfbMs")
        value.downloadMs = try o.double("downloadMs")
        value.totalMs = try o.double("totalMs")
        value.reused = try o.bool("reused")
    }
}

private struct RedirectYAML: YAMLDecodable {
    let value: Redirect
    init(yaml o: YAMLObject) throws {
        value = Redirect(status: try o.int("status"), method: try o.string("method"), url: try o.string("url"),
                         location: try o.string("location"))
    }
}

private struct SavedResponseYAML: YAMLDecodable {
    var value = SavedResponse.Response()
    init(yaml o: YAMLObject) throws {
        value.status = try o.int("status")
        value.statusText = try o.string("statusText")
        value.proto = try o.string("proto")
        value.remoteAddr = try o.string("remoteAddr")
        value.localAddr = try o.string("localAddr")
        value.tls = (try o.object("tls") as TLSYAML?)?.value
        value.headers = try (o.list("headers") as [HeaderYAML]).map(\.value)
        value.sizes = (try o.object("sizes") as SizesYAML?)?.value ?? Sizes()
        value.timing = (try o.object("timing") as TimingYAML?)?.value ?? Timing()
        value.redirects = try (o.list("redirects") as [RedirectYAML]).map(\.value)
        value.contentType = try o.string("contentType")
        value.charset = try o.string("charset")
    }
}

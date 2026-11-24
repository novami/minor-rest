import Foundation

/// Uložená odpověď (kap. 2.6) – formát `.responses/<requestId>/vNNNN.yaml` i historie (`history/<ULID>.yaml`).
nonisolated struct SavedResponse: Sendable, Equatable {
    /// Číslo verze (uložené odpovědi); v historii 0.
    var version = 0
    /// ULID záznamu historie; u uložených odpovědí prázdné.
    var id = ""
    /// RFC 3339 s místní zónou.
    var savedAt = ""
    var label = ""
    /// Jen historie: odkud request je (pro „Otevřít request“).
    var projectID = ""
    var requestID = ""
    var requestName = ""
    /// Kód chyby odeslání (`NET_REFUSED` …) a detail; pak `response` obsahuje jen timing a redirecty.
    var error = ""
    var errorDetail = ""
    /// Tělo v `.body` je oříznuté (limit historie nebo `maxBodyBytes`).
    var truncated = false
    var request = Request()
    var response = Response()

    struct Request: Sendable, Equatable {
        var method = ""
        var url = ""
        var headers: [KV] = []
        var bodySize: Int64 = 0
        /// Jen textové tělo do 256 kB (celé), jinak prázdné.
        var body = ""
    }

    struct Response: Sendable, Equatable {
        var status = 0
        var statusText = ""
        var proto = ""
        var remoteAddr = ""
        var localAddr = ""
        var tls: TLSInfo?
        var headers: [KV] = []
        var sizes = Sizes()
        var timing = Timing()
        var redirects: [Redirect] = []
        var contentType = ""
        var charset = ""
        init() {}
    }

    init() {}

    static let maxRequestBody: Int64 = 256 << 10

    /// Snímek běhu s maskováním (kap. 2.8); `request` = připravený request (URL před redirecty).
    init(_ res: RunResult, request par: PreparedRequest, secrets: [String], now: Date = Date()) {
        let map = Mask(secrets: secrets)
        savedAt = Self.timestamp(now)
        request.method = par.method
        request.url = map.text(par.url)
        request.headers = map.headers(res.sent.headers.isEmpty ? par.headers.filter(\.enabled) : res.sent.headers)
        request.bodySize = res.sent.bodySize
        if res.sent.bodySize <= Self.maxRequestBody, Int64(res.sent.bodyPreview.utf8.count) == res.sent.bodySize {
            request.body = map.text(res.sent.bodyPreview)
        }
        if let elem = res.error {
            error = elem.code.rawValue
            errorDetail = map.text(elem.detail)
        }
        truncated = res.truncated
        response.status = res.status
        response.statusText = res.statusText
        response.proto = res.proto
        response.remoteAddr = res.remoteAddr
        response.localAddr = res.localAddr
        response.tls = res.tls
        response.headers = map.headers(res.headers)
        response.sizes = res.sizes
        response.timing = res.timing
        response.redirects = res.redirects.map {
            Redirect(status: $0.status, method: $0.method, url: map.text($0.url), location: map.text($0.location))
        }
        response.contentType = res.contentType
        response.charset = res.charset
    }

    static func timestamp(_ dat: Date) -> String {
        let fn = ISO8601DateFormatter()
        fn.timeZone = .current
        return fn.string(from: dat)
    }
}

/// Maskování tajných hodnot (kap. 2.8).
nonisolated struct Mask {
    let secrets: [String]

    static let headers: Set<String> = ["authorization", "proxy-authorization", "cookie", "set-cookie"]

    func text(_ str: String) -> String {
        secrets.reduce(str) { $0.replacingOccurrences(of: $1, with: Resolver.masked) }
    }

    /// `Authorization: Bearer x` → `Bearer ***`; ostatní citlivé hlavičky → `***`.
    func headers(_ rows: [KV]) -> [KV] {
        rows.map { hdr in
            var hdr = hdr
            let key = hdr.name.lowercased()
            if key.hasSuffix("authorization"), let sp = hdr.value.firstIndex(of: " ") {
                hdr.value = hdr.value[..<sp] + " " + Resolver.masked
            } else if Self.headers.contains(key) {
                hdr.value = Resolver.masked
            } else {
                hdr.value = text(hdr.value)
            }
            return hdr
        }
    }
}

nonisolated extension SavedResponse: YAMLCodable {
    var yaml: YNode {
        var map = YMap()
        if version > 0 { map.add("version", version) }
        map.addIfNotEmpty("id", id)
        map.add("savedAt", savedAt)
        if id.isEmpty { map.add("label", label) }
        map.addIfNotEmpty("projectId", projectID)
        map.addIfNotEmpty("requestId", requestID)
        map.addIfNotEmpty("requestName", requestName)
        map.addIfNotEmpty("error", error)
        map.addIfNotEmpty("errorDetail", errorDetail)
        map.addIfTrue("truncated", truncated)

        var que = YMap()
        que.add("method", request.method)
        que.add("url", request.url)
        que.add("headers", .seq(request.headers.map(\.header)))
        que.add("bodySize", Int(request.bodySize))
        que.addIfNotEmpty("body", request.body)
        map.add("request", que.node)

        let res = response
        var str = YMap()
        str.add("status", res.status)
        str.add("statusText", res.statusText)
        str.add("proto", res.proto)
        str.add("remoteAddr", res.remoteAddr)
        str.add("localAddr", res.localAddr)
        if let txt = res.tls {
            var tm = YMap()
            tm.add("version", txt.version)
            tm.add("cipher", txt.cipher)
            tm.add("serverName", txt.serverName)
            tm.add("certSubject", txt.subject)
            tm.add("certIssuer", txt.issuer)
            tm.add("certExpires", txt.notAfter)
            str.add("tls", tm.node)
        }
        str.add("headers", .seq(res.headers.map(\.header)))
        var sz = YMap()
        sz.add("reqHeaders", Int(res.sizes.reqHeaders))
        sz.add("reqBody", Int(res.sizes.reqBody))
        sz.add("headers", Int(res.sizes.headers))
        sz.add("bodyWire", Int(res.sizes.bodyWire))
        sz.add("bodyDecoded", Int(res.sizes.bodyDecoded))
        str.add("sizes", sz.node)
        var tm = YMap()
        tm.add("dnsMs", res.timing.dnsMs)
        tm.add("connectMs", res.timing.connectMs)
        tm.add("tlsMs", res.timing.tlsMs)
        tm.add("ttfbMs", res.timing.ttfbMs)
        tm.add("downloadMs", res.timing.downloadMs)
        tm.add("totalMs", res.timing.totalMs)
        tm.addIfTrue("reused", res.timing.reused)
        str.add("timing", tm.node)
        str.add(
            "redirects",
            .seq(
                res.redirects.map { hdr in
                    var x = YMap()
                    x.add("status", hdr.status)
                    x.add("method", hdr.method)
                    x.add("url", hdr.url)
                    x.add("location", hdr.location)
                    return x.node
                }))
        str.add("contentType", res.contentType)
        str.add("charset", res.charset)
        map.add("response", str.node)
        return map.node
    }

    init(yaml opt: YAMLObject) throws {
        version = try opt.int("version")
        id = try opt.string("id")
        savedAt = try opt.string("savedAt")
        label = try opt.string("label")
        projectID = try opt.string("projectId")
        requestID = try opt.string("requestId")
        requestName = try opt.string("requestName")
        error = try opt.string("error")
        errorDetail = try opt.string("errorDetail")
        truncated = try opt.bool("truncated")
        if let que: SavedRequestYAML = try opt.object("request") { request = que.value }
        if let str: SavedResponseYAML = try opt.object("response") { response = str.value }
    }
}

nonisolated extension KV {
    /// Hlavička uložené odpovědi: jen název a hodnota.
    fileprivate var header: YNode {
        var map = YMap()
        map.add("name", name)
        map.add("value", value)
        return map.node
    }
}

nonisolated private struct HeaderYAML: YAMLDecodable {
    let value: KV
    init(yaml opt: YAMLObject) throws { value = KV(name: try opt.string("name"), value: try opt.string("value")) }
}

nonisolated private struct SavedRequestYAML: YAMLDecodable {
    var value = SavedResponse.Request()
    init(yaml opt: YAMLObject) throws {
        value.method = try opt.string("method")
        value.url = try opt.string("url")
        value.headers = try (opt.list("headers") as [HeaderYAML]).map(\.value)
        value.bodySize = Int64(try opt.int("bodySize"))
        value.body = try opt.string("body")
    }
}

nonisolated private struct TLSYAML: YAMLDecodable {
    var value = TLSInfo()
    init(yaml opt: YAMLObject) throws {
        value.version = try opt.string("version")
        value.cipher = try opt.string("cipher")
        value.serverName = try opt.string("serverName")
        value.subject = try opt.string("certSubject")
        value.issuer = try opt.string("certIssuer")
        value.notAfter = try opt.string("certExpires")
    }
}

nonisolated private struct SizesYAML: YAMLDecodable {
    var value = Sizes()
    init(yaml opt: YAMLObject) throws {
        value.reqHeaders = Int64(try opt.int("reqHeaders"))
        value.reqBody = Int64(try opt.int("reqBody"))
        value.headers = Int64(try opt.int("headers"))
        value.bodyWire = Int64(try opt.int("bodyWire"))
        value.bodyDecoded = Int64(try opt.int("bodyDecoded"))
    }
}

nonisolated private struct TimingYAML: YAMLDecodable {
    var value = Timing()
    init(yaml opt: YAMLObject) throws {
        value.dnsMs = try opt.double("dnsMs")
        value.connectMs = try opt.double("connectMs")
        value.tlsMs = try opt.double("tlsMs")
        value.ttfbMs = try opt.double("ttfbMs")
        value.downloadMs = try opt.double("downloadMs")
        value.totalMs = try opt.double("totalMs")
        value.reused = try opt.bool("reused")
    }
}

nonisolated private struct RedirectYAML: YAMLDecodable {
    let value: Redirect
    init(yaml opt: YAMLObject) throws {
        value = Redirect(
            status: try opt.int("status"), method: try opt.string("method"), url: try opt.string("url"),
            location: try opt.string("location"))
    }
}

nonisolated private struct SavedResponseYAML: YAMLDecodable {
    var value = SavedResponse.Response()
    init(yaml opt: YAMLObject) throws {
        value.status = try opt.int("status")
        value.statusText = try opt.string("statusText")
        value.proto = try opt.string("proto")
        value.remoteAddr = try opt.string("remoteAddr")
        value.localAddr = try opt.string("localAddr")
        value.tls = (try opt.object("tls") as TLSYAML?)?.value
        value.headers = try (opt.list("headers") as [HeaderYAML]).map(\.value)
        value.sizes = (try opt.object("sizes") as SizesYAML?)?.value ?? Sizes()
        value.timing = (try opt.object("timing") as TimingYAML?)?.value ?? Timing()
        value.redirects = try (opt.list("redirects") as [RedirectYAML]).map(\.value)
        value.contentType = try opt.string("contentType")
        value.charset = try opt.string("charset")
    }
}

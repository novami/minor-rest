import Foundation

/// Sestavení URL pro odeslání a kódování query (PLAN kap. 3).
public enum URLBuilder {
    /// Proměnné v URL → doplnění `http://` → `:param` v cestě → zapnuté query parametry.
    /// Nevyhodnocené proměnné hlásí `resolver.unresolved`; nevyhodnocený host → `VAR_UNRESOLVED_HOST`.
    public static func build(_ raw: String, path: [PathParam], query: [KV], resolver r: Resolver) throws -> String {
        let (resolved, unresolved) = try r.resolve(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        var u = resolved.contains("://") ? resolved : "http://" + resolved
        u = try replacePathParams(u, path, r)
        var params: [KV] = []
        for var q in query where q.enabled {
            q.name = try r.resolve(q.name).value
            q.value = try r.resolve(q.value).value
            params.append(q)
        }
        let qs = encodeQuery(params)
        if !qs.isEmpty { u += (u.contains("?") ? "&" : "?") + qs }

        if let problem = validate(u) {
            if !unresolved.isEmpty && hostPart(u).contains("{{") {
                throw CoreError(.varUnresolvedHost, unresolved.joined(separator: ", "))
            }
            throw CoreError(.urlInvalid, problem)
        }
        return u
    }

    /// Zapnuté parametry `name=value` spojené `&`; prázdná hodnota → `name=`, `bare` → jen `name`.
    public static func encodeQuery(_ params: [KV]) -> String {
        params.filter { $0.enabled && !$0.name.isEmpty }.map { p in
            var part = encodeQueryComponent(p.name)
            if !p.value.isEmpty || !p.bare { part += "=" + encodeQueryComponent(p.value) }
            return part
        }.joined(separator: "&")
    }

    /// Percent-encoding UTF-8 (mezera `%20`, kóduje `& = + #`); platné `%XX` sekvence zachová.
    public static func encodeQueryComponent(_ s: String) -> String {
        let bytes = Array(s.utf8)
        var out = ""
        var i = 0
        while i < bytes.count {
            let c = bytes[i]
            if c == UInt8(ascii: "%"), i + 2 < bytes.count, isHex(bytes[i + 1]), isHex(bytes[i + 2]) {
                out += String(decoding: bytes[i...i + 2], as: UTF8.self)
                i += 3
                continue
            }
            if keepInQuery(c) {
                out.unicodeScalars.append(Unicode.Scalar(c))
            } else {
                out += String(format: "%%%02X", c)
            }
            i += 1
        }
        return out
    }

    // MARK: - Interní

    private static let pathSegmentAllowed: CharacterSet = {
        var set = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        set.insert(charactersIn: "-_.~$&+,:;=@")
        return set
    }()

    /// `:name` na začátku segmentu cesty → hodnota (po vyhodnocení, percent-encoding segmentu).
    private static func replacePathParams(_ u: String, _ params: [PathParam], _ r: Resolver) throws -> String {
        guard !params.isEmpty, let scheme = u.range(of: "://"),
              let pathStart = u[scheme.upperBound...].firstIndex(of: "/") else { return u }
        let pathEnd = u[pathStart...].firstIndex(where: { $0 == "?" || $0 == "#" }) ?? u.endIndex
        var values: [String: String] = [:]
        for p in params { values[p.name] = try r.resolve(p.value).value }
        let segments = u[pathStart..<pathEnd].split(separator: "/", omittingEmptySubsequences: false).map { seg -> String in
            guard seg.count >= 2, seg.first == ":" else { return String(seg) }
            let name = seg.dropFirst().prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
            guard let value = values[String(name)] else { return String(seg) }
            return (value.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) ?? value)
                + seg.dropFirst(1 + name.count)
        }
        return u[..<pathStart] + segments.joined(separator: "/") + u[pathEnd...]
    }

    /// Kontrola jako Go `url.Parse` + neprázdný host; vrací popis problému nebo `nil`.
    static func validate(_ u: String) -> String? {
        guard u.wholeMatch(of: /[A-Za-z][A-Za-z0-9+.\-]*:\/\/.*/.dotMatchesNewlines()) != nil else { return "invalid scheme" }
        if u.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) { return "invalid control character" }
        var host = hostPart(u)
        if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
        if host.isEmpty { return "missing host" }
        if host.hasPrefix("[") {
            guard let end = host.firstIndex(of: "]") else { return "missing ']' in host" }
            let after = host[host.index(after: end)...]
            if !after.isEmpty && !(after.first == ":" && after.dropFirst().allSatisfy(\.isASCII) && after.dropFirst().allSatisfy(\.isNumber)) {
                return "invalid port"
            }
            return nil
        }
        if host.contains(where: { " {}\\^`|".contains($0) }) { return "invalid character in host \"\(host)\"" }
        if let colon = host.lastIndex(of: ":") {
            let port = host[host.index(after: colon)...]
            if !port.allSatisfy({ $0.isASCII && $0.isNumber }) { return "invalid port \"\(port)\"" }
            if host[..<colon].isEmpty { return "missing host" }
        }
        return nil
    }

    /// Část URL mezi `://` a první `/`, `?` nebo `#`.
    static func hostPart(_ u: String) -> String {
        var s = u[...]
        if let r = s.range(of: "://") { s = s[r.upperBound...] }
        if let i = s.firstIndex(where: { "/?#".contains($0) }) { s = s[..<i] }
        return String(s)
    }

    private static func isHex(_ c: UInt8) -> Bool {
        (48...57).contains(c) || (65...70).contains(c) || (97...102).contains(c)
    }

    private static func keepInQuery(_ c: UInt8) -> Bool {
        (48...57).contains(c) || (65...90).contains(c) || (97...122).contains(c) || "-._~!$'()*,;:@/?".utf8.contains(c)
    }
}

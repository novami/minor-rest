import Foundation

/// Sestavení URL pro odeslání a kódování query (PLAN kap. 3).
nonisolated enum URLBuilder {
    /// Proměnné v URL → doplnění `http://` → `:param` v cestě → zapnuté query parametry.
    /// Nevyhodnocené proměnné hlásí `resolver.unresolved`; nevyhodnocený host → `VAR_UNRESOLVED_HOST`.
    static func build(_ raw: String, path: [PathParam], query: [KeyValue], resolver res: Resolver) throws -> String {
        let (resolved, unresolved) = try res.resolve(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        var url = resolved.contains("://") ? resolved : "http://" + resolved
        url = try replacePathParams(url, path, res)
        var params: [KeyValue] = []
        for var que in query where que.enabled {
            que.name = try res.resolve(que.name).value
            que.value = try res.resolve(que.value).value
            params.append(que)
        }
        let qs = encodeQuery(params)
        if !qs.isEmpty { url += (url.contains("?") ? "&" : "?") + qs }

        if let problem = validate(url) {
            if !unresolved.isEmpty && hostPart(url).contains("{{") {
                throw CoreError(.varUnresolvedHost, unresolved.joined(separator: ", "))
            }
            throw CoreError(.urlInvalid, problem)
        }
        return url
    }

    /// Zapnuté parametry `name=value` spojené `&`; prázdná hodnota → `name=`, `bare` → jen `name`.
    static func encodeQuery(_ params: [KeyValue]) -> String {
        params.filter { $0.enabled && !$0.name.isEmpty }.map { par in
            var part = encodeQueryComponent(par.name)
            if !par.value.isEmpty || !par.bare { part += "=" + encodeQueryComponent(par.value) }
            return part
        }.joined(separator: "&")
    }

    /// Percent-encoding UTF-8 (mezera `%20`, kóduje `& = + #`); platné `%XX` sekvence zachová.
    static func encodeQueryComponent(_ str: String) -> String {
        let bytes = Array(str.utf8)
        var out = ""
        var i = 0
        while i < bytes.count {
            let cur = bytes[i]
            if cur == UInt8(ascii: "%"), i + 2 < bytes.count, isHex(bytes[i + 1]), isHex(bytes[i + 2]) {
                out +=
                    String(bytes: bytes[i...i + 2], encoding: .utf8) ?? String(
                        bytes: bytes[i...i + 2], encoding: .isoLatin1) ?? ""
                i += 3
                continue
            }
            if keepInQuery(cur) {
                out.unicodeScalars.append(Unicode.Scalar(cur))
            } else {
                out += String(format: "%%%02X", cur)
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
    private static func replacePathParams(_ url: String, _ params: [PathParam], _ res: Resolver) throws -> String {
        guard !params.isEmpty, let scheme = url.range(of: "://"),
            let pathStart = url[scheme.upperBound...].firstIndex(of: "/")
        else { return url }
        let pathEnd = url[pathStart...].firstIndex(where: { $0 == "?" || $0 == "#" }) ?? url.endIndex
        var values: [String: String] = [:]
        for par in params { values[par.name] = try res.resolve(par.value).value }
        let segments = url[pathStart..<pathEnd].split(separator: "/", omittingEmptySubsequences: false)
            .map { substituteSegment($0, values: values) }
        return url[..<pathStart] + segments.joined(separator: "/") + url[pathEnd...]
    }

    private static func substituteSegment(_ seg: Substring, values: [String: String]) -> String {
        guard seg.count >= 2, seg.first == ":" else { return String(seg) }
        let name = seg.dropFirst().prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
        guard let value = values[String(name)] else { return String(seg) }
        return (value.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) ?? value)
            + seg.dropFirst(1 + name.count)
    }

    /// Kontrola jako Go `url.Parse` + neprázdný host; vrací popis problému nebo `nil`.
    static func validate(_ url: String) -> String? {
        guard url.wholeMatch(of: /[A-Za-z][A-Za-z0-9+.\-]*:\/\/.*/.dotMatchesNewlines()) != nil else {
            return "invalid scheme"
        }
        if url.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
            return "invalid control character"
        }
        var host = hostPart(url)
        if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
        if host.isEmpty { return "missing host" }
        if host.hasPrefix("[") { return validateIPv6Host(host) }
        if host.contains(where: { " {}\\^`|".contains($0) }) { return "invalid character in host \"\(host)\"" }
        if let colon = host.lastIndex(of: ":") {
            let port = host[host.index(after: colon)...]
            if !port.allSatisfy({ $0.isASCII && $0.isNumber }) { return "invalid port \"\(port)\"" }
            if host[..<colon].isEmpty { return "missing host" }
        }
        return nil
    }

    private static func validateIPv6Host(_ host: String) -> String? {
        guard let end = host.firstIndex(of: "]") else { return "missing ']' in host" }
        let after = host[host.index(after: end)...]
        if after.isEmpty { return nil }
        let digits = after.dropFirst()
        let validPort = after.first == ":" && digits.allSatisfy(\.isASCII) && digits.allSatisfy(\.isNumber)
        return validPort ? nil : "invalid port"
    }

    /// Část URL mezi `://` a první `/`, `?` nebo `#`.
    static func hostPart(_ url: String) -> String {
        var str = url[...]
        if let res = str.range(of: "://") { str = str[res.upperBound...] }
        if let i = str.firstIndex(where: { "/?#".contains($0) }) { str = str[..<i] }
        return String(str)
    }

    private static func isHex(_ cur: UInt8) -> Bool {
        (48...57).contains(cur) || (65...70).contains(cur) || (97...102).contains(cur)
    }

    private static func keepInQuery(_ cur: UInt8) -> Bool {
        (48...57).contains(cur) || (65...90).contains(cur) || (97...122).contains(cur)
            || "-._~!$'()*,;:@/?".utf8.contains(cur)
    }
}

import Foundation

/// Export requestu (kap. 6).
public enum Export {
    /// cURL z připraveného requestu (to, co by se odeslalo). `mask` = maskování tajných hodnot (kap. 2.8) přes `secrets`.
    public static func curl(_ p: PreparedRequest, options o: HTTPEngine.Options = .init(), multiline: Bool = true,
                            mask: Bool = false, secrets: [String] = []) -> String {
        let m = Mask(secrets: mask ? secrets : [])
        let method = p.method.uppercased()
        var parts: [String] = []   // každá položka = jeden flag (na vlastním řádku ve víceřádkovém tvaru)
        let hasBody = hasBody(p.body)

        var head = ["curl"]
        if method == "HEAD" { head.append("--head") }
        else if method != "GET" || hasBody { head.append("-X " + method) }
        head.append(quote(m.text(p.url)))
        parts.append(head.joined(separator: " "))

        if o.followRedirects { parts.append("-L --max-redirs \(o.maxRedirects)") }
        if !o.verifyTLS { parts.append("-k") }
        if o.timeoutMs > 0 { parts.append("--max-time " + seconds(o.timeoutMs)) }
        parts.append("--compressed")

        var headers = p.headers.filter { $0.enabled && !$0.name.isEmpty }
        if let ct = autoContentType(p), !p.noAuto.contains(where: { $0.caseInsensitiveCompare("Content-Type") == .orderedSame }),
           !headers.contains(where: { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }) {
            headers.append(KV(name: "Content-Type", value: ct))
        }
        for h in (mask ? m.headers(headers) : headers) { parts.append("-H " + quote("\(h.name): \(h.value)")) }

        switch p.body.type {
        case BodyType.form:
            for r in p.body.form where r.enabled && !r.name.isEmpty { parts.append("--data-urlencode " + quote(m.text("\(r.name)=\(r.value)"))) }
        case BodyType.multipart:
            for r in p.body.multipart where r.enabled && !r.name.isEmpty {
                if r.kind == "file" {
                    let u = Payload.fileURL(r.path, p.baseDir)
                    let type = r.contentType.isEmpty ? Payload.mimeType(u) : r.contentType
                    parts.append("-F " + quote("\(r.name)=@\(u.path);type=\(type)"))
                } else {
                    parts.append("--form-string " + quote(m.text("\(r.name)=\(r.value)")))
                }
            }
        case BodyType.binary:
            if !p.body.binaryPath.isEmpty { parts.append("--data-binary " + quote("@" + Payload.fileURL(p.body.binaryPath, p.baseDir).path)) }
        default:
            if Payload.rawTypes[p.body.type] != nil, !p.body.raw.isEmpty { parts.append("--data-raw " + quote(m.text(p.body.raw))) }
        }
        return parts.joined(separator: multiline ? " \\\n  " : " ")
    }

    /// cURL z uložené verze / záznamu historie (hlavičky už maskované; automatické `User-Agent`, `Accept*`, `Host`, `Content-Length` se vynechají).
    public static func curl(_ e: SavedResponse, options: HTTPEngine.Options = .init(), multiline: Bool = true) -> String {
        let skip: Set<String> = ["user-agent", "accept", "accept-encoding", "host", "content-length"]
        let headers = e.request.headers.filter { !skip.contains($0.name.lowercased()) }
        let body = e.request.body.isEmpty ? Body() : Body(type: BodyType.text, raw: e.request.body)
        return curl(PreparedRequest(method: e.request.method, url: e.request.url, headers: headers, body: body),
                    options: options, multiline: multiline)
    }

    /// Jednoduché uvozovky; `'` uvnitř → `'\''`.
    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    private static func hasBody(_ b: Body) -> Bool {
        switch b.type {
        case BodyType.form: b.form.contains { $0.enabled && !$0.name.isEmpty }
        case BodyType.multipart: b.multipart.contains { $0.enabled && !$0.name.isEmpty }
        case BodyType.binary: !b.binaryPath.isEmpty
        default: Payload.rawTypes[b.type] != nil && !b.raw.isEmpty
        }
    }

    /// Content-Type, který by doplnila aplikace; form a multipart doplní curl sám.
    private static func autoContentType(_ p: PreparedRequest) -> String? {
        if let ct = Payload.rawTypes[p.body.type], !p.body.raw.isEmpty { return ct }
        if p.body.type == BodyType.binary, !p.body.binaryPath.isEmpty { return Payload.mimeType(Payload.fileURL(p.body.binaryPath, p.baseDir)) }
        return nil
    }

    private static func seconds(_ ms: Int) -> String {
        ms % 1000 == 0 ? String(ms / 1000) : String(format: "%.3f", Double(ms) / 1000).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
    }
}

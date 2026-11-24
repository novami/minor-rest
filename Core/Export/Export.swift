import Foundation

/// Export requestu (kap. 6).
nonisolated enum Export {
    /// cURL z připraveného requestu (to, co by se odeslalo). `mask` = maskování tajných hodnot (kap. 2.8) přes `secrets`.
    static func curl(_ par: PreparedRequest, options opt: HTTPEngine.Options = .init(), multiline: Bool = true,
                            mask: Bool = false, secrets: [String] = []) -> String {
        let map = Mask(secrets: mask ? secrets : [])
        let method = par.method.uppercased()
        var parts: [String] = []   // každá položka = jeden flag (na vlastním řádku ve víceřádkovém tvaru)
        let hasBody = hasBody(par.body)

        var head = ["curl"]
        if method == "HEAD" { head.append("--head") } else if method != "GET" || hasBody { head.append("-X " + method) }
        head.append(quote(map.text(par.url)))
        parts.append(head.joined(separator: " "))

        if opt.followRedirects { parts.append("-L --max-redirs \(opt.maxRedirects)") }
        if !opt.verifyTLS { parts.append("-k") }
        if opt.timeoutMs > 0 { parts.append("--max-time " + seconds(opt.timeoutMs)) }
        parts.append("--compressed")

        var headers = par.headers.filter { $0.enabled && !$0.name.isEmpty }
        if let ct = autoContentType(par), !par.noAuto.contains(where: { $0.caseInsensitiveCompare("Content-Type") == .orderedSame }),
           !headers.contains(where: { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }) {
            headers.append(KV(name: "Content-Type", value: ct))
        }
        for hdr in (mask ? map.headers(headers) : headers) { parts.append("-H " + quote("\(hdr.name): \(hdr.value)")) }

        switch par.body.type {
        case BodyType.form:
            for res in par.body.form where res.enabled && !res.name.isEmpty { parts.append("--data-urlencode " + quote(map.text("\(res.name)=\(res.value)"))) }
        case BodyType.multipart:
            for res in par.body.multipart where res.enabled && !res.name.isEmpty {
                if res.kind == "file" {
                    let urlVal = Payload.fileURL(res.path, par.baseDir)
                    let type = res.contentType.isEmpty ? Payload.mimeType(urlVal) : res.contentType
                    parts.append("-F " + quote("\(res.name)=@\(urlVal.path);type=\(type)"))
                } else {
                    parts.append("--form-string " + quote(map.text("\(res.name)=\(res.value)")))
                }
            }
        case BodyType.binary:
            if !par.body.binaryPath.isEmpty { parts.append("--data-binary " + quote("@" + Payload.fileURL(par.body.binaryPath, par.baseDir).path)) }
        default:
            if Payload.rawTypes[par.body.type] != nil, !par.body.raw.isEmpty { parts.append("--data-raw " + quote(map.text(par.body.raw))) }
        }
        return parts.joined(separator: multiline ? " \\\n  " : " ")
    }

    /// cURL z uložené verze / záznamu historie (hlavičky už maskované; automatické `User-Agent`, `Accept*`, `Host`, `Content-Length` se vynechají).
    static func curl(_ elem: SavedResponse, options: HTTPEngine.Options = .init(), multiline: Bool = true) -> String {
        let skip: Set<String> = ["user-agent", "accept", "accept-encoding", "host", "content-length"]
        let headers = elem.request.headers.filter { !skip.contains($0.name.lowercased()) }
        let body = elem.request.body.isEmpty ? Body() : Body(type: BodyType.text, raw: elem.request.body)
        return curl(PreparedRequest(method: elem.request.method, url: elem.request.url, headers: headers, body: body),
                    options: options, multiline: multiline)
    }

    /// Jednoduché uvozovky; `'` uvnitř → `'\''`.
    static func quote(_ str: String) -> String { "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    private static func hasBody(_ buf: Body) -> Bool {
        switch buf.type {
        case BodyType.form: buf.form.contains { $0.enabled && !$0.name.isEmpty }
        case BodyType.multipart: buf.multipart.contains { $0.enabled && !$0.name.isEmpty }
        case BodyType.binary: !buf.binaryPath.isEmpty
        default: Payload.rawTypes[buf.type] != nil && !buf.raw.isEmpty
        }
    }

    /// Content-Type, který by doplnila aplikace; form a multipart doplní curl sám.
    private static func autoContentType(_ par: PreparedRequest) -> String? {
        if let ct = Payload.rawTypes[par.body.type], !par.body.raw.isEmpty { return ct }
        if par.body.type == BodyType.binary, !par.body.binaryPath.isEmpty { return Payload.mimeType(Payload.fileURL(par.body.binaryPath, par.baseDir)) }
        return nil
    }

    private static func seconds(_ ms: Int) -> String {
        ms % 1000 == 0 ? String(ms / 1000) : String(format: "%.3f", Double(ms) / 1000).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
    }
}

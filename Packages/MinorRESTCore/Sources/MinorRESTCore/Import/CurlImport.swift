import Foundation

/// Import příkazu cURL do requestu (kap. 6): vlastní shell tokenizér + podmnožina přepínačů.
public enum CurlImport {
    /// `true` pokud text vypadá jako příkaz cURL (nabídka importu při vložení do URL baru).
    public static func looksLikeCurl(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("curl ") || t.hasPrefix("curl\t") || t.hasPrefix("curl\\")
    }

    public static func parse(_ text: String) throws(CoreError) -> (Request, warnings: [String]) {
        let tokens = try tokenize(text)
        guard tokens.first == "curl" else { throw CoreError(.curlInvalid, "curl") }
        var st = State()
        var i = 1
        func value(_ flag: String) throws(CoreError) -> String {
            guard i + 1 < tokens.count else { throw CoreError(.curlInvalid, flag) }
            i += 1
            return tokens[i]
        }
        var onlyArgs = false
        while i < tokens.count {
            let tok = tokens[i]
            if onlyArgs || !tok.hasPrefix("-") || tok == "-" {
                st.positional(tok)
            } else if tok == "--" {
                onlyArgs = true
            } else if tok.hasPrefix("--") {
                var name = tok, inline: String?
                if let eq = tok.firstIndex(of: "=") { name = String(tok[..<eq]); inline = String(tok[tok.index(after: eq)...]) }
                if Self.longWithValue.contains(name) {
                    let v: String
                    if let inline { v = inline } else { v = try value(name) }
                    st.apply(name, v)
                } else {
                    st.apply(name, nil)
                }
            } else {
                // Sdružené krátké přepínače: `-sSL`, `-XPOST`, `-H'…'`.
                let chars = Array(tok.dropFirst())
                var k = 0
                while k < chars.count {
                    let flag = "-" + String(chars[k])
                    if Self.shortWithValue.contains(chars[k]) {
                        let rest = String(chars[(k + 1)...])
                        let v: String
                        if rest.isEmpty { v = try value(flag) } else { v = rest }
                        st.apply(flag, v)
                        break
                    }
                    st.apply(flag, nil)
                    k += 1
                }
            }
            i += 1
        }
        return try st.build()
    }

    // MARK: - Přepínače

    private static let shortWithValue: Set<Character> = ["X", "H", "d", "F", "u", "A", "b", "m", "e", "o", "T", "w", "x", "c", "D", "K", "E", "z", "Y", "y"]
    private static let longWithValue: Set<String> = [
        "--request", "--header", "--data", "--data-raw", "--data-binary", "--data-ascii", "--data-urlencode", "--form", "--form-string",
        "--user", "--user-agent", "--cookie", "--max-time", "--max-redirs", "--url", "--referer", "--output", "--upload-file",
        "--write-out", "--proxy", "--cookie-jar", "--config", "--cert", "--key", "--cacert", "--connect-timeout", "--retry",
        "--limit-rate", "--resolve", "--interface", "--oauth2-bearer", "--proxy-user", "--dump-header", "--json",
    ]
    private static let ignored: Set<String> = [
        "-s", "-S", "-v", "-i", "-f", "-g", "-#", "-N", "-O", "-J", "-Z", "-q", "-4", "-6",
        "--silent", "--show-error", "--verbose", "--include", "--fail", "--globoff", "--compressed", "--no-buffer", "--http1.0", "--http1.1",
        "--http2", "--http2-prior-knowledge", "--http3", "--tcp-nodelay", "--no-keepalive", "--tlsv1.2", "--tlsv1.3", "--ipv4", "--ipv6",
        "--location-trusted", "--remote-name", "--progress-bar", "--fail-with-body", "--raw", "--path-as-is", "--no-progress-meter",
    ]

    private struct State {
        var method: String?
        var url: String?
        var headers: [KV] = []
        var data: [String] = []        // -d / --data* (raw)
        var urlencoded: [KV] = []      // --data-urlencode
        var multipart: [MultipartPart] = []
        var user: String?
        var follow = false
        var maxRedirs: Int?
        var insecure = false
        var timeoutMs: Int?
        var head = false
        var get = false
        var warnings: [String] = []

        mutating func positional(_ tok: String) {
            if url == nil { url = tok } else { warnings.append(tok) }
        }

        mutating func apply(_ flag: String, _ v: String?) {
            let v = v ?? ""
            switch flag {
            case "-X", "--request": method = v.uppercased()
            case "-H", "--header": header(v)
            case "-d", "--data", "--data-ascii", "--data-binary": data.append(fileRef(v, flag))
            case "--data-raw": data.append(v)
            case "--json": data.append(fileRef(v, flag)); headers.append(KV(name: "Content-Type", value: "application/json"))
            case "--data-urlencode": urlencode(v)
            case "-F", "--form", "--form-string": form(v, literal: flag == "--form-string")
            case "-u", "--user": user = v
            case "--url": url = v
            case "-L", "--location": follow = true
            case "--max-redirs": maxRedirs = Int(v)
            case "-k", "--insecure": insecure = true
            case "-I", "--head": head = true
            case "-G", "--get": get = true
            case "-A", "--user-agent": headers.append(KV(name: "User-Agent", value: v))
            case "-e", "--referer": headers.append(KV(name: "Referer", value: v))
            case "-b", "--cookie":
                if v.contains("=") { headers.append(KV(name: "Cookie", value: v)) } else { warnings.append(flag) }
            case "-m", "--max-time": timeoutMs = Double(v).map { Int($0 * 1000) }
            default:
                if !CurlImport.ignored.contains(flag) { warnings.append(flag) }
            }
        }

        mutating func header(_ v: String) {
            guard let c = v.firstIndex(of: ":") else { return }   // `Name;` (prázdná hlavička) a nesmysly se přeskočí
            let name = v[..<c].trimmingCharacters(in: .whitespaces)
            let value = v[v.index(after: c)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty else { return }
            switch name.lowercased() {
            case "host", "content-length", "accept-encoding", "connection": return
            default: headers.append(KV(name: name, value: value))
            }
        }

        /// `@soubor` u `-d` se neimportuje (soubor není v requestu); vrací prázdný řetězec a varování.
        mutating func fileRef(_ v: String, _ flag: String) -> String {
            guard v.hasPrefix("@") else { return v }
            warnings.append("\(flag) \(v)")
            return ""
        }

        mutating func urlencode(_ v: String) {
            if let eq = v.firstIndex(of: "=") {
                urlencoded.append(KV(name: String(v[..<eq]), value: String(v[v.index(after: eq)...])))
            } else if v.contains("@") {
                warnings.append("--data-urlencode \(v)")
            } else {
                urlencoded.append(KV(name: "", value: v))
            }
        }

        mutating func form(_ v: String, literal: Bool) {
            guard let eq = v.firstIndex(of: "=") else { return }
            let name = String(v[..<eq]), rest = String(v[v.index(after: eq)...])
            if !literal, rest.hasPrefix("@") || rest.hasPrefix("<") {
                var path = String(rest.dropFirst()), type = ""
                let segs = path.components(separatedBy: ";")
                path = segs[0]
                for s in segs.dropFirst() where s.hasPrefix("type=") { type = String(s.dropFirst(5)) }
                multipart.append(MultipartPart(name: name, kind: "file", path: path, contentType: type))
            } else {
                multipart.append(MultipartPart(name: name, value: rest))
            }
        }

        func contentType() -> String {
            headers.first { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value.lowercased() ?? ""
        }

        mutating func build() throws(CoreError) -> (Request, warnings: [String]) {
            guard var url, !url.isEmpty else { throw CoreError(.curlInvalid, "URL") }
            if !url.contains("://"), !url.hasPrefix("{{") { url = "http://" + url }

            var r = Request()
            var body = Body(type: BodyType.none)
            let ct = contentType()
            let joined = data.joined(separator: "&")
            var query: [KV] = []

            if get {
                // `-G`: data jdou do query místo těla.
                query = (data.flatMap { $0.split(separator: "&").map(String.init) }.map(Self.pair)) + urlencoded
                data = []
            } else if !multipart.isEmpty {
                body = Body(type: BodyType.multipart, multipart: multipart)
                headers.removeAll { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame && ct.hasPrefix("multipart/") }
            } else if !urlencoded.isEmpty || (!data.isEmpty && Self.looksLikeForm(joined, ct)) {
                var rows = data.isEmpty ? [] : joined.split(separator: "&", omittingEmptySubsequences: true).map { Self.pair(String($0)) }
                rows += urlencoded
                body = Body(type: BodyType.form, form: rows)
                headers.removeAll { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame && ct.hasPrefix("application/x-www-form-urlencoded") }
            } else if !data.isEmpty {
                let type: String
                if ct.contains("json") || (ct.isEmpty && Self.isJSON(joined)) { type = BodyType.json }
                else if ct.contains("xml") { type = BodyType.xml }
                else if ct.contains("html") { type = BodyType.html }
                else { type = BodyType.text }
                body = Body(type: type, raw: joined)
                let auto = [BodyType.json: "application/json", BodyType.xml: "application/xml", BodyType.html: "text/html", BodyType.text: "text/plain"][type] ?? ""
                if ct == auto || ct.hasPrefix(auto + ";") {
                    headers.removeAll { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }
                }
            }

            let hasBody = !data.isEmpty || !urlencoded.isEmpty && !get || !multipart.isEmpty
            r.method = head ? "HEAD" : (method ?? (hasBody ? "POST" : "GET"))
            let (u, q) = URLBar.parse(url, query: query)
            r.url = u
            r.params = Params(query: q, path: PathParams.sync(u, []) ?? [])
            r.headers = headers
            r.body = body
            if let user {
                let c = user.firstIndex(of: ":")
                r.auth = Auth(type: AuthType.basic, basic: BasicAuth(username: c.map { String(user[..<$0]) } ?? user,
                                                                    password: c.map { String(user[user.index(after: $0)...]) } ?? ""))
            }
            if follow { r.settings.followRedirects = true; r.settings.maxRedirects = maxRedirs ?? r.settings.maxRedirects }
            if insecure { r.settings.verifyTLS = false }
            if let timeoutMs { r.settings.timeoutMs = timeoutMs }
            return (r, warnings)
        }

        static func isJSON(_ s: String) -> Bool {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t.hasPrefix("{") || t.hasPrefix("[")) && (try? JSONValue.parse(t)) != nil
        }

        /// `a=1&b=2` bez JSON/XML a bez jiného Content-Type než formulářového.
        static func looksLikeForm(_ s: String, _ ct: String) -> Bool {
            if ct.hasPrefix("application/x-www-form-urlencoded") { return true }
            guard ct.isEmpty, !isJSON(s), !s.hasPrefix("<"), !s.isEmpty else { return false }
            return s.split(separator: "&").allSatisfy { $0.contains("=") && !$0.contains(" ") && !$0.contains("\n") }
        }

        /// `name=value` s dekódováním `%xx` a `+`.
        static func pair(_ s: String) -> KV {
            let eq = s.firstIndex(of: "=")
            func dec(_ x: Substring) -> String {
                let p = x.replacingOccurrences(of: "+", with: " ")
                return p.removingPercentEncoding ?? p
            }
            guard let eq else { return KV(name: dec(Substring(s)), value: "", bare: true) }
            return KV(name: dec(s[..<eq]), value: dec(s[s.index(after: eq)...]))
        }
    }

    // MARK: - Tokenizér

    /// Shell tokeny: `'…'`, `"…"` (escape `\" \\ \$ \``), `$'…'` (ANSI-C), `\x` mimo uvozovky; `\`+newline = spojení řádků.
    static func tokenize(_ text: String) throws(CoreError) -> [String] {
        let s = Array(text.replacingOccurrences(of: "\\\r\n", with: " ").replacingOccurrences(of: "\\\n", with: " "))
        var out: [String] = []
        var cur = "", has = false
        var i = 0
        func unterminated() -> CoreError { CoreError(.curlInvalid, "quote") }
        while i < s.count {
            let c = s[i]
            switch c {
            case " ", "\t", "\n", "\r":
                // Samostatná mezera vzniká z `\`+newline slepeného jednořádkovým polem při vložení; zahodit.
                if has, cur != " " { out.append(cur) }
                cur = ""; has = false
            case "'":
                i += 1
                var closed = false
                while i < s.count { if s[i] == "'" { closed = true; break }; cur.append(s[i]); i += 1 }
                guard closed else { throw unterminated() }
                has = true
            case "\"":
                i += 1
                var closed = false
                while i < s.count {
                    if s[i] == "\"" { closed = true; break }
                    if s[i] == "\\", i + 1 < s.count, "\"\\$`".contains(s[i + 1]) { i += 1 }
                    cur.append(s[i]); i += 1
                }
                guard closed else { throw unterminated() }
                has = true
            case "$" where i + 1 < s.count && s[i + 1] == "'":
                i += 2
                var closed = false
                while i < s.count {
                    if s[i] == "'" { closed = true; break }
                    if s[i] == "\\", i + 1 < s.count {
                        i += 1
                        switch s[i] {
                        case "n": cur.append("\n")
                        case "t": cur.append("\t")
                        case "r": cur.append("\r")
                        case "x", "u", "U":
                            let n = s[i] == "x" ? 2 : s[i] == "u" ? 4 : 8
                            let hex = String(s[(i + 1)..<min(i + 1 + n, s.count)])
                            if let v = UInt32(hex, radix: 16), let sc = Unicode.Scalar(v) { cur.append(Character(sc)); i += hex.count }
                            else { cur.append(s[i]) }
                        default: cur.append(s[i])
                        }
                    } else { cur.append(s[i]) }
                    i += 1
                }
                guard closed else { throw unterminated() }
                has = true
            case "\\":
                if i + 1 < s.count { i += 1; cur.append(s[i]); has = true }
            default:
                cur.append(c); has = true
            }
            i += 1
        }
        if has, cur != " " { out.append(cur) }
        return out
    }
}

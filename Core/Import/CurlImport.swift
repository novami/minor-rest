import Foundation

/// Import příkazu cURL do requestu (kap. 6): vlastní shell tokenizér + podmnožina přepínačů.
nonisolated enum CurlImport {
    /// `true` pokud text vypadá jako příkaz cURL (nabídka importu při vložení do URL baru).
    static func looksLikeCurl(_ text: String) -> Bool {
        let txt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return txt.hasPrefix("curl ") || txt.hasPrefix("curl\t") || txt.hasPrefix("curl\\")
    }

    static func parse(_ text: String) throws(CoreError) -> (Request, warnings: [String]) {
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
                var name = tok
                var inline: String?
                if let eq = tok.firstIndex(of: "=") {
                    name = String(tok[..<eq])
                    inline = String(tok[tok.index(after: eq)...])
                }
                if Self.longWithValue.contains(name) {
                    let val: String
                    if let inline { val = inline } else { val = try value(name) }
                    st.apply(name, val)
                } else {
                    st.apply(name, nil)
                }
            } else {
                // Sdružené krátké přepínače: `-sSL`, `-XPOST`, `-H'…'`.
                let chars = Array(tok.dropFirst())
                var key = 0
                while key < chars.count {
                    let flag = "-" + String(chars[key])
                    if Self.shortWithValue.contains(chars[key]) {
                        let rest = String(chars[(key + 1)...])
                        let val: String
                        if rest.isEmpty { val = try value(flag) } else { val = rest }
                        st.apply(flag, val)
                        break
                    }
                    st.apply(flag, nil)
                    key += 1
                }
            }
            i += 1
        }
        return try st.build()
    }

    // MARK: - Přepínače

    private static let shortWithValue: Set<Character> = [
        "X", "H", "d", "F", "u", "A", "b", "m", "e", "o", "T", "w", "x", "c", "D", "K", "E", "z", "Y", "y"
    ]
    private static let longWithValue: Set<String> = [
        "--request", "--header", "--data", "--data-raw", "--data-binary", "--data-ascii", "--data-urlencode", "--form",
        "--form-string",
        "--user", "--user-agent", "--cookie", "--max-time", "--max-redirs", "--url", "--referer", "--output",
        "--upload-file",
        "--write-out", "--proxy", "--cookie-jar", "--config", "--cert", "--key", "--cacert", "--connect-timeout",
        "--retry",
        "--limit-rate", "--resolve", "--interface", "--oauth2-bearer", "--proxy-user", "--dump-header", "--json"
    ]
    private static let ignored: Set<String> = [
        "-s", "-S", "-v", "-i", "-f", "-g", "-#", "-N", "-O", "-J", "-Z", "-q", "-4", "-6",
        "--silent", "--show-error", "--verbose", "--include", "--fail", "--globoff", "--compressed", "--no-buffer",
        "--http1.0", "--http1.1",
        "--http2", "--http2-prior-knowledge", "--http3", "--tcp-nodelay", "--no-keepalive", "--tlsv1.2", "--tlsv1.3",
        "--ipv4", "--ipv6",
        "--location-trusted", "--remote-name", "--progress-bar", "--fail-with-body", "--raw", "--path-as-is",
        "--no-progress-meter"
    ]

    private struct State {
        var method: String?
        var url: String?
        var headers: [KV] = []
        var data: [String] = []  // -d / --data* (raw)
        var urlencoded: [KV] = []  // --data-urlencode
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

        mutating func apply(_ flag: String, _ val: String?) {
            let val = val ?? ""
            switch flag {
            case "-X", "--request": method = val.uppercased()
            case "-H", "--header": header(val)
            case "-d", "--data", "--data-ascii", "--data-binary": data.append(fileRef(val, flag))
            case "--data-raw": data.append(val)
            case "--json":
                data.append(fileRef(val, flag))
                headers.append(KV(name: "Content-Type", value: "application/json"))
            case "--data-urlencode": urlencode(val)
            case "-F", "--form", "--form-string": form(val, literal: flag == "--form-string")
            case "-u", "--user": user = val
            case "--url": url = val
            case "-L", "--location": follow = true
            case "--max-redirs": maxRedirs = Int(val)
            case "-k", "--insecure": insecure = true
            case "-I", "--head": head = true
            case "-G", "--get": get = true
            case "-A", "--user-agent": headers.append(KV(name: "User-Agent", value: val))
            case "-e", "--referer": headers.append(KV(name: "Referer", value: val))
            case "-b", "--cookie":
                if val.contains("=") { headers.append(KV(name: "Cookie", value: val)) } else { warnings.append(flag) }
            case "-m", "--max-time": timeoutMs = Double(val).map { Int($0 * 1000) }
            default:
                if !CurlImport.ignored.contains(flag) { warnings.append(flag) }
            }
        }

        mutating func header(_ val: String) {
            guard let curVal = val.firstIndex(of: ":") else { return }  // `Name;` (prázdná hlavička) a nesmysly se přeskočí
            let name = val[..<curVal].trimmingCharacters(in: .whitespaces)
            let value = val[val.index(after: curVal)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty else { return }
            switch name.lowercased() {
            case "host", "content-length", "accept-encoding", "connection": return
            default: headers.append(KV(name: name, value: value))
            }
        }

        /// `@soubor` u `-d` se neimportuje (soubor není v requestu); vrací prázdný řetězec a varování.
        mutating func fileRef(_ val: String, _ flag: String) -> String {
            guard val.hasPrefix("@") else { return val }
            warnings.append("\(flag) \(val)")
            return ""
        }

        mutating func urlencode(_ val: String) {
            if let eq = val.firstIndex(of: "=") {
                urlencoded.append(KV(name: String(val[..<eq]), value: String(val[val.index(after: eq)...])))
            } else if val.contains("@") {
                warnings.append("--data-urlencode \(val)")
            } else {
                urlencoded.append(KV(name: "", value: val))
            }
        }

        mutating func form(_ val: String, literal: Bool) {
            guard let eq = val.firstIndex(of: "=") else { return }
            let name = String(val[..<eq])
            let rest = String(val[val.index(after: eq)...])
            if !literal, rest.hasPrefix("@") || rest.hasPrefix("<") {
                var path = String(rest.dropFirst())
                var type = ""
                let segs = path.components(separatedBy: ";")
                path = segs[0]
                for str in segs.dropFirst() where str.hasPrefix("type=") { type = String(str.dropFirst(5)) }
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

            var res = Request()
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
                headers.removeAll {
                    $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame && ct.hasPrefix("multipart/")
                }
            } else if !urlencoded.isEmpty || (!data.isEmpty && Self.looksLikeForm(joined, ct)) {
                var rows =
                    data.isEmpty
                    ? [] : joined.split(separator: "&", omittingEmptySubsequences: true).map { Self.pair(String($0)) }
                rows += urlencoded
                body = Body(type: BodyType.form, form: rows)
                headers.removeAll {
                    $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame
                        && ct.hasPrefix("application/x-www-form-urlencoded")
                }
            } else if !data.isEmpty {
                let type: String
                if ct.contains("json") || (ct.isEmpty && Self.isJSON(joined)) {
                    type = BodyType.json
                } else if ct.contains("xml") {
                    type = BodyType.xml
                } else if ct.contains("html") {
                    type = BodyType.html
                } else {
                    type = BodyType.text
                }
                body = Body(type: type, raw: joined)
                let auto =
                    [
                        BodyType.json: "application/json", BodyType.xml: "application/xml", BodyType.html: "text/html",
                        BodyType.text: "text/plain"
                    ][type] ?? ""
                if ct == auto || ct.hasPrefix(auto + ";") {
                    headers.removeAll { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }
                }
            }

            let hasBody = !data.isEmpty || !urlencoded.isEmpty && !get || !multipart.isEmpty
            res.method = head ? "HEAD" : (method ?? (hasBody ? "POST" : "GET"))
            let (urlVal, que) = URLBar.parse(url, query: query)
            res.url = urlVal
            res.params = Params(query: que, path: PathParams.sync(urlVal, []) ?? [])
            res.headers = headers
            res.body = body
            if let user {
                let curVal = user.firstIndex(of: ":")
                res.auth = Auth(
                    type: AuthType.basic,
                    basic: BasicAuth(
                        username: curVal.map { String(user[..<$0]) } ?? user,
                        password: curVal.map { String(user[user.index(after: $0)...]) } ?? ""))
            }
            if follow {
                res.settings.followRedirects = true
                res.settings.maxRedirects = maxRedirs ?? res.settings.maxRedirects
            }
            if insecure { res.settings.verifyTLS = false }
            if let timeoutMs { res.settings.timeoutMs = timeoutMs }
            return (res, warnings)
        }

        static func isJSON(_ str: String) -> Bool {
            let txt = str.trimmingCharacters(in: .whitespacesAndNewlines)
            return (txt.hasPrefix("{") || txt.hasPrefix("[")) && (try? JSONValue.parse(txt)) != nil
        }

        /// `a=1&b=2` bez JSON/XML a bez jiného Content-Type než formulářového.
        static func looksLikeForm(_ str: String, _ ct: String) -> Bool {
            if ct.hasPrefix("application/x-www-form-urlencoded") { return true }
            guard ct.isEmpty, !isJSON(str), !str.hasPrefix("<"), !str.isEmpty else { return false }
            return str.split(separator: "&").allSatisfy { $0.contains("=") && !$0.contains(" ") && !$0.contains("\n") }
        }

        /// `name=value` s dekódováním `%xx` a `+`.
        static func pair(_ str: String) -> KV {
            let eq = str.firstIndex(of: "=")
            func dec(_ x: Substring) -> String {
                let par = x.replacingOccurrences(of: "+", with: " ")
                return par.removingPercentEncoding ?? par
            }
            guard let eq else { return KV(name: dec(Substring(str)), value: "", bare: true) }
            return KV(name: dec(str[..<eq]), value: dec(str[str.index(after: eq)...]))
        }
    }

    // MARK: - Tokenizér

    /// Shell tokeny: `'…'`, `"…"` (escape `\" \\ \$ \``), `$'…'` (ANSI-C), `\x` mimo uvozovky; `\`+newline = spojení řádků.
    static func tokenize(_ text: String) throws(CoreError) -> [String] {
        let str = Array(text.replacingOccurrences(of: "\\\r\n", with: " ").replacingOccurrences(of: "\\\n", with: " "))
        var out: [String] = []
        var cur = ""
        var has = false
        var i = 0
        func unterminated() -> CoreError { CoreError(.curlInvalid, "quote") }
        while i < str.count {
            let curVal = str[i]
            switch curVal {
            case " ", "\t", "\n", "\r":
                // Samostatná mezera vzniká z `\`+newline slepeného jednořádkovým polem při vložení; zahodit.
                if has, cur != " " { out.append(cur) }
                cur = ""
                has = false
            case "'":
                i += 1
                var closed = false
                while i < str.count {
                    if str[i] == "'" {
                        closed = true
                        break
                    }
                    cur.append(str[i])
                    i += 1
                }
                guard closed else { throw unterminated() }
                has = true
            case "\"":
                i += 1
                var closed = false
                while i < str.count {
                    if str[i] == "\"" {
                        closed = true
                        break
                    }
                    if str[i] == "\\", i + 1 < str.count, "\"\\$`".contains(str[i + 1]) { i += 1 }
                    cur.append(str[i])
                    i += 1
                }
                guard closed else { throw unterminated() }
                has = true
            case "$" where i + 1 < str.count && str[i + 1] == "'":
                i += 2
                var closed = false
                while i < str.count {
                    if str[i] == "'" {
                        closed = true
                        break
                    }
                    if str[i] == "\\", i + 1 < str.count {
                        i += 1
                        switch str[i] {
                        case "n": cur.append("\n")
                        case "t": cur.append("\t")
                        case "r": cur.append("\r")
                        case "x", "u", "U":
                            let num = str[i] == "x" ? 2 : str[i] == "u" ? 4 : 8
                            let hex = String(str[(i + 1)..<min(i + 1 + num, str.count)])
                            if let val = UInt32(hex, radix: 16), let sc = Unicode.Scalar(val) {
                                cur.append(Character(sc))
                                i += hex.count
                            } else {
                                cur.append(str[i])
                            }
                        default: cur.append(str[i])
                        }
                    } else {
                        cur.append(str[i])
                    }
                    i += 1
                }
                guard closed else { throw unterminated() }
                has = true
            case "\\":
                if i + 1 < str.count {
                    i += 1
                    cur.append(str[i])
                    has = true
                }
            default:
                cur.append(curVal)
                has = true
            }
            i += 1
        }
        if has, cur != " " { out.append(cur) }
        return out
    }
}

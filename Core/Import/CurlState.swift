import Foundation

/// Stav rozboru příkazu cURL: nasbírané přepínače, ze kterých se sestaví `Request`.
nonisolated struct CurlState {
    var method: String?
    var url: String?
    var headers: [KeyValue] = []
    var data: [String] = []  // -d / --data* (raw)
    var urlencoded: [KeyValue] = []  // --data-urlencode
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
        if applyBody(flag, val) || applyRequest(flag, val) || applyHeader(flag, val) { return }
        if !CurlImport.ignored.contains(flag) { warnings.append(flag) }
    }

    /// Přepínače s daty těla; `false` = přepínač sem nepatří.
    private mutating func applyBody(_ flag: String, _ val: String) -> Bool {
        switch flag {
        case "-d", "--data", "--data-ascii", "--data-binary": data.append(fileRef(val, flag))
        case "--data-raw": data.append(val)
        case "--json":
            data.append(fileRef(val, flag))
            headers.append(KeyValue(name: "Content-Type", value: "application/json"))
        case "--data-urlencode": urlencode(val)
        case "-F", "--form", "--form-string": form(val, literal: flag == "--form-string")
        default: return false
        }
        return true
    }

    /// Metoda, adresa, hlavičky a síťové volby; `false` = přepínač sem nepatří.
    private mutating func applyRequest(_ flag: String, _ val: String) -> Bool {
        switch flag {
        case "-X", "--request": method = val.uppercased()
        case "-u", "--user": user = val
        case "--url": url = val
        case "-L", "--location": follow = true
        case "--max-redirs": maxRedirs = Int(val)
        case "-k", "--insecure": insecure = true
        case "-I", "--head": head = true
        case "-G", "--get": get = true
        case "-m", "--max-time": timeoutMs = Double(val).map { Int($0 * 1000) }
        default: return false
        }
        return true
    }

    /// Hlavičky zadané přímo či zkratkou (`-A`, `-e`, `-b`); `false` = přepínač sem nepatří.
    private mutating func applyHeader(_ flag: String, _ val: String) -> Bool {
        switch flag {
        case "-H", "--header": header(val)
        case "-A", "--user-agent": headers.append(KeyValue(name: "User-Agent", value: val))
        case "-e", "--referer": headers.append(KeyValue(name: "Referer", value: val))
        case "-b", "--cookie": cookie(val, flag)
        default: return false
        }
        return true
    }

    private mutating func cookie(_ val: String, _ flag: String) {
        if val.contains("=") {
            headers.append(KeyValue(name: "Cookie", value: val))
        } else {
            warnings.append(flag)
        }
    }

    private mutating func header(_ val: String) {
        // `Name;` (prázdná hlavička) a nesmysly se přeskočí
        guard let curVal = val.firstIndex(of: ":") else { return }
        let name = val[..<curVal].trimmingCharacters(in: .whitespaces)
        let value = val[val.index(after: curVal)...].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !value.isEmpty else { return }
        switch name.lowercased() {
        case "host", "content-length", "accept-encoding", "connection": return
        default: headers.append(KeyValue(name: name, value: value))
        }
    }

    /// `@soubor` u `-d` se neimportuje (soubor není v requestu); vrací prázdný řetězec a varování.
    private mutating func fileRef(_ val: String, _ flag: String) -> String {
        guard val.hasPrefix("@") else { return val }
        warnings.append("\(flag) \(val)")
        return ""
    }

    private mutating func urlencode(_ val: String) {
        if let eq = val.firstIndex(of: "=") {
            urlencoded.append(KeyValue(name: String(val[..<eq]), value: String(val[val.index(after: eq)...])))
        } else if val.contains("@") {
            warnings.append("--data-urlencode \(val)")
        } else {
            urlencoded.append(KeyValue(name: "", value: val))
        }
    }

    private mutating func form(_ val: String, literal: Bool) {
        guard let eq = val.firstIndex(of: "=") else { return }
        let name = String(val[..<eq])
        let rest = String(val[val.index(after: eq)...])
        if !literal, rest.hasPrefix("@") || rest.hasPrefix("<") {
            let segs = String(rest.dropFirst()).components(separatedBy: ";")
            var type = ""
            for str in segs.dropFirst() where str.hasPrefix("type=") { type = String(str.dropFirst(5)) }
            multipart.append(MultipartPart(name: name, kind: "file", path: segs[0], contentType: type))
        } else {
            multipart.append(MultipartPart(name: name, value: rest))
        }
    }

    private func contentType() -> String {
        headers.first { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value.lowercased() ?? ""
    }

    private mutating func removeContentType(whenStartingWith prefix: String, _ ct: String) {
        headers.removeAll { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame && ct.hasPrefix(prefix) }
    }

    /// Tělo requestu podle dat a `Content-Type`; s `-G` jdou data do query.
    private mutating func makeBody(query: inout [KeyValue]) -> Body {
        let ct = contentType()
        let joined = data.joined(separator: "&")
        if get {
            // `-G`: data jdou do query místo těla.
            query = (data.flatMap { $0.split(separator: "&").map(String.init) }.map(Self.pair)) + urlencoded
            data = []
            return Body(type: BodyType.none)
        }
        if !multipart.isEmpty {
            removeContentType(whenStartingWith: "multipart/", ct)
            return Body(type: BodyType.multipart, multipart: multipart)
        }
        if !urlencoded.isEmpty || (!data.isEmpty && Self.looksLikeForm(joined, ct)) {
            var rows =
                data.isEmpty
                ? [] : joined.split(separator: "&", omittingEmptySubsequences: true).map { Self.pair(String($0)) }
            rows += urlencoded
            removeContentType(whenStartingWith: "application/x-www-form-urlencoded", ct)
            return Body(type: BodyType.form, form: rows)
        }
        guard !data.isEmpty else { return Body(type: BodyType.none) }
        let type = Self.rawType(ct, joined)
        let auto =
            [
                BodyType.json: "application/json", BodyType.xml: "application/xml", BodyType.html: "text/html",
                BodyType.text: "text/plain"
            ][type] ?? ""
        if ct == auto || ct.hasPrefix(auto + ";") {
            headers.removeAll { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }
        }
        return Body(type: type, raw: joined)
    }

    private static func rawType(_ ct: String, _ joined: String) -> String {
        if ct.contains("json") || (ct.isEmpty && isJSON(joined)) { return BodyType.json }
        if ct.contains("xml") { return BodyType.xml }
        if ct.contains("html") { return BodyType.html }
        return BodyType.text
    }

    private func basicAuth() -> Auth? {
        guard let user else { return nil }
        let curVal = user.firstIndex(of: ":")
        return Auth(
            type: AuthType.basic,
            basic: BasicAuth(
                username: curVal.map { String(user[..<$0]) } ?? user,
                password: curVal.map { String(user[user.index(after: $0)...]) } ?? ""))
    }

    mutating func build() throws(CoreError) -> (Request, warnings: [String]) {
        guard var url, !url.isEmpty else { throw CoreError(.curlInvalid, "URL") }
        if !url.contains("://"), !url.hasPrefix("{{") { url = "http://" + url }

        var res = Request()
        var query: [KeyValue] = []
        let body = makeBody(query: &query)
        let hasBody = !data.isEmpty || !urlencoded.isEmpty && !get || !multipart.isEmpty
        res.method = head ? "HEAD" : (method ?? (hasBody ? "POST" : "GET"))
        let (urlVal, que) = URLBar.parse(url, query: query)
        res.url = urlVal
        res.params = Params(query: que, path: PathParams.sync(urlVal, []) ?? [])
        res.headers = headers
        res.body = body
        if let auth = basicAuth() { res.auth = auth }
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
    static func pair(_ str: String) -> KeyValue {
        let eq = str.firstIndex(of: "=")
        func dec(_ x: Substring) -> String {
            let par = x.replacingOccurrences(of: "+", with: " ")
            return par.removingPercentEncoding ?? par
        }
        guard let eq else { return KeyValue(name: dec(Substring(str)), value: "", bare: true) }
        return KeyValue(name: dec(str[..<eq]), value: dec(str[str.index(after: eq)...]))
    }
}

// Převod modelu na YAML a zpět. Pořadí klíčů a vynechávání prázdných hodnot odpovídá
// Go verzi (struktury s `omitempty`), chybějící `enabled` znamená zapnuto.

extension KV: YAMLCodable {
    public var yaml: YNode {
        var m = YMap()
        m.add("name", name)
        m.add("value", value)
        m.add("enabled", enabled)
        m.addIfNotEmpty("description", description)
        m.addIfTrue("bare", bare)
        return m.node
    }

    public init(yaml o: YAMLObject) throws {
        self.init(name: try o.string("name"), value: try o.string("value"), enabled: try o.bool("enabled", default: true),
                  description: try o.string("description"), bare: try o.bool("bare"))
    }
}

extension PathParam: YAMLCodable {
    public var yaml: YNode {
        var m = YMap()
        m.add("name", name)
        m.add("value", value)
        m.addIfNotEmpty("description", description)
        return m.node
    }

    public init(yaml o: YAMLObject) throws {
        self.init(name: try o.string("name"), value: try o.string("value"), description: try o.string("description"))
    }
}

extension Var: YAMLCodable {
    public var yaml: YNode {
        var m = YMap()
        m.add("name", name)
        m.addIfNotEmpty("value", value)
        m.addIfTrue("secret", secret)
        m.add("enabled", enabled)
        return m.node
    }

    public init(yaml o: YAMLObject) throws {
        self.init(name: try o.string("name"), value: try o.string("value"), secret: try o.bool("secret"),
                  enabled: try o.bool("enabled", default: true))
    }
}

extension HTTPSettings: YAMLCodable {
    public var yaml: YNode { map.node }

    var map: YMap {
        var m = YMap()
        m.addIfPresent("httpVersion", httpVersion)
        m.addIfPresent("followRedirects", followRedirects)
        m.addIfPresent("maxRedirects", maxRedirects)
        m.addIfPresent("timeoutMs", timeoutMs)
        m.addIfPresent("verifyTls", verifyTLS)
        m.addIfPresent("cookieJar", cookieJar)
        return m
    }

    public init(yaml o: YAMLObject) throws {
        self.init(httpVersion: try o.optionalString("httpVersion"), followRedirects: try o.optionalBool("followRedirects"),
                  maxRedirects: try o.optionalInt("maxRedirects"), timeoutMs: try o.optionalInt("timeoutMs"),
                  verifyTLS: try o.optionalBool("verifyTls"), cookieJar: try o.optionalBool("cookieJar"))
    }
}

extension BasicAuth: YAMLCodable {
    public var yaml: YNode {
        var m = YMap()
        m.add("username", username)
        m.add("password", password)
        return m.node
    }

    public init(yaml o: YAMLObject) throws {
        self.init(username: try o.string("username"), password: try o.string("password"))
    }
}

extension BearerAuth: YAMLCodable {
    public var yaml: YNode {
        var m = YMap()
        m.add("token", token)
        m.add("prefix", prefix)
        return m.node
    }

    public init(yaml o: YAMLObject) throws {
        self.init(token: try o.string("token"), prefix: try o.string("prefix"))
    }
}

extension APIKeyAuth: YAMLCodable {
    public var yaml: YNode {
        var m = YMap()
        m.add("key", key)
        m.add("value", value)
        m.add("in", location)
        return m.node
    }

    public init(yaml o: YAMLObject) throws {
        self.init(key: try o.string("key"), value: try o.string("value"), location: try o.string("in"))
    }
}

extension OAuth2Auth: YAMLCodable {
    public var yaml: YNode {
        var m = YMap()
        m.add("grantType", grantType)
        m.add("authUrl", authURL)
        m.add("tokenUrl", tokenURL)
        m.add("clientId", clientID)
        m.add("clientSecret", clientSecret)
        m.add("scope", scope)
        m.add("usePkce", usePKCE)
        m.add("redirectPort", redirectPort)
        m.add("username", username)
        m.add("password", password)
        m.add("clientAuth", clientAuth)
        m.add("tokenPlacement", tokenPlacement)
        m.add("headerPrefix", headerPrefix)
        m.add("autoRefresh", autoRefresh)
        return m.node
    }

    public init(yaml o: YAMLObject) throws {
        self.init()
        grantType = try o.string("grantType")
        authURL = try o.string("authUrl")
        tokenURL = try o.string("tokenUrl")
        clientID = try o.string("clientId")
        clientSecret = try o.string("clientSecret")
        scope = try o.string("scope")
        usePKCE = try o.bool("usePkce")
        redirectPort = try o.int("redirectPort")
        username = try o.string("username")
        password = try o.string("password")
        clientAuth = try o.string("clientAuth")
        tokenPlacement = try o.string("tokenPlacement")
        headerPrefix = try o.string("headerPrefix")
        autoRefresh = try o.bool("autoRefresh")
    }
}

extension Auth: YAMLCodable {
    public var yaml: YNode {
        var m = YMap()
        m.add("type", type)
        m.addIfPresent("basic", basic)
        m.addIfPresent("bearer", bearer)
        m.addIfPresent("apikey", apiKey)
        m.addIfPresent("oauth2", oauth2)
        return m.node
    }

    public init(yaml o: YAMLObject) throws {
        self.init(type: try o.string("type"), basic: try o.object("basic"), bearer: try o.object("bearer"),
                  apiKey: try o.object("apikey"), oauth2: try o.object("oauth2"))
    }
}

extension Params: YAMLCodable {
    public var yaml: YNode { map.node }

    var map: YMap {
        var m = YMap()
        m.addIfNotEmpty("query", query)
        m.addIfNotEmpty("path", path)
        return m
    }

    public init(yaml o: YAMLObject) throws {
        self.init(query: try o.list("query"), path: try o.list("path"))
    }
}

extension MultipartPart: YAMLCodable {
    public var yaml: YNode {
        var m = YMap()
        m.add("name", name)
        m.add("kind", kind)
        m.addIfNotEmpty("value", value)
        m.addIfNotEmpty("path", path)
        m.addIfNotEmpty("contentType", contentType)
        m.add("enabled", enabled)
        return m.node
    }

    public init(yaml o: YAMLObject) throws {
        self.init(name: try o.string("name"), kind: try o.string("kind"), value: try o.string("value"),
                  path: try o.string("path"), contentType: try o.string("contentType"),
                  enabled: try o.bool("enabled", default: true))
    }
}

extension Body: YAMLCodable {
    public var yaml: YNode {
        var m = YMap()
        m.add("type", type)
        m.addIfNotEmpty("raw", raw)
        m.addIfNotEmpty("form", form)
        m.addIfNotEmpty("multipart", multipart)
        m.addIfNotEmpty("binaryPath", binaryPath)
        return m.node
    }

    public init(yaml o: YAMLObject) throws {
        self.init(type: try o.string("type"), raw: try o.string("raw"), form: try o.list("form"),
                  multipart: try o.list("multipart"), binaryPath: try o.string("binaryPath"))
    }
}

extension Extract: YAMLCodable {
    public var yaml: YNode {
        var m = YMap()
        m.add("name", name)
        m.add("from", from)
        m.add("path", path)
        m.add("enabled", enabled)
        return m.node
    }

    public init(yaml o: YAMLObject) throws {
        self.init(name: try o.string("name"), from: try o.string("from"), path: try o.string("path"),
                  enabled: try o.bool("enabled", default: true))
    }
}

extension Request: YAMLCodable {
    public var yaml: YNode {
        var m = YMap()
        m.add("id", id)
        m.add("name", name)
        m.add("seq", seq)
        m.add("method", method)
        m.add("url", url)
        m.addIfNotEmpty("params", params.map)
        m.addIfNotEmpty("headers", headers)
        m.add("auth", auth.yaml)
        m.add("body", body.yaml)
        m.addIfNotEmpty("vars", vars)
        m.addIfNotEmpty("extract", extract)
        m.addIfNotEmpty("settings", settings.map)
        m.addIfNotEmpty("docs", docs)
        return m.node
    }

    public init(yaml o: YAMLObject) throws {
        self.init(id: try o.string("id"), name: try o.string("name"), seq: try o.int("seq"),
                  method: try o.string("method"), url: try o.string("url"),
                  params: try o.object("params") ?? Params(), headers: try o.list("headers"),
                  auth: try o.object("auth") ?? Auth(), body: try o.object("body") ?? Body(),
                  vars: try o.list("vars"), extract: try o.list("extract"),
                  settings: try o.object("settings") ?? HTTPSettings(), docs: try o.string("docs"))
    }
}

extension FolderConfig: YAMLCodable {
    public var yaml: YNode {
        var m = YMap()
        m.add("name", name)
        m.add("seq", seq)
        m.addIfNotEmpty("vars", vars)
        m.addIfNotEmpty("headers", headers)
        m.add("auth", auth.yaml)
        return m.node
    }

    public init(yaml o: YAMLObject) throws {
        self.init(name: try o.string("name"), seq: try o.int("seq"), vars: try o.list("vars"),
                  headers: try o.list("headers"), auth: try o.object("auth") ?? Auth())
    }
}

extension ProjectConfig: YAMLCodable {
    public var yaml: YNode {
        var m = YMap()
        m.add("formatVersion", formatVersion)
        m.add("id", id)
        m.add("name", name)
        m.addIfNotEmpty("description", description)
        m.addIfNotEmpty("vars", vars)
        m.addIfNotEmpty("headers", headers)
        m.add("auth", auth.yaml)
        m.addIfNotEmpty("settings", settings.map)
        m.add("ignoreResponsesInGit", ignoreResponsesInGit)
        return m.node
    }

    public init(yaml o: YAMLObject) throws {
        self.init(formatVersion: try o.int("formatVersion"), id: try o.string("id"), name: try o.string("name"),
                  description: try o.string("description"), vars: try o.list("vars"), headers: try o.list("headers"),
                  auth: try o.object("auth") ?? Auth(), settings: try o.object("settings") ?? HTTPSettings(),
                  ignoreResponsesInGit: try o.bool("ignoreResponsesInGit"))
    }
}

extension Environment: YAMLCodable {
    public var yaml: YNode {
        var m = YMap()
        m.add("id", id)
        m.add("name", name)
        m.addIfNotEmpty("vars", vars)
        return m.node
    }

    public init(yaml o: YAMLObject) throws {
        self.init(id: try o.string("id"), name: try o.string("name"), vars: try o.list("vars"))
    }
}

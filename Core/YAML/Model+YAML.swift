// Převod modelu na YAML a zpět. Pořadí klíčů a vynechávání prázdných hodnot odpovídá
// Go verzi (struktury s `omitempty`), chybějící `enabled` znamená zapnuto.

nonisolated extension KeyValue: YAMLCodable {
    var yaml: YNode {
        var mapVal = YMap()
        mapVal.add("name", name)
        mapVal.add("value", value)
        mapVal.add("enabled", enabled)
        mapVal.addIfNotEmpty("description", description)
        mapVal.addIfTrue("bare", bare)
        return mapVal.node
    }

    init(yaml opt: YAMLObject) throws {
        self.init(
            name: try opt.string("name"), value: try opt.string("value"),
            enabled: try opt.bool("enabled", default: true),
            description: try opt.string("description"), bare: try opt.bool("bare"))
    }
}

nonisolated extension PathParam: YAMLCodable {
    var yaml: YNode {
        var mapVal = YMap()
        mapVal.add("name", name)
        mapVal.add("value", value)
        mapVal.addIfNotEmpty("description", description)
        return mapVal.node
    }

    init(yaml opt: YAMLObject) throws {
        self.init(
            name: try opt.string("name"), value: try opt.string("value"), description: try opt.string("description"))
    }
}

nonisolated extension Var: YAMLCodable {
    var yaml: YNode {
        var mapVal = YMap()
        mapVal.add("name", name)
        mapVal.addIfNotEmpty("value", value)
        mapVal.addIfTrue("secret", secret)
        mapVal.add("enabled", enabled)
        return mapVal.node
    }

    init(yaml opt: YAMLObject) throws {
        self.init(
            name: try opt.string("name"), value: try opt.string("value"), secret: try opt.bool("secret"),
            enabled: try opt.bool("enabled", default: true))
    }
}

nonisolated extension HTTPSettings: YAMLCodable {
    var yaml: YNode { map.node }

    var map: YMap {
        var mapVal = YMap()
        mapVal.addIfPresent("httpVersion", httpVersion)
        mapVal.addIfPresent("followRedirects", followRedirects)
        mapVal.addIfPresent("maxRedirects", maxRedirects)
        mapVal.addIfPresent("timeoutMs", timeoutMs)
        mapVal.addIfPresent("verifyTls", verifyTLS)
        mapVal.addIfPresent("cookieJar", cookieJar)
        return mapVal
    }

    init(yaml opt: YAMLObject) throws {
        self.init(
            httpVersion: try opt.optionalString("httpVersion"),
            followRedirects: try opt.optionalBool("followRedirects"),
            maxRedirects: try opt.optionalInt("maxRedirects"), timeoutMs: try opt.optionalInt("timeoutMs"),
            verifyTLS: try opt.optionalBool("verifyTls"), cookieJar: try opt.optionalBool("cookieJar"))
    }
}

nonisolated extension BasicAuth: YAMLCodable {
    var yaml: YNode {
        var mapVal = YMap()
        mapVal.add("username", username)
        mapVal.add("password", password)
        return mapVal.node
    }

    init(yaml opt: YAMLObject) throws {
        self.init(username: try opt.string("username"), password: try opt.string("password"))
    }
}

nonisolated extension BearerAuth: YAMLCodable {
    var yaml: YNode {
        var mapVal = YMap()
        mapVal.add("token", token)
        mapVal.add("prefix", prefix)
        return mapVal.node
    }

    init(yaml opt: YAMLObject) throws {
        self.init(token: try opt.string("token"), prefix: try opt.string("prefix"))
    }
}

nonisolated extension APIKeyAuth: YAMLCodable {
    var yaml: YNode {
        var mapVal = YMap()
        mapVal.add("key", key)
        mapVal.add("value", value)
        mapVal.add("in", location)
        return mapVal.node
    }

    init(yaml opt: YAMLObject) throws {
        self.init(key: try opt.string("key"), value: try opt.string("value"), location: try opt.string("in"))
    }
}

nonisolated extension OAuth2Auth: YAMLCodable {
    var yaml: YNode {
        var mapVal = YMap()
        mapVal.add("grantType", grantType)
        mapVal.add("authUrl", authURL)
        mapVal.add("tokenUrl", tokenURL)
        mapVal.add("clientId", clientID)
        mapVal.add("clientSecret", clientSecret)
        mapVal.add("scope", scope)
        mapVal.add("usePkce", usePKCE)
        mapVal.add("redirectPort", redirectPort)
        mapVal.add("username", username)
        mapVal.add("password", password)
        mapVal.add("clientAuth", clientAuth)
        mapVal.add("tokenPlacement", tokenPlacement)
        mapVal.add("headerPrefix", headerPrefix)
        mapVal.add("autoRefresh", autoRefresh)
        return mapVal.node
    }

    init(yaml opt: YAMLObject) throws {
        self.init()
        grantType = try opt.string("grantType")
        authURL = try opt.string("authUrl")
        tokenURL = try opt.string("tokenUrl")
        clientID = try opt.string("clientId")
        clientSecret = try opt.string("clientSecret")
        scope = try opt.string("scope")
        usePKCE = try opt.bool("usePkce")
        redirectPort = try opt.int("redirectPort")
        username = try opt.string("username")
        password = try opt.string("password")
        clientAuth = try opt.string("clientAuth")
        tokenPlacement = try opt.string("tokenPlacement")
        headerPrefix = try opt.string("headerPrefix")
        autoRefresh = try opt.bool("autoRefresh")
    }
}

nonisolated extension Auth: YAMLCodable {
    var yaml: YNode {
        var mapVal = YMap()
        mapVal.add("type", type)
        mapVal.addIfPresent("basic", basic)
        mapVal.addIfPresent("bearer", bearer)
        mapVal.addIfPresent("apikey", apiKey)
        mapVal.addIfPresent("oauth2", oauth2)
        return mapVal.node
    }

    init(yaml opt: YAMLObject) throws {
        self.init(
            type: try opt.string("type"), basic: try opt.object("basic"), bearer: try opt.object("bearer"),
            apiKey: try opt.object("apikey"), oauth2: try opt.object("oauth2"))
    }
}

nonisolated extension Params: YAMLCodable {
    var yaml: YNode { map.node }

    var map: YMap {
        var mapVal = YMap()
        mapVal.addIfNotEmpty("query", query)
        mapVal.addIfNotEmpty("path", path)
        return mapVal
    }

    init(yaml opt: YAMLObject) throws {
        self.init(query: try opt.list("query"), path: try opt.list("path"))
    }
}

nonisolated extension MultipartPart: YAMLCodable {
    var yaml: YNode {
        var mapVal = YMap()
        mapVal.add("name", name)
        mapVal.add("kind", kind)
        mapVal.addIfNotEmpty("value", value)
        mapVal.addIfNotEmpty("path", path)
        mapVal.addIfNotEmpty("contentType", contentType)
        mapVal.add("enabled", enabled)
        return mapVal.node
    }

    init(yaml opt: YAMLObject) throws {
        self.init(
            name: try opt.string("name"), kind: try opt.string("kind"), value: try opt.string("value"),
            path: try opt.string("path"), contentType: try opt.string("contentType"),
            enabled: try opt.bool("enabled", default: true))
    }
}

nonisolated extension Body: YAMLCodable {
    var yaml: YNode {
        var mapVal = YMap()
        mapVal.add("type", type)
        mapVal.addIfNotEmpty("raw", raw)
        mapVal.addIfNotEmpty("form", form)
        mapVal.addIfNotEmpty("multipart", multipart)
        mapVal.addIfNotEmpty("binaryPath", binaryPath)
        return mapVal.node
    }

    init(yaml opt: YAMLObject) throws {
        self.init(
            type: try opt.string("type"), raw: try opt.string("raw"), form: try opt.list("form"),
            multipart: try opt.list("multipart"), binaryPath: try opt.string("binaryPath"))
    }
}

nonisolated extension Extract: YAMLCodable {
    var yaml: YNode {
        var mapVal = YMap()
        mapVal.add("name", name)
        mapVal.add("from", from)
        mapVal.add("path", path)
        mapVal.add("enabled", enabled)
        return mapVal.node
    }

    init(yaml opt: YAMLObject) throws {
        self.init(
            name: try opt.string("name"), from: try opt.string("from"), path: try opt.string("path"),
            enabled: try opt.bool("enabled", default: true))
    }
}

nonisolated extension Request: YAMLCodable {
    var yaml: YNode {
        var mapVal = YMap()
        mapVal.add("id", id)
        mapVal.add("name", name)
        mapVal.add("seq", seq)
        mapVal.add("method", method)
        mapVal.add("url", url)
        mapVal.addIfNotEmpty("params", params.map)
        mapVal.addIfNotEmpty("headers", headers)
        mapVal.add("auth", auth.yaml)
        mapVal.add("body", body.yaml)
        mapVal.addIfNotEmpty("vars", vars)
        mapVal.addIfNotEmpty("extract", extract)
        mapVal.addIfNotEmpty("settings", settings.map)
        mapVal.addIfNotEmpty("docs", docs)
        return mapVal.node
    }

    init(yaml opt: YAMLObject) throws {
        self.init(
            id: try opt.string("id"), name: try opt.string("name"), seq: try opt.int("seq"),
            method: try opt.string("method"), url: try opt.string("url"),
            params: try opt.object("params") ?? Params(), headers: try opt.list("headers"),
            auth: try opt.object("auth") ?? Auth(), body: try opt.object("body") ?? Body(),
            vars: try opt.list("vars"), extract: try opt.list("extract"),
            settings: try opt.object("settings") ?? HTTPSettings(), docs: try opt.string("docs"))
    }
}

nonisolated extension FolderConfig: YAMLCodable {
    var yaml: YNode {
        var mapVal = YMap()
        mapVal.add("name", name)
        mapVal.add("seq", seq)
        mapVal.addIfNotEmpty("vars", vars)
        mapVal.addIfNotEmpty("headers", headers)
        mapVal.add("auth", auth.yaml)
        return mapVal.node
    }

    init(yaml opt: YAMLObject) throws {
        self.init(
            name: try opt.string("name"), seq: try opt.int("seq"), vars: try opt.list("vars"),
            headers: try opt.list("headers"), auth: try opt.object("auth") ?? Auth())
    }
}

nonisolated extension ProjectConfig: YAMLCodable {
    var yaml: YNode {
        var mapVal = YMap()
        mapVal.add("formatVersion", formatVersion)
        mapVal.add("id", id)
        mapVal.add("name", name)
        mapVal.addIfNotEmpty("description", description)
        mapVal.addIfNotEmpty("vars", vars)
        mapVal.addIfNotEmpty("headers", headers)
        mapVal.add("auth", auth.yaml)
        mapVal.addIfNotEmpty("settings", settings.map)
        mapVal.add("ignoreResponsesInGit", ignoreResponsesInGit)
        return mapVal.node
    }

    init(yaml opt: YAMLObject) throws {
        self.init(
            formatVersion: try opt.int("formatVersion"), id: try opt.string("id"), name: try opt.string("name"),
            description: try opt.string("description"), vars: try opt.list("vars"), headers: try opt.list("headers"),
            auth: try opt.object("auth") ?? Auth(), settings: try opt.object("settings") ?? HTTPSettings(),
            ignoreResponsesInGit: try opt.bool("ignoreResponsesInGit"))
    }
}

nonisolated extension EnvironmentConfig: YAMLCodable {
    var yaml: YNode {
        var mapVal = YMap()
        mapVal.add("id", id)
        mapVal.add("name", name)
        mapVal.addIfNotEmpty("vars", vars)
        return mapVal.node
    }

    init(yaml opt: YAMLObject) throws {
        self.init(id: try opt.string("id"), name: try opt.string("name"), vars: try opt.list("vars"))
    }
}

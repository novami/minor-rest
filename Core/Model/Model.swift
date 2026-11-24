// Datový model projektu (PLAN kap. 2). Typy výčtových hodnot jsou řetězce, aby se neznámá
// hodnota z novější verze při uložení neztratila.

/// Verze formátu projektu; projekt s vyšší verzí se otevře jen pro čtení.
nonisolated enum ProjectFormat {
    static let version = 1
    static let projectFile = "minorrest.yaml"
    static let folderFile = "_folder.yaml"
    static let requestSuffix = ".req.yaml"
    static let environmentDir = "environments"
    static let responsesDir = ".responses"
}

nonisolated enum HTTPMethod {
    static let get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
    static let head = "HEAD", options = "OPTIONS"
    static let all = [get, post, put, patch, delete, head, options]
}

nonisolated enum BodyType {
    static let none = "none", json = "json", xml = "xml", text = "text", html = "html"
    static let form = "form-urlencoded", multipart = "multipart", binary = "binary"
    static let all = [none, json, xml, text, html, form, multipart, binary]
}

nonisolated enum AuthType {
    static let inherit = "inherit", none = "none", basic = "basic", bearer = "bearer"
    static let apiKey = "apikey", oauth2 = "oauth2"
}

/// Řádek název–hodnota (query, hlavičky, form).
nonisolated struct KV: Hashable, Sendable {
    var name: String
    var value: String
    var enabled: Bool
    var description: String
    /// Jen query: prázdná hodnota se pošle jako `?name` místo `?name=`.
    var bare: Bool

    init(name: String = "", value: String = "", enabled: Bool = true, description: String = "", bare: Bool = false) {
        self.name = name
        self.value = value
        self.enabled = enabled
        self.description = description
        self.bare = bare
    }
}

nonisolated struct PathParam: Hashable, Sendable {
    var name: String
    var value: String
    var description: String

    init(name: String = "", value: String = "", description: String = "") {
        self.name = name
        self.value = value
        self.description = description
    }
}

nonisolated struct Var: Hashable, Sendable {
    var name: String
    var value: String
    var secret: Bool
    var enabled: Bool

    init(name: String = "", value: String = "", secret: Bool = false, enabled: Bool = true) {
        self.name = name
        self.value = value
        self.secret = secret
        self.enabled = enabled
    }
}

/// HTTP nastavení; `nil` = zděděno.
nonisolated struct HTTPSettings: Hashable, Sendable {
    var httpVersion: String?
    var followRedirects: Bool?
    var maxRedirects: Int?
    var timeoutMs: Int?
    var verifyTLS: Bool?
    var cookieJar: Bool?

    init(httpVersion: String? = nil, followRedirects: Bool? = nil, maxRedirects: Int? = nil,
                timeoutMs: Int? = nil, verifyTLS: Bool? = nil, cookieJar: Bool? = nil) {
        self.httpVersion = httpVersion
        self.followRedirects = followRedirects
        self.maxRedirects = maxRedirects
        self.timeoutMs = timeoutMs
        self.verifyTLS = verifyTLS
        self.cookieJar = cookieJar
    }

    var isEmpty: Bool { self == HTTPSettings() }

    /// Vestavěné výchozí hodnoty (globální nastavení aplikace přibude v F11).
    static let builtin = HTTPSettings(httpVersion: "auto", followRedirects: true, maxRedirects: 10,
                                             timeoutMs: 30_000, verifyTLS: true, cookieJar: true)

    /// Doplní nevyplněné (zděděné) položky z `base`.
    func over(_ base: HTTPSettings) -> HTTPSettings {
        HTTPSettings(httpVersion: httpVersion ?? base.httpVersion,
                     followRedirects: followRedirects ?? base.followRedirects,
                     maxRedirects: maxRedirects ?? base.maxRedirects,
                     timeoutMs: timeoutMs ?? base.timeoutMs,
                     verifyTLS: verifyTLS ?? base.verifyTLS,
                     cookieJar: cookieJar ?? base.cookieJar)
    }
}

nonisolated struct Auth: Hashable, Sendable {
    var type: String
    var basic: BasicAuth?
    var bearer: BearerAuth?
    var apiKey: APIKeyAuth?
    var oauth2: OAuth2Auth?

    init(type: String = "", basic: BasicAuth? = nil, bearer: BearerAuth? = nil,
                apiKey: APIKeyAuth? = nil, oauth2: OAuth2Auth? = nil) {
        self.type = type
        self.basic = basic
        self.bearer = bearer
        self.apiKey = apiKey
        self.oauth2 = oauth2
    }
}

nonisolated struct BasicAuth: Hashable, Sendable {
    var username = ""
    var password = ""
}

nonisolated struct BearerAuth: Hashable, Sendable {
    var token = ""
    var prefix = ""
}

nonisolated struct APIKeyAuth: Hashable, Sendable {
    var key = ""
    var value = ""
    /// `header` | `query`
    var location = ""
}

nonisolated struct OAuth2Auth: Hashable, Sendable {
    /// `client_credentials` | `authorization_code` | `password`
    var grantType = ""
    var authURL = ""
    var tokenURL = ""
    var clientID = ""
    var clientSecret = ""
    var scope = ""
    var usePKCE = false
    var redirectPort = 0
    var username = ""
    var password = ""
    /// `header` | `body`
    var clientAuth = ""
    /// `header` | `query`
    var tokenPlacement = ""
    var headerPrefix = ""
    var autoRefresh = false
}

nonisolated struct Params: Hashable, Sendable {
    var query: [KV]
    var path: [PathParam]
    init(query: [KV] = [], path: [PathParam] = []) {
        self.query = query
        self.path = path
    }
    var isEmpty: Bool { query.isEmpty && path.isEmpty }
}

nonisolated struct MultipartPart: Hashable, Sendable {
    var name: String
    /// `text` | `file`
    var kind: String
    var value: String
    var path: String
    var contentType: String
    var enabled: Bool

    init(name: String = "", kind: String = "text", value: String = "", path: String = "",
                contentType: String = "", enabled: Bool = true) {
        self.name = name
        self.kind = kind
        self.value = value
        self.path = path
        self.contentType = contentType
        self.enabled = enabled
    }
}

nonisolated struct Body: Hashable, Sendable {
    var type: String
    var raw: String
    var form: [KV]
    var multipart: [MultipartPart]
    var binaryPath: String

    init(type: String = "", raw: String = "", form: [KV] = [], multipart: [MultipartPart] = [], binaryPath: String = "") {
        self.type = type
        self.raw = raw
        self.form = form
        self.multipart = multipart
        self.binaryPath = binaryPath
    }
}

/// Po odpovědi nastaví runtime proměnnou.
nonisolated struct Extract: Hashable, Sendable {
    var name: String
    /// `body` (JSONPath) | `header` (název)
    var from: String
    var path: String
    var enabled: Bool

    init(name: String = "", from: String = "body", path: String = "", enabled: Bool = true) {
        self.name = name
        self.from = from
        self.path = path
        self.enabled = enabled
    }
}

/// Obsah `*.req.yaml`.
nonisolated struct Request: Hashable, Sendable {
    var id: String
    var name: String
    var seq: Int
    var method: String
    var url: String
    var params: Params
    var headers: [KV]
    var auth: Auth
    var body: Body
    var vars: [Var]
    var extract: [Extract]
    var settings: HTTPSettings
    var docs: String

    init(id: String = "", name: String = "", seq: Int = 0, method: String = "", url: String = "",
                params: Params = Params(), headers: [KV] = [], auth: Auth = Auth(), body: Body = Body(),
                vars: [Var] = [], extract: [Extract] = [], settings: HTTPSettings = HTTPSettings(), docs: String = "") {
        self.id = id
        self.name = name
        self.seq = seq
        self.method = method
        self.url = url
        self.params = params
        self.headers = headers
        self.auth = auth
        self.body = body
        self.vars = vars
        self.extract = extract
        self.settings = settings
        self.docs = docs
    }

    /// Nový request s výchozími hodnotami (GET, auth inherit, bez těla).
    static func new(id: String, name: String) -> Request {
        Request(id: id, name: name, method: HTTPMethod.get, auth: Auth(type: AuthType.inherit), body: Body(type: BodyType.none))
    }
}

/// Obsah `_folder.yaml`.
nonisolated struct FolderConfig: Hashable, Sendable {
    var name: String
    var seq: Int
    var vars: [Var]
    var headers: [KV]
    var auth: Auth

    init(name: String = "", seq: Int = 0, vars: [Var] = [], headers: [KV] = [], auth: Auth = Auth()) {
        self.name = name
        self.seq = seq
        self.vars = vars
        self.headers = headers
        self.auth = auth
    }
}

/// Obsah `minorrest.yaml`.
nonisolated struct ProjectConfig: Hashable, Sendable {
    var formatVersion: Int
    var id: String
    var name: String
    var description: String
    var vars: [Var]
    var headers: [KV]
    var auth: Auth
    var settings: HTTPSettings
    var ignoreResponsesInGit: Bool

    init(formatVersion: Int = 0, id: String = "", name: String = "", description: String = "",
                vars: [Var] = [], headers: [KV] = [], auth: Auth = Auth(), settings: HTTPSettings = HTTPSettings(),
                ignoreResponsesInGit: Bool = false) {
        self.formatVersion = formatVersion
        self.id = id
        self.name = name
        self.description = description
        self.vars = vars
        self.headers = headers
        self.auth = auth
        self.settings = settings
        self.ignoreResponsesInGit = ignoreResponsesInGit
    }
}

/// Obsah `environments/<slug>.yaml`.
nonisolated struct EnvironmentConfig: Hashable, Sendable {
    var id: String
    var name: String
    var vars: [Var]

    init(id: String = "", name: String = "", vars: [Var] = []) {
        self.id = id
        self.name = name
        self.vars = vars
    }
}

/// Uzel stromu projektu pro UI.
nonisolated struct TreeNode: Hashable, Sendable {
    enum Kind: String, Sendable { case folder, request }

    var kind: Kind
    var rel: String
    var name: String
    var seq: Int
    var id: String
    var method: String
    var url: String
    /// Kód chyby, pokud soubor nejde načíst.
    var error: String
    var children: [TreeNode]

    init(kind: Kind, rel: String, name: String, seq: Int = 0, id: String = "", method: String = "",
                url: String = "", error: String = "", children: [TreeNode] = []) {
        self.kind = kind
        self.rel = rel
        self.name = name
        self.seq = seq
        self.id = id
        self.method = method
        self.url = url
        self.error = error
        self.children = children
    }
}

nonisolated struct ProjectInfo: Hashable, Sendable {
    var id: String
    var name: String
    var path: String
    var readOnly: Bool

    init(id: String, name: String, path: String, readOnly: Bool = false) {
        self.id = id
        self.name = name
        self.path = path
        self.readOnly = readOnly
    }
}

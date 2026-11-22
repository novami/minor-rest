// Datový model projektu (PLAN kap. 2). Typy výčtových hodnot jsou řetězce, aby se neznámá
// hodnota z novější verze při uložení neztratila.

/// Verze formátu projektu; projekt s vyšší verzí se otevře jen pro čtení.
public enum ProjectFormat {
    public static let version = 1
    public static let projectFile = "minorrest.yaml"
    public static let folderFile = "_folder.yaml"
    public static let requestSuffix = ".req.yaml"
    public static let environmentDir = "environments"
    public static let responsesDir = ".responses"
}

public enum HTTPMethod {
    public static let get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
    public static let head = "HEAD", options = "OPTIONS"
    public static let all = [get, post, put, patch, delete, head, options]
}

public enum BodyType {
    public static let none = "none", json = "json", xml = "xml", text = "text", html = "html"
    public static let form = "form-urlencoded", multipart = "multipart", binary = "binary"
    public static let all = [none, json, xml, text, html, form, multipart, binary]
}

public enum AuthType {
    public static let inherit = "inherit", none = "none", basic = "basic", bearer = "bearer"
    public static let apiKey = "apikey", oauth2 = "oauth2"
}

/// Řádek název–hodnota (query, hlavičky, form).
public struct KV: Hashable, Sendable {
    public var name: String
    public var value: String
    public var enabled: Bool
    public var description: String
    /// Jen query: prázdná hodnota se pošle jako `?name` místo `?name=`.
    public var bare: Bool

    public init(name: String = "", value: String = "", enabled: Bool = true, description: String = "", bare: Bool = false) {
        self.name = name
        self.value = value
        self.enabled = enabled
        self.description = description
        self.bare = bare
    }
}

public struct PathParam: Hashable, Sendable {
    public var name: String
    public var value: String
    public var description: String

    public init(name: String = "", value: String = "", description: String = "") {
        self.name = name
        self.value = value
        self.description = description
    }
}

public struct Var: Hashable, Sendable {
    public var name: String
    public var value: String
    public var secret: Bool
    public var enabled: Bool

    public init(name: String = "", value: String = "", secret: Bool = false, enabled: Bool = true) {
        self.name = name
        self.value = value
        self.secret = secret
        self.enabled = enabled
    }
}

/// HTTP nastavení; `nil` = zděděno.
public struct HTTPSettings: Hashable, Sendable {
    public var httpVersion: String?
    public var followRedirects: Bool?
    public var maxRedirects: Int?
    public var timeoutMs: Int?
    public var verifyTLS: Bool?
    public var cookieJar: Bool?

    public init(httpVersion: String? = nil, followRedirects: Bool? = nil, maxRedirects: Int? = nil,
                timeoutMs: Int? = nil, verifyTLS: Bool? = nil, cookieJar: Bool? = nil) {
        self.httpVersion = httpVersion
        self.followRedirects = followRedirects
        self.maxRedirects = maxRedirects
        self.timeoutMs = timeoutMs
        self.verifyTLS = verifyTLS
        self.cookieJar = cookieJar
    }

    public var isEmpty: Bool { self == HTTPSettings() }

    /// Doplní nevyplněné (zděděné) položky z `base`.
    public func over(_ base: HTTPSettings) -> HTTPSettings {
        HTTPSettings(httpVersion: httpVersion ?? base.httpVersion,
                     followRedirects: followRedirects ?? base.followRedirects,
                     maxRedirects: maxRedirects ?? base.maxRedirects,
                     timeoutMs: timeoutMs ?? base.timeoutMs,
                     verifyTLS: verifyTLS ?? base.verifyTLS,
                     cookieJar: cookieJar ?? base.cookieJar)
    }
}

public struct Auth: Hashable, Sendable {
    public var type: String
    public var basic: BasicAuth?
    public var bearer: BearerAuth?
    public var apiKey: APIKeyAuth?
    public var oauth2: OAuth2Auth?

    public init(type: String = "", basic: BasicAuth? = nil, bearer: BearerAuth? = nil,
                apiKey: APIKeyAuth? = nil, oauth2: OAuth2Auth? = nil) {
        self.type = type
        self.basic = basic
        self.bearer = bearer
        self.apiKey = apiKey
        self.oauth2 = oauth2
    }
}

public struct BasicAuth: Hashable, Sendable {
    public var username = ""
    public var password = ""
    public init(username: String = "", password: String = "") {
        self.username = username
        self.password = password
    }
}

public struct BearerAuth: Hashable, Sendable {
    public var token = ""
    public var prefix = ""
    public init(token: String = "", prefix: String = "") {
        self.token = token
        self.prefix = prefix
    }
}

public struct APIKeyAuth: Hashable, Sendable {
    public var key = ""
    public var value = ""
    /// `header` | `query`
    public var location = ""
    public init(key: String = "", value: String = "", location: String = "") {
        self.key = key
        self.value = value
        self.location = location
    }
}

public struct OAuth2Auth: Hashable, Sendable {
    /// `client_credentials` | `authorization_code` | `password`
    public var grantType = ""
    public var authURL = ""
    public var tokenURL = ""
    public var clientID = ""
    public var clientSecret = ""
    public var scope = ""
    public var usePKCE = false
    public var redirectPort = 0
    public var username = ""
    public var password = ""
    /// `header` | `body`
    public var clientAuth = ""
    /// `header` | `query`
    public var tokenPlacement = ""
    public var headerPrefix = ""
    public var autoRefresh = false
    public init() {}
}

public struct Params: Hashable, Sendable {
    public var query: [KV]
    public var path: [PathParam]
    public init(query: [KV] = [], path: [PathParam] = []) {
        self.query = query
        self.path = path
    }
    public var isEmpty: Bool { query.isEmpty && path.isEmpty }
}

public struct MultipartPart: Hashable, Sendable {
    public var name: String
    /// `text` | `file`
    public var kind: String
    public var value: String
    public var path: String
    public var contentType: String
    public var enabled: Bool

    public init(name: String = "", kind: String = "text", value: String = "", path: String = "",
                contentType: String = "", enabled: Bool = true) {
        self.name = name
        self.kind = kind
        self.value = value
        self.path = path
        self.contentType = contentType
        self.enabled = enabled
    }
}

public struct Body: Hashable, Sendable {
    public var type: String
    public var raw: String
    public var form: [KV]
    public var multipart: [MultipartPart]
    public var binaryPath: String

    public init(type: String = "", raw: String = "", form: [KV] = [], multipart: [MultipartPart] = [], binaryPath: String = "") {
        self.type = type
        self.raw = raw
        self.form = form
        self.multipart = multipart
        self.binaryPath = binaryPath
    }
}

/// Po odpovědi nastaví runtime proměnnou.
public struct Extract: Hashable, Sendable {
    public var name: String
    /// `body` (JSONPath) | `header` (název)
    public var from: String
    public var path: String
    public var enabled: Bool

    public init(name: String = "", from: String = "body", path: String = "", enabled: Bool = true) {
        self.name = name
        self.from = from
        self.path = path
        self.enabled = enabled
    }
}

/// Obsah `*.req.yaml`.
public struct Request: Hashable, Sendable {
    public var id: String
    public var name: String
    public var seq: Int
    public var method: String
    public var url: String
    public var params: Params
    public var headers: [KV]
    public var auth: Auth
    public var body: Body
    public var vars: [Var]
    public var extract: [Extract]
    public var settings: HTTPSettings
    public var docs: String

    public init(id: String = "", name: String = "", seq: Int = 0, method: String = "", url: String = "",
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
    public static func new(id: String, name: String) -> Request {
        Request(id: id, name: name, method: HTTPMethod.get, auth: Auth(type: AuthType.inherit), body: Body(type: BodyType.none))
    }
}

/// Obsah `_folder.yaml`.
public struct FolderConfig: Hashable, Sendable {
    public var name: String
    public var seq: Int
    public var vars: [Var]
    public var headers: [KV]
    public var auth: Auth

    public init(name: String = "", seq: Int = 0, vars: [Var] = [], headers: [KV] = [], auth: Auth = Auth()) {
        self.name = name
        self.seq = seq
        self.vars = vars
        self.headers = headers
        self.auth = auth
    }
}

/// Obsah `minorrest.yaml`.
public struct ProjectConfig: Hashable, Sendable {
    public var formatVersion: Int
    public var id: String
    public var name: String
    public var description: String
    public var vars: [Var]
    public var headers: [KV]
    public var auth: Auth
    public var settings: HTTPSettings
    public var ignoreResponsesInGit: Bool

    public init(formatVersion: Int = 0, id: String = "", name: String = "", description: String = "",
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
public struct Environment: Hashable, Sendable {
    public var id: String
    public var name: String
    public var vars: [Var]

    public init(id: String = "", name: String = "", vars: [Var] = []) {
        self.id = id
        self.name = name
        self.vars = vars
    }
}

/// Uzel stromu projektu pro UI.
public struct TreeNode: Hashable, Sendable {
    public enum Kind: String, Sendable { case folder, request }

    public var kind: Kind
    public var rel: String
    public var name: String
    public var seq: Int
    public var id: String
    public var method: String
    public var url: String
    /// Kód chyby, pokud soubor nejde načíst.
    public var error: String
    public var children: [TreeNode]

    public init(kind: Kind, rel: String, name: String, seq: Int = 0, id: String = "", method: String = "",
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

public struct ProjectInfo: Hashable, Sendable {
    public var id: String
    public var name: String
    public var path: String
    public var readOnly: Bool

    public init(id: String, name: String, path: String, readOnly: Bool = false) {
        self.id = id
        self.name = name
        self.path = path
        self.readOnly = readOnly
    }
}

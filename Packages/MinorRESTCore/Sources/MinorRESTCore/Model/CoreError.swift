/// Kód chyby jádra; texty jsou jen v lokalizaci UI (`errors.<kód>`).
public struct ErrorCode: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }

    public static let yamlInvalid = ErrorCode(rawValue: "YAML_INVALID")
    public static let notFound = ErrorCode(rawValue: "NOT_FOUND")
    public static let pathInvalid = ErrorCode(rawValue: "PATH_INVALID")
    public static let nameEmpty = ErrorCode(rawValue: "NAME_EMPTY")
    public static let projectReadOnly = ErrorCode(rawValue: "PROJECT_READONLY")
    public static let projectInvalid = ErrorCode(rawValue: "PROJECT_INVALID")
    public static let moveIntoSelf = ErrorCode(rawValue: "MOVE_INTO_SELF")
    public static let fsError = ErrorCode(rawValue: "FS_ERROR")
    public static let trashFailed = ErrorCode(rawValue: "TRASH_FAILED")
    public static let varCycle = ErrorCode(rawValue: "VAR_CYCLE")
    public static let varUnresolvedHost = ErrorCode(rawValue: "VAR_UNRESOLVED_HOST")
    public static let urlInvalid = ErrorCode(rawValue: "URL_INVALID")
    public static let jsonInvalid = ErrorCode(rawValue: "JSON_INVALID")
    public static let jsonPathInvalid = ErrorCode(rawValue: "JSONPATH_INVALID")
    // Odeslání (F4)
    public static let canceled = ErrorCode(rawValue: "CANCELED")
    public static let netTimeout = ErrorCode(rawValue: "NET_TIMEOUT")
    public static let netDNS = ErrorCode(rawValue: "NET_DNS")
    public static let netRefused = ErrorCode(rawValue: "NET_REFUSED")
    public static let netError = ErrorCode(rawValue: "NET_ERROR")
    public static let tlsVerify = ErrorCode(rawValue: "TLS_VERIFY")
    public static let tlsError = ErrorCode(rawValue: "TLS_ERROR")
    public static let redirectLimit = ErrorCode(rawValue: "REDIRECT_LIMIT")
    public static let fileNotFound = ErrorCode(rawValue: "FILE_NOT_FOUND")
    public static let methodInvalid = ErrorCode(rawValue: "METHOD_INVALID")
    public static let bodyNotAllowed = ErrorCode(rawValue: "BODY_NOT_ALLOWED")
    public static let runNotFound = ErrorCode(rawValue: "RUN_NOT_FOUND")
    public static let secretError = ErrorCode(rawValue: "SECRET_ERROR")
    // OAuth2 (F7)
    public static let oauthLoginRequired = ErrorCode(rawValue: "OAUTH_LOGIN_REQUIRED")
    public static let oauthTokenError = ErrorCode(rawValue: "OAUTH_TOKEN_ERROR")
}

/// Chyba jádra: kód pro UI a technický detail.
public struct CoreError: Error, Equatable, Sendable, CustomStringConvertible {
    public let code: ErrorCode
    public let detail: String

    public init(_ code: ErrorCode, _ detail: String = "") {
        self.code = code
        self.detail = detail
    }

    public var description: String { detail.isEmpty ? code.rawValue : "\(code.rawValue): \(detail)" }
}

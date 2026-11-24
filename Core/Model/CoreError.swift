/// Kód chyby jádra; texty jsou jen v lokalizaci UI (`errors.<kód>`).
nonisolated struct ErrorCode: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    var description: String { rawValue }

    static let yamlInvalid = ErrorCode(rawValue: "YAML_INVALID")
    static let notFound = ErrorCode(rawValue: "NOT_FOUND")
    static let pathInvalid = ErrorCode(rawValue: "PATH_INVALID")
    static let nameEmpty = ErrorCode(rawValue: "NAME_EMPTY")
    static let projectReadOnly = ErrorCode(rawValue: "PROJECT_READONLY")
    static let projectInvalid = ErrorCode(rawValue: "PROJECT_INVALID")
    static let moveIntoSelf = ErrorCode(rawValue: "MOVE_INTO_SELF")
    static let fsError = ErrorCode(rawValue: "FS_ERROR")
    static let trashFailed = ErrorCode(rawValue: "TRASH_FAILED")
    static let varCycle = ErrorCode(rawValue: "VAR_CYCLE")
    static let varUnresolvedHost = ErrorCode(rawValue: "VAR_UNRESOLVED_HOST")
    static let urlInvalid = ErrorCode(rawValue: "URL_INVALID")
    static let jsonInvalid = ErrorCode(rawValue: "JSON_INVALID")
    static let jsonPathInvalid = ErrorCode(rawValue: "JSONPATH_INVALID")
    static let curlInvalid = ErrorCode(rawValue: "CURL_INVALID")
    static let importInvalid = ErrorCode(rawValue: "IMPORT_INVALID")
    static let importFetch = ErrorCode(rawValue: "IMPORT_FETCH")
    // Odeslání (F4)
    static let canceled = ErrorCode(rawValue: "CANCELED")
    static let netTimeout = ErrorCode(rawValue: "NET_TIMEOUT")
    static let netDNS = ErrorCode(rawValue: "NET_DNS")
    static let netRefused = ErrorCode(rawValue: "NET_REFUSED")
    static let netError = ErrorCode(rawValue: "NET_ERROR")
    static let tlsVerify = ErrorCode(rawValue: "TLS_VERIFY")
    static let tlsError = ErrorCode(rawValue: "TLS_ERROR")
    static let redirectLimit = ErrorCode(rawValue: "REDIRECT_LIMIT")
    static let fileNotFound = ErrorCode(rawValue: "FILE_NOT_FOUND")
    static let methodInvalid = ErrorCode(rawValue: "METHOD_INVALID")
    static let bodyNotAllowed = ErrorCode(rawValue: "BODY_NOT_ALLOWED")
    static let runNotFound = ErrorCode(rawValue: "RUN_NOT_FOUND")
    static let secretError = ErrorCode(rawValue: "SECRET_ERROR")
    // OAuth2 (F7)
    static let oauthLoginRequired = ErrorCode(rawValue: "OAUTH_LOGIN_REQUIRED")
    static let oauthTokenError = ErrorCode(rawValue: "OAUTH_TOKEN_ERROR")
    // Aktualizace (F12)
    static let updateFeed = ErrorCode(rawValue: "UPDATE_FEED")
    static let updateDownload = ErrorCode(rawValue: "UPDATE_DOWNLOAD")
    static let updateBadSignature = ErrorCode(rawValue: "UPDATE_BAD_SIGNATURE")
    static let updateBadBundle = ErrorCode(rawValue: "UPDATE_BAD_BUNDLE")
    static let updateNotConfigured = ErrorCode(rawValue: "UPDATE_NOT_CONFIGURED")
    static let updateInstall = ErrorCode(rawValue: "UPDATE_INSTALL")
}

/// Chyba jádra: kód pro UI a technický detail.
nonisolated struct CoreError: Error, Equatable, Sendable, CustomStringConvertible {
    let code: ErrorCode
    let detail: String

    init(_ code: ErrorCode, _ detail: String = "") {
        self.code = code
        self.detail = detail
    }

    var description: String { detail.isEmpty ? code.rawValue : "\(code.rawValue): \(detail)" }
}

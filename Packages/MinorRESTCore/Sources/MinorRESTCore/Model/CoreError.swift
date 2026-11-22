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

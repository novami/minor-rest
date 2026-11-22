/// Kód chyby jádra; texty jsou jen v lokalizaci UI (`errors.<kód>`).
public struct ErrorCode: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }

    public static let yamlInvalid = ErrorCode(rawValue: "YAML_INVALID")
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

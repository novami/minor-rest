import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Sendable {
    case auto, cs, en
}

/// Překlady z `Localizable.xcstrings` s přepnutím jazyka za běhu (nezávisle na jazyce systému).
@MainActor @Observable
final class L10n {
    static let shared = L10n()

    var language: AppLanguage = .auto {
        didSet { bundle = Self.bundle(for: language) }
    }
    private(set) var bundle: Bundle

    private init() {
        bundle = Self.bundle(for: .auto)
    }

    /// Kód skutečně použitého jazyka (`cs` | `en`).
    var code: String { Self.resolve(language) }

    func text(_ key: String, _ args: [String: String]) -> String {
        var str = bundle.localizedString(forKey: key, value: key, table: nil)
        for (name, value) in args {
            str = str.replacingOccurrences(of: "{\(name)}", with: value)
        }
        return str
    }

    private static func resolve(_ language: AppLanguage) -> String {
        if language != .auto { return language.rawValue }
        for preferred in Locale.preferredLanguages {
            let code = String(preferred.prefix(2))
            if code == "cs" || code == "en" { return code }
        }
        return "en"
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        Bundle.main.path(forResource: resolve(language), ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }
}

/// Přeložený text; `{name}` v textu nahradí `args["name"]`.
@MainActor
func t(_ key: String, _ args: [String: String] = [:]) -> String {
    L10n.shared.text(key, args)
}

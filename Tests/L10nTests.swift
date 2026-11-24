import XCTest

@testable import MinorREST

@MainActor
final class L10nTests: XCTestCase {
    func testLanguageSwitchesAtRuntimeAndKeepsPlaceholders() {
        let l10n = L10n.shared
        let saved = l10n.language
        defer { l10n.language = saved }
        l10n.language = .cs
        XCTAssertEqual(t("menu.save"), "Uložit")
        XCTAssertEqual(t("import.done", ["count": "3"]), "Naimportováno požadavků: 3")
        l10n.language = .en
        XCTAssertEqual(t("menu.save"), "Save")
        XCTAssertEqual(t("import.done", ["count": "3"]), "Requests imported: 3")
    }
}

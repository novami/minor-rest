# MinorREST

REST klient pro macOS 26+ (Apple Silicon), Swift: SwiftUI + AppKit, URLSession, YAML (Yams), tajemství v Keychain, aktualizace `MinorUpdater` z `novami/minor-swift-core`. Go/Wails verze je jen v tagu `go-wails-f4` (reference). Struktura a pravidla: `CONTRIBUTING.md`, příkazy a release: `README.md`.

## Stav
- Hotovo F0–F11 (vč. nastavení). Větve `f10-import-wizard` → `f11-settings` nepushnuté, bez PR.
- Další krok: F12 – release (reálný cyklus updateru proti vydání, `Scripts/release.sh`). Vyžaduje uživatele: veřejný klíč MinorUpdate do konfigurace, schválení pushe a tagu.
- Ručně neověřeno: průvodce importem, okno Nastavení, přepnutí jazyka, cURL z URL baru, ⌘E, OAuth2, Verze/Historie.

## Workflow
- Na začátku sezení (i po „pokračuj“): tento soubor, `git log --oneline | head -5`, `git status --short`.
- Dotazy průvodcem (AskUserQuestion), jednou dávkou, doporučená varianta první. Větší odchylku od zadání nejdřív navrhnout.
- Po kroku: `xcodebuild test -scheme MinorREST -destination 'platform=macOS,arch=arm64'`, `swiftlint lint --strict`, `python3 Scripts/check-i18n.py` (jen signál: `error:`, `TEST SUCCEEDED`). UI ověřit v běžící aplikaci; testovací projekty jen ve scratch adresáři a zavřít.
- Commit jen vlastních souborů, zpráva česky, malými písmeny, bez AI podpisů; pak aktualizovat sekci Stav a po uložení postupu říct, že lze smazat kontext. Žádný `git push` bez pokynu.

## Konvence kódu
- Logika v `Core/` (bez SwiftUI/AppKit, `nonisolated`, testovatelná); `Features/` a `App/` jen views a `@Observable @MainActor` stores.
- Swift 6 strict concurrency; modely `struct … : Codable, Sendable, Equatable`, sdílený stav v `actor` nebo za zámkem.
- Build jen v `Config/*.xcconfig`; `MinorREST.xcodeproj` je commitnutý. Jen závislosti `minor-swift-core` a Yams.
- Do logů nikdy `Authorization`/`Cookie` ani těla; citlivé hodnoty requestů jen v Keychainu (`RequestSecrets`).
- Jednořádková pole s proměnnými = `VarField` (ne `CodeTextView`). JSON formátovat `JSONFormatter` z jádra, ne `JSONSerialization`.
- Chyby jako `CoreError` s kódem, UI texty jen v `Localizable.xcstrings` přes `t()`.
- UTF-8 + NFC; názvy souborů ASCII slug, diakritika jen v poli `name`; YAML formát beze změny oproti Go verzi.
- Složky s velkým počátečním písmenem (výjimka `.github`).
- Testy: hlavní cesta + nejdůležitější edge case, Swift Testing (`@Test(arguments:)`); případy z Go testů v tagu `go-wails-f4`.

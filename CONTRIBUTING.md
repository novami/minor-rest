# Přispívání

macOS 26+ na Apple Silicon, Xcode 26+, SwiftLint.

| Příkaz | Účel |
|---|---|
| `xcodebuild test -scheme MinorREST -destination 'platform=macOS,arch=arm64'` | testy (XCTest) |
| `swiftlint lint --strict` | lint (CI ho spouští také se `--strict`) |

Nastavení buildu je jen v `Config/*.xcconfig` (identita aplikace v `App.xcconfig`, verze ve `Version.xcconfig`).

## Struktura
- `App/` – `@main`, `AppDelegate`, model okna, menu, zdroje (lokalizace, assety).
- `Core/` – logika bez UI (model, YAML, úložiště, HTTP, proměnné, import/export), `nonisolated`.
- `Features/` – UI po funkcích (`Request`, `Response`, `Sidebar`, `Environment`, `Settings`, `Shared`).
- `Tests/` – XCTest, jen hlavní cesta a nejdůležitější okrajové případy.

## Pravidla
- Citlivé hodnoty patří do Keychainu (`Secrets`), do logů nikdy hlavičky ani těla.
- Žádné další externí závislosti bez výslovného souhlasu.
- Verze `MAJOR.MINOR.PATCH`, tag = verze = název GitHub Release.

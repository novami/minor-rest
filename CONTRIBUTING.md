# Přispívání

macOS 26+ na Apple Silicon, Xcode 26+, SwiftLint.

| Příkaz | Účel |
|---|---|
| `xcodebuild test -scheme MinorREST -destination 'platform=macOS,arch=arm64'` | testy  |
| `swiftlint lint --strict` | lint (CI ho spouští také se `--strict`) |
| `python3 Scripts/check-i18n.py` | překlady: úplné cs/en, shodné `{placeholdery}`, použité klíče existují, žádné natvrdo psané UI texty |

Nastavení buildu je jen v `Config/*.xcconfig` (identita aplikace v `App.xcconfig`, verze ve `Version.xcconfig`).

## Struktura
- `App/` – `@main`, `AppDelegate`, model okna, menu, zdroje (lokalizace, assety).
- `Core/` – logika bez UI (model, YAML, úložiště, HTTP, proměnné, import/export), `nonisolated`.
- `Features/` – UI po funkcích (`Request`, `Response`, `Sidebar`, `Environment`, `Settings`, `Shared`).
- `Tests/` – testy, jen hlavní cesta a nejdůležitější okrajové případy; `Fixtures/Go` jsou YAML z Go verze (formát se nemění), `Fixtures/OpenAPI` vzorové specifikace.
- `Scripts/` – pomocné skripty (`check-i18n.py`).

## Pravidla
- Citlivé hodnoty patří do Keychainu (`Secrets`/`RequestSecrets`), do logů nikdy hlavičky ani těla.
- Žádné další externí závislosti bez výslovného souhlasu.
- Verze `MAJOR.MINOR.PATCH`, tag = verze = název GitHub Release.
- Chyby jádra jsou `CoreError` s kódem, UI texty jen v `App/Localizable.xcstrings` přes `t()`.
- Postup vydání je popsán jen v [README](README.md#distribuce-a-aktualizace).

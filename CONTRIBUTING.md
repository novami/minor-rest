# Přispívání

## Požadavky
macOS 15+ na Apple Silicon, Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), volitelně SwiftLint.

## Příkazy
| Příkaz | Účel |
|---|---|
| `make test` | testy jádra (`Packages/MinorRESTCore`, SwiftPM) |
| `make build` | vygeneruje `MinorREST.xcodeproj` a sestaví aplikaci |
| `make run` | sestaví a spustí aplikaci |
| `swiftlint lint` | statická analýza (konfigurace `.swiftlint.yml`) |

`MinorREST.xcodeproj` se negeneruje do gitu – nastavení cíle měňte v `project.yml`.

## Struktura
- `Packages/MinorRESTCore` – logika bez SwiftUI/AppKit (model, YAML, úložiště, HTTP, proměnné, import/export). Testovatelná přes `swift test`.
- `App/Application` – vstupní bod, menu, kořenový stav; `App/Features/<funkce>` – views a stores dané funkce; `App/Shared` – sdílené komponenty, AppKit wrappery, podpora (`t()`, fonty).
- `docs/PLAN.md` – plán a API jádra, `docs/PROGRESS.md` – stav prací.

## Pravidla
- Swift 6 strict concurrency; UI texty jen v `Localizable.xcstrings` (cs + en) přes `t()`.
- Testy: hlavní cesta + nejdůležitější okrajový případ (Swift Testing).
- Commit zprávy česky, malými písmeny, jedna logická změna na commit.

## CI
`.github/workflows/ci.yml` (macOS 26, arm64, Xcode 26.6): `test-core`, `build-app`, `lint` běží paralelně a jen při změně `App/`, `Packages/`, `project.yml`, `Makefile` nebo konfigurace. Akce jsou pinované na commit SHA (aktualizuje Dependabot), oprávnění `contents: read`. Cache obsahuje jen stažené zdrojáky závislostí (klíč: OS + toolchain + `Package.resolved`), nikdy výstupy kompilace.

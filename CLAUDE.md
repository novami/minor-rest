# MinorREST – pokyny pro Claude

REST klient pro macOS 15+ (Apple Silicon) ve Swiftu: SwiftUI + AppKit, logika v SwiftPM balíčku `MinorRESTCore`, HTTP přes URLSession, data v YAML (Yams), tajemství v Keychain. Go/Wails verze je jen v tagu `go-wails-f4` (reference).

## Na začátku každého sezení (zvlášť po „pokračuj“)
1. Přečti `docs/PROGRESS.md` – kde se skončilo a co je další krok.
2. Z `docs/PLAN.md` čti jen: aktuální fázi (`grep -n '^### F'` → rozsah), kapitoly, na které odkazuje, a kap. 11 (API jádra). Před F0 navíc kap. 1.1 (úskalí Swift/SwiftUI).
3. `git log --oneline | head -5` a `git status --short` – ověř, že stav odpovídá PROGRESS.md.

## Komunikace
- Vždy česky.
- Doplňující dotazy formou průvodce (AskUserQuestion): konkrétní varianty, doporučená první. Ptát se jednou dávkou.
- Odchylku od `docs/PLAN.md` nejdřív navrhnout uživateli; schválenou změnu zapsat do PLAN.md.

## Po každém kroku fáze (krok = commit)
1. `make test` (= `swift test` v `Packages/MinorRESTCore`) a `make build` – jen signál (`tail`/`grep` na `error:`, `Test run … passed`). UI ověř v běžící aplikaci (`make run`, snímky obrazovky); testovací projekty jen ve scratch adresáři a po testu zavřít.
2. Commit jen vlastních souborů (`git commit -- <soubory>`), zpráva česky, malými písmeny, bez AI podpisů.
3. Aktualizuj `docs/PROGRESS.md`: hash commitu, co je hotovo, **přesný další krok**, poznámky/rozhodnutí/známé problémy. Commitni i PROGRESS.md.
4. Nikdy `git push` bez výslovného pokynu.

## Konvence kódu
- Logika v `MinorRESTCore` (bez SwiftUI/AppKit, testovatelná); `App/` jen views a `@Observable @MainActor` stores. Názvy API dle PLAN.md kap. 11; změnu signatury tam zapiš.
- Swift 6 strict concurrency; modely `struct … : Codable, Sendable, Equatable`, stav sdílený mezi vlákny v `actor` nebo za zámkem.
- `MinorREST.xcodeproj` se generuje (`make gen`, XcodeGen) – nastavení cíle měnit v `project.yml`, xcodeproj necommitovat.
- Jednořádková pole s proměnnými = `VarField` (ne `CodeTextView`). Formátování JSON vždy `JSONFormatter` z jádra, nikdy `JSONSerialization`.
- Chyby z jádra jako `CoreError` s kódem (`NET_TIMEOUT` …), texty jen v `Localizable.xcstrings` přes `t()` – žádné natvrdo psané UI texty.
- UTF-8 + NFC všude; názvy souborů ASCII slug, diakritika jen v poli `name`. YAML formát beze změny oproti Go verzi.
- Testy: hlavní cesta + nejdůležitější edge case, Swift Testing (`@Test(arguments:)` místo tabulek); případy převzít z Go testů v tagu `go-wails-f4`.

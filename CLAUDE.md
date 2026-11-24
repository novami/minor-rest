# MinorREST – pokyny pro Claude

REST klient pro macOS 26+ (Apple Silicon) ve Swiftu: SwiftUI + AppKit, kostra z `novami/minor-swift-starter` (Xcode projekt, `Config/*.xcconfig`), logika v `Core/`, UI v `Features/`, HTTP přes URLSession, data v YAML (Yams), tajemství v Keychain (`MinorKeychain`), aktualizace `MinorUpdater` z `novami/minor-swift-core`. Go/Wails verze je jen v tagu `go-wails-f4` (reference).

## Na začátku každého sezení (zvlášť po „pokračuj“)
1. Přečti `docs/PROGRESS.md` – kde se skončilo a co je další krok.
2. Z `docs/PLAN.md` čti jen: aktuální fázi (`grep -n '^### F'` → rozsah), kapitoly, na které odkazuje, a kap. 11 (API jádra). Před F0 navíc kap. 1.1 (úskalí Swift/SwiftUI).
3. `git log --oneline | head -5` a `git status --short` – ověř, že stav odpovídá PROGRESS.md.

## Komunikace
- Vždy česky.
- Doplňující dotazy formou průvodce (AskUserQuestion): konkrétní varianty, doporučená první. Ptát se jednou dávkou.
- Odchylku od `docs/PLAN.md` nejdřív navrhnout uživateli; schválenou změnu zapsat do PLAN.md.

## Po každém kroku fáze (krok = commit)
1. `xcodebuild test -scheme MinorREST -destination 'platform=macOS,arch=arm64'` a `swiftlint lint --strict` – jen signál (`grep` na `error:`, `TEST SUCCEEDED`). UI ověř v běžící aplikaci (snímky obrazovky); testovací projekty jen ve scratch adresáři a po testu zavřít.
2. Commit jen vlastních souborů (`git commit -- <soubory>`), zpráva česky, malými písmeny, bez AI podpisů.
3. Aktualizuj `docs/PROGRESS.md`: hash commitu, co je hotovo, **přesný další krok**, poznámky/rozhodnutí/známé problémy. Commitni i PROGRESS.md.
4. Nikdy `git push` bez výslovného pokynu.

## Konvence kódu
- Logika v `Core/` (bez SwiftUI/AppKit, `nonisolated`, testovatelná); `Features/` a `App/` jen views a `@Observable @MainActor` stores. Názvy API dle PLAN.md kap. 11; změnu signatury tam zapiš.
- Swift 6 strict concurrency; modely `struct … : Codable, Sendable, Equatable`, stav sdílený mezi vlákny v `actor` nebo za zámkem.
- Nastavení buildu jen v `Config/*.xcconfig` (cíl v Xcode nechat prázdný); `MinorREST.xcodeproj` je commitnutý. Žádné další externí závislosti kromě `minor-swift-core` a Yams (výslovná výjimka).
- Do logů nikdy hlavičky `Authorization`/`Cookie` ani těla; citlivé hodnoty requestů jen v Keychainu (`RequestSecrets`).
- Jednořádková pole s proměnnými = `VarField` (ne `CodeTextView`). Formátování JSON vždy `JSONFormatter` z jádra, nikdy `JSONSerialization`.
- Chyby z jádra jako `CoreError` s kódem (`NET_TIMEOUT` …), texty jen v `Localizable.xcstrings` přes `t()` – žádné natvrdo psané UI texty.
- UTF-8 + NFC všude; názvy souborů ASCII slug, diakritika jen v poli `name`. YAML formát beze změny oproti Go verzi.
- Testy: hlavní cesta + nejdůležitější edge case, Swift Testing (`@Test(arguments:)` místo tabulek); případy převzít z Go testů v tagu `go-wails-f4`.

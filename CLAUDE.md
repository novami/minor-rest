# MinorREST – pokyny pro Claude

REST klient pro macOS (Apple Silicon) v Go: Wails v2 + Svelte 5 + TypeScript, data v YAML, tajemství v Keychain.

## Na začátku každého sezení (zvlášť po „pokračuj“)
1. Přečti `docs/PROGRESS.md` – kde se skončilo a co je další krok.
2. Z `docs/PLAN.md` čti jen kapitoly relevantní pro aktuální fázi (grep na `### F<n>` a odkazované kapitoly).
3. `git log --oneline | head -5` a `git status --short` – ověř, že stav odpovídá PROGRESS.md.

## Komunikace
- Vždy česky.
- Doplňující dotazy formou průvodce (AskUserQuestion): konkrétní varianty, doporučená první. Ptát se jednou dávkou.
- Odchylku od `docs/PLAN.md` nejdřív navrhnout uživateli; schválenou změnu zapsat do PLAN.md.

## Po dokončení fáze (nebo větší ucelené práce)
1. `go vet ./...`, `go test ./internal/...`, ve `frontend/` `npm run check` – jen signál (tail/grep).
2. Commit jen vlastních souborů (`git commit -- <soubory>`), zpráva česky, malými písmeny, bez AI podpisů.
3. Aktualizuj `docs/PROGRESS.md`: hash commitu, co je hotovo, **přesný další krok**, poznámky/rozhodnutí/známé problémy. Commitni i PROGRESS.md.
4. Nikdy `git push` bez výslovného pokynu.

## Konvence kódu
- Logika v `internal/*` (nezávislé na Wails, testovatelné); `app.go` jen tenké bindingy.
- Chyby z backendu jako kódy (`NET_TIMEOUT` …), texty jen v i18n (`frontend/src/lib/i18n/{cs,en}.json`) – žádné natvrdo psané UI texty.
- UTF-8 + NFC všude; názvy souborů ASCII slug, diakritika jen v poli `name`.
- Testy: hlavní cesta + nejdůležitější edge case, tabulkové testy v Go.
- Svelte 5 runes (`$state`, `$derived`, `$props`), stores v `*.svelte.ts`.

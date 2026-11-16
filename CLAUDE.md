# MinorREST – pokyny pro Claude

REST klient pro macOS (Apple Silicon) v Go: Wails v2 + Svelte 5 + TypeScript, data v YAML, tajemství v Keychain.

## Na začátku každého sezení (zvlášť po „pokračuj“)
1. Přečti `docs/PROGRESS.md` – kde se skončilo a co je další krok.
2. Z `docs/PLAN.md` čti jen: aktuální fázi (`grep -n '^### F'` → rozsah), kapitoly, na které odkazuje, a kap. 11 (kontrakt bindingů). Před F0 navíc kap. 1.1 (úskalí Wails).
3. `git log --oneline | head -5` a `git status --short` – ověř, že stav odpovídá PROGRESS.md.

## Komunikace
- Vždy česky.
- Doplňující dotazy formou průvodce (AskUserQuestion): konkrétní varianty, doporučená první. Ptát se jednou dávkou.
- Odchylku od `docs/PLAN.md` nejdřív navrhnout uživateli; schválenou změnu zapsat do PLAN.md.

## Po každém kroku fáze (krok = commit)
1. `go vet ./internal/... && go test ./internal/...` (ne `./...` – hlavní balíček potřebuje `frontend/dist`), ve `frontend/` `npm run check` – jen signál (tail/grep). UI ověř v `wails dev` přes prohlížeč na `http://localhost:34115` (spouštět na pozadí).
2. Commit jen vlastních souborů (`git commit -- <soubory>`), zpráva česky, malými písmeny, bez AI podpisů.
3. Aktualizuj `docs/PROGRESS.md`: hash commitu, co je hotovo, **přesný další krok**, poznámky/rozhodnutí/známé problémy. Commitni i PROGRESS.md.
4. Nikdy `git push` bez výslovného pokynu.

## Konvence kódu
- Logika v `internal/*` (nezávislé na Wails, testovatelné); `app*.go` jen tenké bindingy. Názvy bindingů a DTO dle PLAN.md kap. 11; změnu signatury tam zapiš.
- DTO: `json` i `yaml` tagy, žádné `time.Time` ani `interface{}`.
- Jednořádková pole s proměnnými = komponenta `VarInput` (ne CodeMirror). Formátování JSON vždy v backendu (`json.Indent`), nikdy `JSON.parse/stringify`.
- Chyby z backendu jako kódy (`NET_TIMEOUT` …), texty jen v i18n (`frontend/src/lib/i18n/{cs,en}.json`) – žádné natvrdo psané UI texty.
- UTF-8 + NFC všude; názvy souborů ASCII slug, diakritika jen v poli `name`.
- Testy: hlavní cesta + nejdůležitější edge case, tabulkové testy v Go.
- Svelte 5 runes (`$state`, `$derived`, `$props`), stores v `*.svelte.ts`.

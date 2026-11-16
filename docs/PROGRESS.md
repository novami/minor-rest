# Stav projektu

## Aktuálně
- **Fáze:** F1, krok 1 hotový.
- **Další krok:** F1, krok 2 – `internal/storage` (CreateProject, OpenProject, LoadTree, CreateFolder/Request, Load/SaveRequest, Rename, Move, Duplicate, Delete do Koše, atomický zápis, přečíslování `seq`); viz `docs/PLAN.md` → `### F1`, kap. 2.2–2.4. Přidat `github.com/oklog/ulid/v2` pro ID.
- **Prostředí:** Go 1.27.4 darwin/arm64, Node 26, Wails CLI v2.17.1 (`~/go/bin/wails`), gh CLI. Příkazy přes `make dev|build|test|check`.

## Co existuje (F0)
- `main.go` (okno 1280×800, HiddenInset titlebar, About), `menu.go` (nativní menu cs/en dle systému, položky emitují `menu:<akce>`), `app.go` (`SetDirty`, `GetVersion`, potvrzení zavření při neuložených změnách).
- Frontend Svelte 5 + Vite 8 + TS: `src/styles/{tokens,fonts,base}.css`, i18n (`src/lib/i18n`), komponenty `Button`, `Modal`, `Toasts`, `Splitter`, util `events.ts`, layout titlebar + sidebar + request/response se splittery. Neimplementované akce menu ukazují toast.
- `Makefile`, `.github/workflows/ci.yml`, bundle ID `com.github.novami.minorrest`, min. macOS 13.
- Ověřeno: `wails build` → `build/bin/MinorREST.app` se spustí; v `wails dev` (localhost:34115) na ne-retina Menlo 13px, čeština, tmavé téma, binding `GetVersion` funguje.

## Co existuje (F1)
- `internal/model`: typy `Request`, `FolderConfig`, `ProjectConfig`, `Environment`, `KV`, `PathParam`, `Var`, `Auth` (+bloky), `Body`, `MultipartPart`, `Extract`, `HTTPSettings` (ukazatele = dědičnost), konstanty metod/typů těla/auth/názvů souborů, `NewRequest`.
- `MarshalYAML` (odsazení 2, víceřádkové řetězce jako `|`), `UnmarshalYAML` (+ NFC normalizace, chyba `YAML_INVALID`), `NormalizeNFC` (reflexe).
- `Slugify`, `UniqueSlug(slug, taken func(lower string) bool)` – volající předává lowercase sadu existujících jmen.

## Log
| Datum | Fáze | Commit | Poznámka |
|---|---|---|---|
| 2026-11-16 | plán | 55207d9 | analýza, plán, pokyny |
| 2026-11-16 | plán rev. 2 | 7679efe | kontrakt bindingů, kroky fází |
| 2026-11-16 | plán | ee7e752, 8c3ec77 | veřejné repo, Menlo, jen cURL |
| 2026-11-16 | F0 | e30f399 | bootstrap Wails + Svelte 5, menu, layout, CI |
| 2026-11-16 | F1/1 | a5e44f8 | model, slugify, YAML roundtrip |

## Rozhodnutí uživatele
- Wails v2 + Svelte 5, YAML soubory, UI cs+en, zatím bez Apple Developer ID (ad-hoc podpis), MIT, auto-update výchozí zapnuto.
- Repozitář i releasy jsou veřejné (updater bez tokenu).
- Ne-retina displej: Menlo 13 (UI i kód). Retina: SF Pro (UI) + SF Mono (kód).
- Kopírování requestu: jen cURL (víceřádkový + jednořádkový), bez bash skriptu.

## Otevřené body / známé problémy
- YAML: chybějící `enabled` u KV/Var/multipart/extract = zapnuto (vlastní `UnmarshalYAML`). Řádky se zapisují blokovým stylem, ne flow `{…}` jako v ukázkách plánu.
- Nil slice → v JSON `null`; frontend s tím musí počítat (případně normalizovat v bindingu F3).
- Retina větev fontů ověřena jen syntakticky (media query platná), vizuálně ne – ověřit na retina displeji.
- Rozměry panelů se zatím neukládají (přijde s workspace v F2).
- F12 vyžaduje od uživatele ed25519 klíč v GitHub Secrets (`UPDATE_SIGNING_KEY`).

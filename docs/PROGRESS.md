# Stav projektu

## Aktuálně
- **Fáze:** F1 hotová.
- **Další krok:** F2, krok 1 – viz `docs/PLAN.md` → `### F2` (sidebar a projekty: bindingy z kap. 11.1 nad `internal/storage`, workspace). Na začátku F2 přečíst kap. 8 (UI) a 11.
- **Prostředí:** Go 1.27.4 darwin/arm64, Node 26, Wails CLI v2.17.1 (`~/go/bin/wails`), gh CLI. Příkazy přes `make dev|build|test|check`.

## Co existuje (F0)
- `main.go` (okno 1280×800, HiddenInset titlebar, About), `menu.go` (nativní menu cs/en dle systému, položky emitují `menu:<akce>`), `app.go` (`SetDirty`, `GetVersion`, potvrzení zavření při neuložených změnách).
- Frontend Svelte 5 + Vite 8 + TS: `src/styles/{tokens,fonts,base}.css`, i18n (`src/lib/i18n`), komponenty `Button`, `Modal`, `Toasts`, `Splitter`, util `events.ts`, layout titlebar + sidebar + request/response se splittery. Neimplementované akce menu ukazují toast.
- Ikona: `build/appicon.svg` (zdroj) → `build/appicon.png` 1024 px (Wails z ní generuje `iconfile.icns`). Render SVG→PNG přes Swift `NSImage` (macOS umí SVG nativně).
- `Makefile`, `.github/workflows/ci.yml`, bundle ID `com.github.novami.minorrest`, min. macOS 13.
- Ověřeno: `wails build` → `build/bin/MinorREST.app` se spustí; v `wails dev` (localhost:34115) na ne-retina Menlo 13px, čeština, tmavé téma, binding `GetVersion` funguje.

## Co existuje (F1)
- `internal/model`: typy `Request`, `FolderConfig`, `ProjectConfig`, `Environment`, `KV`, `PathParam`, `Var`, `Auth` (+bloky), `Body`, `MultipartPart`, `Extract`, `HTTPSettings` (ukazatele = dědičnost), konstanty metod/typů těla/auth/názvů souborů, `NewRequest`.
- `MarshalYAML` (odsazení 2, víceřádkové řetězce jako `|`), `UnmarshalYAML` (+ NFC normalizace, chyba `YAML_INVALID`), `NormalizeNFC` (reflexe).
- `Slugify`, `UniqueSlug(slug, taken func(lower string) bool)` – volající předává lowercase sadu existujících jmen.
- `model.TreeNode` (+ pole `Error` = kód chyby nečitelného souboru), `model.ProjectInfo`, `model.NewID()` (ULID).
- `internal/storage`: `CreateProject(parentDir, name)`, `OpenProject(root)` → `*Project` (`Info`, `Config`, `SaveConfig` + správa `.gitignore`), `LoadTree`, `CreateFolder/CreateRequest(parentRel, name)`, `LoadRequest/SaveRequest`, `LoadFolderConfig/SaveFolderConfig`, `Rename`, `Move(rel, target, index)` (index mezi sourozenci stejného druhu), `Duplicate`, `Delete` (Koš přes cgo `trash_darwin.go`, i `.responses/<id>`). Atomický zápis, přečíslování `seq` 1..n, ochrana proti `..`, read-only při vyšší formatVersion. Chyby: `NOT_FOUND`, `PATH_INVALID`, `NAME_EMPTY`, `PROJECT_READONLY`, `PROJECT_INVALID`, `MOVE_INTO_SELF`, `FS_ERROR`, `TRASH_FAILED`.

- `internal/vars`: `New(scopes...)`, `Resolve` (→ text, nevyhodnocené, `VAR_CYCLE`), `Unresolved()`, `Explain()` (tajné maskované), dynamické `$uuid $ulid $timestamp $timestampMs $isoTimestamp $randomInt $randomString` (časové jednou na resolver = na odeslání), escape `\{{`. `BuildURL` (proměnné → `:param` přes PathEscape → `http://` → query), `EncodeQuery` (prázdná hodnota → jen název), `EncodeQueryComponent` (zachová `%XX`, enkóduje `& = + #`), `URL_INVALID`.

## Log
| Datum | Fáze | Commit | Poznámka |
|---|---|---|---|
| 2026-11-16 | plán | 55207d9 | analýza, plán, pokyny |
| 2026-11-16 | plán rev. 2 | 7679efe | kontrakt bindingů, kroky fází |
| 2026-11-16 | plán | ee7e752, 8c3ec77 | veřejné repo, Menlo, jen cURL |
| 2026-11-16 | F0 | e30f399 | bootstrap Wails + Svelte 5, menu, layout, CI |
| 2026-11-16 | F1/1 | a5e44f8 | model, slugify, YAML roundtrip |
| 2026-11-17 | F1/2 | 2420b89 | storage: strom, CRUD, přesun, duplikace, koš |
| 2026-11-17 | ikona | 897e237 | smaragdová ikona { ▶ } s odleskem |
| 2026-11-17 | F1/3 | caf8f68 | proměnné, sestavení URL |
| 2026-11-17 | F1/2 | 5d6e771 | přípona duplikátu parametrem, ochrana odpovědí sdíleného ID |

## Rozhodnutí uživatele
- Wails v2 + Svelte 5, YAML soubory, UI cs+en, zatím bez Apple Developer ID (ad-hoc podpis), MIT, auto-update výchozí zapnuto.
- Repozitář i releasy jsou veřejné (updater bez tokenu).
- Ne-retina displej: Menlo 13 (UI i kód). Retina: SF Pro (UI) + SF Mono (kód).
- Kopírování requestu: jen cURL (víceřádkový + jednořádkový), bez bash skriptu.

## Otevřené body / známé problémy
- YAML: chybějící `enabled` u KV/Var/multipart/extract = zapnuto (vlastní `UnmarshalYAML`). Řádky se zapisují blokovým stylem, ne flow `{…}` jako v ukázkách plánu.
- Storage: složky a requesty sdílí jmenný prostor slugů (kolize case-insensitive); v kořeni je `environments` rezervované. Nečitelné soubory jsou ve stromu na konci s `Error`. `Duplicate(rel, copySuffix)` – binding `DuplicateNode` předá příponu v jazyce UI (prázdná = „ kopie“). Mazání nepřesune do Koše `.responses/<id>`, pokud stejné ID má jiný request.
- Návrh pro F2 (watcher): při načtení stromu detekovat duplicitní ID (soubor zkopírovaný ve Finderu) a novějšímu souboru přidělit nové ID.
- Testy storage nahrazují `trashItem` přesunem do TempDir; skutečný Koš ověřen jednorázově ručně.
- Vars: nevyhodnocená proměnná v hostu → `URL_INVALID` (odeslat nejde); v cestě se pošle enkódovaně (`%7B%7Bid%7D%7D`) a je v `Unresolved`. Hodnota proměnné se vyhodnocuje při každém výskytu (proměnná s `{{$uuid}}` dá pokaždé jiné UUID).
- Nil slice → v JSON `null`; frontend s tím musí počítat (případně normalizovat v bindingu F3).
- Retina větev fontů ověřena jen syntakticky (media query platná), vizuálně ne – ověřit na retina displeji.
- Rozměry panelů se zatím neukládají (přijde s workspace v F2).
- F12 vyžaduje od uživatele ed25519 klíč v GitHub Secrets (`UPDATE_SIGNING_KEY`).

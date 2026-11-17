# Stav projektu

## Aktuálně
- **Fáze:** F2, krok 2 hotový.
- **Další krok:** F2, krok 3 – drag & drop ve stromu (HTML5 DnD, kdyby ve WKWebView zlobil → pointer events): přesun mezi složkami + pořadí, indikátor místa vložení, složku nelze do sebe; volá `moveNode(rel, targetParent, index)` z `stores/tree.svelte.ts` (index = pozice mezi sourozenci stejného druhu). Pak hledání (filtr podle názvu, URL a metody bez diakritiky; URL vyžaduje doplnit do `TreeNode` nebo samostatný binding). Kap. 8.2.
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

## Co existuje (F2)
- `internal/settings`: `Workspace` (+ `LoadWorkspace/SaveWorkspace(dir)`, výchozí rozměry), `AppDir()`, `DefaultProjectsDir()`.
- `internal/storage`: `Registry` (Open/Add s deduplikací podle ID, Get, Close, List, Paths), exportované `WriteFileAtomic`, `Project.Abs`.
- `app_projects.go`: všechny bindingy F2 z kap. 11.1; při startu `loadWorkspace` znovu otevře projekty (nečitelné vynechá + log). Seznam projektů ve workspace spravuje backend.
- `storage.InitProject(root, name)` + `IsProjectDir`; „Otevřít adresář…“ na adresáři bez projektu nabídne nativním dialogem založení (název = název adresáře). Bindingy `PickDirectory`, `DefaultProjectsDir`; modál nového projektu má volbu umístění.
- Strom (`Tree.svelte` plochý seznam viditelných řádků + `stores/tree.svelte.ts`): rozbalení ve `ws.expanded`, výběr, klávesy (šipky, Enter = rozbalit, F2 přejmenovat, Cmd+Backspace/Delete smazat), kontextové menu (`ContextMenu.svelte`) na uzlu i prázdné ploše, inline přejmenování, nový request/složka rovnou v editaci názvu, duplikace s příponou dle jazyka, mazání s potvrzením, Zobrazit ve Finderu. Menu `new-request`/`new-folder`/`duplicate` napojeno (cíl = vybraná složka / složka vybraného requestu / kořen).
- Frontend: `stores/workspace.svelte.ts` (`ws`, init, debounced `saveWorkspace`, create/open/close/select), `ProjectSwitcher` v titlebaru (+ modál nového projektu), `Tree` (zatím jen zobrazení), `util/errors.ts` (`errorText` → `errors.<CODE>`), i18n sekce `errors`. Rozměry/viditelnost panelů se ukládají.

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
| 2026-11-17 | F1/3 | ec5b2ca | opravy: VAR_UNRESOLVED_HOST, cache proměnných, KV.bare |
| 2026-11-17 | F1/2 | 5d6e771 | přípona duplikátu parametrem, ochrana odpovědí sdíleného ID |
| 2026-11-17 | F2/1 | 3a5a628 | workspace, registr projektů, bindingy, přepínač projektů |
| 2026-11-17 | F2/1 | 7440a15 | modál uprostřed, volba umístění, založení projektu v adresáři |
| 2026-11-17 | F2/2 | 056c3d6 | interaktivní strom |

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
- Vars: nevyhodnocená proměnná v hostu → `VAR_UNRESOLVED_HOST: <názvy>`; v cestě se pošle enkódovaně (`%7B%7Bid%7D%7D`) a je v `Unresolved`. Pojmenovaná proměnná = jedna hodnota na resolver (cache), přímé `{{$uuid}}` pokaždé nové. Query: prázdná hodnota → `name=`, `KV.Bare` → `name` (URL bar v F3 nastaví `bare` při `?name` bez `=`).
- i18n `errors.*` pokrývá kódy z `internal/*`; nové kódy (HTTP, auth…) přidávat průběžně.
- `wails dev` v prohlížeči: chyba z `wails/ipc.js` („reading 'nodes'“) je v overlayi Wails „odpojeno“ (Svelte v ipc.js), jen dev, aplikaci neovlivňuje.
- Strom: Enter na requestu zatím nic neotevře (taby v F3). Kontextové menu bez „Kopírovat jako cURL“ (F9) a „Nastavení složky“ (F3). Zobrazit ve Finderu neověřeno v UI (jen `open -R`).
- Screenshoty v panelu prohlížeče občas ukazují zastaralý stav – ověřovat přes DOM (`javascript_tool`).
- Testy v `wails dev` zapisují do skutečného `~/Library/Application Support/MinorREST/workspace.yaml` – testovací projekty zakládat přes binding do scratch adresáře a po testu zavřít.
- Nil slice → v JSON `null`; frontend s tím musí počítat (případně normalizovat v bindingu F3).
- Retina větev fontů ověřena jen syntakticky (media query platná), vizuálně ne – ověřit na retina displeji.
- F12 vyžaduje od uživatele ed25519 klíč v GitHub Secrets (`UPDATE_SIGNING_KEY`).

# Stav projektu

## Aktuálně
- **Změna zadání (2026-11-22):** aplikace se přepisuje do Swiftu (SwiftUI + AppKit, URLSession, macOS 15+). Plán revize 3 v `docs/PLAN.md`, Go/Wails stav v tagu `go-wails-f4` (lokální, nepushnutý).
- **Fáze:** F2, krok 2 hotový (59688ae).
- **Další krok:** F2, krok 3 – drag & drop a hledání ve stromu (PLAN 8.2, chování jako Go F2/3 níže): `TreeOutline` pasteboard (`pasteboardWriterForItem` s `rel`, `validateDrop` – složka: horní/dolní čtvrtina před/za, střed dovnitř; request nad složkou dovnitř, nad requestem před/za; složka nad requestem do jeho složky; prázdná plocha = kořen; složku ne do sebe; podržení nad sbalenou složkou ji rozbalí – `NSOutlineView` to umí sám přes `autoexpand`), `TreeStore.move(rel, to:, index:)` (index mezi sourozenci stejného druhu bez přetahovaného uzlu, stejné místo nevolat, přepis rozbalených cest jako u přejmenování). Hledání: `SearchField` nad stromem (`tree.search`), filtr `folding(.diacriticInsensitive, .caseInsensitive)` podle názvu/URL/metody, shody s nadřazenými složkami rozbalené (rozbalení workspace během filtru neměnit), u shody složky celý podstrom, prázdný výsledek `tree.noMatches`, Esc vymaže, ↓/Enter fokus do stromu, během filtru DnD vypnutý.
- **Prostředí:** Xcode 27.2, Swift 6.4.2, XcodeGen 2.48.0 (Homebrew), Yams 6.2.2. Příkazy `make gen|build|run|test|clean`.

### Co existuje (Swift)
- `project.yml` (XcodeGen): cíl `MinorREST`, macOS 15, arm64, Swift 6 + strict concurrency complete, ad-hoc podpis (`CODE_SIGN_IDENTITY: "-"`), bez hardened runtime a sandboxu, Info.plist generovaný do `App/Info.plist` (v `.gitignore`) s ATS `NSAllowsArbitraryLoads` a `NSLocalNetworkUsageDescription` (zatím jen anglicky).
- `App/MinorRESTApp.swift` – jediné okno `Window` 1280×800 (min 900×600), zatím prázdné. `App/Resources/Assets.xcassets/AppIcon` (velikosti 16–1024 vygenerované `sips` z `App/Resources/appicon.png`; zdroj `appicon.svg`).
- `Packages/MinorRESTCore` (Yams, `Package.resolved` commitnutý), zatím jen `ProjectFormat.version` + test (Swift Testing).
- `make build` → `.build/xcode/Build/Products/Debug/MinorREST.app`; ověřeno spuštění, ikona, podpis adhoc.
- F0/2: `MinorRESTApp` (`Window` 1280×800, min 900×600, unified toolbar, `Settings` scéna s placeholderem), `AppCommands` – menu dle PLAN 8.7 (Soubor: nový request/složka, uložit, uložit odpověď, zavřít záložku – nahrazuje `.newItem` a `.saveItem`; menu Request: odeslat ⌘↩, zrušit ⌘., cURL ⇧⌘C, duplikovat ⌘D, URL ⌘L, prostředí ⌘E; Zobrazení: sidebar ⌘B, hledat ⌘K). Akce zatím `AppModel.notImplemented` → toast. Konflikt ⌘E s „Use Selection for Find“ nenastal (SwiftUI Find menu nepřidává).
- `L10n` (`t(key, args)`, `{name}` placeholdery, jazyk `auto|cs|en` přepínatelný za běhu přes `Bundle` z `.lproj`), `Localizable.xcstrings` (147 klíčů převzatých z Go verze + `menu.*`, `quit.*`, `project.init*`, `settings.*`; `extractionState: manual`), `InfoPlist.xcstrings` (`NSLocalNetworkUsageDescription`). Systémové položky menu (O aplikaci, Ukončit…) lokalizuje macOS dle `.lproj`.
- `AppFonts` (`ui`, `small`, `code`, `codeNSFont`; ne-retina Menlo 13, retina systémový + SF Mono) v `@Environment(\.appFonts)`, `BackingScaleReader` (`viewDidChangeBackingProperties`). `MainView`: `NavigationSplitView` (sidebar 180–600) + `VSplitView` request/odpověď s prázdnými stavy, `ToastStack` dole. `AppModel` (toasty, viditelnost sidebaru).
- `DebugTools` (jen DEBUG): `--snapshot <png>`, `--dump-menu <txt>`, `--quit-after-debug`; spouštět binárku přímo `.build/xcode/Build/Products/Debug/MinorREST.app/Contents/MacOS/MinorREST …`, jazyk `-AppleLanguages '(en)'`.
- Ověřeno snímky (cs, en) na ne-retina displeji v tmavém režimu a výpisem menu. Neověřeno: retina větev fontů, světlý režim, zobrazení toastu (menu nelze z CLI vyvolat), přepnutí jazyka za běhu (UI pro to přijde v F11).

## Otevřené body (Swift)
- CI (`ci.yml`: `macos-latest`, `setup-xcode` latest-stable, `brew install xcodegen`, `make test`, `make build`) ověřeno jen lokálně od čistého stavu; na GitHubu poběží až po pushi (ten schvaluje uživatel).
- Ověřování UI: `osascript` přes System Events nemá oprávnění (-1743), `screencapture` nemá oprávnění k nahrávání obrazovky a nástroje computer-use v relaci nejsou → snímky přes `--snapshot` (DebugTools). NavigationSplitView navíc nechává funkční systémovou zkratku ⌥⌘S pro sidebar.
- YAML: yaml.v3 (Go verze) ztrácí úvodní nový řádek u víceřádkového řetězce (`\nx` → `|2-` bez prázdného řádku); Swift zapisuje správně, jen tento případ se od Go liší.
- Ověřit v F4/1: vypnutý `User-Agent` přes URLSession, GET s tělem, chování vlastního `Accept-Encoding`; v F7/1 hlavička `Authorization`; v F12/1 Sparkle s ad-hoc podpisem.

## Go verze – reference (tag `go-wails-f4`)
Níže je stav Go verze; popisuje chování, které se má ve Swiftu zachovat (kód: `git show go-wails-f4:<cesta>`).

- F1/1: `Model/` – `Model.swift` (všechny typy kap. 2 jako `Hashable, Sendable` struktury, výčtové hodnoty jako `String` + konstanty `HTTPMethod`, `BodyType`, `AuthType`, `ProjectFormat`; `HTTPSettings.over`, `Request.new`; `TreeNode`, `ProjectInfo`), `CoreError`/`ErrorCode` (rozšiřitelný `RawRepresentable`), `Slug.make/unique`, `String.nfc`, `ULID.make`. `YAML/` – `YAML.encode/decode`, protokoly `YAMLEncodable/YAMLDecodable`, `YMap` (vynechávání prázdných = Go `omitempty`), `YAMLObject` (čtení přes `Yams.compose`, výchozí hodnoty, `enabled` chybí = true, NFC, chyby `YAML_INVALID: <cesta>: …`), `YAMLWriter` (vlastní emitor kopírující yaml.v3: dvojité uvozovky pro bool/int/float/null/timestamp-like a staré booly, `'…'` při indikátorech, `|`/`|-`/`|+`/`|2-` literály, escapy, bez zalamování).
- Testy: `Fixtures/go/*.yaml` + `scalars.json` (~100 hraničních řetězců) vygenerované Go verzí (dočasný program nad `git archive go-wails-f4 internal/model go.mod go.sum`, `model.MarshalYAML`) – Swift zápis je bajtově shodný; roundtrip, výchozí hodnoty, NFC, chyby, slug, ULID.

- F1/2: `Storage/` – `FileIO` (atomický zápis `.tmp-<uuid>` + `rename(2)`, `readYAML/writeYAML`, převod chyb na `NOT_FOUND`/`FS_ERROR`, `takenNames`, `realPath` přes `realpath(3)` na nejbližším existujícím předkovi, `creationDate`), `RelPath` (validace bez `\`, `/` na začátku, prázdných segmentů, `.`, `..`), `Project` (final class, `NSLock`; `create/initProject/open/isProjectDir`, `config/saveConfig/reloadConfig` + `.gitignore`, strom, CRUD, `rename`, `move`, `duplicate`, `delete` s `.responses/<id>`, `fileRef`; Koš injektovatelný `trash:` – výchozí `FileManager.trashItem`), `ProjectRegistry` (actor), `Workspace` (YAML, mapy se seřazenými klíči). Zápis YAML normalizuje řetězce do NFC (`YMap.add`). Chybové kódy úložiště v `ErrorCode`.
- Testy (port Go `storage_test.go` + kopie složky s novými ID, symlink `/var` v `fileRef`, workspace roundtrip): 20 testů celkem zelených. Skutečný Koš v testech nahrazen přesunem do dočasného adresáře (neověřeno).

- F1/3: `Vars/Resolver` (`VarSource`, `VarScope`, `VarInfo`; vyhodnocení jako Go – `\{{` literál, neznámé ponechá, cache pojmenovaných, časové dynamické jednou na resolver, `VAR_CYCLE` s cestou `a → b → a`, hloubka 10), `Vars/URLBuilder` (`build`, `encodeQuery`, `encodeQueryComponent`, `validate` napodobující Go `url.Parse`, `VAR_UNRESOLVED_HOST`, `URL_INVALID`), `JSON/JSONFormatter` (`format`/`validate`, iterativní tokenizér nad UTF-8 bajty bez rekurze, výstup jako Go `json.Indent`, proměnné jako hodnota i klíč, `\{{…}}` v řetězci, chyby `JSON_INVALID: <řádek>: …`). Testy: port Go `vars_test.go` a `jsonfmt_test.go` + chybové případy, IPv6, ~4 MB JSON. Celkem 29 testů.

- F2/1: `WorkspaceStore` (načtení při startu, `update {}` s uložením po 0,5 s a při ukončení aplikace, logování přes `os.Logger`), `ProjectsStore` (`ProjectRegistry`, `restore()` – nečitelné projekty vynechá a z workspace zmizí, `activate`, `create(name:in:)`, `openDirectory()` – `NSOpenPanel` + `NSAlert` „Založit projekt“ pro adresář bez projektu, `close` – smaže i taby/rozbalení projektu; seznam cest a aktivní projekt zrcadlí do workspace), `errorText(_:)` (lokalizovaná chyba jádra + detail), `ProjectSwitcher` (Menu v toolbaru, titulek okna odstraněn, read-only projekt s příznakem) + `NewProjectSheet` (název, umístění se „Změnit…“). `ResponseSplit` – vlastní svislý split s výškou odpovědi ve workspace. Viditelnost sidebaru ve workspace (`AppModel.columnVisibility`).
- Šířku sidebaru a rámec okna ukládá AppKit sám (`NSSplitView Subview Frames …`, `NSWindow Frame main` v předvolbách `com.github.novami.minorrest`) – `workspace.sidebarWidth` se nepoužívá, jen zachovává. `VSplitView` uloženou výšku neuplatnil, proto vlastní split.
- `DebugTools`: nový přepínač `--workspace-dir <adresář>` (izolovaný workspace pro testy UI; enum `DebugTools` je teď i v Release, ladicí funkce jen v DEBUG).
- Model `Environment` přejmenován na `EnvironmentConfig` (kolize se SwiftUI `@Environment`).
- Ověřeno snímkem v izolovaném workspace: obnova dvou projektů, neexistující cesta vynechána, aktivní projekt zachován, projekt s `formatVersion: 2` jako „jen pro čtení“, výška odpovědi 200 z workspace. **Neověřeno** (chybí nástroje pro klikání): otevření menu přepínače, sheet nového projektu, `NSOpenPanel`/`NSAlert` při otevření adresáře, zavření projektu.
- `standardizedFileURL` mění `/private/tmp/…` na `/tmp/…` (cesty ve workspace pak mají kratší tvar; funkčně stejné).

- F2/2: `App/AppKit/TreeOutlineView` (`NSViewRepresentable` nad `TreeOutline: NSOutlineView`, source list, buňka `TreeCellView`: ikona složky / badge metody s barvou z assetů `Method<Get…>`, nečitelný uzel šedě + tooltip `errorText(code:)`; `ActionMenuItem` = položka `NSMenu` s closure). `TreeStore` (`load/reload` při změně aktivního projektu, `version` jako signál pro reload view, `selection`, `pendingEdit`, rozbalení ve `workspace.expanded` – při přejmenování/smazání složky se cesty přepíší/odstraní; `createRequest/createFolder(near:)` – cíl složka / složka requestu / kořen, `rename`, `duplicate` s `tree.copySuffix`, `delete` s `NSAlert`, `reveal`). Klávesy: Return/Enter rozbalí/sbalí složku, F2 přejmenuje, ⌘⌫ a Delete smaže. Menu Nový request/složka a Duplikovat napojeno.
- Ověřeno snímkem a dočasným ladicím háčkem (necommitnut): rozbalení z workspace, přejmenování složky s přepisem `expanded`, duplikace za originál, nový request ve složce vybraného requestu se otevře v editaci názvu (vybraný celý název), potvrzení editace → přejmenování souboru. **Neověřeno** (chybí klikání): kontextové menu, Esc při editaci, klávesy, `NSAlert` mazání, Zobrazit ve Finderu. Výběr řádku na snímku `cacheDisplay` vypadá černě (vibrancy se nevykreslí).
- Pozor pro F2/4: reload stromu (watcher) během inline editace zahodí field editor a `controlTextDidEndEditing` by přejmenoval na rozepsaný text – při editaci reload odložit.

### Co existuje (F0)
- `main.go` (okno 1280×800, HiddenInset titlebar, About), `menu.go` (nativní menu cs/en dle systému, položky emitují `menu:<akce>`), `app.go` (`SetDirty`, `GetVersion`, potvrzení zavření při neuložených změnách).
- Frontend Svelte 5 + Vite 8 + TS: `src/styles/{tokens,fonts,base}.css`, i18n (`src/lib/i18n`), komponenty `Button`, `Modal`, `Toasts`, `Splitter`, util `events.ts`, layout titlebar + sidebar + request/response se splittery. Neimplementované akce menu ukazují toast.
- Ikona: `build/appicon.svg` (zdroj) → `build/appicon.png` 1024 px (Wails z ní generuje `iconfile.icns`). Render SVG→PNG přes Swift `NSImage` (macOS umí SVG nativně).
- `Makefile`, `.github/workflows/ci.yml`, bundle ID `com.github.novami.minorrest`, min. macOS 13.
- Ověřeno: `wails build` → `build/bin/MinorREST.app` se spustí; v `wails dev` (localhost:34115) na ne-retina Menlo 13px, čeština, tmavé téma, binding `GetVersion` funguje.

### Co existuje (F1)
- `internal/model`: typy `Request`, `FolderConfig`, `ProjectConfig`, `Environment`, `KV`, `PathParam`, `Var`, `Auth` (+bloky), `Body`, `MultipartPart`, `Extract`, `HTTPSettings` (ukazatele = dědičnost), konstanty metod/typů těla/auth/názvů souborů, `NewRequest`.
- `MarshalYAML` (odsazení 2, víceřádkové řetězce jako `|`), `UnmarshalYAML` (+ NFC normalizace, chyba `YAML_INVALID`), `NormalizeNFC` (reflexe).
- `Slugify`, `UniqueSlug(slug, taken func(lower string) bool)` – volající předává lowercase sadu existujících jmen.
- `model.TreeNode` (+ pole `Error` = kód chyby nečitelného souboru), `model.ProjectInfo`, `model.NewID()` (ULID).
- `internal/storage`: `CreateProject(parentDir, name)`, `OpenProject(root)` → `*Project` (`Info`, `Config`, `SaveConfig` + správa `.gitignore`), `LoadTree`, `CreateFolder/CreateRequest(parentRel, name)`, `LoadRequest/SaveRequest`, `LoadFolderConfig/SaveFolderConfig`, `Rename`, `Move(rel, target, index)` (index mezi sourozenci stejného druhu), `Duplicate`, `Delete` (Koš přes cgo `trash_darwin.go`, i `.responses/<id>`). Atomický zápis, přečíslování `seq` 1..n, ochrana proti `..`, read-only při vyšší formatVersion. Chyby: `NOT_FOUND`, `PATH_INVALID`, `NAME_EMPTY`, `PROJECT_READONLY`, `PROJECT_INVALID`, `MOVE_INTO_SELF`, `FS_ERROR`, `TRASH_FAILED`.

- `internal/vars`: `New(scopes...)`, `Resolve` (→ text, nevyhodnocené, `VAR_CYCLE`), `Unresolved()`, `Explain()` (tajné maskované), dynamické `$uuid $ulid $timestamp $timestampMs $isoTimestamp $randomInt $randomString` (časové jednou na resolver = na odeslání), escape `\{{`. `BuildURL` (proměnné → `:param` přes PathEscape → `http://` → query), `EncodeQuery` (prázdná hodnota → jen název), `EncodeQueryComponent` (zachová `%XX`, enkóduje `& = + #`), `URL_INVALID`.

### Co existuje (F2)
- `internal/settings`: `Workspace` (+ `LoadWorkspace/SaveWorkspace(dir)`, výchozí rozměry), `AppDir()`, `DefaultProjectsDir()`.
- `internal/storage`: `Registry` (Open/Add s deduplikací podle ID, Get, Close, List, Paths), exportované `WriteFileAtomic`, `Project.Abs`.
- `app_projects.go`: všechny bindingy F2 z kap. 11.1; při startu `loadWorkspace` znovu otevře projekty (nečitelné vynechá + log). Seznam projektů ve workspace spravuje backend.
- `storage.InitProject(root, name)` + `IsProjectDir`; „Otevřít adresář…“ na adresáři bez projektu nabídne nativním dialogem založení (název = název adresáře). Bindingy `PickDirectory`, `DefaultProjectsDir`; modál nového projektu má volbu umístění.
- Strom (`Tree.svelte` plochý seznam viditelných řádků + `stores/tree.svelte.ts`): rozbalení ve `ws.expanded`, výběr, klávesy (šipky, Enter = rozbalit, F2 přejmenovat, Cmd+Backspace/Delete smazat), kontextové menu (`ContextMenu.svelte`) na uzlu i prázdné ploše, inline přejmenování, nový request/složka rovnou v editaci názvu, duplikace s příponou dle jazyka, mazání s potvrzením, Zobrazit ve Finderu. Menu `new-request`/`new-folder`/`duplicate` napojeno (cíl = vybraná složka / složka vybraného requestu / kořen).
- Drag & drop ve stromu (HTML5 DnD): složka – horní/dolní čtvrtina = před/za, střed = dovnitř (rozbalená jen před/dovnitř); request nad složkou = dovnitř, nad requestem = před/za; složka nad requestem = do jeho složky; prázdná plocha = kořen. Indikátor čárou / rámečkem, podržení nad sbalenou složkou 700 ms ji rozbalí, složku nelze do sebe. Index se počítá mezi sourozenci stejného druhu bez přetahovaného uzlu; přesun na stejné místo se nevolá.
- Hledání: pole nad stromem, filtr bez diakritiky a velikosti písmen (`util/text.ts` `fold`) podle názvu, URL a metody; zobrazí shody s nadřazenými složkami (rozbalené), u shody složky celý podstrom. Esc vymaže / vrátí fokus, Enter/↓ přejde do stromu. Během filtru je DnD vypnutý. `TreeNode` má nově `URL`.
- `internal/watch` (FSEvents, `github.com/fsnotify/fsevents`): `New(onChange, ignoreSelf)`, `Add(id, root)`, `Remove`, `Close`; jeden rekurzivní stream na projekt, latence 300 ms, skryté položky (`.git`, `.responses`, `.tmp-*`) ignoruje, `IgnoreSelf` potlačí vlastní zápisy (schválená odchylka od fsnotify, zapsáno v PLAN 8.2). App sleduje každý otevřený projekt (start, vytvoření, otevření), při zavření/ukončení stream zastaví; emit `tree:changed {projectID}` → frontend `reloadTree` u aktivního projektu.
- `LoadTree` přidělí nové ID requestům se shodným ID (kopie z Finderu); původní zůstane nejdříve vytvořenému souboru (`birthTime`, macOS Birthtimespec). V read-only projektu ne.
- Frontend: `stores/workspace.svelte.ts` (`ws`, init, debounced `saveWorkspace`, create/open/close/select), `ProjectSwitcher` v titlebaru (+ modál nového projektu), `Tree` (zatím jen zobrazení), `util/errors.ts` (`errorText` → `errors.<CODE>`), i18n sekce `errors`. Rozměry/viditelnost panelů se ukládají.

### Co existuje (F3)
- Bindingy `GetRequest` (nil slice → `[]` přes `model.FillNilSlices`), `SaveRequest` (`app_requests.go`); `storage.SaveRequest` převezme ID, název a pořadí ze souboru (identitu drží strom – zastaralý tab nepřepíše přejmenování).
- Workspace: `tabs` (projekt → ID requestů), `activeTab` (projekt → ID); zavřené projekty se z map mažou.
- `stores/tabs.svelte.ts`: tab = {id (ID requestu), projectID, rel, draft, saved (JSON)}, dirty = porovnání JSON. Taby per projekt, obnova při prvním načtení stromu projektu, po každém načtení stromu sledují přejmenování/přesun (podle ID), smazaný čistý tab se zavře. `workspace.treeLoaded` = háčky po načtení stromu. Uložení → `reloadTree` (metoda/URL ve stromu). `SetDirty` podle libovolného dirty tabu.
- Komponenty: `TabBar` (metoda, název ze stromu, tečka = neuloženo, × / prostřední tlačítko zavře, + nový request, dialog Uložit/Zahodit/Zrušit), `RequestEditor` (MethodSelect + URL bar + Odeslat), `MethodSelect` (nativní select, barva metody), `VarInput` (průhledný input nad zrcadlem, tokenizace `{{…}}`, `\{{` = escape, `$` modře; synchronizovaný scroll ověřen).
- URL bar (`util/urlbar.ts`): text = URL + zapnuté query; při psaní se rozdělí do `url` a `params.query` (zapnuté řádky se nahradí v pořadí, popisy zůstanou, vypnuté řádky zůstanou na místě, `?name` → `bare`). Vlastní text se drží, dokud se URL/query nezmění odjinud.
- Strom: dvojklik/Enter na requestu otevře tab; nový request (Cmd+N, +) se otevře v tabu a název je v editaci. Menu: Cmd+S uložit, Cmd+W zavřít tab, Cmd+L fokus URL. Cmd+Enter / Odeslat zatím toast (F4).
- `KvEditor` (`rows` bindable, volitelné; `fixed` = path params; `allowBare`; `names` + `valuesFor` = datalist našeptávač): checkbox, název a hodnota `VarInput` (nové props `list`, `compact`), popis (prázdný se maže kvůli omitempty), smazání, „duch“ řádek na konci (stejný klíč indexu → fokus se při prvním znaku neztratí), přetažení za úchyt (HTML5 DnD, čára před/za), Hromadná úprava (`util/kv.ts` `toBulk/fromBulk`, popisy podle názvu, řádek bez `:` = `bare` jen u query).
- Tělo (`BodyEditor`): přepínač 8 typů (data ostatních typů se při přepnutí zachovají), raw typy v `CodeEditor` (CodeMirror 6 `basicSetup`, jazyk dle typu, `readonly`, téma z CSS proměnných `--code-*`, zvýraznění `{{…}}`, externí změna hodnoty přepíše dokument). JSON: tlačítko Formátovat → binding `FormatJSON` (`internal/jsonfmt`: `json.Indent`, `{{…}}` i `\{{…}}` přes zástupce – mimo řetězec v uvozovkách, chyba `JSON_INVALID: <řádek>: …`), validace jen varováním pod editorem (`JSON.parse` na textu s proměnnými nahrazenými `1` + mezery stejné délky). Formulář = `KvEditor`, multipart = `KvEditor multipart` (text/soubor, výběr souboru, sloupec Content-Type místo popisu, bez bulk), binary = výběr souboru.
- `PickFile(projectID)` (schválená změna signatury, PLAN 11) → `storage.Project.FileRef`: uvnitř projektu relativně s `/`, jinak absolutně; symlinky (/var → /private/var) se rozvinou u nejbližšího existujícího předka.
- `RequestEditor`: záložky Parametry | Tělo | Hlavičky s počty (poslední záložka per tab v paměti). Query tabulka ↔ URL bar, path params (`syncPath`) podle `:name` v URL (stejná pravidla jako `vars.BuildURL`, hodnoty se drží podle názvu). Headers: `util/headers.ts` (běžné názvy a hodnoty).
- Záložka Nastavení (`SettingsEditor`): HTTP verze, redirecty, max redirectů, timeout, ověřování TLS; select „Zdědit (aktuálně: …)“ / hodnota („Vlastní“ + číslo). Zdědit = klíč se smaže (na disku chybí); klíče se skládají v pořadí polí Go, aby porovnání JSON nehlásilo falešné změny. Binding `GetInheritedSettings(projectID)` = nastavení projektu `.Over(settings.DefaultHTTP())` (globální nastavení v F11). Záložka Dokumentace = `CodeEditor` markdown (prázdná → `docs` se vynechá); tečka u záložky, když je vyplněná.
- Zavření okna/aplikace s neuloženými taby: nativní dialog Uložit / Neukládat / Zrušit; Uložit → událost `app:saveAndQuit` → frontend `saveAll()` → binding `Quit()` (příznak `quitting` přeskočí dialog). Selže-li uložení, aplikace zůstane otevřená (toast).
- Zavření projektu s neuloženými taby (`closeProjectSafe`): modál Uložit vše / Zahodit / Zrušit.
- Watcher emituje navíc `request:changedOnDisk {projectID, rel}` pro změněné `*.req.yaml`; čistý tab se tiše znovu načte, neuložený ukáže banner „Načíst z disku / Ponechat moje“ (Ponechat = verze z disku se stane základem, tab zůstane neuložený). Funguje i pro taby neaktivních projektů.

### Co existuje (F4)
- `internal/httpclient`: `Engine` (`New`, `Do(ctx, runID, Request, Options) (*Result, error)`, `Cancel(runID)`), `OptionsFrom(HTTPSettings, userAgent)`. Nový `http.Transport` na odeslání (`Protocols`: auto = h1+h2, http1, http2 / h2c prior knowledge pro `http://`), `DisableCompression`, `InsecureSkipVerify = !VerifyTLS`, vlastní `CheckRedirect` (záznam skoků `{status, method, url, location}`, limit → `REDIRECT_LIMIT`), timeout i zrušení přes context s příčinou (`NET_TIMEOUT` vs `CANCELED`), `TLSInfo` (verze, cipher, SNI, subjekt, vydavatel, expirace).
- `Request{Method, URL, Headers []KV, Body model.Body, BaseDir, NoAuto []string}` – hlavičky kanonizované (`Add`, opakované se zachovají), `Host` → `req.Host`, `Content-Length` ignorován, auto `User-Agent`/`Accept: */*`/`Content-Type` jen když chybí a nejsou v `NoAuto`; vypnutý UA = prázdný (Go nedoplní vlastní).
- Těla: raw typy s `; charset=utf-8`, form v pořadí řádků (`url.QueryEscape`, plné kódování), multipart v paměti (UTF-8 `filename`, Content-Type z přípony), binary streamem ze souboru; relativní cesty vůči `BaseDir`; `GetBody` → 307/308 pošle tělo znovu. Uživatelský `multipart/…` Content-Type bez boundary dostane boundary doplněné.
- Chyby `*httpclient.Error{Code, Detail}` (`Error()` = `KÓD: detail`): `CANCELED NET_TIMEOUT NET_DNS NET_REFUSED NET_ERROR TLS_VERIFY TLS_ERROR HTTP2_UNSUPPORTED REDIRECT_LIMIT FILE_NOT_FOUND URL_INVALID METHOD_INVALID` (+ i18n cs/en). `HTTP2_UNSUPPORTED` jen při vynuceném http2 podle textu chyby (chybí ALPN h2 / h2c na HTTP/1 serveru). `DECODE_ERROR` = poškozené komprimované tělo.
- Metriky (F4/2): `trace.go` – `httptrace` hooky drží stav per skok (reset v `GetConn`), do `Timing` jde poslední skok (`dnsMs connectMs tlsMs ttfbMs downloadMs totalMs`, `reused`), `RemoteAddr/LocalAddr/ResolvedAddrs`, `Sent` (metoda, URL, hlavičky z `WroteHeaderField` v pořadí odeslání, u h2 i pseudo-hlavičky; `BodyPreview` max 64 KiB, u binary souboru prázdný; po 301–303 tělo 0). `Sizes` dle kap. 4 (request line jen u HTTP/1). Při chybě `Do` vrací i částečný `Result` (Sent, Timing, Redirects).
- Tělo odpovědi (`respbody.go`): auto `Accept-Encoding: gzip, deflate, br, zstd`, dekomprese (deflate: zlib, jinak raw; více kódování v opačném pořadí; neznámé → bajty beze změny), `Body` v paměti do 10 MB, pak temp soubor, oříznutí na `MaxBodyBytes` (výchozí 100 MB) → `Truncated`. `sniff`: `ContentType` (media type), `Charset` (JSON bez charsetu = utf-8, jinak `charset.DetermineEncoding`; výchozí odhad windows-1252 u platného UTF-8 → utf-8), `IsBinary` (netextový typ a vzorek není UTF-8 text). `ToUTF8(b, cs)` pro zobrazení. Engine drží 20 posledních úspěšných výsledků (`Get`, LRU maže temp soubory, `Close()`).

- F4/3: `internal/prepare` – `Prepare(Input) (Prepared, error)`: `Input{Request, Project, Folders []Folder{Rel, Config} (od kořene), Runtime, Env, Globals, Defaults, BaseDir, UserAgent}` → `httpclient.Request` + `Options` + `Unresolved`. Proměnné v pořadí runtime → request → složky (nejbližší první) → prostředí → projekt → globální. Hlavičky projekt → složky → request: název uvedený na nižší úrovni (i vypnutý) odstraní výše zděděné (case-insensitive); vypnutý řádek `User-Agent/Accept/Accept-Encoding/Content-Type` bez zapnutého protějšku → `NoAuto`. Tělo: vyhodnocené proměnné, jen zapnuté form/multipart řádky (i cesty souborů a Content-Type části). Nastavení request → projekt → `settings.DefaultHTTP()`. Auth se zatím ignoruje.
- `internal/run`: DTO `Input`, `Result`, `Error`, `BodyView`; `ErrorOf` (`KÓD: detail` → kód, jinak `INTERNAL_ERROR`), `FromResult` (nil slice → `[]`), `View` (UTF-8, pretty JSON přes `json.Indent`, max 2 MB → `Partial`, binární bez textu).
- `app_run.go`: `Send` (chyby přípravy i odeslání v `Result.Error`), `Cancel`, `GetRunBody` (`RUN_NOT_FOUND`); `App.engine` vzniká ve `startup`, `Close()` v `shutdown`. `folderChain` načte `_folder.yaml` nadřazených složek.
- Frontend: `stores/runs.svelte.ts` (poslední běh per tab v paměti, `send`, `cancel`; runID = `crypto.randomUUID()`), `ResponseView.svelte` (dočasné: status barevně, protokol, čas, velikost, chyba, nevyhodnocené proměnné, `<pre>` s tělem), Odeslat ↔ Zrušit v URL baru, Cmd+Enter/Enter odešle.

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
| 2026-11-17 | F2/3 | 521ce8f | drag & drop, hledání ve stromu |
| 2026-11-17 | F2/4 | 942083b | watcher (FSEvents), tree:changed, oprava duplicitních ID |
| 2026-11-17 | F3/1 | 647e970 | taby, načtení/uložení requestu, MethodSelect, VarInput, URL bar |
| 2026-11-17 | F3/2 | fd322c1 | KvEditor, bulk edit, Params/Headers, path params, našeptávač hlaviček |
| 2026-11-17 | F3/3 | 9264db3 | tělo: CodeEditor, typy těla, FormatJSON, PickFile(projectID) |
| 2026-11-17 | F3/4 | 96cf3dd | nastavení, dokumentace, dialog zavření okna/projektu, změna na disku |
| 2026-11-17 | F4/1 | d5efcf7 | jádro httpclient: verze, těla, redirecty, timeout/cancel, chybové kódy |
| 2026-11-17 | F4/2 | 9b9120a | metriky, dekomprese, charset, limity těla, LRU výsledků |
| 2026-11-18 | F4/3 | baf2801 | prepare, Send/Cancel/GetRunBody, Odeslat/Zrušit, dočasná odpověď |
| 2026-11-22 | plán rev. 3 | 44ab8ae | přechod na Swift, tag go-wails-f4 |
| 2026-11-22 | F0/1 (Swift) | a448e3a | xcodegen, MinorRESTCore, odstranění go/svelte |
| 2026-11-22 | F0/2 (Swift) | e6cab8f | okno, menu, cs/en, fonty, rozvržení, ladicí snímky |
| 2026-11-22 | F0/3 (Swift) | b116273 | CI pro Swift |
| 2026-11-22 | F1/1 (Swift) | 78b228b | model, yaml shodný s go, slug, ulid |
| 2026-11-22 | F1/2 (Swift) | 70ac3ed | úložiště, registr, workspace |
| 2026-11-22 | F1/3 (Swift) | 3bc599e | proměnné, url, formátování json |
| 2026-11-22 | F2/1 (Swift) | fc7ca0f | workspace, projekty, přepínač, výška odpovědi |
| 2026-11-22 | F2/2 (Swift) | 59688ae | strom (NSOutlineView), operace nad uzly, kontextové menu |

## Rozhodnutí uživatele
- ~~Wails v2 + Svelte 5~~ → **Swift (SwiftUI + AppKit), URLSession, macOS 15+, tag + přepis na main** (2026-11-22). YAML soubory, UI cs+en, zatím bez Apple Developer ID (ad-hoc podpis), MIT, auto-update výchozí zapnuto.
- Repozitář i releasy jsou veřejné (updater bez tokenu).
- Ne-retina displej: Menlo 13 (UI i kód). Retina: SF Pro (UI) + SF Mono (kód).
- Swift verze: editor kódu nativní `NSTextView` (ne CodeMirror), Keychain přes `SecItem` (dotaz na přístup po každé aktualizaci je přijatelný).
- Kopírování requestu: jen cURL (víceřádkový + jednořádkový), bez bash skriptu.

## Otevřené body / známé problémy (Go verze, reference)
- YAML: chybějící `enabled` u KV/Var/multipart/extract = zapnuto (vlastní `UnmarshalYAML`). Řádky se zapisují blokovým stylem, ne flow `{…}` jako v ukázkách plánu.
- Storage: složky a requesty sdílí jmenný prostor slugů (kolize case-insensitive); v kořeni je `environments` rezervované. Nečitelné soubory jsou ve stromu na konci s `Error`. `Duplicate(rel, copySuffix)` – binding `DuplicateNode` předá příponu v jazyce UI (prázdná = „ kopie“). Mazání nepřesune do Koše `.responses/<id>`, pokud stejné ID má jiný request.
- Testy storage nahrazují `trashItem` přesunem do TempDir; skutečný Koš ověřen jednorázově ručně.
- Vars: nevyhodnocená proměnná v hostu → `VAR_UNRESOLVED_HOST: <názvy>`; v cestě se pošle enkódovaně (`%7B%7Bid%7D%7D`) a je v `Unresolved`. Pojmenovaná proměnná = jedna hodnota na resolver (cache), přímé `{{$uuid}}` pokaždé nové. Query: prázdná hodnota → `name=`, `KV.Bare` → `name` (URL bar v F3 nastaví `bare` při `?name` bez `=`).
- i18n `errors.*` pokrývá kódy z `internal/*`; nové kódy (HTTP, auth…) přidávat průběžně.
- `wails dev` v prohlížeči: chyba z `wails/ipc.js` („reading 'nodes'“) je v overlayi Wails „odpojeno“ (Svelte v ipc.js), jen dev, aplikaci neovlivňuje.
- Strom: Enter na requestu zatím nic neotevře (taby v F3). Kontextové menu bez „Kopírovat jako cURL“ (F9) a „Nastavení složky“ (F3). Zobrazit ve Finderu neověřeno v UI (jen `open -R`).
- DnD ověřen jen syntetickými událostmi v prohlížeči (wails dev); v nativním WKWebView neověřeno – při potížích přejít na pointer events (PLAN 8.2).
- Watcher: Finder „Duplikovat“ zachová datum změny, proto se rozhoduje podle data vytvoření; při shodě podle rel. Změna kořenového adresáře projektu (přesun/smazání) se nehlásí (bez `WatchRoot`).
- `make dev` potřebuje `~/go/bin` v PATH (jinak „wails: No such file“).
- Screenshoty v panelu prohlížeče občas ukazují zastaralý stav – ověřovat přes DOM (`javascript_tool`).
- Testy v `wails dev` zapisují do skutečného `~/Library/Application Support/MinorREST/workspace.yaml` – testovací projekty zakládat přes binding do scratch adresáře a po testu zavřít.
- Nil slice → v JSON `null`; `GetRequest` normalizuje (`FillNilSlices`), ostatní DTO zatím ne.
- Tab smazaného requestu s neuloženými změnami zůstane otevřený, uložení skončí `NOT_FOUND` (pak blokuje i „Uložit“ při ukončení – zbývá „Neukládat“).
- F3/4 ověřeno v `wails dev` (prohlížeč): nastavení + docs → uložení → YAML dle 2.5, změna zvenku u čistého i neuloženého tabu, modál zavření projektu s „Uložit vše“. Neověřeno: nativní dialog při zavření okna / Cmd+Q a `Quit()` (jen v sestavené aplikaci), vzhled záložky Nastavení (jen DOM). Při hromadném přeskenování FSEvents (`rels == nil`) se `request:changedOnDisk` neposílá.
- `VarInput` zatím barví všechny `{{proměnné}}` jako známé (vyhodnocení a hover v F6).
- Retina větev fontů ověřena jen syntakticky (media query platná), vizuálně ne – ověřit na retina displeji.
- F12 vyžaduje od uživatele ed25519 klíč v GitHub Secrets (`UPDATE_SIGNING_KEY`).
- KvEditor: blok „Automatické a zděděné hlavičky“ (kap. 8.3) odložen – potřebuje `prepare`/nastavení složek (F4/F6). Request s `:param` v URL, ale bez `params.path` v YAML, je po otevření hned neuložený (doplní se řádky). V režimu hromadné úpravy se textarea nepřepočítá, když se query změní z URL baru. Datalist (našeptávač) a DnD řádků ověřeny jen v prohlížeči, ne v nativním WKWebView. Při přejmenování `:i` → `:id` během psaní se hodnota path paramu nepřenese.
- Tělo: drop souboru do multipart/binary zatím není (Wails `OnFileDrop` – doplnit v F13 nebo dle potřeby). Text varování nevalidního JSON je z `JSON.parse` prohlížeče (WebKit má jiné znění a bez pozice). Výběr souboru (nativní dialog) v prohlížeči neověřen, jen v kódu.
- httpclient: hlavičky odpovědi jsou seřazené podle názvu (net/http nedrží pořadí ze serveru, plán chce „pořadí dle serveru“ – pro HTTP/1 by šlo jen vlastním čtením). Proxy zatím `ProxyFromEnvironment` z klonu `DefaultTransport` (F4/4). Multipart soubory se načítají celé do paměti.
- F4/3 ověřeno v `wails dev` (prohlížeč) proti lokálnímu serveru: dědičnost hlaviček projekt/složka, vypnutý UA (pošle se prázdný), vypnutá zděděná hlavička, path param s diakritikou, nevyhodnocená proměnná v query (varování), `VAR_UNRESOLVED_HOST`, zrušení tlačítkem, `RUN_NOT_FOUND`. Konfigurace projektu (`minorrest.yaml`) se drží v paměti a změna zvenku se nenačte (až restart) – řešit s bindingy `Get/SaveProjectConfig` v F6 (+ reload z watcheru). Bindingy `Get/SaveFolderConfig`, `Get/SaveProjectConfig` zatím nejsou. Výsledky běhů ve frontendu (`runs`) se při zavření tabu nemažou. Vypnutý řádek `Accept` apod. v requestu vypne i automatickou hlavičku (dle kap. 8.3), i když ho uživatel jen „odškrtl“.

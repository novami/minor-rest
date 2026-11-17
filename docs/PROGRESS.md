# Stav projektu

## Aktuálně
- **Fáze:** F4, krok 2 hotový.
- **Další krok:** F4, krok 3 – `internal/prepare`: dědičnost hlaviček (projekt → složky → request, pozdější přepisuje dle názvu case-insensitive) a nastavení (request → projekt → globální), proměnné (`vars`), sestavení URL (`vars.BuildURL`), auth zatím jen `none` → `httpclient.Request`. Bindingy `Send(RunInput) (RunResult, error)`, `Cancel`, `GetRunBody(runID, pretty)` (DTO dle 11.2; `Engine.Close()` při ukončení aplikace). UI: Odeslat/Zrušit, dočasné jednoduché zobrazení (status + raw tělo). Ověřit v `wails dev`.
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
- Drag & drop ve stromu (HTML5 DnD): složka – horní/dolní čtvrtina = před/za, střed = dovnitř (rozbalená jen před/dovnitř); request nad složkou = dovnitř, nad requestem = před/za; složka nad requestem = do jeho složky; prázdná plocha = kořen. Indikátor čárou / rámečkem, podržení nad sbalenou složkou 700 ms ji rozbalí, složku nelze do sebe. Index se počítá mezi sourozenci stejného druhu bez přetahovaného uzlu; přesun na stejné místo se nevolá.
- Hledání: pole nad stromem, filtr bez diakritiky a velikosti písmen (`util/text.ts` `fold`) podle názvu, URL a metody; zobrazí shody s nadřazenými složkami (rozbalené), u shody složky celý podstrom. Esc vymaže / vrátí fokus, Enter/↓ přejde do stromu. Během filtru je DnD vypnutý. `TreeNode` má nově `URL`.
- `internal/watch` (FSEvents, `github.com/fsnotify/fsevents`): `New(onChange, ignoreSelf)`, `Add(id, root)`, `Remove`, `Close`; jeden rekurzivní stream na projekt, latence 300 ms, skryté položky (`.git`, `.responses`, `.tmp-*`) ignoruje, `IgnoreSelf` potlačí vlastní zápisy (schválená odchylka od fsnotify, zapsáno v PLAN 8.2). App sleduje každý otevřený projekt (start, vytvoření, otevření), při zavření/ukončení stream zastaví; emit `tree:changed {projectID}` → frontend `reloadTree` u aktivního projektu.
- `LoadTree` přidělí nové ID requestům se shodným ID (kopie z Finderu); původní zůstane nejdříve vytvořenému souboru (`birthTime`, macOS Birthtimespec). V read-only projektu ne.
- Frontend: `stores/workspace.svelte.ts` (`ws`, init, debounced `saveWorkspace`, create/open/close/select), `ProjectSwitcher` v titlebaru (+ modál nového projektu), `Tree` (zatím jen zobrazení), `util/errors.ts` (`errorText` → `errors.<CODE>`), i18n sekce `errors`. Rozměry/viditelnost panelů se ukládají.

## Co existuje (F3)
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

## Co existuje (F4)
- `internal/httpclient`: `Engine` (`New`, `Do(ctx, runID, Request, Options) (*Result, error)`, `Cancel(runID)`), `OptionsFrom(HTTPSettings, userAgent)`. Nový `http.Transport` na odeslání (`Protocols`: auto = h1+h2, http1, http2 / h2c prior knowledge pro `http://`), `DisableCompression`, `InsecureSkipVerify = !VerifyTLS`, vlastní `CheckRedirect` (záznam skoků `{status, method, url, location}`, limit → `REDIRECT_LIMIT`), timeout i zrušení přes context s příčinou (`NET_TIMEOUT` vs `CANCELED`), `TLSInfo` (verze, cipher, SNI, subjekt, vydavatel, expirace).
- `Request{Method, URL, Headers []KV, Body model.Body, BaseDir, NoAuto []string}` – hlavičky kanonizované (`Add`, opakované se zachovají), `Host` → `req.Host`, `Content-Length` ignorován, auto `User-Agent`/`Accept: */*`/`Content-Type` jen když chybí a nejsou v `NoAuto`; vypnutý UA = prázdný (Go nedoplní vlastní).
- Těla: raw typy s `; charset=utf-8`, form v pořadí řádků (`url.QueryEscape`, plné kódování), multipart v paměti (UTF-8 `filename`, Content-Type z přípony), binary streamem ze souboru; relativní cesty vůči `BaseDir`; `GetBody` → 307/308 pošle tělo znovu. Uživatelský `multipart/…` Content-Type bez boundary dostane boundary doplněné.
- Chyby `*httpclient.Error{Code, Detail}` (`Error()` = `KÓD: detail`): `CANCELED NET_TIMEOUT NET_DNS NET_REFUSED NET_ERROR TLS_VERIFY TLS_ERROR HTTP2_UNSUPPORTED REDIRECT_LIMIT FILE_NOT_FOUND URL_INVALID METHOD_INVALID` (+ i18n cs/en). `HTTP2_UNSUPPORTED` jen při vynuceném http2 podle textu chyby (chybí ALPN h2 / h2c na HTTP/1 serveru). `DECODE_ERROR` = poškozené komprimované tělo.
- Metriky (F4/2): `trace.go` – `httptrace` hooky drží stav per skok (reset v `GetConn`), do `Timing` jde poslední skok (`dnsMs connectMs tlsMs ttfbMs downloadMs totalMs`, `reused`), `RemoteAddr/LocalAddr/ResolvedAddrs`, `Sent` (metoda, URL, hlavičky z `WroteHeaderField` v pořadí odeslání, u h2 i pseudo-hlavičky; `BodyPreview` max 64 KiB, u binary souboru prázdný; po 301–303 tělo 0). `Sizes` dle kap. 4 (request line jen u HTTP/1). Při chybě `Do` vrací i částečný `Result` (Sent, Timing, Redirects).
- Tělo odpovědi (`respbody.go`): auto `Accept-Encoding: gzip, deflate, br, zstd`, dekomprese (deflate: zlib, jinak raw; více kódování v opačném pořadí; neznámé → bajty beze změny), `Body` v paměti do 10 MB, pak temp soubor, oříznutí na `MaxBodyBytes` (výchozí 100 MB) → `Truncated`. `sniff`: `ContentType` (media type), `Charset` (JSON bez charsetu = utf-8, jinak `charset.DetermineEncoding`; výchozí odhad windows-1252 u platného UTF-8 → utf-8), `IsBinary` (netextový typ a vzorek není UTF-8 text). `ToUTF8(b, cs)` pro zobrazení. Engine drží 20 posledních úspěšných výsledků (`Get`, LRU maže temp soubory, `Close()`).

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

## Rozhodnutí uživatele
- Wails v2 + Svelte 5, YAML soubory, UI cs+en, zatím bez Apple Developer ID (ad-hoc podpis), MIT, auto-update výchozí zapnuto.
- Repozitář i releasy jsou veřejné (updater bez tokenu).
- Ne-retina displej: Menlo 13 (UI i kód). Retina: SF Pro (UI) + SF Mono (kód).
- Kopírování requestu: jen cURL (víceřádkový + jednořádkový), bez bash skriptu.

## Otevřené body / známé problémy
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

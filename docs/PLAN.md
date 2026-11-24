# MinorREST – implementační plán (revize 3: Swift)

> Implementuje se po fázích F0–F13, každá fáze má očíslované **kroky = commity**. Po každém kroku aktualizuj
> `docs/PROGRESS.md`. Analýza konkurence: `docs/ANALYZA.md`. API jádra pro UI: kapitola 11.
> Kde plán říká „přesně“, drž se ho; kde je jen cíl, zvol nejjednodušší řešení.
>
> **Revize 3 (2026-11-22):** aplikace se přepisuje z Go + Wails + Svelte do Swiftu. Poslední stav Go verze je
> v tagu `go-wails-f4` (F0–F4/3 hotovo) – slouží jako **referenční implementace**: testovací případy, edge case
> a chování (`git show go-wails-f4:internal/vars/vars_test.go` apod.). Formát dat na disku (kap. 2) se nemění –
> projekty vytvořené Go verzí musí jít otevřít beze změny.

## 0. Rozhodnutí (schválená uživatelem)

| Oblast | Volba |
|---|---|
| Platforma | **macOS 15+**, pouze Apple Silicon (arm64) |
| Jazyk | **Swift 6** (strict concurrency), vše ve Swiftu |
| GUI | **SwiftUI** + AppKit přes `NSViewRepresentable` tam, kde SwiftUI nestačí (strom, jednořádková pole s proměnnými, editor kódu) |
| HTTP | **URLSession** (omezení viz kap. 4.1) |
| Projekt | **XcodeGen** (`project.yml` → `MinorREST.xcodeproj`, generovaný, není v gitu) + lokální SwiftPM balíček `MinorRESTCore` s logikou |
| Úložiště | **YAML soubory** (projekt = adresář, formát beze změny oproti rev. 2), tajné proměnné v **macOS Keychain** |
| YAML knihovna | [Yams](https://github.com/jpsim/Yams) (SwiftPM) |
| Jazyk UI | čeština + angličtina (String Catalog `Localizable.xcstrings`, výchozí dle systému, přepnutelné za běhu) |
| Podpis | ad-hoc (`codesign -s -`), bez notarizace a bez App Sandboxu; auto-update z GitHub Releases ověřený EdDSA |
| Licence / repo | MIT, https://github.com/novami/minor-rest.git |
| Bundle ID | `cz.novami.minor.rest` |
| Kopírování requestu | jen cURL (víceřádkový + jednořádkový) |
| Fonty | ne-retina Menlo 13 (UI i kód), retina SF Pro (UI) + SF Mono (kód) |

## 1. Architektura

```
minor-rest/
├── project.yml                     # XcodeGen: cíl MinorREST (app), závislost na Packages/MinorRESTCore
├── Makefile                        # gen, build, run, test, release
├── App/                            # cíl aplikace – tenká vrstva nad jádrem
│   ├── Application/                # MinorRESTApp (@main, scény, Commands), AppModel, WorkspaceStore, MainView, MainWindowHook
│   ├── Features/                   # členění podle funkce; každá: views + @Observable @MainActor store
│   │   ├── Sidebar/                # ProjectSwitcher, strom (TreeOutlineView), TreeStore, ProjectsStore, historie
│   │   ├── Request/                # taby (TabsStore), URL bar, KvEditor, BodyEditor, Auth, Settings, Docs
│   │   ├── Response/               # RunStore, meta bar, tělo, hlavičky, časování, verze
│   │   ├── Environment/            # EnvironmentsStore, VarsStore, editor prostředí a proměnných
│   │   └── Settings/               # okno Nastavení (Cmd+,)
│   ├── Shared/
│   │   ├── Components/             # MethodBadge, StatusBadge, Toast, Banner…
│   │   ├── AppKit/                 # NSViewRepresentable: VarField, CodeTextView
│   │   └── Support/                # L10n (t()), formátování čísel, fonty dle displeje
│   └── Resources/                  # Localizable.xcstrings, Assets.xcassets (ikona), Info.plist
├── Packages/MinorRESTCore/         # SwiftPM, bez SwiftUI/AppKit (jen Foundation, Security, CoreServices, Network)
│   ├── Package.swift               # závislost Yams
│   ├── Sources/MinorRESTCore/
│   │   ├── Model/                  # Codable typy (kap. 2), ULID, slug, NFC
│   │   ├── YAML/                   # kódování/dekódování přes Yams (stabilní pořadí, `|` u víceřádkových)
│   │   ├── Storage/                # projekt, strom, CRUD, přesun, koš, registr, workspace
│   │   ├── Watch/                  # FSEvents
│   │   ├── Vars/                   # resolver {{x}}, dynamické proměnné, URL
│   │   ├── JSON/                   # formátování (tokenizér, zachová čísla i pořadí), JSONPath
│   │   ├── HTTP/                   # URLSession engine, metriky, tělo odpovědi, chyby
│   │   ├── Prepare/                # dědičnost + proměnné + auth → PreparedRequest
│   │   ├── Auth/                   # basic, bearer, apikey, oauth2
│   │   ├── Secrets/                # Keychain
│   │   ├── Responses/              # uložené odpovědi, historie, maskování
│   │   ├── Export/                 # cURL generátor
│   │   ├── Import/{Curl,OpenAPI,Postman}/
│   │   └── Settings/               # globální nastavení
│   └── Tests/MinorRESTCoreTests/   # Swift Testing (@Test, parametrizované = tabulkové testy)
├── scripts/                        # release, podpis aktualizace
├── docs/
└── .github/workflows/              # ci.yml
```

**Zásady:**
- Jádro (`MinorRESTCore`) je zdroj pravdy pro disk a veškerou logiku; UI drží jen stav zobrazení (otevřené taby, neuložené změny). Jádro neimportuje SwiftUI ani AppKit → `swift test` běží bez Xcode projektu.
- Modelové typy jsou `struct … : Codable, Sendable, Equatable`. Služby s měnitelným stavem jsou `actor` (Engine, Registry), čistá logika jsou funkce/`struct`. UI stores jsou `@Observable @MainActor final class`.
- Chyby: `struct CoreError: Error { let code: ErrorCode; let detail: String }`, `ErrorCode` = `String` enum (`NET_TIMEOUT`…, stejné kódy jako rev. 2). UI zobrazí `t("errors.<CODE>")` + detail. Žádné natvrdo psané texty v jádru.
- Dlouhé operace (I/O, síť) jsou `async` a neblokují hlavní vlákno; UI volá jádro z `Task {}`.

### 1.1 Swift / SwiftUI – úskalí (čti před F0!)
1. **XcodeGen:** `brew install xcodegen`; `MinorREST.xcodeproj` je v `.gitignore`, generuje `make gen` (volají ho i `build`/`run`). Nastavení cíle (deployment target 15.0, arm64, Swift 6, `ENABLE_HARDENED_RUNTIME: NO`, bez sandboxu, `CODE_SIGN_IDENTITY: "-"`) patří do `project.yml`, ne do Xcode.
2. **Build a spuštění z CLI:** `xcodebuild -project MinorREST.xcodeproj -scheme MinorREST -configuration Debug -derivedDataPath .build/xcode build` → `.build/xcode/Build/Products/Debug/MinorREST.app`; `make run` = build + `open`. Testy jádra: `cd Packages/MinorRESTCore && swift test` (rychlé, bez app cíle).
3. **ATS:** `Info.plist` → `NSAppTransportSecurity.NSAllowsArbitraryLoads = YES` (REST klient musí umět `http://` i libovolné hosty).
4. **Local Network privacy (macOS 15):** requesty na adresy v LAN (ne `localhost`) vyvolají systémový dotaz → `NSLocalNetworkUsageDescription` v `Info.plist` (cs/en přes `InfoPlist.xcstrings`).
5. **Bez App Sandboxu:** projekty jsou libovolné adresáře, FSEvents na libovolné cestě.
6. **Menu a zkratky – jeden zdroj:** vše přes SwiftUI `Commands` (`CommandGroup`/`CommandMenu`, `.keyboardShortcut`). Aplikace má jedno hlavní okno (`Window`), proto menu volá akce přímo na sdíleném `AppModel` (ne NotificationCenter; `@FocusedValue` až kdyby přibyla další okna). Cmd+C/V/Z funguje automaticky v textových polích (standardní `CommandGroup(replacing:)` nepoužívat pro Edit).
7. **Ukončení s neuloženými změnami:** `NSApplicationDelegateAdaptor` → `applicationShouldTerminate` vrátí `.terminateLater`, zobrazí `NSAlert` Uložit / Neukládat / Zrušit, po uložení `reply(toApplicationShouldTerminate:)`. Zavření okna: `NSWindowDelegate.windowShouldClose`. `isDocumentEdited` okna = tečka v zavíracím tlačítku.
8. **Strom:** `NSOutlineView` (spolehlivý drag & drop, inline přejmenování, kontextové menu, klávesnice, výkon u velkých stromů) – SwiftUI `List`/`OutlineGroup` tohle neumí dobře.
9. **Jednořádková pole s proměnnými (`VarField`):** `NSTextField` s vlastním field editorem (`NSTextView`), zvýraznění přes `layoutManager` temporary attributes (nemění text ani undo). Ne `CodeTextView`.
10. **Editor kódu (`CodeTextView`):** `NSTextView` v `NSScrollView` (TextKit 2, barvy přes `renderingAttributesValidator` – jen vykreslované fragmenty), vlastní jednoduché lexery (JSON, XML/HTML, markdown, text), hledání přes vestavěný `NSTextFinder` (Cmd+F), `allowsUndo`. Velké texty: zvýraznění jen viditelné oblasti / do limitu, vypnout automatické nahrazování (uvozovky, pomlčky, kontrola pravopisu) – **všude** v textových polích s kódem a URL.
11. **Fonty dle displeje:** `NSWindow.backingScaleFactor` (sledovat `NSWindow.didChangeBackingPropertiesNotification` a `didChangeScreenNotification`) → `@Environment` hodnota s fonty UI/kódu.
12. **i18n:** String Catalog; jazyk `auto | cs | en` za běhu: helper `t(_ key: String, _ args…)` hledá v `Bundle` pro zvolené `.lproj`. Nativní menu se překreslí samo (SwiftUI). Klíče stejné jako v rev. 2 (`errors.NET_DNS`, `request.send`…) – lze převzít z `git show go-wails-f4:frontend/src/lib/i18n/cs.json`.
13. **Ověřování UI:** Debug build má přepínače `--snapshot <png>` (vykreslí okno do PNG bez oprávnění k nahrávání obrazovky), `--dump-menu <txt>` (menu se zkratkami) a `--quit-after-debug`; jazyk `-AppleLanguages '(en)'`. Interakci (kliky, psaní) zatím jen přes computer-use, pokud je v relaci dostupné; stav raději ověřovat testy jádra. Testovací projekty zakládat ve scratch adresáři a po testu je zavřít (workspace je ve skutečném `~/Library/Application Support/MinorREST/`).
14. **Swift 6 concurrency:** URLSession delegate je `final class … : NSObject, URLSessionDataDelegate, @unchecked Sendable` se stavem chráněným `Mutex`/`OSAllocatedUnfairLock`; ven publikovat přes `async` API (`withCheckedThrowingContinuation`).

## 2. Datový model a formát na disku

Beze změny oproti rev. 2 (kompatibilita s projekty z Go verze). Implementační poznámky pro Swift jsou u jednotlivých bodů.

### 2.1 Umístění
- `~/Library/Application Support/MinorREST/`
  - `settings.yaml` – globální nastavení (kap. 9)
  - `workspace.yaml` – otevřené projekty (cesty), aktivní projekt, otevřené taby, aktivní prostředí per projekt, rozbalené složky, šířky panelů
  - `globals.yaml` – globální proměnné (formát jako prostředí)
  - `history/<ULID>.yaml` + `<ULID>.body` – historie odeslání (posledních N, výchozí 200; tělo max 1 MB, delší oříznout a označit `truncated: true`)
  - `cookies/<projectId>.json` – cookie jar
- Projekt: libovolný adresář; nové se zakládají do `~/Documents/MinorREST/<slug>/` (lze změnit).

### 2.2 Struktura projektu
```
muj-projekt/
├── minorrest.yaml              # metadata projektu
├── environments/vyvoj.yaml
├── uzivatele/                  # složka (adresář se souborem _folder.yaml)
│   ├── _folder.yaml
│   ├── seznam-uzivatelu.req.yaml
│   └── detail/…                # vnořené složky povoleny, bez limitu hloubky
├── .responses/<requestId>/     # uložené odpovědi (2.6)
└── .gitignore                  # spravuje aplikace (řádek .responses/ dle nastavení projektu)
```
- **Složka** = adresář obsahující `_folder.yaml`. Adresáře bez něj, začínající `.` nebo `_`, a `environments` se ve stromu ignorují.
- **Request** = soubor `*.req.yaml`.
- **Adresace ve všech API:** `projectID` + `rel` (relativní cesta od kořene projektu s `/`, kořen = `""`). `Request.id` (ULID) slouží pro `.responses/`, otevřené taby a historii – přežije přejmenování i přesun.
- **Slug:** NFC → NFD → odstranit znaky kategorie `Mn` → mapa nerozložitelných (`ł→l, đ→d, ß→ss, ø→o, æ→ae`) → lowercase → vše mimo `[a-z0-9]` na `-` → sloučit a oříznout `-` → max 60 znaků. Prázdný výsledek → `polozka`. Kolize (case-insensitive) → `-2`, `-3`. Příklad: `Příliš žluťoučký kůň` → `prilis-zlutoucky-kun`. Složky a requesty sdílí jmenný prostor slugů; v kořeni je `environments` rezervované.
- Přejmenování = změna `name` + přejmenování souboru/adresáře na nový slug.
- Zápis atomicky (temp soubor `.tmp-*` ve stejném adresáři + `rename(2)`). Všechny vstupní řetězce normalizovat do NFC (`precomposedStringWithCanonicalMapping`).
- Mazání = `FileManager.trashItem` (Koš), nikdy `removeItem`. Při smazání requestu přesunout do Koše i jeho `.responses/<id>/` (pokud stejné ID nemá jiný request).
- **Pořadí:** `seq` (int) u složek i requestů; ve stromu nejdřív složky, pak requesty, obojí dle `seq`, při shodě dle `name`. Po přesunu/vložení přečíslovat sourozence 1..n a zapsat jen změněné.
- **Duplicitní ID** (kopie souboru ve Finderu): při načtení stromu dostanou requesty se shodným ID nové ID; původní zůstane nejdříve vytvořenému souboru (`creationDate`), při shodě dle `rel`. V read-only projektu ne.
- **formatVersion:** projekt s vyšší verzí, než aplikace zná, otevřít jen pro čtení (banner „Aktualizujte MinorREST“).

### 2.3 `minorrest.yaml`
```yaml
formatVersion: 1
id: 01JCX6...                  # ULID; klíč pro Keychain a cookies
name: Můj projekt
description: ""
vars:
  - { name: baseUrl, value: "https://api.example.com", enabled: true }
headers:                       # dědí se do všech requestů
  - { name: Accept, value: application/json, enabled: true }
auth: { type: none }
settings:                      # chybějící položka = globální výchozí z nastavení aplikace
  httpVersion: auto            # v Swift verzi jen čteno a zachováno, neuplatňuje se (kap. 4.1)
  followRedirects: true
  maxRedirects: 10
  timeoutMs: 30000
  verifyTls: true
  cookieJar: true
ignoreResponsesInGit: true
```

### 2.4 `_folder.yaml`
```yaml
name: Uživatelé
seq: 1
vars: []          # jako u projektu
headers: []
auth: { type: inherit }
```

### 2.5 Request `*.req.yaml`
```yaml
id: 01JCX7...
name: Seznam uživatelů
seq: 3
method: GET                 # GET | POST | PUT | PATCH | DELETE | HEAD | OPTIONS
url: "{{baseUrl}}/users/:id" # BEZ query stringu a fragmentu
params:
  query:
    - { name: page, value: "{{page}}", enabled: true, description: "" }
  path:
    - { name: id, value: "42" }
headers:
  - { name: X-Trace, value: "{{$uuid}}", enabled: true }
auth: { type: inherit }     # inherit | none | basic | bearer | apikey | oauth2
body:
  type: none                # none | json | xml | text | html | form-urlencoded | multipart | binary
  raw: ""                   # json/xml/text/html
  form:
    - { name: q, value: "kůň", enabled: true }
  multipart:
    - { name: popis, kind: text, value: "Žluťoučký", enabled: true }
    - { name: soubor, kind: file, path: "data/foto.jpg", contentType: "", enabled: true }
  binaryPath: ""
vars: []                    # proměnné requestu
extract:                    # po odpovědi → runtime proměnná (F8)
  - { name: token, from: body, path: "$.data.token", enabled: true }   # from: body (JSONPath) | header (název)
settings: {}                # jen přepsané položky; chybějící = zděděno (Swift: optionals)
docs: ""
```
- **Zdroj pravdy pro query je `params.query`**, `url` na disku query neobsahuje. URL bar zobrazuje `url + "?" + zapnuté parametry` (bez kódování); při editaci se text za prvním `?` rozparsuje zpět do `params.query` (zapnuté řádky se nahradí v pořadí, popisy zůstanou, vypnuté řádky zůstávají na svých pozicích). Parametr bez `=` (`?wsdl`) dostane `bare: true` a odešle se bez `=`; `?flag=` i nový prázdný řádek se odešlou jako `flag=`. Parsování ručně (split `&`, `=`), ne přes `URLComponents` – nesmí se rozbít `{{proměnné}}`.
- `:nazev` v cestě (segment začínající `:`, ne port) → automaticky řádek v `params.path`; zmizí-li z URL, řádek odstranit (hodnoty se drží podle názvu).
- Cesty k souborům (`multipart.path`, `binaryPath`): uvnitř projektu relativně ke kořeni (s `/`), jinak absolutně; symlinky rozvinout (`/var` → `/private/var`).
- Chybějící `enabled` u KV/Var/multipart/extract = zapnuto.
- **YAML zápis:** prázdné sekce se nezapisují, pořadí klíčů dle struktury, odsazení 2, víceřádkové řetězce jako blokový literál `|`, řádky blokovým stylem → stabilní diffy v gitu. Implementace: čtení přes Yams (`compose` → vlastní `YAMLObject` s výchozími hodnotami), zápis **vlastním emitorem** `YAMLWriter` (kopie pravidel yaml.v3/libyaml pro volbu stylu řetězce – plain / `'…'` / `"…"` / `|`), protože Yams neodsazuje sekvence jako Go. Testy porovnávají bajtově s fixtures zapsanými Go verzí. Jediná záměrná odchylka: literál začínající novým řádkem (yaml.v3 ho ztrácí, my ne). Neplatný YAML → `YAML_INVALID`.

Auth bloky:
```yaml
auth: { type: basic, basic: { username: "{{user}}", password: "{{pass}}" } }
auth: { type: bearer, bearer: { token: "{{token}}", prefix: Bearer } }
auth: { type: apikey, apikey: { key: X-API-Key, value: "{{apiKey}}", in: header } }   # header | query
auth:
  type: oauth2
  oauth2:
    grantType: client_credentials   # client_credentials | authorization_code | password
    authUrl: ""
    tokenUrl: "{{baseUrl}}/oauth/token"
    clientId: "{{clientId}}"
    clientSecret: "{{clientSecret}}"
    scope: "read write"
    usePkce: true
    redirectPort: 0                 # 0 = náhodný volný port; redirect URI = http://127.0.0.1:<port>/callback
    username: ""
    password: ""
    clientAuth: header              # header (Basic) | body
    tokenPlacement: header          # header | query
    headerPrefix: Bearer
    autoRefresh: true
```

### 2.6 Uložené odpovědi (verzování)
`.responses/<requestId>/v0001.yaml` (metadata) + `v0001.body` (**tělo vždy v samostatném souboru**, dekomprimované bajty v původním kódování).
```yaml
version: 3
savedAt: "2026-11-16T15:04:05+01:00"
label: ""
request:                         # snímek odeslaného requestu
  method: POST
  url: https://api.example.com/users?page=2
  headers: [{ name: Authorization, value: "Bearer ***" }]   # maskování viz 2.8
  bodySize: 128
  body: "…"                      # jen textové tělo do 256 kB, jinak vynechat
response:
  status: 201
  statusText: Created
  proto: HTTP/2
  remoteAddr: "93.184.216.34:443"
  localAddr: "192.168.1.10:53122"
  tls: { version: "TLS 1.3", cipher: TLS_AES_128_GCM_SHA256, serverName: api.example.com, certSubject: "CN=…", certExpires: "2027-01-01T00:00:00Z" }
  headers: [{ name: Content-Type, value: "application/json; charset=utf-8" }]
  sizes: { reqHeaders: 310, reqBody: 128, headers: 412, bodyWire: 1830, bodyDecoded: 6402 }
  timing: { dnsMs: 4.1, connectMs: 12.3, tlsMs: 25.0, ttfbMs: 88.2, downloadMs: 3.4, totalMs: 133.0 }
  redirects: []
  contentType: application/json
  charset: utf-8
```
Číslo verze = nejvyšší existující + 1 (smazané se nerecyklují). Historie (2.1) používá stejný formát. Časy jako RFC 3339 řetězce.

### 2.7 Prostředí `environments/<slug>.yaml`
```yaml
id: 01JCX8...      # ULID – přežije přejmenování
name: Vývoj
vars:
  - { name: baseUrl, value: "http://localhost:8080", enabled: true }
  - { name: apiKey, secret: true, enabled: true }   # hodnota v Keychain, v YAML není
```

### 2.8 Tajemství
- `secret: true` lze nastavit u proměnných **prostředí a globálních**. Keychain: služba `MinorREST`, účet `<projectId>/<envId>/<name>` resp. `global/<name>`. Přejmenování proměnné = přesun položky; smazání proměnné/prostředí = smazání položek.
- Přístup přes **`SecItem` API** (`kSecClassGenericPassword`, legacy file keychain – data protection keychain potřebuje access group a Developer ID). Důsledek ad-hoc podpisu (schváleno uživatelem): po každé aktualizaci aplikace se změní podpis a macOS se jednou zeptá na povolení přístupu („Vždy povolit“). Položky vytvořené Go verzí (přes `security`) vyvolají při prvním čtení stejný dotaz. Limit hodnoty neřešíme (Keychain velké hodnoty unese); chyba zápisu → `SECRET_ERROR`.
- Auth pole (heslo, token, client secret) jsou obyčejná textová pole ukládaná do YAML. Pokud obsahují literál (ne `{{…}}`), zobrazit u pole varování s akcí **„Převést na tajnou proměnnou“** (vytvoří secret proměnnou v aktivním prostředí a pole nahradí `{{nazev}}`).
- **Maskování** (uložené odpovědi, historie, volitelně export): hodnoty hlaviček `Authorization`, `Proxy-Authorization`, `Cookie`, `Set-Cookie`, hlavičky/query z apikey auth a všechny výskyty hodnot secret proměnných → `***` (u `Authorization` zachovat schéma: `Bearer ***`).

## 3. Proměnné

- Syntaxe `{{nazev}}`, název `[A-Za-z0-9_.-]+`, mezery uvnitř závorek tolerovat. `\{{` = literál `{{`.
- **Priorita (vyšší vyhrává):** runtime → request → složky (nejbližší první) → prostředí → projekt → globální. Vypnuté (`enabled: false`) se ignorují.
- **Runtime proměnné:** jen v paměti, per projekt, plní je `extract` a zobrazují se v přehledu „oko“ (lze je tam smazat). Po restartu prázdné.
- Dynamické: `{{$uuid}}`, `{{$ulid}}`, `{{$timestamp}}`, `{{$timestampMs}}`, `{{$isoTimestamp}}`, `{{$randomInt}}` (0–1000), `{{$randomString}}` (16 znaků). Každý **výskyt** se vyhodnotí zvlášť, kromě `$timestamp*` (jedna hodnota na odeslání). Pojmenovaná proměnná má v rámci odeslání jednu hodnotu (`id: "{{$uuid}}"` → `{{id}}` všude stejné).
- Rekurze: hodnota může obsahovat proměnné, max hloubka 10, cyklus → chyba `VAR_CYCLE`.
- Neznámá proměnná: ponechat literál `{{x}}`, vrátit v seznamu `unresolved`; UI zobrazí nemodální varování (odeslání neblokuje). Výjimka: nevyhodnocená proměnná v hostu → chyba `VAR_UNRESOLVED_HOST` (detail = názvy; UI napoví vybrat prostředí).
- Platí v: URL, query, path, headers (název i hodnota), body raw/form/multipart (text, cesta, Content-Type části), binary cesta, všechna auth pole.
- **Sestavení URL při odeslání:** vyhodnotit proměnné v `url` → pokud chybí schéma, doplnit `http://` → nahradit `:param` (hodnota po vyhodnocení, percent-encoding pro segment cesty) → připojit zapnuté query parametry kódované `encodeQuery` (percent-encode UTF-8, mezera jako `%20`, `& = + #` kódovat, **existující platné `%XX` sekvence zachovat**, prázdná hodnota → `name=`, `bare` → `name`) → `URL(string:)` + kontrola hostu (chyba → `URL_INVALID`).
- API (`Vars`): `Resolver(scopes: [VarScope], now:)` (pořadí = priorita; `VarScope(.folder, ref:, vars:)`), `resolve(_:) throws -> (value: String, unresolved: [String])`, `unresolved`, `explain() -> [VarInfo{name, value, resolved, source, ref, secret}]` pro UI – tajné hodnoty se v `resolved` maskují `***`. `URLBuilder.build(_ url:, path:, query:, resolver:) throws -> String` (výsledek může obsahovat znaky k zakódování v cestě – zakóduje až HTTP vrstva, jako Go `net/http`), `URLBuilder.encodeQuery`, `encodeQueryComponent`. Kontrola URL napodobuje Go `url.Parse`: schéma, neprázdný host bez ` {}\^`|`, číselný port, `[IPv6]`, žádné řídicí znaky.

## 4. HTTP engine (`HTTP/`)

Vstup `PreparedRequest{method, url, headers [KV] (pořadí), body, baseDir, noAuto}` + `Options{followRedirects, maxRedirects, timeout, verifyTLS, userAgent, proxy, cookieJar, maxBodyBytes}`. Výstup `RunResult` (kap. 11).

- **Nová `URLSession` pro každé odeslání** (`URLSessionConfiguration.ephemeral`, vlastní delegát, `urlCache = nil`, `httpCookieStorage = nil`, `httpShouldSetCookies = false`, `requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData`) → žádné sdílení spojení mezi běhy, kompletní časování; po dokončení `finishTasksAndInvalidate()`.
- **HTTP verze:** vyjedná URLSession (ALPN: HTTP/1.1 / HTTP/2 / případně HTTP/3). Skutečná verze z `URLSessionTaskTransactionMetrics.networkProtocolName` (`http/1.1`, `h2`, `h3`) → `proto` `HTTP/1.1` / `HTTP/2` / `HTTP/3`.
- **TLS:** ověřování vypnuté (`verifyTLS = false`) → v `urlSession(_:didReceive:completionHandler:)` pro `NSURLAuthenticationMethodServerTrust` vrátit `URLCredential(trust:)`. Info z metrik (`negotiatedTLSProtocolVersion`, `negotiatedTLSCipherSuite`) + z `SecTrust` leaf certifikátu (subjekt, vydavatel, expirace přes `SecCertificateCopyValues`), SNI = host.
- **Redirecty:** `urlSession(_:task:willPerformHTTPRedirection:newRequest:)` – při `followRedirects = false` vrátit `nil` (odpovědí je 3xx); jinak limit `maxRedirects` (překročení → zrušit s `REDIRECT_LIMIT`). Každý skok `{status, method, url, location}`. Nový request po 307/308 zachová metodu a tělo, po 301–303 URLSession přepne na GET (zaznamenat). Uživatelské hlavičky přenést do nového requestu (kromě `Authorization` při změně hostu – URLSession ji při redirectu zahodí vždy, engine ji vrací jen pro původní host, ověřeno v F4/4); cookie jar doplní cookies pro nový host.
- **Timing:** `urlSession(_:task:didFinishCollecting:)` → `transactionMetrics` (jedna transakce na skok); do `timing` jde **poslední skok**: `dnsMs` (domainLookupStart→End), `connectMs` (connectStart→End bez TLS), `tlsMs` (secureConnectionStart→End), `ttfbMs` (requestEnd→responseStart), `downloadMs` (responseStart→responseEnd), `totalMs` = `taskInterval` (+ čtení těla); `reused` = `isReusedConnection`.
- **IP adresy:** `remoteAddress`/`remotePort`, `localAddress`/`localPort` posledního skoku. `resolvedAddrs` (všechny adresy z DNS) URLSession nedává → vypuštěno.
- **Odeslané hlavičky:** `task.currentRequest?.allHTTPHeaderFields` + hlavičky, které doplní systém a lze je odvodit (`Host`, `Connection: keep-alive` u HTTP/1.1, `Cache-Control: no-cache` kvůli politice cache; `Content-Length`, `Accept-Encoding`, `Accept-Language` už v `currentRequest` jsou – ověřeno v F4/2 proti echo serveru). Pořadí odeslání ani HTTP/2 pseudo-hlavičky nejsou dostupné → záložka „Odesláno“ to uvádí poznámkou. Velikosti hlaviček z metrik (`countOfRequestHeaderBytesSent`).
- **Hlavičky requestu:** `Host` a `Content-Length` nelze nastavit (URLSession je určuje sám; uživatelskou hodnotu ignorovat s varováním v UI). Automatické hlavičky, pokud je uživatel nezadal: `User-Agent: MinorREST/<verze>`, `Accept: */*`, `Content-Type` dle typu body; `Accept-Encoding` doplňuje URLSession (`gzip, deflate, br`). V UI šedě a jdou vypnout (`User-Agent`, `Accept`, `Content-Type`; vypnutí = řádek se stejným názvem a `enabled: false`); vypnutý `User-Agent` = prázdná hodnota (jinak by systém doplnil vlastní) – **ověřit v F4/1**.
- **Komprese:** URLSession dekóduje `gzip`, `deflate`, `br` automaticky (vypnout nejde). Velikosti: `bodyWire` = `countOfResponseBodyBytesReceived`, `bodyDecoded` = `countOfResponseBodyBytesAfterDecoding`. Neznámé kódování (např. `zstd`) zůstane nedekódované.
- **Velikosti:** `reqHeaders` = `countOfRequestHeaderBytesSent`, `reqBody` = `countOfRequestBodyBytesSent`, `headers` = `countOfResponseHeaderBytesReceived`, `bodyWire`, `bodyDecoded` (HTTP/2: komprimované HPACK hodnoty dle systému – uvést v tooltipu).
- **Tělo odpovědi – limity:** `dataTask` s delegátem, `didReceive data` → do 10 MB v paměti, pak temp soubor (`FileManager.temporaryDirectory`), nad `maxBodyBytes` (výchozí 100 MB) zrušit čtení a `truncated: true` (odpověď platí). Engine drží posledních 20 výsledků (LRU, `runID → Result`), temp soubory maže při vyřazení a ukončení.
- **Kódování textu:** `charset` z `Content-Type` (`CFStringConvertIANACharSetNameToEncoding`), JSON bez charsetu = UTF-8, jinak odhad (platné UTF-8 → utf-8, jinak `NSString.stringEncoding(for:…)`); pro zobrazení převést do UTF-8 (`windows-1250`, `iso-8859-2`). Uložené tělo zůstává v původních bajtech. Binární obsah (netextový Content-Type a vzorek není text) → `isBinary: true`.
- **Tělo requestu:** JSON/XML/text/HTML jako UTF-8, `Content-Type` s `; charset=utf-8` (jen pokud ho doplňujeme). Form-urlencoded: vlastní encoder se zachováním pořadí (plné kódování). Multipart: vlastní builder (boundary, `filename="…"` v UTF-8, `Content-Type` části z přípony přes `UTType`), soubory streamem (`httpBodyStream` / `uploadTask(fromFile:)` pro binary). Uživatelský `multipart/…` Content-Type bez boundary → boundary doplnit. Relativní cesty vůči `baseDir`. Chybějící soubor → `FILE_NOT_FOUND`. GET/HEAD s tělem: ověřit chování URLSession v F4/1 (případně chyba `BODY_NOT_ALLOWED`).
- **Zrušení/timeout:** celkový timeout přes vlastní `Task` s limitem (ne `timeoutIntervalForRequest`, ten je jen na nečinnost) → `task.cancel()` s příčinou; `cancel(runID)` → `CANCELED`, vypršení → `NET_TIMEOUT`. Při chybě vrátit i částečný výsledek (odeslané, timing, redirecty).
- **Mapování chyb (`URLError.Code`):** `.cannotFindHost`, `.dnsLookupFailed` → `NET_DNS`; `.cannotConnectToHost` → `NET_REFUSED`; `.timedOut` → `NET_TIMEOUT`; `.serverCertificate*`, `.clientCertificate*` → `TLS_VERIFY`; `.secureConnectionFailed` → `TLS_ERROR`; `.cancelled` → `CANCELED` (dle příčiny); `.httpTooManyRedirects` → `REDIRECT_LIMIT`; `.badURL`, `.unsupportedURL` → `URL_INVALID`; jinak `NET_ERROR` (+ `localizedDescription` jako detail).
- **Cookies:** vlastní jar per projekt (`[Cookie]`, parsování přes `HTTPCookie.cookies(withResponseHeaderFields:for:)` po jednotlivých `Set-Cookie`, párování domény/cesty/Secure/expirace vlastní dle RFC 6265 – `HTTPCookie` přijme i cizí `Domain`), uplatnit i na skoky redirectu, perzistence `cookies/<projectId>.json` (JSON pole `Cookie`, i relační cookies) po každém odeslání; vypnutelné (`cookieJar`). Uživatelská hlavička `Cookie` se odešle a cookies z jaru se připojí za ni. Sloučené `Set-Cookie` z `allHeaderFields` se dělí na čárce před `název=` (čárka v `Expires` zůstane) → samostatné řádky v `headers`.
- **Proxy:** `system` (výchozí – URLSession použije systémové nastavení **včetně PAC**), `none` (`connectionProxyDictionary = [:]`), `manual` (HTTP/HTTPS proxy host:port).

### 4.1 Omezení URLSession oproti rev. 2 (schváleno volbou URLSession)
Nelze: vynutit HTTP/1.1 vs HTTP/2 ani h2c (nastavení `httpVersion` se v UI nezobrazuje, z YAML se jen zachová), nastavit vlastní `Host`, vypnout automatickou dekompresi a `Accept-Encoding`, zjistit přesné pořadí odeslaných hlaviček a HTTP/2 pseudo-hlavičky, seznam všech DNS adres. Export cURL proto nevypisuje `--http1.1`/`--http2`.

Ověřeno v F4/1: GET/HEAD s tělem URLSession odmítne (`NSURLErrorDataLengthExceedsMaximum`, i jako stream) → engine vrátí `BODY_NOT_ALLOWED` ještě před odesláním (prázdné tělo se u GET/HEAD tiše vynechá, bez `Content-Type`). Vypnutý `User-Agent`/`Accept` = hlavička s prázdnou hodnotou (bez ní systém doplní vlastní; úplně vynechat nejde). `Authorization` se odešle beze změny. Po 302 URLSession mění na GET jen POST (PUT/PATCH/DELETE zůstanou), 303 vždy na GET. `HTTPURLResponse.allHeaderFields` spojuje opakované hlavičky (i `Set-Cookie`) do jedné hodnoty – řeší F4/4. Text stavu (`statusText`) je ze standardní tabulky (reason phrase serveru URLSession nedává).

- Testy: lokální testovací HTTP/1.1 server v testech (`Network.framework` `NWListener`, malý parser requestu) – metody, hlavičky, těla, redirect on/off/limit, gzip velikosti, windows-1250 → UTF-8, timeout, cancel, chyby (DNS na `.invalid`, refused na volném portu). HTTP/2 a TLS ověřit ručně proti veřejnému HTTPS serveru (QA checklist).

## 5. Autorizace (`Auth/`)

`apply(to: inout PreparedRequest, auth: Auth, deps) async throws` – volá se v `prepare` po vyhodnocení proměnných v polích auth.
- **inherit:** od requestu přes složky nahoru k projektu, první ne-`inherit` vyhrává; projekt s `inherit` = `none`. `prepare` vrací i `authSource` (odkud se zdědilo) pro UI.
- **basic:** `base64(utf8(user + ":" + pass))`. **bearer:** `Authorization: <prefix> <token>`. **apikey:** hlavička nebo query parametr.
- Uživatelem ručně zadaná hlavička `Authorization` má přednost před auth (v UI varování). (`Authorization` nastavená na `URLRequest` se odešle – ověřeno v F7/1.) Totéž platí pro hlavičku/query parametr API klíče se stejným názvem. Prázdný token/klíč nebo prázdné jméno i heslo = auth se nepřidá; prázdný prefix bearer = `Bearer`.
- **oauth2** (vlastní implementace, token endpoint přes stejný engine – stejné TLS/proxy nastavení jako request):
  - `clientAuth`: `header` (Basic `client_id:client_secret`, URL-encoded dle RFC 6749) / `body`.
  - authorization_code: `NWListener` na `127.0.0.1:<redirectPort>`, `state` (náhodných 32 B) + PKCE S256 (`CryptoKit.SHA256`), otevřít prohlížeč (`NSWorkspace.open`), čekat na `/callback` max 5 min (zrušitelné z UI), odpovědět HTML stránkou „Hotovo, okno můžete zavřít“, vyměnit code za token.
  - Cache: klíč `sha256(tokenUrl|clientId|scope|grantType|username)[:16]`; do Keychain zvlášť `…/oauth/<klíč>/access` a `…/refresh`, expirace, typ a scope jako JSON v třetí položce `…/oauth/<klíč>/meta` (+ paměť; `workspace.yaml` se nepoužije – jednodušší, bez zápisu do gitu). `tokenPlacement: query` posílá `access_token=<token>`. Chyba token endpointu = `OAUTH_TOKEN_ERROR` (detail `HTTP <status>: <error> – <popis>`).
  - Před odesláním: platný token použít; expirovaný (rezerva 30 s) → refresh, při neúspěchu u client_credentials/password získat nový automaticky, u authorization_code vrátit `OAUTH_LOGIN_REQUIRED` (UI nabídne „Přihlásit“).
- Digest = backlog.

## 6. Export – kopírování jedním klikem (`Export/`)

Ikona ⧉ vedle „Odeslat“: klik = zkopíruje v naposledy zvoleném formátu + toast; šipka = výběr:
1. **cURL – víceřádkový** (výchozí; ` \` + odsazení 2 mezery, jeden flag na řádek)
2. **cURL – jeden řádek**

Vstup je stejný `PreparedRequest` jako pro odeslání (vyhodnocené proměnné, auth, path params, query) → export = přesně to, co by se odeslalo. OAuth2: token z cache, bez tokenu → `OAUTH_LOGIN_REQUIRED`.

Pravidla cURL:
- Quoting: vše v single quotes; `'` uvnitř → `'\''`. Diakritika zůstává UTF-8. Žádné `$'…'`.
- Metoda: GET bez těla → nic; **HEAD → `--head`**; jinak `-X METHOD`.
- `-H 'Name: value'` pro uživatelské/zděděné/auth hlavičky a automatický `Content-Type`; nevypisovat automatické `User-Agent`, `Accept`, `Host`, `Content-Length`. Vždy `--compressed` (URLSession dekomprimuje vždy).
- Tělo: raw → `--data-raw '…'`; form → `--data-urlencode 'name=value'` za každé pole; multipart → `-F 'name=value'` / `-F 'name=@/abs/cesta;type=…'`; binary → `--data-binary '@/abs/cesta'`.
- Volby: `-L --max-redirs N` pokud follow; `-k` pokud verifyTls=false; `--max-time <s>`.
- cURL se kopíruje vždy víceřádkový. Přepínač „Při kopírování maskovat tajné hodnoty“ (výchozí vypnuto, pravidla 2.8); při zapnutí hláška/poznámka, že `***` je před spuštěním nutné nahradit skutečnou hodnotou.

Testy: parametrizované („golden“) – diakritika (`Příliš žluťoučký kůň úpěl ďábelské ódy`), apostrof, `$HOME`, `!`, zpětné lomítko, víceřádkový JSON, multipart se souborem, HEAD, všechny volby.

**Import cURL** (`Import/Curl`): vlastní shell tokenizér (single/double quotes, `\` escape, předtím odstranit `\`+newline), flagy `-X/--request, -H, -d/--data/--data-raw/--data-binary/--data-urlencode, -F/--form, -u, --url, -L, -k, -I/--head, --compressed, -b, -A` (`--http1.1/--http2` přijmout a ignorovat); neznámé flagy ignorovat a vrátit ve `warnings`. `-d` bez `-X` → POST; JSON tělo → `body.type: json`; `-u` → basic auth; query z URL → `params.query`.

## 7. Import OpenAPI / Swagger (`Import/OpenAPI`)

- Vlastní `Decodable` model jen potřebné podmnožiny (paths, operations, parameters, requestBody, components/definitions, securitySchemes, servers / host+basePath+schemes, tags) pro **Swagger 2.0 i OpenAPI 3.0/3.1**, JSON i YAML (Yams). Vlastní resolver `$ref` (lokální `#/…`) s detekcí cyklu. Zdroj: soubor nebo URL. (Knihovna OpenAPIKit neumí 2.0 → nepoužívat.)
- **Dva kroky:** (1) obě verze převést na neutrální `Spec{title, description, servers, security…, operations [Operation{method, path, tag, summary, description, params, body}]}`; (2) jeden generátor `Spec` → projekt/složky/requesty. Testuje se hlavně krok 2.
- Mapování:
  - `info.title` → název projektu; alternativně import do existujícího projektu jako nová složka,
  - první tag operace → složka (název tagu), bez tagu → „Ostatní“ / „Other“; alternativa seskupení dle prvního segmentu cesty,
  - název requestu: `summary` → `operationId` → `METHOD /path`; `description` → `docs`; `seq` dle pořadí ve specifikaci,
  - servery (3.x `servers[].url` s dosazenými default proměnnými / 2.0 `schemes://host/basePath`) → proměnná `baseUrl`; první server = prostředí „Default“, další = další prostředí; `url` requestu = `{{baseUrl}}/path`,
  - `{id}` → `:id` + `params.path` (hodnota z `example`/`default`),
  - query a header parametry → `params.query` / `headers` (required → zapnuté, ostatní vypnuté; hodnota z example/default/enum[0]),
  - tělo: preferovat `application/json` → `example` → první z `examples` → vygenerovat ze schématu (object rekurzivně, array s 1 prvkem, enum[0], default, dle `format`: date-time/date/uuid/email/uri → ukázka, string → `"string"`, number → `0`, boolean → `false`; `allOf` sloučit, `oneOf/anyOf` první; **max hloubka 6 a detekce cyklických `$ref`**); form typy → `form` / `multipart`,
  - `securitySchemes` + globální `security` → auth projektu: http basic → basic `{{username}}/{{password}}`; http bearer → bearer `{{token}}`; apiKey → apikey `{{apiKey}}`; oauth2 → oauth2 (první flow, URL, scopes); odpovídající prázdné proměnné založit v projektu. Requesty mají `inherit`; operace se `security: []` → `none`.
- Průvodce (sheet): zdroj (soubor / URL / drop) → náhled (název, počty složek a requestů, varování) → cíl (nový projekt / existující) a seskupení → Import.
- Testy: fixtures Petstore 2.0, Petstore 3.0, malá 3.1 s `$ref` cyklem.

Postman Collection v2.1 (`Import/Postman`, volitelné v F10): item/folder → strom, `request` (method, url.raw, header, body modes raw/urlencoded/formdata), `auth` (basic/bearer/apikey/oauth2), `variable` → proměnné projektu; skripty ignorovat s varováním.

## 8. UI / UX

### 8.1 Rozvržení
```
┌───────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●  [Projekt ▾]                         [Prostředí: Vývoj ▾] [👁] [⚙]      │  ← unified toolbar
├──────────────┬────────────────────────────────────────────────────────────────┤
│ Projekt|Historie│ [GET Seznam ×][POST Login ●][+]                              │
│ 🔍 Hledat…   │ [GET ▾] [{{baseUrl}}/users?page=2            ] [⧉▾] [Odeslat ▸] │
│ ▾ 📁 Uživatelé│ Params | Body | Headers (3) | Auth | Nastavení | Dokumentace  │
│   GET Seznam │ ┌ KvEditor ───────────────────────────────────────────────────┐ │
│   POST Vytvoř│ │ ☑ page   {{page}}   popis                       [Bulk edit] │ │
│ ▸ 📁 Objednáv│ └─────────────────────────────────────────────────────────────┘ │
│              ├────────────────────────────────────────────────────────────────┤
│              │ [201 Created] 133 ms  6,4 kB  HTTP/2  93.184.216.34:443  [💾 Uložit] │
│              │ Tělo | Hlavičky (12) | Cookies | Časování | Odesláno | Verze (3)│
│              │ [Pretty|Raw|Náhled]  🔍  JSONPath filtr                          │
└──────────────┴────────────────────────────────────────────────────────────────┘
```
- `NavigationSplitView` (sidebar skrytelný Cmd+B – stav ve workspace; šířku sidebaru a rámec okna si ukládá AppKit sám v předvolbách, `workspace.sidebarWidth` se jen zachovává kvůli kompatibilitě) + vlastní `ResponseSplit` request/odpověď (dole výchozí, nebo vpravo; `VSplitView` neuplatní uloženou výšku), výška odpovědi ve workspace.
- Barvy metod: GET zelená, POST oranžová, PUT modrá, PATCH fialová, DELETE červená, HEAD šedá, OPTIONS tyrkysová (asset barvy se světlou/tmavou variantou, hodnoty jako rev. 2).
- **Status badge:** 1xx šedá, 2xx zelená, 3xx modrá, 4xx oranžová, 5xx červená; text `201 Created`; tooltip = lokalizovaný popis kódu (`status.<kód>`). Chyba sítě = červený panel s lokalizovanou chybou + detail.
- Popover času: vodopád DNS / TCP / TLS / TTFB / Download. Popover velikosti: odpověď hlavičky / tělo (přenesené → dekomprimované), request hlavičky / tělo.
- Čísla přes `FormatStyle` dle jazyka UI (cs: `6,4 kB`, `1 234 ms`); jednotky B / kB / MB (1 kB = 1000 B), čas ms do 1000, pak s.

### 8.2 Sidebar
- Záložky **Projekt** (strom) a **Historie** (posledních N odeslání: čas, metoda, URL, status; klik otevře detail odpovědi jen pro čtení + „Otevřít request“).
- Přepínač projektů (toolbar menu): seznam otevřených + „Nový projekt…“, „Otevřít adresář…“ (adresář bez projektu → nabídnout založení, název = název adresáře), „Importovat OpenAPI…“, „Nastavení projektu“, „Zavřít projekt“.
- Strom (`NSOutlineView`): složky rozbalitelné (stav ve workspace), requesty s badge metody. Dvojklik/Enter = otevřít v tabu, F2 = přejmenovat, Cmd+Backspace = smazat.
- Kontextové menu (nativní `NSMenu`): Nový request, Nová složka, Přejmenovat, Duplikovat, Kopírovat jako cURL, Nastavení složky, Zobrazit ve Finderu, Smazat (potvrzení → Koš). Na prázdné ploše: Nový request, Nová složka.
- **Nový request** se hned vytvoří na disku s názvem „Nový request“ (GET, prázdná URL), otevře se v tabu a název je v inline editaci. Žádné „koncepty jen v paměti“.
- Drag & drop (`NSOutlineView` pasteboard): přesun mezi složkami + pořadí, indikátor místa vložení; složku nelze vložit do sebe sama; podržení nad sbalenou složkou ji rozbalí.
- Hledání: filtr podle názvu, URL a metody (bez ohledu na diakritiku a velikost písmen – `folding(options: [.diacriticInsensitive, .caseInsensitive])`); zobrazí shody včetně nadřazených složek, u shody složky celý podstrom. Během filtru DnD vypnutý.
- **Watcher** (`Watch/`: `FSEventStreamCreate` s `kFSEventStreamCreateFlagFileEvents | IgnoreSelf | NoDefer`, latence 0,3 s, jeden stream na projekt; ignorovat `.git`, `.responses`, `.tmp-*`): po změně znovu načíst strom; změněné `*.req.yaml` → otevřený tab bez lokálních změn tiše znovu načíst, s lokálními změnami banner „Změněno na disku: Načíst z disku / Ponechat moje“. Změna `minorrest.yaml`, `_folder.yaml` a prostředí → znovu načíst konfiguraci.

### 8.3 Editor requestu
- **`VarField`** – jednořádkové pole se zvýrazněním proměnných, použité všude (URL bar, buňky KvEditoru, auth pole): známá proměnná zeleně, neznámá červeně, dynamická `$` modře, `\{{` jako text. Hover nad tokenem → popover s hodnotou a zdrojem (secret jako `••••`). Po napsání `{{` našeptávač.
- URL bar: Enter = odeslat; vložení textu začínajícího `curl ` → nabídka „Importovat cURL do tohoto requestu“.
- **`KvEditor`** (query, path, headers, form, multipart, vars, extract): checkbox, klíč, hodnota (`VarField`), popis, smazat; psaní do posledního prázdného („duch“) řádku vytvoří nový bez ztráty fokusu; přetažení pořadí; **Bulk edit** (textová plocha, řádek `klíč: hodnota`, prefix `//` = vypnutý; popis se zachová podle klíče). U headers našeptávač názvů a běžných hodnot; nad tabulkou sbalitelný blok „Automatické a zděděné hlavičky“ (šedě, se zdrojem, s možností vypnout).
- Body: přepínač typu (data ostatních typů se zachovají). Raw = `CodeTextView` (jazyk dle typu), „Formátovat“ (jádro `JSONFormatter`) a validace jen jako varování. **Formátování JSON dělá vlastní tokenizér v jádře** (odsazení 2 mezery, zachová přesný text čísel a pořadí klíčů) – nikdy `JSONSerialization`. Proměnné mimo řetězce (`{"id": {{id}}}`) tokenizér bere jako hodnotu. Chyba → `JSON_INVALID: <řádek>: …`.
- Form/multipart = KvEditor (multipart: text/soubor, výběr souboru `NSOpenPanel` nebo drop, sloupec Content-Type). Binary = výběr souboru.
- Auth: výběr typu + formulář; u `inherit` řádek „Zděděno z: Složka X → Basic“. OAuth2 panel: stav tokenu, expirace, Získat token / Obnovit / Smazat.
- Nastavení: redirecty, max redirectů, timeout, TLS – každé „Zdědit (aktuálně: …)“ / vlastní hodnota.
- Dokumentace: `CodeTextView` markdown, bez náhledu (backlog).
- Taby (vlastní lišta): tečka = neuložené změny; Cmd+S uloží; zavření neuloženého → Uložit / Zahodit / Zrušit. **Odeslat funguje i bez uložení** (odesílá se stav tabu). Otevřené taby se obnoví po restartu, sledují přejmenování/přesun (podle ID). Uložení nepřepíše ID, název a `seq` (patří stromu).

### 8.4 Odpověď
- **Tělo:** Pretty (JSON přes `JSONFormatter`, XML/HTML odsazení v jádře; `CodeTextView` read-only, obarvení, Cmd+F), Raw (text v UTF-8 bez úprav), Náhled (HTML: `WKWebView` s vypnutým JavaScriptem a bez síťových požadavků; obrázky: `NSImage` do 10 MB). Výchozí pohled dle Content-Type.
- Binární nebo oříznuté tělo → informační panel (typ, velikost) + „Uložit do souboru“.
- Tělo do 10 MB se zobrazuje celé; > 5 MB: Pretty se nespouští automaticky („Přesto formátovat“). Tělo > 10 MB: zobrazit první 1 MB (jen Raw, bez filtru) + „Uložit do souboru“.
- JSONPath filtr (vlastní implementace RFC 9535: selektory jméno/`*`/index/slice/sjednocení, `..`, filtry `?…` s porovnáním, `&& || !`, testem existence a funkcemi `length/count/match/search/value`; výsledek vždy jako formátované pole shod; chybný výraz → červený rámeček s popisem v tooltipu; jen pro JSON tělo zobrazené celé).
- Hlavičky (tabulka, kopírování hodnoty), Cookies (z `Set-Cookie`), Časování (vodopád, IP vzdálená/lokální, protokol, TLS detail), Odesláno (hlavičky + tělo requestu, poznámka o omezení 4.1), Redirecty (jen pokud byly), Verze.
- Akce: **Uložit odpověď** (Cmd+Shift+S, volitelný popisek), Kopírovat tělo, Uložit tělo do souboru (`NSSavePanel`).
- Stavy panelu: prázdný (nápověda Cmd+Enter), odesílání (spinner, uplynulý čas, Zrušit), odpověď, chyba.

### 8.5 Prostředí a proměnné
- Výběr prostředí v toolbaru („Žádné“ + seznam + „Spravovat…“), Cmd+E.
- „Oko“: popover se všemi platnými proměnnými pro aktivní tab (název, hodnota, zdroj), runtime proměnné lze smazat.
- Okno/sheet „Prostředí“: seznam vlevo (přidat, duplikovat, přejmenovat, smazat), KvEditor vpravo se sloupcem 🔒 (secret; hodnota `••••` + zobrazit). Záložky: Prostředí | Proměnné projektu | Globální.
- Proměnné, hlavičky a auth složky: sheet „Nastavení složky“; totéž pro projekt („Nastavení projektu“ + HTTP nastavení + `ignoreResponsesInGit`).

### 8.6 Fonty a vzhled
- Ne-retina (`backingScaleFactor < 2`): Menlo 13 pro UI i kód. Retina: systémový font (SF Pro) pro UI, `.monospaced` (SF Mono) pro kód. Přepočet při přesunu okna mezi monitory. Nastavení může přepsat: Automaticky / vlastní rodina + velikost zvlášť pro UI a kód.
- Téma Systém / Světlé / Tmavé (`preferredColorScheme` + `NSApp.appearance`); barvy jako asset/semantické barvy, `CodeTextView` téma ze stejných barev.
- Nativní ovládací prvky SwiftUI/AppKit; vlastní jen MethodBadge, StatusBadge, TabBar, Toast, Banner.

### 8.7 Zkratky
V menu (`Commands`): Cmd+N nový request, Cmd+Shift+N nová složka, Cmd+S uložit, Cmd+Shift+S uložit odpověď, Cmd+W zavřít tab, Cmd+K paleta, Cmd+E prostředí, Cmd+B sidebar, Cmd+, nastavení (scéna `Settings`), Cmd+Shift+C kopírovat jako cURL, Cmd+L fokus URL, Cmd+D duplikovat, Cmd+Enter odeslat, Cmd+. zrušit.
Jen lokálně: Escape zavřít popover/sheet, F2 přejmenovat ve stromu, Enter v URL baru odeslat.

### 8.8 i18n
- `Localizable.xcstrings` (cs, en), ploché klíče s tečkami, `t(key, args…)`, jazyk `auto | cs | en` (`auto` = preferovaný jazyk systému). Žádný natvrdo psaný text ve views. Kontrola úplnosti: skript porovná klíče obou jazyků (F11).
- Menu i `Info.plist` texty lokalizované stejným mechanismem; přepnutí jazyka za běhu překreslí UI i menu.

## 9. Nastavení aplikace (`settings.yaml`, okno Cmd+,)
- **Obecné:** jazyk, výchozí adresář projektů, obnovit projekty a taby při startu, při kopírování maskovat tajné hodnoty. Téma vždy dle systému (bez volby).
- **Vzhled:** font UI a kódu (Automaticky dle displeje / vlastní), velikost, poloha panelu odpovědi.
- **Requesty (výchozí):** redirecty + max, timeout (v sekundách, uložený jako `timeoutMs`), ověřování TLS, User-Agent, cookie jar; sekce Odpovědi: max velikost těla, délka historie, práh automatického formátování. Proxy je vždy systémová (bez nastavení).
- **Aktualizace:** automaticky kontrolovat a stahovat (výchozí **zapnuto**), „Zkontrolovat nyní“, aktuální verze.
Změny se projeví ihned bez restartu. Priorita HTTP nastavení: request → projekt → globální.

## 10. Automatické aktualizace a release

Repozitář a releasy jsou veřejné → updater nepotřebuje token.

- Verze: vždy jen `MAJOR.MINOR.PATCH` (např. `0.3.5`) – bez `v`, bez hashe a čísla buildu; stejný tvar má i git tag. `MARKETING_VERSION` = `CURRENT_PROJECT_VERSION` = verze z tagu (About panel pak nezobrazuje „(build)“), vývojový build `0.0.0` (kontrola aktualizací vypnutá).
- **Vlastní updater (rozhodnutí uživatele 2026-11-23, místo Sparkle):** `MinorRESTCore/Updates` – feed `appcast.json` (asset posledního releasu: version, url, sha256, signature, notes), podpis ed25519 sdíleným klíčem MinorUpdate (zpráva `minorupdate-v1\n<bundle ID>\n<verze>\n<sha256>`, privátní klíč jen v Keychainu, podepisuje se lokálně `scripts/release.sh`), veřejný klíč `MRUpdatePublicKey` v `Info.plist`; kontrola bundle ID a verze, výměna bundlu při ukončení/„Restartovat“ s rollbackem. UI: `App/Features/Updates`, sekce v Nastavení, menu. Podrobně `docs/RELEASE.md`.
- Nelze aktualizovat z translokované cesty (`/AppTranslocation/`) → vyzvat k přesunu do `/Applications`.
- **První ruční instalace (README):** aplikace není notarizovaná → po přetažení do `/Applications` buď `xattr -dr com.apple.quarantine /Applications/MinorREST.app`, nebo Nastavení systému → Soukromí a zabezpečení → „Přesto otevřít“.
- **`ci.yml`** (push/PR, `macos-15`+): `swift test` v `Packages/MinorRESTCore`; `brew install xcodegen && make build`.
- **Vydání:** lokálně `scripts/release.sh <verze>` (build, ad-hoc podpis, zip, podepsaný `appcast.json`), publikace `gh release create` jen na pokyn; žádný `release.yml` (klíč nesmí do CI).
- `Info.plist`: `LSMinimumSystemVersion` 15.0, `CFBundleIdentifier` viz kap. 0.

## 11. API jádra pro UI (`MinorRESTCore`)

Názvy jsou závazné (odpovídají bindingům rev. 2); drobné úpravy signatur jsou v pořádku, ale zapiš je sem. Všechny chyby jsou `CoreError`.

### 11.1 Služby
```swift
// Projekty a strom (F1, F2)
actor ProjectRegistry {                                          // init(trash:) – Koš lze v testech nahradit
  func open(_ root: URL) throws -> Project                       // stejné ID → už otevřená instance
  func add(_ p: Project) -> Project; func project(_ id: String) throws -> Project
  func close(_ id: String) throws; func list() -> [ProjectInfo]; func paths() -> [String]
}
final class Project: @unchecked Sendable {                       // operace serializované zámkem
  static func create(name: String, in parentDir: URL, trash:) throws -> Project   // podadresář <slug>
  static func initProject(at: URL, name: String, trash:) throws -> Project; static func isProjectDir(_:) -> Bool
  static func open(_ root: URL, trash:) throws -> Project
  let root: URL; let readOnly: Bool; var info: ProjectInfo; var config: ProjectConfig
  func saveConfig(_:) throws; func reloadConfig() throws
  func loadTree() throws -> TreeNode                             // {kind, rel, name, seq, id, method, url, error, children}
  func createFolder(parent: String, name: String) throws -> TreeNode
  func createRequest(parent: String, name: String) throws -> TreeNode
  func rename(_ rel: String, to: String) throws -> TreeNode      // vrací nový rel
  func move(_ rel: String, to parent: String, index: Int) throws -> TreeNode
  func duplicate(_ rel: String, copySuffix: String = "") throws -> TreeNode   // "" = „ kopie“
  func delete(_ rel: String) throws                              // Koš
  func loadRequest(_ rel: String) throws -> Request
  func saveRequest(_ rel: String, _ r: Request) throws           // id, name, seq se převezmou z disku
  func loadFolderConfig(_ rel: String) throws -> FolderConfig; func saveFolderConfig(_ rel: String, _: FolderConfig) throws
  func fileRef(_ path: String) -> String                         // uvnitř projektu relativní (s /), jinak absolutní
  func absoluteURL(_ rel: String) throws -> URL
}
struct Workspace { projects, activeProject, expanded [projectID: [rel]], tabs [projectID: [requestID]],
                   activeTab [projectID: requestID], sidebarHidden, sidebarWidth, responseHeight, activeEnvironment [projectID: envID] }
  // static load(from: URL) throws, save(to: URL) throws, appDirectory, defaultProjectsDirectory
final class ProjectWatcher { init(ignoreSelf: Bool = true, onChange: @Sendable (projectID, [rel]?) -> Void); add(id:root:); remove(id:) }  // onChange na vlastní frontě

extension TreeNode { static parent(of:), find(_ rel:), static fold(_:), filtered(_ query:) -> TreeNode,
                    moveIndex(of: dragged, before child: Int?) -> Int? }   // hledání a DnD ve stromu (F2/3)
extension TreeNode { findRequest(id:) -> TreeNode? }               // taby podle ID (F3/1)
enum URLBar { static compose(url:query:) -> String; static parse(_ text:, query:) -> (url, query) }   // F3/1
struct VarToken { range: NSRange (UTF-16), name, kind: .variable | .dynamic; static scan(_:) -> [VarToken] }  // zvýraznění
enum KVBulk { static text(_ rows: [KV]) -> String; static parse(_ text:, prev: [KV], allowBare: Bool) -> [KV] }   // F3/2
enum PathParams { static names(_ url:) -> [String]; static sync(_ url:, _ path: [PathParam]) -> [PathParam]? }
enum HeaderHints { static names; static values(for:) -> [String]; static complete(_ prefix:, in:) -> [String] }
enum Syntax { static tokens(_ text:, _ lang: SyntaxLang) -> [SyntaxToken] }   // zvýraznění v CodeTextView (F3/3); SyntaxLang(bodyType:), .markdown (F3/4)
extension HTTPSettings { static let builtin; func over(_ base:) -> HTTPSettings }   // zděděné hodnoty v záložce Nastavení (F3/4)

// JSON (F1/F3)
enum JSONFormatter { static func format(_ text: String) throws -> String; static func validate(_:) -> CoreError? }
enum JSONValue { static parse(_:) throws -> JSONValue; var compact: String }   // pořadí klíčů a text čísel zachovány
struct JSONPath { init(_ expr:) throws /* JSONPATH_INVALID: <pozice>: … */; select(_ root:) -> [JSONValue]; static filter(json:_ expr:) throws -> String }

// Odeslání (F4, F5)
actor HTTPEngine {                                                                  // Options = HTTPEngine.Options (init z HTTPSettings + userAgent)
  func send(runID: String, _ r: PreparedRequest, _ o: Options, jar: CookieJar? = nil) async -> RunResult   // chyby v RunResult.error; jar jen při o.cookieJar
  func rawBody(runID: String, limit: Int) throws -> Data                            // začátek surového těla (historie)
  func cancel(runID: String)
  func body(runID: String, pretty: Bool) throws -> BodyView                         // RUN_NOT_FOUND
  func filter(runID: String, jsonPath: String) throws -> String
  func saveBody(runID: String, to: URL) throws
  func close()                                                                      // smaže výsledky a temp soubory (ukončení aplikace)
}
enum Prepare { static func prepare(_ in: PrepareInput) async throws -> Prepared }   // {request, options, unresolved, authSource, secrets}
  // PrepareInput{request, project: ProjectConfig, folders: [PrepareFolder{rel, config}] (od kořene), runtime, environment, globals, defaults = .builtin, baseDir, userAgent}
extension Project { func folderChain(_ rel:) throws -> [PrepareFolder] }        // chybějící _folder.yaml = prázdná konfigurace
// Options: + cookieJar: Bool, proxy: Proxy (.system | .none | .manual(host:port:)) – proxy z globálního nastavení (F11)
final class CookieJar: Sendable { init(file: URL?); static file(projectID:in:); cookies; header(for: URL) -> String; store([Cookie]); clear(); save() throws }  // save jen při změně
struct History { init(dir:limit: = 200); add(_ e: SavedResponse, body: Data?) throws -> HistoryItem; list() -> [HistoryItem]; entry(id) throws -> SavedResponse; body(id) throws -> Data?; clear() throws }
struct SavedResponse { init(_ r: RunResult, request: PreparedRequest, secrets: [String]) }   // formát 2.6 s maskováním; historie navíc id, projectId, requestId, requestName, error, errorDetail, truncated
enum DisplayFormat { static bytes(_:locale:) -> String; static duration(ms:locale:) -> String }   // meta bar odpovědi (F5/1)
enum HTTPStatus { static text(_ code: Int) -> String }   // standardní reason phrase (štítky redirectů, F5/2)
enum MarkupFormatter { static format(_ text:, html: Bool) -> String }   // Pretty pro XML/HTML (v HTTPEngine.body)
enum HTMLPreview { static sandboxed(_ html:) -> String }                // CSP bez sítě a skriptů pro Náhled

// Proměnné a prostředí (F6)
extension Project { listEnvironments() throws -> [EnvironmentConfig]          // dle názvu, bez tajných hodnot; chybějící/duplicitní ID doplní
                    saveEnvironment(_:secrets:) throws -> EnvironmentConfig   // "" id = nové; tajné → SecretStore, změna názvu = nový soubor
                    deleteEnvironment(id:secrets:) throws; secretAccount(envID:) -> (String) -> String }
enum Globals { static load(from: URL) throws -> [Var]; static save(_ vars:, to: URL, secrets:) throws }   // globals.yaml = jen `vars`
protocol SecretStore: Sendable { get(account:) throws -> String?; set(account:value:) /* "" = smazat */; delete(account:) }
  // + fill(_ vars:, account:) (Keychain přebíjí hodnotu z YAML), sync(old:new:account:), deleteAll(_:account:)
struct Secrets: SecretStore { init(service: = "MinorREST"); static account(projectID:envID:name:), globalAccount(_:) }  // SecItem, SECRET_ERROR
final class MemorySecrets: SecretStore                                // testy
// Workspace.activeEnvironment [projectID: envID]
Prepare.explain(_ input: PrepareInput) -> [VarInfo]   // tajné bez načtené hodnoty = `***`; Resolver.dynamicNames
// runtime proměnné per projekt v paměti drží UI (`VarsStore.runtime`, `setRuntime`/`deleteRuntime`), do `PrepareInput.runtime`

// Auth (F7)
enum AuthApply { static effective(_ auth:, folders:, project:) -> (auth: Auth, source: String) /* request | folder:<rel> | project */; static isLiteral(_:) -> Bool }   // apply volá Prepare; hodnota API klíče jde do Prepared.secrets
OAuth (F7/2): actor OAuthClient(engine:secrets:) { accessToken(_ p: OAuthParams, options:) async throws -> String; fetchToken; refresh; tokenInfo(_:) -> TokenInfo?; clearToken }; Prepare.oauthParams(_:_:); PrepareInput.oauth; cancel + authorization_code login = F7/3

// Uložené odpovědi (F8)
Responses: save(runID:label:) -> SavedInfo; list(requestID:) ; get(requestID:version:) ; body(…pretty:) -> BodyView ; setLabel ; delete

// Export / import (F9, F10)
Export.curl(_ p: PreparedRequest, multiline: Bool, mask: Bool) -> String
CurlImport.parse(_ text: String) throws -> (Request, warnings: [String])
OpenAPIImport.preview(source:) async throws -> ImportPreview; importProject(source:options:) async throws -> ProjectInfo

// Nastavení (F11)
AppSettings: load() / save(_:)
```

Model prostředí se jmenuje `EnvironmentConfig` (název `Environment` koliduje se SwiftUI `@Environment`).

### 11.2 Klíčová DTO
```swift
struct RunResult: Sendable {
  let runID: String
  var error: CoreError?          // pak ostatní pole prázdná (kromě sent, timing, redirects pokud jsou)
  var status: Int; var statusText: String; var proto: String
  var remoteAddr: String; var localAddr: String
  var tls: TLSInfo?
  var headers: [KV]              // jak je vrátí HTTPURLResponse (pořadí serveru nedostupné), opakované jako samostatné řádky
  var cookies: [Cookie]
  var sizes: Sizes; var timing: Timing
  var redirects: [Redirect]
  var sent: SentRequest          // {method, url, headers [KV], bodyPreview, bodySize}
  var contentType: String; var charset: String
  var isBinary: Bool; var truncated: Bool
  var unresolved: [String]       // nevyhodnocené proměnné
  var extracted: [KV]            // nastavené runtime proměnné (F8)
  var authSource: String         // (F7)
}
struct BodyView: Sendable { var text: String; var lang: String /* json|xml|html|text */; var size: Int64; var partial: Bool; var image: Data? /* celé tělo binárního image/* */ }
// BodyView.maxView = 10 MB (celé tělo), headView = 1 MB (partial), autoPretty = 5 MB; filter/saveBody pracují s celým tělem
```
`RunResult` záměrně **neobsahuje tělo** – UI si ho vyžádá přes `HTTPEngine.body` (líné načtení, Pretty/Raw bez kopírování metadat). `body` vrací celé tělo do 10 MB, větší jen první 1 MB (`partial`).

## 12. Fáze implementace

Postup v každém kroku: implementace → `make test` (jádro) a `make build` → ověření v běžící aplikaci (`make run`, snímky obrazovky) → commit → `docs/PROGRESS.md`.
Testy: hlavní cesta + nejdůležitější edge case, parametrizované `@Test(arguments:)`. Testovací případy převzít z Go verze (tag `go-wails-f4`), kde existují. Texty UI rovnou přes `t()` v obou jazycích.

### F0 – Bootstrap
1. Odstranit Go/Wails/Svelte (`main.go`, `app*.go`, `menu.go`, `go.mod`, `go.sum`, `internal/`, `frontend/`, `wails.json`, `build/darwin`, `build/bin`); ikonu (`build/appicon.svg`, `.png`) přesunout do `App/Resources/` (zdroj) + `Assets.xcassets`. `project.yml`, `Packages/MinorRESTCore` (prázdná knihovna + 1 test), `Makefile` (`gen`, `build`, `run`, `test`), `.gitignore`. **Hotovo:** `make build` vytvoří `MinorREST.app`, která se spustí; `make test` zelený.
2. `MinorRESTApp`: hlavní okno (1280×800, min 900×600, unified toolbar), `Settings` scéna (prázdná), menu dle 8.7 (položky zatím zobrazí toast „Zatím není implementováno“), `L10n` + `Localizable.xcstrings` (cs/en), fonty dle displeje, prázdné rozvržení sidebar / request / odpověď s děliči. **Hotovo:** cs/en dle systému; světlé/tmavé téma; ne-retina Menlo 13.
3. `ci.yml`. **Hotovo:** CI zelené (ověřit po pushi – push jen na pokyn uživatele).

### F1 – Jádro: model, YAML, úložiště, proměnné (bez UI)
1. `Model` (kap. 2, Codable, optionals u dědičných nastavení), ULID, slug, NFC, YAML kódování (`Yams.Node`, styly dle 2.5). Testy: roundtrip requestu s diakritikou a víceřádkovým tělem, **čtení souborů zapsaných Go verzí** (fixtures z tagu), slug tabulka.
2. `Storage`: `Project` (create/open/init, strom, CRUD, přesun + přečíslování, duplikace, koš, `fileRef`, read-only dle formatVersion, oprava duplicitních ID), `ProjectRegistry`, `Workspace`. Testy v dočasném adresáři.
3. `Vars` (kap. 3) + `encodeQuery` + `buildURL`; `JSONFormatter`. Testy: priorita scope, rekurze a cyklus, neznámá proměnná, `VAR_UNRESOLVED_HOST`, path params, zachování `%XX`, diakritika v query; formátování s proměnnými mimo řetězce, velká čísla, chyba s řádkem.

### F2 – Sidebar a projekty
1. Stores `WorkspaceStore`, `ProjectsStore`; přepínač projektů (nový – sheet s volbou umístění, otevřít adresář, zavřít), obnova projektů po startu.
2. `TreeOutlineView`: rozbalování (do workspace), výběr, klávesy, kontextové menu, inline přejmenování, vytvoření/duplikace/smazání, Zobrazit ve Finderu.
3. Drag & drop + hledání.
4. `ProjectWatcher` (FSEvents) + reload stromu a konfigurace.
**Hotovo:** vnořené složky a requesty lze vytvořit, přejmenovat (s diakritikou), přesunout, smazat do Koše; změna ve Finderu se do 1 s projeví.

### F3 – Editor requestu
1. `TabsStore` (otevřít, zavřít, dirty, obnovení ze workspace, sledování přejmenování), TabBar, načtení/uložení, `MethodPicker`, `VarField` (zatím jen syntaktické zvýraznění), URL bar ↔ query.
2. `KvEditor` + Bulk edit; Params (query ↔ URL, path params), Headers s našeptávačem.
3. Body: `CodeTextView` (lexery, read-only, téma, NSTextFinder), všechny typy těla, Formátovat, výběr souborů.
4. Nastavení a Dokumentace, dialogy neuložených změn (tab, zavření okna, Cmd+Q), změna na disku.
**Hotovo:** request jde kompletně upravit, uložit a po restartu je identický; YAML odpovídá 2.5 a je bajtově shodný s tím, co by zapsala Go verze.

### F4 – HTTP engine a odeslání
1. `HTTPEngine` jádro: metody, hlavičky, těla (raw, form, multipart, binary), TLS (vypnuté ověření), redirecty, timeout/cancel, chybové kódy + testovací server a testy. Ověřit body z 4.1 (vypnutý UA, GET s tělem, Authorization).
2. Metriky: timing, adresy, odeslané hlavičky, velikosti, charset, limity těla, LRU výsledků + testy.
3. `Prepare` (dědičnost hlaviček projekt → složky → request – název na nižší úrovni, i vypnutý, odstraní zděděný case-insensitive; vypnutý řádek automatické hlavičky → `noAuto`; nastavení request → projekt → globální; proměnné; URL; auth zatím jen `none`). UI: Odeslat/Zrušit (Cmd+Enter, Cmd+.), dočasné jednoduché zobrazení (status + raw tělo).
4. Cookie jar, proxy, zápis historie.
**Hotovo:** všech 7 metod proti lokálnímu testovacímu serveru; `Proto` ukazuje HTTP/2 u HTTPS serveru s h2; redirect on/off; zrušení funguje.

### F5 – Zobrazení odpovědi
1. Meta bar (status badge + tooltip, čas + vodopád, velikost + rozpad, protokol, IP), záložka Tělo (Pretty/Raw/Náhled, hledání), stavy panelu.
2. Záložky Hlavičky, Cookies, Časování, Odesláno, Redirecty; i18n popisy status kódů.
3. JSONPath filtr, velká/binární těla, kopírování a uložení těla, chybové stavy.
**Hotovo:** 5 MB JSON se zobrazí bez zamrznutí; odpověď ve windows-1250 má správnou diakritiku; chyba DNS/timeout je srozumitelná.

### F6 – Prostředí, proměnné, tajemství
1. `Secrets`, CRUD prostředí a globálních, výběr prostředí, zapojení do `Prepare`.
2. Okno Prostředí / Proměnné projektu / Globální; nastavení složky a projektu (vars, headers, HTTP nastavení).
3. `explain` → `VarField`: známá/neznámá, hover, našeptávač; „oko“; varování nevyhodnocených.
**Hotovo:** přepnutí prostředí změní `{{baseUrl}}`; secret není v YAML (`grep`), je v Keychain (`security find-generic-password -s MinorREST`).

### F7 – Autorizace
1. `Auth`: inherit, none, basic, bearer, apikey + záložka Auth (request, složka, projekt), zdroj zdědění, varování na literál + „Převést na tajnou proměnnou“.
2. OAuth2 client_credentials a password + cache a refresh + panel tokenu. Testy proti testovacímu token serveru.
3. OAuth2 authorization_code + PKCE (listener, prohlížeč, zrušení).
**Hotovo:** každý typ pošle správnou hlavičku (ověřit v „Odesláno“ a na testovacím serveru); expirovaný token se obnoví sám.

### F8 – Ukládání odpovědí, verze, historie
1. `Responses` (uložit, seznam, načíst, popisek, smazat, maskování), Uložit odpověď, záložka Verze, otevření uložené verze, `.gitignore` projektu.
2. Diff dvou verzí (vlastní řádkový diff – Myers – zobrazený v `CodeTextView`; hlavičky jako text `Name: value`).
3. `extract` (JSONPath / hlavička → runtime proměnná po **každé** úspěšné odpovědi), editor v záložce „Proměnné“ requestu.
4. Záložka Historie v sidebaru.
**Hotovo:** tři uložení = `v0001`–`v0003` s úplnými metadaty; diff ukáže změny; login → token → další request funguje přes `extract`.

### F9 – Kopírování jako cURL, import cURL
1. `Export` + golden testy; tlačítko ⧉ s výběrem formátu, kontextové menu stromu, uložené verze.
2. `CurlImport` + nabídka v URL baru.
**Hotovo:** zkopírovaný příkaz spuštěný v zsh i bash proti testovacímu serveru doručí bajtově stejné tělo a hlavičky jako aplikace (včetně diakritiky).

### F10 – Import OpenAPI / Swagger
1. Parsování → `Spec` → generátor + testy na fixtures.
2. Průvodce importem (soubor, URL, drop do okna).
3. (volitelné) Postman v2.1.
**Hotovo:** Petstore 2.0 i 3.0 → složky dle tagů, `baseUrl` v prostředí, ukázková těla, auth projektu.

### F11 – Nastavení a i18n
1. Okno Nastavení (kap. 9), okamžitá aplikace, napojení globálních výchozích do `Prepare`.
2. Kontrola úplnosti překladů, přepnutí jazyka za běhu (UI i menu).

### F12 – Auto-update a release
1. ~~Sparkle~~ → vlastní updater (kap. 10): jádro + UI hotové, zbývá reálný cyklus proti release.
2. UI (menu „Zkontrolovat aktualizace…“, sekce v Nastavení).
3. `scripts/release.sh`, README (instalace, první spuštění, build ze zdrojů).
**Vyžaduje uživatele:** zjistit veřejný klíč MinorUpdate (`swift scripts/minorupdate.swift keygen`) a vložit do `project.yml` (`MRUpdatePublicKey`); schválit push a tag. **Hotovo:** lokální build s nižší verzí najde release, ověří, nainstaluje a restartuje se.

### F13 – Dotažení
Command palette (Cmd+K: requesty napříč projekty + akce), prázdné stavy, ukázkový projekt při prvním spuštění, a11y (VoiceOver popisky, fokus), výkon stromu nad 500 položek, QA checklist.

## 13. QA checklist (před v1.0)
- [ ] 7 metod, všechny typy těla, multipart se souborem s diakritikou v názvu.
- [ ] HTTP/1.1 i HTTP/2 (HTTPS) – zobrazení protokolu; redirect on/off/limit; timeout; zrušení; self-signed s vypnutým ověřením.
- [ ] Metriky: součet fází ≈ total, IP správná, velikosti sedí s `curl -w '%{size_header} %{size_download}'`.
- [ ] Proměnné ve všech polích, priorita, secret v Keychain, runtime z `extract`.
- [ ] Auth: basic, bearer, apikey (header/query), OAuth2 tři granty + refresh.
- [ ] Uložení odpovědi, verze, diff, historie.
- [ ] Kopírování cURL (víceřádkový i jednořádkový) → Terminál (zsh i bash) → stejný výsledek.
- [ ] Import Petstore 2.0 / 3.0 / 3.1, import cURL.
- [ ] Ne-retina: Menlo 13; retina: systémový font; přesun okna mezi monitory.
- [ ] Světlý/tmavý režim, cs/en včetně menu.
- [ ] Auto-update end-to-end.
- [ ] Změna souborů přes `git pull`/Finder se projeví; projekt z Go verze se otevře a uloží beze změn diffu.
- [ ] Systémová proxy (i PAC) a dotaz Local Network u LAN adresy.

## 14. Rizika a otevřené body
- **Omezení URLSession** (kap. 4.1): bez vynucení HTTP verze, h2c, vlastního `Host`, přesného pořadí odeslaných hlaviček. Pokud bude potřeba, lze později přidat druhý engine (SwiftNIO / AsyncHTTPClient) za stejné rozhraní `HTTPEngine`.
- **Vypnutý `User-Agent`, GET s tělem, `Authorization`** – chování URLSession ověřit v F4/1 a F7/1, výsledek zapsat sem.
- **Bez notarizace:** první spuštění vyžaduje ruční povolení (kap. 10). Lze doplnit později (Developer ID + `notarytool`).
- **Keychain přes SecItem bez Developer ID:** po každé aktualizaci jeden dotaz na přístup ke Keychainu na položku (ACL vázané na podpis). S Developer ID lze přejít na data protection keychain + access group bez dotazů.
- **Vlastní updater** – reálný cyklus (release → stažení → výměna → restart) ověřit po vydání první verze.
- **Vlastní editor kódu** (`NSTextView` + jednoduché lexery): bez foldingu; výkon zvýraznění u 5 MB JSON hlídat (zvýrazňovat jen viditelnou oblast).
- **Literály v auth polích** končí v YAML (a tedy v gitu) – řeší jen varování a převod na secret proměnnou.
- **OAuth2 authorization code:** servery vyžadující přesnou redirect URI → pole `redirectPort`.
- **Mimo rozsah v1:** skripty, testy/asserty, runner, mock server, WebSocket/GraphQL/gRPC, mTLS, Digest, markdown náhled, folding v editoru.


## Změny po migraci (2026-11-24)
- Nová kostra (starter + minor-swift-core), macOS 26+, Bundle ID `cz.novami.minor.rest`; kap. 10 (vlastní updater, Sparkle, ad-hoc podpis) je nahrazena `MinorUpdater` + Developer ID + notarizace.
- OAuth2 `authorization_code` odstraněn (žádný lokální listener); zůstávají `client_credentials` a `password` (+ refresh).
- Kap. 2.8: tajemství requestů (auth pole, `Authorization`/`Proxy-Authorization`/`Cookie`) jsou v Keychainu, v YAML `{{keychain}}`.

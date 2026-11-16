# MinorREST – implementační plán

> Plán je psaný pro postupnou implementaci po fázích (F0–F13). Každá fáze = jeden commit (případně několik malých),
> po každé fázi aktualizuj `docs/PROGRESS.md`. Analýza konkurence: `docs/ANALYZA.md`.

## 0. Rozhodnutí (schválená uživatelem)

| Oblast | Volba |
|---|---|
| Platforma | macOS 13+, pouze Apple Silicon (`darwin/arm64`) |
| Jazyk backendu | Go (aktuální stabilní, nyní 1.27) |
| GUI | **Wails v2** (nejnovější v2.x) + **Svelte 5 + TypeScript + Vite** |
| Editor kódu | CodeMirror 6 (JSON/XML/HTML zvýraznění, folding, hledání, `@codemirror/merge` pro diff) |
| Úložiště | **YAML soubory** (projekt = adresář), tajemství v **macOS Keychain** |
| Jazyk UI | čeština + angličtina (i18n, výchozí dle systému) |
| Podpis | zatím ad-hoc (`codesign -s -`), bez notarizace; auto-update z GitHub Releases ověřený ed25519 |
| Licence | MIT |
| Repo | https://github.com/novami/minor-rest.git, Go modul `github.com/novami/minor-rest` |

## 1. Architektura

```
minor-rest/
├── main.go                 # wails.Run, menu (vč. Edit menu!), okno, embed frontend/dist
├── app.go                  # App struct = tenká vrstva Wails bindingů → volá internal/*
├── internal/
│   ├── model/              # datové typy (Project, Folder, Request, Response, Env, Settings…)
│   ├── storage/            # čtení/zápis YAML, strom projektu, slugy, řazení, watcher (fsnotify)
│   ├── vars/               # resolver proměnných {{x}}, dynamické proměnné, path params
│   ├── secrets/            # Keychain (github.com/zalando/go-keyring)
│   ├── httpclient/         # odesílání, HTTP/1.1 vs HTTP/2, redirecty, timing, IP, velikosti
│   ├── auth/               # basic, bearer, apikey, oauth2 (golang.org/x/oauth2)
│   ├── responses/          # ukládání a verzování odpovědí, historie, diff data
│   ├── export/             # cURL / bash generátor
│   ├── importer/
│   │   ├── openapi/        # OpenAPI 3.0/3.1 + Swagger 2.0 (github.com/pb33f/libopenapi)
│   │   ├── postman/        # Postman Collection v2.1 (volitelné, F10)
│   │   └── curl/           # vložení cURL příkazu → request
│   ├── settings/           # globální nastavení aplikace
│   └── updater/            # kontrola GitHub Releases, stažení, ověření, výměna .app
├── frontend/
│   ├── src/
│   │   ├── App.svelte
│   │   ├── lib/
│   │   │   ├── components/ # Sidebar, Tree, Tabs, UrlBar, KvEditor, CodeEditor, ResponsePane…
│   │   │   ├── stores/     # *.svelte.ts (runes) – projekty, otevřené taby, prostředí, nastavení
│   │   │   ├── i18n/       # cs.json, en.json, t() helper
│   │   │   └── util/
│   │   └── styles/         # tokens.css (barvy, light/dark), fonts.css
│   └── wailsjs/            # generované bindingy (necommitovat ručně upravené)
├── build/                  # Wails build assets (appicon.png, darwin/Info.plist)
├── scripts/                # release.sh, sign-update.go
├── .github/workflows/      # ci.yml, release.yml
└── docs/
```

**Zásady:**
- Backend je zdroj pravdy pro data na disku; frontend drží jen stav UI (otevřené taby, neuložené změny).
- Veškerá logika (resolver, HTTP, export, import) je v Go a je pokrytá unit testy. Frontend jen zobrazuje.
- `app.go` nemá logiku – jen převádí volání a chyby. Chyby vracet jako `error` s kódem (`ErrCode: message`), frontend překládá kód přes i18n.
- Dlouhé operace (odeslání requestu, import, update) běží s `context.Context`, jdou zrušit; průběh přes `runtime.EventsEmit`.
- `internal/*` nesmí importovat Wails → testovatelné přes `go test ./internal/...` (bez sestaveného frontendu).

### Wails v2 – úskalí (důležité!)
1. **Edit menu**: bez `menu.EditMenu()` v aplikačním menu nefunguje na macOS Cmd+C/V/X/A/Z ve WebView. Přidat AppMenu + EditMenu + vlastní menu (Soubor, Request, Zobrazení, Nápověda).
2. Šablona `svelte-ts` z `wails init` obsahuje starý Svelte 3 → frontend vytvořit znovu přes `npm create vite@latest frontend -- --template svelte-ts` (Svelte 5) a ponechat `wailsjs/`.
3. `//go:embed all:frontend/dist` – při `go build` musí `frontend/dist` existovat. CI testy spouštět jen nad `./internal/...`.
4. Bindingy se generují při `wails dev` / `wails build` (nebo `wails generate module`). Po změně signatury v `app.go` je regenerovat.
5. Okno: `Mac: &mac.Options{TitleBar: mac.TitleBarHiddenInset(), WebviewIsTransparent: false, Appearance: mac.DefaultAppearance}`; tažitelnou oblast označit CSS `--wails-draggable: drag`.
6. Schránka: `runtime.ClipboardSetText`; otevření URL v prohlížeči: `runtime.BrowserOpenURL`; dialogy: `runtime.OpenFileDialog/SaveFileDialog/MessageDialog`.
7. Velká data (odpovědi > 5 MB) neposílat přes binding opakovaně – backend drží poslední odpověď v paměti, frontend si bere části (`GetResponseBody(id, offset, limit)`).

## 2. Datový model a formát na disku

### 2.1 Umístění
- Konfigurace aplikace: `~/Library/Application Support/MinorREST/`
  - `settings.yaml` – globální nastavení
  - `workspace.yaml` – seznam otevřených projektů (cesty), poslední otevřené taby, vybrané prostředí
  - `history/` – historie odeslaných requestů (posledních N, výchozí 200), mimo projekty
  - `globals.yaml` – globální proměnné
- Projekt: libovolný adresář, výchozí nové projekty do `~/Documents/MinorREST/<slug>/`.

### 2.2 Struktura projektu
```
muj-projekt/
├── minorrest.yaml              # metadata projektu (název, verze formátu, vars, auth, headers, nastavení)
├── environments/
│   ├── vyvoj.yaml
│   └── produkce.yaml
├── uzivatele/                  # složka
│   ├── _folder.yaml            # název složky (s diakritikou), seq, auth, headers, vars
│   ├── seznam-uzivatelu.req.yaml
│   └── detail/                 # vnořená složka (povoleno)
│       └── ...
├── .responses/                 # uložené odpovědi (verze), viz 2.5
└── .gitignore                  # generuje se: .responses/ je volitelně ignorován (nastavení projektu)
```

**Pravidla pojmenování:** název souboru/adresáře = ASCII slug z názvu (`Příliš žluťoučký kůň` → `prilis-zlutoucky-kun`),
skutečný název s diakritikou v poli `name`. Kolize → suffix `-2`, `-3`. Přejmenování = přejmenování souboru + `name`.
Vstupní řetězce vždy normalizovat do NFC (`golang.org/x/text/unicode/norm`). Mazání = přesun do Koše přes cgo `NSFileManager trashItemAtURL` (`internal/storage/trash_darwin.go`; ne přes `osascript`/Finder – to vyvolá dotaz na oprávnění Automatizace), nikdy `os.RemoveAll`.

### 2.3 `minorrest.yaml`
```yaml
formatVersion: 1
name: Můj projekt
description: ""
vars:                          # proměnné projektu
  - { name: baseUrl, value: "https://api.example.com", enabled: true }
headers:                       # dědí se do všech requestů
  - { name: Accept, value: application/json, enabled: true }
auth: { type: none }           # výchozí auth projektu
settings:
  httpVersion: auto            # auto | http1 | http2
  followRedirects: true
  maxRedirects: 10
  timeoutMs: 30000
  verifyTls: true
  cookieJar: true
  ignoreResponsesInGit: true
```

### 2.4 Request `*.req.yaml`
```yaml
id: 01JCX7...               # ULID (github.com/oklog/ulid/v2), stabilní i při přejmenování
name: Seznam uživatelů
seq: 3                      # pořadí ve složce
method: GET                 # GET | POST | PUT | PATCH | DELETE | HEAD | OPTIONS
url: "{{baseUrl}}/users/:id?page={{page}}"
params:
  query:                    # synchronizováno s URL
    - { name: page, value: "{{page}}", enabled: true, description: "" }
  path:
    - { name: id, value: "42" }
headers:
  - { name: X-Trace, value: "{{$uuid}}", enabled: true }
auth:
  type: inherit             # inherit | none | basic | bearer | apikey | oauth2
body:
  type: none                # none | json | xml | text | html | form-urlencoded | multipart | binary
  raw: ""                   # pro json/xml/text/html
  form:                     # pro form-urlencoded
    - { name: q, value: "kůň", enabled: true }
  multipart:
    - { name: popis, kind: text, value: "Žluťoučký", enabled: true }
    - { name: soubor, kind: file, path: "/Users/.../foto.jpg", contentType: "", enabled: true }
  binaryPath: ""
vars:                       # proměnné na úrovni requestu
  pre: []
  post:                     # extrakce z odpovědi → runtime proměnná (F8)
    - { name: token, from: body, path: "$.data.token", enabled: true }
settings:                   # každá položka může být "inherit"
  httpVersion: inherit
  followRedirects: inherit
  maxRedirects: inherit
  timeoutMs: inherit
  verifyTls: inherit
docs: |                     # markdown poznámky
```
Auth bloky:
```yaml
auth: { type: basic, basic: { username: "{{user}}", password: "{{pass}}" } }
auth: { type: bearer, bearer: { token: "{{token}}", prefix: "Bearer" } }
auth: { type: apikey, apikey: { key: X-API-Key, value: "{{apiKey}}", in: header } }   # header | query
auth:
  type: oauth2
  oauth2:
    grantType: client_credentials        # client_credentials | authorization_code | password
    authUrl: ""                          # authorization_code
    tokenUrl: "{{baseUrl}}/oauth/token"
    clientId: "{{clientId}}"
    clientSecret: "{{clientSecret}}"
    scope: "read write"
    usePkce: true
    redirectUrl: "http://127.0.0.1:{port}/callback"   # port se zvolí automaticky
    username: ""                         # password grant
    password: ""
    clientAuth: header                   # header (Basic) | body
    tokenPlacement: header               # header | query
    headerPrefix: Bearer
    autoRefresh: true
```

### 2.5 Uložené odpovědi (verzování)
`.responses/<requestId>/v0001.yaml`, `v0002.yaml`, … + velká/binární těla zvlášť `v0001.body` (> 256 KB nebo nebinárně nečitelná).
```yaml
version: 3
savedAt: 2026-11-16T15:04:05+01:00
label: ""                        # volitelný popisek verze
request:                         # snímek SKUTEČNĚ odeslaného requestu (po vyhodnocení proměnných)
  method: POST
  url: https://api.example.com/users?page=2
  httpVersion: HTTP/2.0
  headers: [{ name: Authorization, value: "Bearer ***" }]   # tajné hodnoty maskované
  bodySize: 128
response:
  status: 201
  statusText: Created
  proto: HTTP/2.0
  remoteAddr: "93.184.216.34:443"
  localAddr: "192.168.1.10:53122"
  tls: { version: TLS 1.3, cipher: TLS_AES_128_GCM_SHA256, serverName: api.example.com, certExpires: 2027-01-01 }
  headers: [{ name: Content-Type, value: application/json; charset=utf-8 }]
  sizes: { headers: 412, bodyWire: 1830, bodyDecoded: 6402 }
  timing: { dnsMs: 4.1, connectMs: 12.3, tlsMs: 25.0, ttfbMs: 88.2, downloadMs: 3.4, totalMs: 133.0 }
  redirects: []
  body: |                         # nebo bodyFile: v0003.body
    {"id": 1}
```
Verze se číslují automaticky (max + 1). UI: seznam verzí, přejmenování popisku, smazání, porovnání dvou verzí (diff těla i hlaviček).

### 2.6 Prostředí `environments/*.yaml`
```yaml
name: Vývoj
vars:
  - { name: baseUrl, value: "http://localhost:8080", enabled: true }
  - { name: apiKey, secret: true, enabled: true }   # hodnota v Keychain
```
Keychain klíč: služba `MinorREST`, účet `<projectId>/<envSlug>/<varName>` (projectId = ULID v `minorrest.yaml`).

## 3. Proměnné

- Syntaxe `{{nazev}}`; povolené znaky `[A-Za-z0-9_.-]`. Escapování: `\{{` = literál.
- **Priorita (vyšší vyhrává):** runtime (post-response vars, OAuth token) → request vars → složka (nejbližší první) → prostředí → projekt → globální.
- Dynamické: `{{$uuid}}`, `{{$ulid}}`, `{{$timestamp}}` (unix s), `{{$timestampMs}}`, `{{$isoTimestamp}}`, `{{$randomInt}}` (0–1000), `{{$randomString}}`. Vyhodnocují se jednou na odeslání (stejná hodnota v celém requestu).
- Rekurze: hodnota proměnné může obsahovat další proměnné, max hloubka 10, detekce cyklu → chyba `VAR_CYCLE`.
- Path params `:id` v URL → nahrazení z `params.path` (po vyhodnocení `{{}}`), URL-encode segmentu.
- Proměnné fungují v: URL, query, path, headers, body (raw, form, multipart text), auth polích, OAuth2 polích.
- API resolveru: `Resolve(input string, scope Scope) (string, []Unresolved)` + `Explain(name) (value, source)` pro hover v UI.
- Nevyhodnocená proměnná → request se odešle (s literálem) a v UI je varování; v URL baru je červeně podtržená.

## 4. HTTP engine (`internal/httpclient`)

Vstup: `PreparedRequest` (vše vyhodnoceno) + `Options` (httpVersion, followRedirects, maxRedirects, timeout, verifyTls, proxy, cookieJar).

- **Transport:** nový `http.Transport` per volání (nebo cache dle klíče options). `DisableCompression: true` a ručně přidat `Accept-Encoding: gzip, deflate, br, zstd` (pokud uživatel nenastavil vlastní) → měříme **přenesenou** velikost a pak dekomprimujeme sami (`compress/gzip`, `compress/flate`, `github.com/andybalholm/brotli`, `github.com/klauspost/compress/zstd`).
- **HTTP verze** (Go ≥ 1.24 `http.Protocols`):
  - `auto` → `SetHTTP1(true); SetHTTP2(true)` (ALPN rozhodne),
  - `http1` → jen `SetHTTP1(true)`,
  - `http2` → `SetHTTP2(true)`, pro `http://` navíc `SetUnencryptedHTTP2(true)` (h2c prior knowledge).
  - Skutečně použitou verzi brát z `resp.Proto`.
- **Redirecty:** `CheckRedirect` – při `followRedirects=false` vrací `http.ErrUseLastResponse`; jinak limit `maxRedirects`. Každý skok zaznamenat (status, URL, čas) do `redirects`.
- **Timing** přes `net/http/httptrace`: DNSStart/Done, ConnectStart/Done, TLSHandshakeStart/Done, GotConn (Reused → nulové DNS/connect), WroteRequest, GotFirstResponseByte; download = konec čtení těla. Použít `time.Now()` monotónní.
- **IP adresy:** `GotConnInfo.Conn.RemoteAddr()` / `LocalAddr()`.
- **TLS info:** `resp.TLS` → verze, cipher, SNI, subjekt a expirace leaf certifikátu.
- **Velikosti:**
  - request headers: součet `Name: value\r\n` + request line (u HTTP/2 uvést „nekomprimovaně“),
  - request body: délka odeslaných bajtů,
  - response headers: status line + `Name: value\r\n` + `\r\n`,
  - response body: `bodyWire` (počítaný reader před dekompresí) a `bodyDecoded`.
- **Limit těla:** výchozí 100 MB, nad 10 MB ukládat do temp souboru a frontend dostane jen náhled.
- **Zrušení:** `Send` vrací `requestId`, `Cancel(requestId)` ruší context. Timeout přes `context.WithTimeout`.
- **Auto hlavičky** (zobrazené šedě, vypnutelné): `User-Agent: MinorREST/<verze>`, `Accept: */*`, `Accept-Encoding`, `Content-Type` dle typu body, `Content-Length`, `Host`.
- **Body kódování:** JSON/text vždy UTF-8, `Content-Type: application/json; charset=utf-8` (u textu `text/plain; charset=utf-8`). Form-urlencoded přes `url.Values.Encode()` (diakritika → percent-encoding). Multipart přes `mime/multipart`, názvy souborů s diakritikou → `filename*=UTF-8''...` (RFC 5987) plus `filename` ASCII fallback.
- **Cookies:** `net/http/cookiejar` per projekt (v paměti, volitelně perzistence do `~/Library/Application Support/MinorREST/cookies/<projectId>.json`); záložka Cookies v odpovědi + jednoduchý správce (smazat vše / jednotlivé).
- **Proxy:** nastavení `none | system | manual`. `system` = čtení `scutil --proxy` při startu (HTTP/HTTPS proxy), manual = URL.
- Testy: `httptest.NewServer` + `NewTLSServer` (h1, h2 přes `EnableHTTP2`), redirect řetěz, gzip/br, timeout, cancel, velikosti.

## 5. Autorizace (`internal/auth`)

Rozhraní: `Apply(ctx, req *http.Request, cfg AuthConfig, resolver) error`.
- **inherit**: projde složky nahoru až k projektu, první ne-`inherit` vyhrává (výchozí projektu `none`).
- **basic**: `req.SetBasicAuth` (UTF-8 username/password → base64 bajtů UTF-8).
- **bearer**: `Authorization: <prefix> <token>`.
- **apikey**: header nebo query param.
- **oauth2** (`golang.org/x/oauth2`, `clientcredentials`):
  - client_credentials, password, authorization_code (+PKCE S256).
  - Authorization code: spustit lokální HTTP listener na `127.0.0.1:0`, otevřít `authUrl` v systémovém prohlížeči (`runtime.BrowserOpenURL`), počkat na `/callback` (timeout 5 min, ověřit `state`), vyměnit code za token, stránka „Můžete zavřít okno“.
  - Token cache v Keychain (účet `<projectId>/oauth/<hash(tokenUrl+clientId+scope)>`), automatický refresh před expirací (refresh_token), tlačítka „Získat nový token“, „Smazat token“, zobrazení expirace.
- Digest auth = backlog.

## 6. Export – kopírování jedním klikem (`internal/export`)

Ikona „Kopírovat“ vedle tlačítka Odeslat: klik = zkopíruje v naposledy zvoleném formátu; šipka vedle = výběr formátu:
1. **cURL – jeden řádek**
2. **cURL – víceřádkový** (bash/zsh, `\` na konci řádků) – výchozí
3. **Bash skript** – `#!/usr/bin/env bash`, `set -euo pipefail`, proměnné jako `BASE_URL='...'` nahoře, curl je používá (`"${BASE_URL}/users"`)
4. **HTTPie** (`http` příkaz) – nice-to-have

Pravidla:
- Vše plně vyhodnocené (proměnné, auth → hlavička, path params, auto hlavičky jen pokud jsou zapnuté a nejsou výchozí curl).
- Quoting: single quotes, uvnitř `'` → `'\''`. Diakritika zůstává UTF-8 (terminál macOS je UTF-8); URL percent-encode jen tam, kde to vyžaduje RFC 3986.
- Flagy: `-X METHOD` (vynechat u GET bez body), `-H`, `--data-raw` (raw), `--data-urlencode` (form), `-F 'name=@"/cesta/soubor"';type=...` (multipart), `--data-binary @file`, `--http1.1` / `--http2` / `--http2-prior-knowledge`, `-L --max-redirs N` (pokud follow), `-k` (pokud verifyTls=false), `--max-time`, `--compressed` pokud Accept-Encoding automatický.
- Přepínač „Maskovat tajné hodnoty“ (výchozí vypnuto, v UI tooltip).
- Kopírování i z kontextového menu ve stromu a uložené verze odpovědi (snímek requestu).
- Testy: tabulkové testy s diakritikou (`Příliš žluťoučký kůň úpěl ďábelské ódy`), uvozovkami, `$`, `!`, newlines v body, multipart.

**Import cURL** (opačný směr): vložení textu začínajícího `curl ` do URL baru → nabídne „Převést na request“. Parser shell slov (`github.com/google/shlex` nebo vlastní), podporované flagy: `-X -H -d --data* -F -u --url -L -k --http1.1 --http2 --compressed -b`.

## 7. Import OpenAPI / Swagger (`internal/importer/openapi`)

- Knihovna `github.com/pb33f/libopenapi` (Swagger 2.0 i OpenAPI 3.0/3.1, JSON i YAML).
- Zdroj: soubor (dialog / drag & drop) nebo URL.
- Mapování:
  - `info.title` → název nového projektu (nebo import do existujícího projektu jako nová složka – volba v průvodci),
  - `tags` → složky (operace bez tagu → složka „Ostatní“; první tag vyhrává),
  - operace → request (`summary` || `operationId` || `METHOD path`), `description` → `docs`,
  - `servers[]` (3.x) / `host+basePath+schemes` (2.0) → proměnná `baseUrl` v prostředí; více serverů → více prostředí,
  - path params `{id}` → `:id` + `params.path` (hodnota z example/default),
  - query/header params → `params.query` / `headers` (required → enabled, jinak disabled),
  - requestBody: preferovat `application/json` → vygenerovat ukázkové JSON z `example`/`examples`/schéma (rekurzivně, max hloubka 6, enum → první hodnota, formáty date-time/uuid/email → ukázka); `application/x-www-form-urlencoded` / `multipart/form-data` → form pole,
  - `securitySchemes` → auth projektu (http basic → basic, http bearer → bearer s `{{token}}`, apiKey → apikey, oauth2 → oauth2 s tokenUrl/authUrl/scopes) + odpovídající prázdné proměnné.
- Průvodce importu: náhled (počet složek/requestů), volby (cílový projekt, jak seskupit: tagy / cesty), potvrzení.
- Testy: fixture Petstore 2.0, Petstore 3.0, malá 3.1 specifikace.

Postman Collection v2.1 import (F10, volitelné): složky/requesty/auth/variables.

## 8. UI / UX

### 8.1 Rozvržení
```
┌───────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●  [Projekt ▾]                         [Prostředí: Vývoj ▾] [👁] [⚙]      │  ← HiddenInset titlebar, draggable
├──────────────┬────────────────────────────────────────────────────────────────┤
│ 🔍 Hledat…   │ [GET Seznam ×][POST Login ●][+]                                 │  ← taby otevřených requestů
│ ▾ 📁 Uživatelé│ [GET ▾] [{{baseUrl}}/users?page=2            ] [⧉▾] [Odeslat ▸] │
│   GET Seznam │ Params | Body | Headers (3) | Auth | Nastavení | Dokumentace  │
│   POST Vytvoř│ ┌ KV editor ──────────────────────────────────────────────────┐ │
│ ▸ 📁 Objednáv│ │ ☑ page   {{page}}   popis                       [Bulk edit] │ │
│              │ └─────────────────────────────────────────────────────────────┘ │
│              ├────────────────────────────────────────────────────────────────┤
│              │ [201 Created] 133 ms  6,4 kB  HTTP/2  93.184.216.34:443  [💾 Uložit] │
│              │ Tělo | Hlavičky (12) | Cookies | Časování | Odesláno | Verze (3)│
│              │ [Pretty|Raw|Náhled]  🔍  JSONPath filtr                          │
│              │ { "id": 1, ... }   ← CodeMirror, obarvené, folding               │
└──────────────┴────────────────────────────────────────────────────────────────┘
```
- Sidebar šířka měnitelná (uložit), skrytelný (Cmd+B). Split request/odpověď vertikálně i horizontálně (přepínač v menu Zobrazení).
- Barvy metod: GET zelená, POST oranžová, PUT modrá, PATCH fialová, DELETE červená, HEAD šedá, OPTIONS tyrkysová.
- Status badge: 1xx šedá, 2xx zelená, 3xx modrá, 4xx oranžová, 5xx červená, chyba sítě červený outline + text chyby (DNS, connection refused, TLS, timeout – srozumitelně česky).
- Hover nad statusem: český/anglický popis kódu (tabulka v i18n pro všechny standardní kódy).
- Hover nad časem: vodopád DNS / TCP / TLS / TTFB / Download. Hover nad velikostí: Hlavičky / Tělo (přenesené vs. dekomprimované) + request velikosti.
- Meta bar ukazuje: status, čas, velikost, protokol, vzdálená IP:port; detail (TLS, lokální adresa) v záložce Časování.

### 8.2 Strom (sidebar)
- Přepínač projektů nahoře (dropdown + „Nový projekt“, „Otevřít adresář…“, „Importovat OpenAPI…“, „Zavřít projekt“).
- Strom: složky (rozbalitelné, stav uložen), requesty s badge metody.
- Kontextové menu: Nový request, Nová složka, Přejmenovat (F2 / Enter), Duplikovat (Cmd+D), Kopírovat jako cURL, Zobrazit ve Finderu, Smazat (do Koše, potvrzení).
- Drag & drop: přesun requestu/složky mezi složkami a změna pořadí (`seq`).
- Hledání: filtr podle názvu, URL a metody (fuzzy).
- Watcher (fsnotify, debounce 300 ms): externí změny se promítnou; pokud je otevřený tab se změnami, zobrazit dialog „Soubor byl změněn na disku – Načíst / Ponechat moje“.

### 8.3 Editor requestu
- Výběr metody (7 metod), URL bar = jednoradkový CodeMirror se zvýrazněním `{{proměnných}}` (zelená/červená), autocomplete po napsání `{{`, hover = hodnota + zdroj.
- Vložení cURL do URL baru → nabídka importu.
- **KvEditor** (sdílená komponenta pro query, path, headers, form, multipart, vars): checkbox, klíč, hodnota (s highlightem proměnných), popis, mazání, nový řádek se vytvoří psaním do posledního prázdného, přetažení pořadí, **Bulk edit** textový režim (`klíč: hodnota`, `//` = vypnutý řádek). Autocomplete běžných hlaviček a hodnot (Content-Type, Accept, Authorization, Cache-Control…).
- Body: přepínač typu; raw = CodeMirror s jazykem dle typu + tlačítko „Formátovat“ (JSON beautify), validace JSON (podtržení chyby); form/multipart = KvEditor (multipart: přepínač text/soubor, výběr souboru dialogem); binary = výběr souboru.
- Auth: výběr typu + formulář; u inherit zobrazit „Zděděno z: Složka X → Basic“.
- Nastavení: HTTP verze (Zdědit / Auto / HTTP/1.1 / HTTP/2), Následovat redirecty (Zdědit/Ano/Ne), max redirectů, timeout, ověřovat TLS.
- Dokumentace: markdown editor + náhled.
- Neuložené změny: tečka v tabu, Cmd+S uloží, zavření tabu s neuloženými změnami → dialog. Odeslat jde i bez uložení.

### 8.4 Odpověď
- Tělo: Pretty (JSON/XML/HTML formátované, obarvené, folding, Cmd+F hledání), Raw, Náhled (HTML v sandboxed iframe `sandbox=""`, obrázky jako `<img>` z data URL, PDF ne).
- JSON filtr (JSONPath, `github.com/ohler55/ojg/jp` na backendu).
- Hlavičky (tabulka, kopírovat), Cookies, Časování (vodopád + TLS + adresy), Odesláno (přesný seznam odeslaných hlaviček a těla – „wire“ pohled), Redirecty, Verze (uložené odpovědi).
- Tlačítko **Uložit odpověď** (Cmd+Shift+S) → nová verze; volitelný popisek. Tlačítka Kopírovat tělo, Uložit tělo do souboru.
- Velké odpovědi (> 5 MB): Pretty vypnuto s nabídkou „Přesto formátovat“, zobrazení po částech.

### 8.5 Prostředí a proměnné
- Dropdown prostředí v titlebaru (+ „Žádné“), Cmd+E.
- „Oko“ – rychlý přehled všech aktivních proměnných s hodnotou a zdrojem.
- Editor prostředí (modal/tab): seznam prostředí vlevo, KvEditor vpravo, sloupec „Tajné“ (zámek) → hodnota do Keychain, zobrazení `••••` s tlačítkem zobrazit.
- Editor proměnných projektu, složky (v nastavení složky) a globálních.

### 8.6 Fonty a vzhled
- `fonts.css`:
  ```css
  :root { --font-ui: Menlo, monospace; --font-code: Menlo, monospace; --font-size: 13px; }
  @media (min-resolution: 2dppx) {
    :root { --font-ui: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            --font-code: ui-monospace, "SF Mono", Menlo, monospace; --font-size: 13px; }
  }
  ```
  Media query se v WKWebView přepočítá i při přesunu okna mezi monitory. V nastavení lze přepsat (Automaticky / vlastní font + velikost pro UI a pro kód).
- Téma: Systém / Světlé / Tmavé (CSS proměnné, `prefers-color-scheme`), CodeMirror téma navázané na proměnné.
- Zkratky: Cmd+Enter odeslat, Cmd+. zrušit, Cmd+S uložit, Cmd+Shift+S uložit odpověď, Cmd+N nový request, Cmd+Shift+N nová složka, Cmd+W zavřít tab, Cmd+K hledání/command palette, Cmd+E prostředí, Cmd+B sidebar, Cmd+, nastavení, Cmd+Shift+C kopírovat jako cURL, Cmd+L fokus URL.

### 8.7 i18n
- `frontend/src/lib/i18n/{cs,en}.json`, helper `t(key, params)`, jazyk z nastavení (`auto` = `navigator.language`).
- Backend vrací kódy chyb (`NET_DNS`, `NET_REFUSED`, `NET_TIMEOUT`, `TLS_VERIFY`, `VAR_CYCLE`, `IO_…`), texty jsou jen ve frontendu. Nativní menu (Go) přeložit jednoduchou mapou v Go podle nastavení.

## 9. Nastavení aplikace (`settings.yaml`, okno Cmd+,)
- Obecné: jazyk, téma, výchozí adresář projektů, otevřít poslední projekty při startu.
- Vzhled: font UI/kód (Automaticky dle displeje / vlastní), velikost, rozložení odpovědi (vpravo/dole).
- Request výchozí: HTTP verze, redirecty + max, timeout, ověřování TLS, User-Agent, auto Accept-Encoding, cookie jar.
- Proxy: žádná / systémová / ruční.
- Odpovědi: limit velikosti, délka historie, limit pro Pretty.
- Export: výchozí formát kopírování, maskovat tajemství.
- Aktualizace: automaticky kontrolovat (výchozí **zapnuto**), automaticky stáhnout a nainstalovat při ukončení (výchozí zapnuto), tlačítko „Zkontrolovat nyní“, zobrazení aktuální verze.

## 10. Automatické aktualizace (`internal/updater`) a release

- Verze vkládána přes `-ldflags "-X main.version=v1.2.3"`, SemVer (`golang.org/x/mod/semver`).
- Kontrola: při startu (po 10 s) a každých 24 h → `GET https://api.github.com/repos/novami/minor-rest/releases/latest` (bez tokenu, `User-Agent: MinorREST/<verze>`, respektovat rate-limit, ETag cache).
- Assety releasu: `MinorREST-<verze>-darwin-arm64.zip`, `MinorREST-<verze>-darwin-arm64.zip.sig` (ed25519 podpis), `MinorREST-<verze>-darwin-arm64.dmg` (pro ruční instalaci), `checksums.txt`.
- Ověření: ed25519 veřejný klíč zakompilovaný v aplikaci (`internal/updater/pubkey.go`), privátní klíč jen v GitHub Secrets (`UPDATE_SIGNING_KEY`). Bez platného podpisu se update neinstaluje.
- Instalace: stáhnout do `~/Library/Caches/MinorREST/update/`, ověřit, rozbalit (`ditto -x -k`), zkontrolovat `CFBundleIdentifier` a verzi, nahradit bundle (přejmenovat starý na `.old`, přesunout nový, smazat starý), spustit `open -n <cesta>` a ukončit se. Pokud aplikace není zapisovatelná (např. v `/Applications` bez práv), nabídnout ruční stažení.
- UI: nenápadná notifikace „K dispozici verze X – Aktualizovat a restartovat / Později“ + changelog z release notes.
- Soubory stažené aplikací přes Go HTTP nedostanou atribut karantény → po ad-hoc podpisu poběží bez Gatekeeper dialogu (ten bude jen u první ruční instalace z DMG: pravý klik → Otevřít; uvést v README).
- **GitHub Actions:**
  - `ci.yml` (push/PR): `macos-latest` (arm64) – `go vet ./...`, `go test ./internal/...`, `npm ci && npm run check && npm run build` ve `frontend`.
  - `release.yml` (tag `v*`): instalace Wails CLI, `wails build -platform darwin/arm64 -clean -ldflags "-X main.version=${TAG}"`, `codesign --force --deep -s - build/bin/MinorREST.app`, `ditto -c -k --keepParent` → zip, DMG (`hdiutil create`), podpis zipu (`go run ./scripts/sign-update`), `gh release create` s assety a notes.
- Bundle ID: `cz.novami.minorrest` (v `wails.json` / `build/darwin/Info.plist`), `LSMinimumSystemVersion` 13.0, `LSArchitecturePriority` arm64.

## 11. Fáze implementace

Každá fáze: implementace → `go vet` + dotčené testy → ruční ověření (`wails dev`) → commit → update `docs/PROGRESS.md`.
Testy jen hlavní cesta + nejdůležitější edge case.

### F0 – Bootstrap
- `go install github.com/wailsapp/wails/v2/cmd/wails@latest`, `wails doctor`.
- `wails init -n minor-rest -t svelte-ts` do dočasného adresáře, přenést do repa; frontend nahradit Svelte 5 (`npm create vite@latest`), zachovat `wailsjs`, upravit `wails.json` (`frontend:install`, `frontend:build`, `frontend:dev:watcher`, `outputfilename: MinorREST`, `info` sekce).
- `go.mod`: `module github.com/novami/minor-rest`.
- `main.go`: okno 1280×800, min 900×600, HiddenInset titlebar, menu (App, Soubor, Úpravy=EditMenu, Zobrazení, Okno, Nápověda).
- Frontend: `tokens.css` (light/dark), `fonts.css` (viz 8.6), i18n skeleton, prázdný 3-panelový layout s měnitelnou šířkou sidebaru.
- `.gitignore` (build/bin, frontend/node_modules, frontend/dist, .DS_Store), `Makefile` (`dev`, `build`, `test`, `lint`), `ci.yml`.
- **Hotovo když:** `wails dev` otevře okno s layoutem, Cmd+C/V funguje v inputu, font se mění retina/ne-retina, `make test` projde.

### F1 – Model, úložiště, resolver proměnných (jen Go)
- `internal/model`: typy dle kapitoly 2 (YAML tagy `yaml:"...,omitempty"`), `gopkg.in/yaml.v3` (zachovat pořadí klíčů, multiline `|`).
- `internal/storage`: `CreateProject`, `OpenProject(path) (*Tree, error)`, `CreateFolder`, `CreateRequest`, `SaveRequest`, `Rename`, `Move(id, targetFolder, index)`, `Duplicate`, `Delete` (Koš), slugify (NFC → ASCII přes `golang.org/x/text` transliteraci / vlastní mapa CZ/SK znaků + fallback), přepočet `seq`, atomický zápis (temp + rename).
- `internal/vars`: resolver dle kapitoly 3 + path params.
- Testy: roundtrip YAML s diakritikou, slugify (`Příliš žluťoučký kůň` → `prilis-zlutoucky-kun`), kolize názvů, move/seq, priorita proměnných, cyklus, dynamické proměnné.
- **Hotovo když:** `go test ./internal/...` zelené.

### F2 – Sidebar a projekty (UI)
- Bindingy v `app.go`: `ListProjects`, `CreateProject`, `OpenProjectDialog`, `CloseProject`, `GetTree`, CRUD operace, `RevealInFinder`.
- Workspace (`workspace.yaml`): otevřené projekty, poslední aktivní.
- Komponenty: `ProjectSwitcher`, `Tree`, `TreeNode`, kontextové menu, inline přejmenování, drag & drop (HTML5 DnD), hledání.
- Watcher fsnotify + event `tree:changed`.
- **Hotovo když:** lze vytvořit projekt, složky (vnořené), requesty, přejmenovat, přesunout, smazat do Koše, změny z Finderu se projeví.

### F3 – Editor requestu
- Taby otevřených requestů (store), dirty stav, Cmd+S, zavření s dialogem, obnovení tabů po restartu.
- `MethodSelect`, `UrlBar` (CodeMirror single-line + highlight `{{}}`), synchronizace query ↔ URL a detekce `:param` → path params.
- `KvEditor` s bulk edit a autocomplete hlaviček.
- Body editor (všechny typy), `CodeEditor` wrapper CodeMirror (json/xml/html/text), JSON format + validace.
- Záložky Nastavení a Dokumentace.
- **Hotovo když:** request se dá kompletně upravit, uložit a po znovuotevření je identický (vč. diakritiky).

### F4 – HTTP engine a odeslání
- `internal/httpclient` dle kapitoly 4 (bez auth – jen `none`/ruční hlavičky), sestavení `PreparedRequest` z requestu + dědičnosti (projekt → složky → request: headers, settings) + resolveru.
- Bindingy `Send(tabState) (runId)`, `Cancel(runId)`, event `request:done` s `ResponseMeta`, `GetResponseBody`.
- Tlačítko Odeslat ↔ Zrušit, spinner, Cmd+Enter / Cmd+.
- Historie odeslaných requestů (`history/`, posledních N).
- Testy viz kapitola 4.
- **Hotovo když:** GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS proti httpbin-like test serveru vrací správné metriky; HTTP/1.1 vs HTTP/2 vynucení funguje; redirect on/off funguje.

### F5 – Zobrazení odpovědi
- `ResponsePane`: meta bar (status badge + popis, čas s vodopádem, velikost rozpadu, protokol, IP), záložky dle 8.4, JSON Pretty s obarvením/folding/hledáním, Raw, Náhled, JSONPath filtr, tabulka hlaviček, cookies, časování, „Odesláno“, redirecty.
- Chybové stavy sítě srozumitelně (i18n).
- **Hotovo když:** velká JSON odpověď (5 MB) se zobrazí plynule, status kódy barevně, tooltips fungují.

### F6 – Prostředí, proměnné, tajemství
- `internal/secrets` (go-keyring), CRUD prostředí, editor prostředí/proměnných projektu/složky/globálních, výběr prostředí, oko (přehled), hover a autocomplete v UrlBaru i KvEditoru, varování nevyhodnocených proměnných před odesláním.
- **Hotovo když:** `{{baseUrl}}` se přepne změnou prostředí; tajná proměnná není v YAML, ale v Keychain (ověřit `security find-generic-password -s MinorREST`).

### F7 – Autorizace
- `internal/auth`: inherit, none, basic, bearer, apikey; OAuth2 (client_credentials, password, authorization_code + PKCE, refresh, cache v Keychain).
- UI záložka Auth u requestu, složky i projektu; zobrazení zdroje zděděné auth; OAuth2 panel s tokenem, expirací a tlačítky.
- Testy: basic s diakritikou, inherit řetěz, OAuth2 client_credentials proti `httptest` serveru, PKCE challenge.
- **Hotovo když:** všechny typy fungují proti testovacímu serveru, token se obnovuje.

### F8 – Ukládání a verzování odpovědí
- `internal/responses`: `Save(projectId, requestId, run, label)`, `List`, `Get`, `Delete`, `Rename`; maskování tajných hodnot ve snímku requestu.
- Tlačítko Uložit odpověď, záložka Verze (seznam, otevření, popisek, smazání), **diff dvou verzí** (`@codemirror/merge`), „Kopírovat jako cURL“ ze snímku.
- Post-response vars (extrakce JSONPath/hlavička → runtime proměnná) – jednoduchý editor v záložce Vars.
- Generování `.gitignore` v projektu dle nastavení `ignoreResponsesInGit`.
- **Hotovo když:** 3× uložení = v0001–v0003, diff ukazuje rozdíly, metadata kompletní.

### F9 – Kopírování jako cURL / bash, import cURL
- `internal/export` dle kapitoly 6 (+ tabulkové testy), ikona ⧉ s dropdownem, zapamatování formátu, toast „Zkopírováno“.
- `internal/importer/curl` + UI v URL baru.
- **Hotovo když:** zkopírovaný příkaz vložený do Terminálu (zsh i bash) vrátí stejnou odpověď jako aplikace, vč. diakritiky v těle i hlavičkách.

### F10 – Import OpenAPI / Swagger (+ Postman)
- `internal/importer/openapi` dle kapitoly 7, průvodce importu (soubor/URL, náhled, cíl), drag & drop souboru do okna.
- Volitelně `internal/importer/postman` (v2.1).
- **Hotovo když:** Petstore 2.0 i 3.0 vytvoří složky dle tagů, baseUrl v prostředí, ukázková těla, auth.

### F11 – Nastavení a i18n
- Okno nastavení (kapitola 9), aplikace nastavení za běhu, kompletní překlady cs/en (žádné natvrdo psané texty), překlad nativního menu.
- **Hotovo když:** přepnutí jazyka/tématu/fontu se projeví bez restartu (menu po restartu je OK).

### F12 – Auto-update a release pipeline
- `internal/updater` dle kapitoly 10, `scripts/sign-update` (generování klíče `-gen`, podpis souboru), `release.yml`, README (instalace, první spuštění, build ze zdrojů).
- Testy: porovnání verzí, ověření podpisu (platný/neplatný), parsování odpovědi GitHub API (fixture).
- **Hotovo když:** tag `v0.1.0` vytvoří release s assety; aplikace verze v0.0.9 (lokální build) najde update, ověří a nainstaluje.
- ⚠️ Vyžaduje od uživatele: vygenerovat klíč a vložit do GitHub Secrets, schválit push tagu.

### F13 – Dotažení
- Command palette (Cmd+K: hledání requestů, akce), prázdné stavy, onboarding (ukázkový projekt), klávesové zkratky v menu, výkon (virtualizace dlouhého stromu > 500 položek), a11y (fokus, aria), ikona aplikace.
- Finální QA checklist (kapitola 12).

## 12. QA checklist (před v1.0)
- [ ] Všech 7 metod, všechny typy body, multipart se souborem s diakritikou v názvu.
- [ ] HTTP/1.1, HTTP/2 (TLS), h2c; redirect on/off; timeout; cancel; self-signed cert s verifyTls=false.
- [ ] Metriky: časy dávají součet ≈ total, IP správná, velikosti headers/body sedí (porovnat s `curl -w`).
- [ ] Proměnné ve všech polích, priorita scope, tajné v Keychain.
- [ ] Auth: basic, bearer, apikey (header/query), OAuth2 3 granty + refresh.
- [ ] Uložení odpovědi, verze, diff.
- [ ] Kopírování cURL/bash → Terminál → stejný výsledek (UTF-8).
- [ ] Import Petstore 2.0/3.0/3.1.
- [ ] Ne-retina monitor: Menlo 13; retina: systémový font; přesun okna mezi monitory.
- [ ] Světlý/tmavý režim, cs/en.
- [ ] Auto-update end-to-end.
- [ ] Změna souboru z gitu se projeví ve stromu.

## 13. Rizika a otevřené body
- **Fonty:** zadání „na retina klasický macOS font“ je interpretováno jako SF Pro pro UI a SF Mono pro kód/odpovědi. Pokud má být i kód v SF Pro (proporcionální), změnit `--font-code`.
- **Bez notarizace:** první ruční spuštění vyžaduje pravý klik → Otevřít (nebo `xattr -dr com.apple.quarantine`). Auto-update to neovlivní. Notarizaci lze doplnit později (Developer ID + `notarytool` v release.yml).
- **Wails v2 vs v3:** v2 je stabilní; v3 přináší víc oken/tray, ale migrace není nutná. Logika v `internal/` je na Wails nezávislá, migrace by se týkala jen `main.go`/`app.go`/bindingů.
- **Odpovědi v gitu:** `.responses/` může repozitář nafouknout → výchozí `ignoreResponsesInGit: true`.
- **OAuth2 authorization code:** některé servery nepovolují `127.0.0.1` redirect s náhodným portem → umožnit pevný port v nastavení auth.
- **HTTP/2 velikost hlaviček:** na drátě jsou HPACK-komprimované; zobrazujeme nekomprimovanou velikost (uvést v tooltipu).
- **Systémová proxy / PAC:** PAC skripty nepodporujeme v1.

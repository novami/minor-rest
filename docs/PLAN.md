# MinorREST – implementační plán (revize 2)

> Implementuje se po fázích F0–F13, každá fáze má očíslované **kroky = commity**. Po každém kroku aktualizuj
> `docs/PROGRESS.md`. Analýza konkurence: `docs/ANALYZA.md`. Kontrakt backend ↔ frontend: kapitola 11.
> Kde plán říká „přesně“, drž se ho; kde je jen cíl, zvol nejjednodušší řešení.

## 0. Rozhodnutí (schválená uživatelem)

| Oblast | Volba |
|---|---|
| Platforma | macOS 13+, pouze Apple Silicon (`darwin/arm64`) |
| Backend | Go (aktuální stabilní, nyní 1.27) |
| GUI | **Wails v2** (nejnovější v2.x) + **Svelte 5 + TypeScript + Vite** |
| Editor kódu | CodeMirror 6 – jen pro víceřádkové editory (body, odpověď, docs, diff) |
| Úložiště | **YAML soubory** (projekt = adresář), tajné proměnné v **macOS Keychain** |
| YAML knihovna | `go.yaml.in/yaml/v3` (udržovaný fork `gopkg.in/yaml.v3`, stejné API) |
| Jazyk UI | čeština + angličtina (i18n, výchozí dle systému) |
| Podpis | ad-hoc (`codesign -s -`), bez notarizace; auto-update z GitHub Releases ověřený ed25519 |
| Licence / repo | MIT, https://github.com/novami/minor-rest.git, modul `github.com/novami/minor-rest` |
| Bundle ID | `com.github.novami.minorrest` |

## 1. Architektura

```
minor-rest/
├── main.go                 # wails.Run, menu, okno, embed frontend/dist
├── app.go, app_*.go        # App struct = tenké Wails bindingy (rozdělit po oblastech) → volá internal/*
├── internal/
│   ├── model/              # datové typy + DTO (yaml i json tagy)
│   ├── storage/            # YAML čtení/zápis, strom projektu, slugy, řazení, koš, watcher
│   ├── vars/               # resolver {{x}}, dynamické proměnné, path params
│   ├── secrets/            # Keychain (github.com/zalando/go-keyring)
│   ├── httpclient/         # odeslání, HTTP verze, redirecty, timing, IP, velikosti, dekomprese
│   ├── prepare/            # Request + dědičnost + proměnné + auth → httpclient.PreparedRequest
│   ├── auth/               # basic, bearer, apikey, oauth2 (golang.org/x/oauth2)
│   ├── responses/          # uložené odpovědi (verze), historie
│   ├── export/             # cURL generátor
│   ├── importer/{openapi,postman,curl}/
│   ├── settings/           # globální nastavení + workspace
│   └── updater/
├── frontend/src/
│   ├── App.svelte
│   ├── lib/components/     # Sidebar, Tree, Tabs, VarInput, KvEditor, CodeEditor, ResponsePane…
│   ├── lib/stores/         # *.svelte.ts (runes)
│   ├── lib/i18n/           # cs.json, en.json, t()
│   └── styles/             # tokens.css, fonts.css
├── frontend/wailsjs/       # generované bindingy (commitovat, needitovat ručně)
├── build/                  # appicon.png, darwin/Info.plist
├── scripts/sign-update/    # generování klíče a podpis update balíčku
└── .github/workflows/      # ci.yml, release.yml
```

**Zásady:**
- Backend je zdroj pravdy pro disk; frontend drží jen stav UI (otevřené taby, neuložené změny).
- Logika (resolver, HTTP, export, import, formátování JSON) je v Go s unit testy. Frontend zobrazuje.
- `internal/*` nesmí importovat Wails → `go test ./internal/...` běží bez sestaveného frontendu.
- Chyby z backendu: `fmt.Errorf("%s: %w", code, err)` kde `code` je konstanta (`NET_TIMEOUT`…). Frontend vezme text před první `:` jako i18n klíč `errors.<CODE>`, zbytek zobrazí jako detail.

### 1.1 Wails v2 – úskalí (čti před F0!)
1. **Edit menu**: bez `menu.EditMenu()` nefunguje Cmd+C/V/X/A/Z ve WebView.
2. Šablona `svelte-ts` má Svelte 3 → frontend vytvořit znovu (`npm create vite@latest frontend -- --template svelte-ts`), zachovat `wailsjs/`, v `wails.json` nastavit `frontend:install: "npm install"`, `frontend:build: "npm run build"`, `frontend:dev:watcher: "npm run dev"`, `frontend:dev:serverUrl: "auto"`.
3. `//go:embed all:frontend/dist` – bez existujícího `frontend/dist` selže `go build`/`go vet` hlavního balíčku. Proto: testy a vet jen `./internal/...`; hlavní balíček ověřuje `wails build`.
4. Bindingy se regenerují při `wails dev`/`wails build` (nebo `wails generate module`) – po každé změně signatur v `app*.go`.
5. DTO pro bindingy: exportovaná pole s **`json` i `yaml` tagy**; žádné `time.Time` (používat RFC 3339 `string` nebo ms `float64`), žádné `[]byte` pro velká data (jdou jako base64), žádná `interface{}`.
6. **Jedno okno**: v2 neumí druhé okno → Nastavení, editor prostředí, průvodce importem jsou modální dialogy ve stejném WebView.
7. Kontextové menu je HTML (nativní není). Výchozí kontextové menu WebView nechat vypnuté.
8. `OnBeforeClose` → pokud frontend hlásí neuložené změny (binding `SetDirty(bool)`), zobrazit `MessageDialog` Uložit vše / Zahodit / Zrušit.
9. Drop souboru do okna: `options.App.DragAndDrop{EnableFileDrop: true}` + `runtime.OnFileDrop` (pro import OpenAPI a multipart soubory).
10. **Zkratky – jeden zdroj:** vše, co je v nativním menu, má akcelerátor tam a menu položka jen emituje event `menu:<akce>`; frontend `keydown` řeší pouze zkratky, které v menu nejsou (Cmd+Enter, Cmd+., Escape). Jinak se akce provede dvakrát.
11. Okno: 1280×800, min 900×600, `mac.TitleBarHiddenInset()`; tažitelná oblast CSS `--wails-draggable: drag` (interaktivní prvky uvnitř `no-drag`); horní lišta má vlevo 80 px odsazení kvůli „semaforu“.
12. Schránka `runtime.ClipboardSetText`, prohlížeč `runtime.BrowserOpenURL`, dialogy `runtime.OpenFileDialog/SaveFileDialog/OpenDirectoryDialog/MessageDialog`.
13. **Ověřování UI:** `wails dev` vystaví aplikaci i na `http://localhost:34115` s funkčními bindingy → spustit na pozadí a ověřovat v prohlížeči (čtení stránky / screenshot), ne slepě.
14. Vygenerovaný `EventsOn` v `wailsjs/runtime/runtime.js` nevrací odhlašovací funkci → používat helper `onEvent`/`onMenu` z `frontend/src/lib/util/events.ts` (volá `EventsOnMultiple`).
15. Wails CLI je v `~/go/bin` (není v PATH) → používat `make dev|build|test|check`; Makefile nastavuje i `CGO_*FLAGS=-mmacosx-version-min=13.0` (jinak varování linkeru).

## 2. Datový model a formát na disku

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
- **Adresace ve všech API:** `projectId` + `rel` (relativní cesta od kořene projektu s `/`, kořen = `""`). `Request.id` (ULID) slouží pro `.responses/`, otevřené taby a historii – přežije přejmenování i přesun.
- **Slug:** NFC → NFD → odstranit znaky kategorie `Mn` → mapa nerozložitelných (`ł→l, đ→d, ß→ss, ø→o, æ→ae`) → lowercase → vše mimo `[a-z0-9]` na `-` → sloučit a oříznout `-` → max 60 znaků. Prázdný výsledek → `polozka`. Kolize (case-insensitive) → `-2`, `-3`. Příklad: `Příliš žluťoučký kůň` → `prilis-zlutoucky-kun`.
- Přejmenování = změna `name` + přejmenování souboru/adresáře na nový slug.
- Zápis atomicky (temp soubor ve stejném adresáři + `os.Rename`). Všechny vstupní řetězce normalizovat do NFC (`golang.org/x/text/unicode/norm`).
- Mazání = přesun do Koše přes cgo `NSFileManager trashItemAtURL` (`internal/storage/trash_darwin.go`), nikdy `os.RemoveAll`. Při smazání requestu přesunout do Koše i jeho `.responses/<id>/`.
- **Pořadí:** `seq` (int) u složek i requestů; ve stromu nejdřív složky, pak requesty, obojí dle `seq`, při shodě dle `name`. Po přesunu/vložení přečíslovat sourozence 1..n a zapsat jen změněné.
- **formatVersion:** projekt s vyšší verzí, než aplikace zná, otevřít jen pro čtení (banner „Aktualizujte MinorREST“).

### 2.3 `minorrest.yaml`
```yaml
formatVersion: 1
id: 01JCX6...                  # ULID (github.com/oklog/ulid/v2); klíč pro Keychain a cookies
name: Můj projekt
description: ""
vars:
  - { name: baseUrl, value: "https://api.example.com", enabled: true }
headers:                       # dědí se do všech requestů
  - { name: Accept, value: application/json, enabled: true }
auth: { type: none }
settings:                      # chybějící položka = globální výchozí z nastavení aplikace
  httpVersion: auto            # auto | http1 | http2
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
settings: {}                # jen přepsané položky; chybějící = zděděno (Go: ukazatele + omitempty)
docs: ""
```
- **Zdroj pravdy pro query je `params.query`**, `url` na disku query neobsahuje. URL bar zobrazuje `url + "?" + zapnuté parametry` (bez kódování, tak jak je uživatel napsal); při editaci URL baru se text za prvním `?` rozparsuje zpět do `params.query` (vypnuté řádky zůstávají na svých pozicích). Parametr bez `=` (`?wsdl`) dostane `bare: true` a odešle se bez `=`; `?flag=` i nový prázdný řádek se odešlou jako `flag=`. Parsování dělat ručně (split `&`, `=`), ne přes `URL` API – nesmí se rozbít `{{proměnné}}`.
- `:nazev` v cestě (segment začínající `:`, ne port) → automaticky řádek v `params.path`; zmizí-li z URL, řádek odstranit.
- Cesty k souborům (`multipart.path`, `binaryPath`): pokud leží uvnitř projektu, ukládat relativně ke kořeni projektu, jinak absolutně.
- Prázdné sekce se nezapisují (`omitempty`), pořadí klíčů dle struktury → stabilní diffy v gitu.

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
`.responses/<requestId>/v0001.yaml` (metadata) + `v0001.body` (**tělo vždy v samostatném souboru**, přesné dekomprimované bajty v původním kódování – žádné vkládání do YAML).
```yaml
version: 3
savedAt: "2026-11-16T15:04:05+01:00"
label: ""
request:                         # snímek skutečně odeslaného requestu
  method: POST
  url: https://api.example.com/users?page=2
  headers: [{ name: Authorization, value: "Bearer ***" }]   # maskování viz 2.8
  bodySize: 128
  body: "…"                      # jen textové tělo do 256 kB, jinak vynechat
response:
  status: 201
  statusText: Created
  proto: HTTP/2.0
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
Číslo verze = nejvyšší existující + 1 (smazané se nerecyklují). Historie (2.1) používá stejný formát.

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
- `go-keyring` na macOS volá `/usr/bin/security` → žádné dialogy oprávnění ani po aktualizaci ad-hoc podepsané aplikace. Limit hodnoty cca 2,5 kB → chybu `SECRET_TOO_BIG` zobrazit uživateli.
- Auth pole (heslo, token, client secret) jsou obyčejná textová pole ukládaná do YAML. Pokud obsahují literál (ne `{{…}}`), zobrazit u pole varování s akcí **„Převést na tajnou proměnnou“** (vytvoří secret proměnnou v aktivním prostředí a pole nahradí `{{nazev}}`).
- **Maskování** (uložené odpovědi, historie, volitelně export): hodnoty hlaviček `Authorization`, `Proxy-Authorization`, `Cookie`, `Set-Cookie`, hlavičky/query z apikey auth a všechny výskyty hodnot secret proměnných → `***` (u `Authorization` zachovat schéma: `Bearer ***`).

## 3. Proměnné

- Syntaxe `{{nazev}}`, název `[A-Za-z0-9_.-]+`, mezery uvnitř závorek tolerovat. `\{{` = literál `{{`.
- **Priorita (vyšší vyhrává):** runtime → request → složky (nejbližší první) → prostředí → projekt → globální. Vypnuté (`enabled: false`) se ignorují.
- **Runtime proměnné:** jen v paměti, per projekt (mapa v App), plní je `extract` a zobrazují se v přehledu „oko“ (lze je tam smazat). Po restartu prázdné.
- Dynamické: `{{$uuid}}`, `{{$ulid}}`, `{{$timestamp}}`, `{{$timestampMs}}`, `{{$isoTimestamp}}`, `{{$randomInt}}` (0–1000), `{{$randomString}}` (16 znaků). Každý **výskyt** se vyhodnotí zvlášť, kromě `$timestamp*` (jedna hodnota na odeslání). Pojmenovaná proměnná má v rámci odeslání jednu hodnotu (`id: "{{$uuid}}"` → `{{id}}` všude stejné).
- Rekurze: hodnota může obsahovat proměnné, max hloubka 10, cyklus → chyba `VAR_CYCLE`.
- Neznámá proměnná: ponechat literál `{{x}}`, vrátit v seznamu `unresolved`; UI před odesláním zobrazí nemodální varování (odeslání neblokuje). Výjimka: nevyhodnocená proměnná v hostu → chyba `VAR_UNRESOLVED_HOST` (detail = názvy; UI napoví vybrat prostředí).
- Platí v: URL, query, path, headers (název i hodnota), body raw/form/multipart text, cesty souborů, všechna auth pole.
- **Sestavení URL při odeslání** (`internal/prepare`): vyhodnotit proměnné v `url` → nahradit `:param` (hodnota po vyhodnocení, `url.PathEscape`) → pokud chybí schéma, doplnit `http://` → připojit zapnuté query parametry kódované funkcí `encodeQuery` (percent-encode UTF-8, mezera jako `%20`, **existující platné `%XX` sekvence zachovat**) → `url.Parse` (chyba → `URL_INVALID`).
- API (`internal/vars`): `New(scopes ...Scope)` (pořadí = priorita), `Resolve(s string) (string, []string /*unresolved*/, error /*VAR_CYCLE*/)`, `Unresolved()`, `Explain() []VarInfo{Name, Value, Resolved, Source, Ref, Secret}` pro UI – tajné hodnoty se nevrací a v `Resolved` se maskují `***`. Sestavení URL: `vars.BuildURL(url, path, query, resolver)`, `EncodeQuery`, `EncodeQueryComponent`; `internal/prepare` je jen volá.

## 4. HTTP engine (`internal/httpclient`)

Vstup `PreparedRequest{Method, URL, Headers []KV (pořadí zachovat), Body io.Reader/bytes, BodySize}` + `Options{HTTPVersion, FollowRedirects, MaxRedirects, Timeout, VerifyTLS, Proxy, Jar, MaxBodyBytes}`. Výstup `Result` (viz 11.2).

- **Nový `http.Transport` pro každé odeslání** (žádné sdílení spojení mezi běhy → kompletní a opakovatelné časování), po dokončení `CloseIdleConnections()`.
- **HTTP verze** (`http.Protocols`, Go ≥ 1.24, nastavit `Transport.Protocols`):
  - `auto`: HTTP1 + HTTP2 (ALPN rozhodne); pro `http://` jen HTTP/1.1,
  - `http1`: jen `SetHTTP1(true)`,
  - `http2`: jen `SetHTTP2(true)`; pro `http://` navíc `SetUnencryptedHTTP2(true)` (h2c prior knowledge).
  - Skutečnou verzi brát z `resp.Proto`. Server bez h2 při `http2` → chyba `HTTP2_UNSUPPORTED`.
- **TLS:** `TLSClientConfig{InsecureSkipVerify: !VerifyTLS}`; z `resp.TLS` verze, cipher, SNI, subjekt a expirace leaf certifikátu.
- **Redirecty:** vlastní `CheckRedirect` – při `FollowRedirects=false` vrací `http.ErrUseLastResponse`; jinak limit `MaxRedirects` (překročení → `REDIRECT_LIMIT`). Každý skok zaznamenat `{status, method, url, location}`.
- **Timing** (`net/http/httptrace`): hooky se volají pro každý skok → držet stav per skok; do `timing` jde **poslední skok** (dns, connect, tls, ttfb, download), `totalMs` = od začátku prvního do konce čtení těla posledního. `ttfbMs` = WroteRequest → GotFirstResponseByte. Z `DNSDone` uložit všechny vrácené adresy (`resolvedAddrs`).
- **IP adresy:** `GotConnInfo.Conn.RemoteAddr()/LocalAddr()` posledního skoku.
- **Skutečně odeslané hlavičky:** hook `WroteHeaderField(key, values)` posledního skoku → záložka „Odesláno“ a `sizes.reqHeaders` (u HTTP/2 obsahuje i pseudo-hlavičky `:method`, `:path`, `:authority` – zobrazit).
- **Hlavičky requestu:** `Host` z uživatelských hlaviček → nastavit `req.Host` (ne do `Header`); `Content-Length` určuje délka těla (uživatelskou hodnotu ignorovat). Automatické hlavičky, pokud je uživatel nezadal: `User-Agent: MinorREST/<verze>`, `Accept: */*`, `Accept-Encoding: gzip, deflate, br, zstd`, `Content-Type` dle typu body. V UI jsou šedě a jdou vypnout (kromě `Host` a `Content-Length`); vypnutý `User-Agent` = `req.Header.Set("User-Agent", "")`.
- **Komprese:** `DisableCompression: true`; tělo číst přes počítající reader (`bodyWire`) a dekódovat dle `Content-Encoding` (`compress/gzip`, `compress/flate` – zkusit zlib, pak raw; `github.com/andybalholm/brotli`; `github.com/klauspost/compress/zstd`). Neznámé kódování → ponechat bajty.
- **Velikosti:** `reqHeaders` = request line + `Name: value\r\n` + `\r\n`; `reqBody`; `headers` = status line + hlavičky + `\r\n`; `bodyWire`; `bodyDecoded`. (HTTP/2: nekomprimovaná velikost – uvést v tooltipu.)
- **Tělo odpovědi – limity:** do 10 MB v paměti; větší se streamuje do temp souboru (`os.CreateTemp`) až do `MaxBodyBytes` (výchozí 100 MB, pak oříznout a `truncated: true`). Engine drží posledních 20 výsledků v paměti (mapa `runId → Result`, LRU), temp soubory mazat při vyřazení a při ukončení.
- **Kódování textu:** `charset` z `Content-Type`, jinak detekce (`golang.org/x/net/html/charset`); pro zobrazení převést do UTF-8 (důležité pro `windows-1250` / `iso-8859-2`). Uložené tělo zůstává v původních bajtech. Binární obsah (není text dle Content-Type ani validní po dekódování) → `isBinary: true`.
- **Tělo requestu:** JSON/XML/text/HTML jako UTF-8, `Content-Type` s `; charset=utf-8` (jen pokud ho doplňujeme automaticky). Form-urlencoded: `url.Values`-like encoder se zachováním pořadí. Multipart: `mime/multipart`, název souboru s diakritikou → `filename="…"` v UTF-8 (jak to dělají prohlížeče), `Content-Type` části z přípony, pokud není zadán. Chybějící soubor → `FILE_NOT_FOUND`.
- **Zrušení/timeout:** `context.WithTimeout` přes celé odeslání včetně čtení těla; `Cancel(runId)` volá cancel → chyba `CANCELED`.
- **Mapování chyb:** DNS → `NET_DNS`, connection refused → `NET_REFUSED`, timeout/deadline → `NET_TIMEOUT`, x509 → `TLS_VERIFY`, ostatní TLS → `TLS_ERROR`, jinak `NET_ERROR` (+ původní text jako detail).
- **Cookies:** `net/http/cookiejar` per projekt, perzistence do `cookies/<projectId>.json` po každém odeslání; vypnutelné (`cookieJar`).
- **Proxy:** `none | system | manual`; `system` = `scutil --proxy` (HTTPEnable/HTTPProxy/HTTPPort, HTTPS…, ExceptionsList) čtené při odeslání; PAC nepodporujeme.
- Testy (`httptest`): h1, h2 (`NewUnstartedServer` + `EnableHTTP2` + `StartTLS`), vynucení verze, řetěz redirectů on/off/limit, gzip + br velikosti, windows-1250 → UTF-8, timeout, cancel, odeslané hlavičky.

## 5. Autorizace (`internal/auth`)

`Apply(ctx, pr *PreparedRequest, cfg model.Auth, deps) error` – volá se v `prepare` po vyhodnocení proměnných v polích auth.
- **inherit:** od requestu přes složky nahoru k projektu, první ne-`inherit` vyhrává; projekt s `inherit` = `none`. `prepare` vrací i `AuthSource` (odkud se zdědilo) pro UI.
- **basic:** `base64(utf8(user + ":" + pass))`. **bearer:** `Authorization: <prefix> <token>`. **apikey:** hlavička nebo query parametr.
- Uživatelem ručně zadaná hlavička `Authorization` má přednost před auth (v UI varování).
- **oauth2** (`golang.org/x/oauth2`, `clientcredentials`):
  - HTTP klient pro token endpoint předat přes `context.WithValue(ctx, oauth2.HTTPClient, client)` – stejné TLS/proxy nastavení jako request.
  - `clientAuth` → `oauth2.AuthStyleInHeader` / `AuthStyleInParams`.
  - authorization_code: listener na `127.0.0.1:<redirectPort>`, `state` (náhodných 32 B) + PKCE S256 (`oauth2.GenerateVerifier`, `S256ChallengeOption`), otevřít prohlížeč, čekat na `/callback` max 5 min (zrušitelné z UI), odpovědět HTML stránkou „Hotovo, okno můžete zavřít“, vyměnit code za token.
  - Cache: klíč `sha256(tokenUrl|clientId|scope|grantType|username)[:16]`; do Keychain zvlášť `…/oauth/<klíč>/access` a `…/refresh`, expirace a typ do paměti + `workspace.yaml`. Token větší než limit Keychain → jen v paměti (bez chyby).
  - Před odesláním: platný token použít; expirovaný (rezerva 30 s) → refresh, při neúspěchu u client_credentials/password získat nový automaticky, u authorization_code vrátit `OAUTH_LOGIN_REQUIRED` (UI nabídne „Přihlásit“).
- Digest = backlog.

## 6. Export – kopírování jedním klikem (`internal/export`)

Ikona ⧉ vedle „Odeslat“: klik = zkopíruje v naposledy zvoleném formátu + toast; šipka = výběr (jen cURL, potvrzeno uživatelem):
1. **cURL – víceřádkový** (výchozí; ` \` + odsazení 2 mezery, jeden flag na řádek)
2. **cURL – jeden řádek**

Vstup je stejný `PreparedRequest` jako pro odeslání (tj. vyhodnocené proměnné, auth, path params, query), takže export = přesně to, co by se odeslalo. OAuth2: použít token z cache, bez tokenu → chyba `OAUTH_LOGIN_REQUIRED`.

Pravidla cURL:
- Quoting: vše v single quotes; `'` uvnitř → `'\''`. Diakritika zůstává UTF-8. Žádné `$'…'`.
- Metoda: GET bez těla → nic; **HEAD → `--head`** (ne `-X HEAD`, to čeká na tělo); jinak `-X METHOD`.
- `-H 'Name: value'` pro uživatelské/zděděné/auth hlavičky a automatický `Content-Type`; nevypisovat automatické `User-Agent`, `Accept`, `Accept-Encoding`, `Host`, `Content-Length`. Pokud je automatický `Accept-Encoding` zapnutý → `--compressed`.
- Tělo: raw → `--data-raw '…'` (newlines ponechat uvnitř quotes); form → `--data-urlencode 'name=value'` za každé pole; multipart → `-F 'name=value'` / `-F 'name=@/abs/cesta;type=…'`; binary → `--data-binary '@/abs/cesta'`.
- Volby: `--http1.1` / `--http2` (https) / `--http2-prior-knowledge` (http) – jen pokud není `auto`; `-L --max-redirs N` pokud follow; `-k` pokud verifyTls=false; `--max-time <s>`.
- Přepínač „Maskovat tajné hodnoty“ (výchozí vypnuto) – pravidla 2.8.

Testy: tabulkové („golden“) – diakritika (`Příliš žluťoučký kůň úpěl ďábelské ódy`), apostrof, `$HOME`, `!`, zpětné lomítko, víceřádkové JSON, multipart se souborem, HEAD, všechny volby.

**Import cURL** (`internal/importer/curl`): tokenizace shellu (`github.com/google/shlex`; předtím odstranit `\`+newline), flagy `-X/--request, -H, -d/--data/--data-raw/--data-binary/--data-urlencode, -F/--form, -u, --url, -L, -k, -I/--head, --http1.1, --http2, --compressed, -b, -A`; neznámé flagy ignorovat a vrátit v `warnings`. `-d` bez `-X` → POST; JSON tělo → `body.type: json`; `-u` → basic auth; query z URL → `params.query`.

## 7. Import OpenAPI / Swagger (`internal/importer/openapi`)

- `github.com/pb33f/libopenapi`: `NewDocument(bytes)` → dle verze `BuildV3Model()` (3.0/3.1) nebo `BuildV2Model()` (Swagger 2.0). JSON i YAML. Zdroj: soubor nebo URL.
- **Dva kroky:** (1) oba modely převést na vlastní neutrální strukturu `Spec{Title, Description, Servers []string, Security…, Operations []Operation{Method, Path, Tag, Summary, Description, Params, Body}}`; (2) jeden generátor `Spec` → projekt/složky/requesty. Testuje se hlavně krok 2.
- Mapování:
  - `info.title` → název projektu; alternativně import do existujícího projektu jako nová složka,
  - první tag operace → složka (název tagu), bez tagu → „Ostatní“ / „Other“; alternativa seskupení dle prvního segmentu cesty,
  - název requestu: `summary` → `operationId` → `METHOD /path`; `description` → `docs`; `seq` dle pořadí ve specifikaci,
  - servery (3.x `servers[].url` s dosazenými default proměnnými / 2.0 `schemes://host/basePath`) → proměnná `baseUrl`; první server = prostředí „Default“, další servery = další prostředí; `url` requestu = `{{baseUrl}}/path`,
  - `{id}` → `:id` + `params.path` (hodnota z `example`/`default`),
  - query a header parametry → `params.query` / `headers` (required → zapnuté, ostatní vypnuté; hodnota z example/default/enum[0]),
  - tělo: preferovat `application/json` → `example` → první z `examples` → vygenerovat ze schématu (object rekurzivně, array s 1 prvkem, enum[0], default, dle `format`: date-time/date/uuid/email/uri → ukázka, string → `"string"`, number → `0`, boolean → `false`; `allOf` sloučit, `oneOf/anyOf` první; **max hloubka 6 a detekce cyklických `$ref`**); form typy → `form` / `multipart` pole,
  - `securitySchemes` + globální `security` → auth projektu: http basic → basic `{{username}}/{{password}}`; http bearer → bearer `{{token}}`; apiKey → apikey `{{apiKey}}`; oauth2 → oauth2 (první flow, URL, scopes); odpovídající prázdné proměnné založit v projektu. Requesty mají `inherit`; operace se `security: []` → `none`.
- Průvodce (modál): zdroj (soubor / URL / drop) → náhled (název, počty složek a requestů, varování) → cíl (nový projekt / existující) a seskupení → Import.
- Testy: fixtures Petstore 2.0, Petstore 3.0, malá 3.1 s `$ref` cyklem.

Postman Collection v2.1 (`internal/importer/postman`, volitelné v F10): item/folder → strom, `request` (method, url.raw, header, body modes raw/urlencoded/formdata), `auth` (basic/bearer/apikey/oauth2), `variable` → proměnné projektu; skripty ignorovat s varováním.

## 8. UI / UX

### 8.1 Rozvržení
```
┌───────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●  [Projekt ▾]                         [Prostředí: Vývoj ▾] [👁] [⚙]      │
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
- Sidebar: měnitelná šířka, skrytelný (Cmd+B). Split request/odpověď: dole (výchozí) nebo vpravo. Vše ukládat do workspace.
- Barvy metod: GET zelená, POST oranžová, PUT modrá, PATCH fialová, DELETE červená, HEAD šedá, OPTIONS tyrkysová.
- **Status badge:** 1xx šedá, 2xx zelená, 3xx modrá, 4xx oranžová, 5xx červená; text `201 Created`; tooltip = lokalizovaný popis kódu (i18n tabulka `status.<kód>` pro všechny registrované kódy IANA). Chyba sítě = červený panel s lokalizovanou chybou + detail.
- Tooltip času: vodopád DNS / TCP / TLS / TTFB / Download. Tooltip velikosti: odpověď hlavičky / tělo (přenesené → dekomprimované), request hlavičky / tělo.
- Čísla formátovat přes `Intl.NumberFormat` dle jazyka UI (cs: `6,4 kB`, `1 234 ms`); jednotky B / kB / MB (1 kB = 1000 B), čas ms do 1000, pak s.

### 8.2 Sidebar
- Záložky **Projekt** (strom) a **Historie** (posledních N odeslání: čas, metoda, URL, status; klik otevře detail odpovědi jen pro čtení + „Otevřít request“).
- Přepínač projektů: seznam otevřených + „Nový projekt…“, „Otevřít adresář…“, „Importovat OpenAPI…“, „Nastavení projektu“, „Zavřít projekt“.
- Strom: složky rozbalitelné (stav ve workspace), requesty s badge metody. Dvojklik/Enter = otevřít v tabu.
- Kontextové menu: Nový request, Nová složka, Přejmenovat, Duplikovat, Kopírovat jako cURL, Nastavení složky, Zobrazit ve Finderu, Smazat (potvrzení → Koš).
- **Nový request** se hned vytvoří na disku s názvem „Nový request“ (GET, prázdná URL), otevře se v tabu a název je v inline editaci. Žádné „koncepty jen v paměti“.
- Drag & drop (HTML5 DnD; kdyby ve WKWebView zlobil, pointer events): přesun mezi složkami + pořadí, indikátor místa vložení; složku nelze vložit do sebe sama.
- Hledání: filtr podle názvu, URL a metody (podřetězec bez ohledu na diakritiku a velikost písmen); zobrazí shody včetně nadřazených složek.
- **Watcher** (`internal/watch`: FSEvents přes `github.com/fsnotify/fsevents` – jeden rekurzivní stream na projekt, bez limitu deskriptorů jako u kqueue/fsnotify; ignorovat skryté položky `.git`, `.responses`, `.tmp-*`; latence 300 ms): po změně emit `tree:changed`. Vlastní zápisy potlačí příznak `IgnoreSelf` (změny vlastního procesu se nehlásí). Při načtení stromu dostanou requesty se shodným ID (kopie z Finderu) nové ID; původní zůstane nejdříve vytvořenému souboru. Otevřený tab: bez lokálních změn → tiše znovu načíst; s lokálními změnami → banner „Změněno na disku: Načíst z disku / Ponechat moje“.

### 8.3 Editor requestu
- **`VarInput`** – jednořádkové pole se zvýrazněním proměnných, použité všude (URL bar, buňky KvEditoru, auth pole): `<input>` s průhledným textem nad zrcadlovým `<div>` s obarvenými tokeny (stejný font a padding, synchronizovaný scroll). Zvýraznění: známá proměnná zeleně, neznámá červeně, dynamická `$` modře. Hover nad tokenem → popover s hodnotou a zdrojem (secret jako `••••`). Po napsání `{{` našeptávač. **Ne** CodeMirror na jednořádková pole.
- URL bar: Enter = odeslat; vložení textu začínajícího `curl ` → nabídka „Importovat cURL do tohoto requestu“.
- **`KvEditor`** (query, path, headers, form, multipart, vars, extract): checkbox, klíč, hodnota (`VarInput`), popis, smazat; psaní do posledního prázdného řádku vytvoří nový; přetažení pořadí; **Bulk edit** (textarea, řádek `klíč: hodnota`, prefix `//` = vypnutý; popis se v bulk režimu zachová podle klíče). U headers našeptávač názvů a běžných hodnot; nad tabulkou sbalitelný blok „Automatické a zděděné hlavičky“ (šedě, se zdrojem, s možností vypnout – vypnutí = řádek se stejným názvem a `enabled: false` v requestu).
- Body: přepínač typu. Raw = CodeMirror (jazyk dle typu), tlačítko „Formátovat“ a validace jen jako varování. **Formátování JSON dělá backend** (`FormatJSON`): `json.Indent` (2 mezery) – nikdy `JSON.parse/stringify` (ztrácí přesnost velkých čísel a mění formát). Kvůli proměnným mimo řetězce (`{"id": {{id}}}`) před formátováním nahradit `{{…}}` zástupnými tokeny a po něm vrátit.
- Form/multipart = KvEditor (multipart: přepínač text/soubor, výběr souboru dialogem nebo dropem). Binary = výběr souboru.
- Auth: výběr typu + formulář; u `inherit` řádek „Zděděno z: Složka X → Basic“. OAuth2 panel: stav tokenu, expirace, tlačítka Získat token / Obnovit / Smazat.
- Nastavení: HTTP verze, redirecty, max redirectů, timeout, TLS – každé s volbou „Zdědit (aktuálně: …)“.
- Dokumentace: CodeMirror markdown, bez náhledu (backlog).
- Taby: tečka = neuložené změny; Cmd+S uloží; zavření neuloženého → dialog Uložit / Zahodit / Zrušit. **Odeslat funguje i bez uložení** (odesílá se stav tabu). Otevřené taby se obnoví po restartu.

### 8.4 Odpověď
- **Tělo:** Pretty (JSON přes backend `json.Indent`; XML/HTML odsazení ve frontendu; CodeMirror read-only, obarvení, folding, Cmd+F), Raw (text v UTF-8 bez úprav), Náhled (HTML: `<iframe sandbox="" srcdoc>`; obrázky: `<img>` z data URL do 10 MB). Výchozí pohled dle Content-Type.
- Binární nebo oříznuté tělo → informační panel (typ, velikost) + „Uložit do souboru“.
- Tělo > 5 MB: Pretty se nespouští automaticky (tlačítko „Přesto formátovat“). Tělo > 10 MB: zobrazit první 1 MB + „Uložit do souboru“.
- JSONPath filtr (pole nad tělem, `github.com/ohler55/ojg/jp` v backendu, výsledek jako formátovaný JSON; chybný výraz → červený rámeček).
- Hlavičky (tabulka, kopírování hodnoty), Cookies (z `Set-Cookie`), Časování (vodopád, IP vzdálená/lokální, DNS adresy, protokol, TLS detail), Odesláno (skutečné hlavičky + tělo requestu), Redirecty (jen pokud nějaké byly), Verze.
- Akce: **Uložit odpověď** (Cmd+Shift+S, volitelný popisek), Kopírovat tělo, Uložit tělo do souboru.
- Stavy panelu: prázdný (nápověda Cmd+Enter), odesílání (spinner, uplynulý čas, Zrušit), odpověď, chyba.

### 8.5 Prostředí a proměnné
- Dropdown prostředí v titlebaru („Žádné“ + seznam + „Spravovat…“), Cmd+E.
- „Oko“: popover se všemi platnými proměnnými pro aktivní tab (název, hodnota, zdroj), runtime proměnné lze smazat.
- Modál „Prostředí“: seznam vlevo (přidat, duplikovat, přejmenovat, smazat), KvEditor vpravo se sloupcem 🔒 (secret; hodnota `••••` + tlačítko zobrazit). Záložky modálu: Prostředí | Proměnné projektu | Globální.
- Proměnné, hlavičky a auth složky: modál „Nastavení složky“; totéž pro projekt („Nastavení projektu“ + HTTP nastavení + `ignoreResponsesInGit`).

### 8.6 Fonty a vzhled
```css
:root { --font-ui: Menlo, monospace; --font-code: Menlo, monospace; --font-size: 13px; }
@media (-webkit-min-device-pixel-ratio: 2), (min-resolution: 2dppx) {
  :root { --font-ui: -apple-system, BlinkMacSystemFont, sans-serif;
          --font-code: ui-monospace, "SF Mono", Menlo, monospace; }
}
```
- Media query se přepočítá i při přesunu okna mezi monitory. Nastavení může přepsat (inline styl na `:root`): Automaticky / vlastní rodina + velikost zvlášť pro UI a kód.
- Téma Systém / Světlé / Tmavé: CSS proměnné v `tokens.css`, `data-theme` na `<html>`; CodeMirror téma postavené na stejných proměnných.
- Bez UI knihovny; vlastní malé komponenty (Button, Modal, Dropdown, Tabs, Toast, Popover, ContextMenu).

### 8.7 Zkratky
V menu (akcelerátor → event `menu:*`): Cmd+N nový request, Cmd+Shift+N nová složka, Cmd+S uložit, Cmd+Shift+S uložit odpověď, Cmd+W zavřít tab, Cmd+K paleta, Cmd+E prostředí, Cmd+B sidebar, Cmd+, nastavení, Cmd+Shift+C kopírovat jako cURL, Cmd+L fokus URL, Cmd+D duplikovat.
Jen ve frontendu: Cmd+Enter odeslat, Cmd+. zrušit, Escape zavřít modál/popover, F2 přejmenovat ve stromu.

### 8.8 i18n
- `cs.json`, `en.json` (ploché klíče s tečkami), `t(key, params)`, jazyk `auto | cs | en` (`auto` = `navigator.language`). Žádný natvrdo psaný text v komponentách.
- Nativní menu: mapa překladů v Go, při změně jazyka menu přestavět (`runtime.MenuSetApplicationMenu` + `MenuUpdateApplicationMenu`).

## 9. Nastavení aplikace (`settings.yaml`, modál Cmd+,)
- **Obecné:** jazyk, téma, výchozí adresář projektů, obnovit projekty a taby při startu.
- **Vzhled:** font UI a kódu (Automaticky dle displeje / vlastní), velikost, poloha panelu odpovědi.
- **Requesty (výchozí):** HTTP verze, redirecty + max, timeout, ověřování TLS, User-Agent, cookie jar.
- **Proxy:** žádná / systémová / ruční URL.
- **Odpovědi:** max velikost těla, délka historie, práh automatického Pretty.
- **Kopírování:** výchozí formát, maskovat tajné hodnoty.
- **Aktualizace:** automaticky kontrolovat a stahovat (výchozí **zapnuto**), „Zkontrolovat nyní“, aktuální verze.
Změny se projeví ihned bez restartu. Priorita HTTP nastavení: request → projekt → globální.

## 10. Automatické aktualizace a release

Repozitář a releasy jsou veřejné (potvrzeno uživatelem) → updater nepotřebuje token.

- Verze: `-ldflags "-X main.version=v1.2.3"`, vývojový build `dev` (kontrola aktualizací vypnutá). Porovnání `golang.org/x/mod/semver`; nikdy neinstalovat nižší ani stejnou verzi; prerelease přeskočit.
- Kontrola: 10 s po startu a pak každých 24 h → `GET https://api.github.com/repos/novami/minor-rest/releases/latest` (`User-Agent: MinorREST/<verze>`, `If-None-Match` s uloženým ETag). Chyby sítě tiše logovat.
- Assety: `MinorREST-<verze>-darwin-arm64.zip`, `….zip.sig` (base64 ed25519 podpis celého zipu), `MinorREST-<verze>-darwin-arm64.dmg` (ruční instalace).
- Ověření: veřejný klíč v `internal/updater/pubkey.go`; privátní jen v GitHub Secret `UPDATE_SIGNING_KEY`. Bez platného podpisu neinstalovat (`UPDATE_BAD_SIGNATURE`).
- Průběh: při nalezení verze stáhnout na pozadí do `~/Library/Caches/MinorREST/update/`, ověřit podpis, rozbalit `ditto -x -k`, zkontrolovat `CFBundleIdentifier` (`/usr/libexec/PlistBuddy`) → toast „Verze X je připravena: Restartovat nyní / Později“ (+ odkaz na poznámky k vydání). „Později“ = instalace při ukončení aplikace.
- Instalace: cesta bundlu = `os.Executable()` → nahoru k `*.app`; přejmenovat starý na `MinorREST.app.old`, přesunout nový, smazat starý, `open -n <cesta>`, ukončit. Selhání → vrátit původní.
- Nelze aktualizovat, pokud: cesta obsahuje `/AppTranslocation/` (aplikace spuštěná z karantény – vyzvat k přesunu do `/Applications`), bundle není zapisovatelný, nebo jde o `dev` build → nabídnout odkaz na ruční stažení.
- **První ruční instalace (README):** aplikace není notarizovaná → po přetažení do `/Applications` buď `xattr -dr com.apple.quarantine /Applications/MinorREST.app`, nebo Nastavení systému → Soukromí a zabezpečení → „Přesto otevřít“ (na macOS 15+ už pravý klik → Otevřít nefunguje). Aktualizace stažené aplikací karanténu nemají.
- **`ci.yml`** (push/PR, `macos-latest`): `go vet ./internal/... && go test ./internal/...`; ve `frontend`: `npm ci && npm run check && npm run build`.
- **`release.yml`** (tag `v*`, `permissions: contents: write`): setup Go + Node, instalace Wails CLI, zapsat verzi do `wails.json` (`info.productVersion`, bez `v`), `wails build -platform darwin/arm64 -clean -ldflags "-X main.version=$TAG"`, `codesign --force --deep -s - build/bin/MinorREST.app`, `ditto -c -k --keepParent` → zip, `hdiutil create -volname MinorREST -srcfolder … -format UDZO` → dmg, `go run ./scripts/sign-update -file <zip>` (klíč z env), `gh release create "$TAG" --generate-notes <assety>`.
- `scripts/sign-update`: `-gen` vypíše nový pár klíčů (base64), `-file` podepíše soubor klíčem z `UPDATE_SIGNING_KEY`.
- `Info.plist`: `LSMinimumSystemVersion` 13.0, `CFBundleIdentifier` viz kap. 0.

## 11. Kontrakt backend ↔ frontend

Názvy jsou závazné; drobné úpravy signatur jsou v pořádku, ale zapiš je sem.

### 11.1 Bindingy (`App` metody)
```go
// Projekty a strom (F2)
ListProjects() []ProjectInfo                       // {ID, Name, Path, ReadOnly}
CreateProject(name, parentDir string) (ProjectInfo, error)
OpenProjectDialog() (*ProjectInfo, error)          // nil = zrušeno
CloseProject(projectID string) error
GetTree(projectID string) (TreeNode, error)        // {Kind: "folder"|"request", Rel, Name, Seq, ID, Method, URL, Children}
CreateFolder(projectID, parentRel, name string) (TreeNode, error)
CreateRequest(projectID, parentRel, name string) (TreeNode, error)
RenameNode(projectID, rel, newName string) (TreeNode, error)   // vrací nový Rel
MoveNode(projectID, rel, targetParentRel string, index int) (TreeNode, error)
DuplicateNode(projectID, rel, copySuffix string) (TreeNode, error)   // přípona v jazyce UI, "" = „ kopie“
DeleteNode(projectID, rel string) error
RevealInFinder(projectID, rel string) error
GetWorkspace() Workspace;  SaveWorkspace(w Workspace) error;  SetDirty(dirty bool)
// Workspace {Projects (spravuje backend, ze SaveWorkspace se ignoruje), ActiveProject, Expanded map[projectID][]rel,
//            Tabs map[projectID][]requestID, ActiveTab map[projectID]requestID,
//            SidebarHidden, SidebarWidth, ResponseHeight}; další pole (prostředí) přibudou v F6
// CreateProject: parentDir "" = ~/Documents/MinorREST; OpenProjectDialog nabídne založit projekt v adresáři bez minorrest.yaml
PickDirectory(defaultDir string) (string, error);  DefaultProjectsDir() string

// Requesty a konfigurace (F3)
GetRequest(projectID, rel string) (Request, error)
SaveRequest(projectID, rel string, r Request) error   // ID, Name, Seq se převezmou z disku (patří stromu)
GetFolderConfig / SaveFolderConfig(projectID, rel string, …)
GetProjectConfig / SaveProjectConfig(projectID string, …)
FormatJSON(text string) (string, error)
PickFile(projectID string) (string, error)        // uvnitř projektu relativní cesta (s `/`), jinak absolutní; "" = zrušeno

// Odeslání (F4, F5)
Send(in RunInput) (RunResult, error)               // blokuje do konce; runID generuje frontend
Cancel(runID string)
GetRunBody(runID string, pretty bool) (BodyView, error)
FilterRunBody(runID, jsonPath string) (string, error)
SaveRunBodyToFile(runID string) error              // SaveFileDialog
ListHistory() []HistoryItem;  GetHistoryEntry(id string) (SavedResponse, error);  ClearHistory() error

// Proměnné a prostředí (F6)
ListEnvironments(projectID string) ([]Environment, error)
SaveEnvironment / DeleteEnvironment / SetActiveEnvironment
GetGlobals() / SaveGlobals(…)
RevealSecret(projectID, envID, name string) (string, error)
ExplainVars(projectID, rel string, draft []KV) ([]VarInfo, error)   // pro highlight, hover, „oko“
ClearRuntimeVar(projectID, name string)

// Auth (F7)
OAuthFetchToken(in RunInput) (TokenInfo, error);  OAuthCancel();  OAuthClearToken(in RunInput) error;  OAuthTokenInfo(in RunInput) (TokenInfo, error)
ConvertToSecret(projectID, name, value string) error

// Uložené odpovědi (F8)
SaveResponse(runID, label string) (SavedInfo, error)
ListSaved(projectID, requestID string) ([]SavedInfo, error)
GetSaved(projectID, requestID string, version int) (SavedResponse, error)
GetSavedBody(projectID, requestID string, version int, pretty bool) (BodyView, error)
SetSavedLabel / DeleteSaved

// Export / import (F9, F10)
ExportSnippet(in RunInput, format string, mask bool) (string, error)   // "curl" | "curl-oneline"
ParseCurl(text string) (CurlImport, error)         // {Request, Warnings}
PreviewOpenAPI(source string) (ImportPreview, error)
ImportOpenAPI(source string, opts ImportOptions) (ProjectInfo, error)

// Nastavení a aktualizace (F11, F12)
GetSettings() Settings;  SaveSettings(s Settings) error
GetVersion() string;  CheckForUpdate() (UpdateInfo, error);  InstallUpdateAndRestart() error
```

### 11.2 Klíčová DTO
```go
type RunInput struct {
    RunID, ProjectID, Rel string
    Request model.Request      // aktuální (i neuložený) stav tabu
}
type RunResult struct {
    RunID string
    Error *RunError            // {Code, Detail}; pak ostatní pole prázdná (kromě Sent, Timing pokud jsou)
    Status int; StatusText, Proto string
    RemoteAddr, LocalAddr string; ResolvedAddrs []string
    TLS *TLSInfo
    Headers []KV               // pořadí dle serveru, opakované názvy jako samostatné řádky
    Cookies []Cookie
    Sizes Sizes; Timing Timing
    Redirects []Redirect
    Sent SentRequest           // {Method, URL, Headers []KV, BodyPreview string, BodySize int64}
    ContentType, Charset string
    IsBinary, Truncated bool
    Unresolved []string        // nevyhodnocené proměnné
    Extracted []KV             // nastavené runtime proměnné
    AuthSource string
}
type BodyView struct { Text string; Lang string /* json|xml|html|text */; Size int64; Partial bool; DataURL string /* obrázky */ }
```
`RunResult` záměrně **neobsahuje tělo** – to si frontend vyžádá přes `GetRunBody` (umožní líné načtení a Pretty/Raw bez opakovaného přenosu metadat).

### 11.3 Události (backend → frontend)
`tree:changed {projectID}` · `request:changedOnDisk {projectID, rel}` · `menu:<akce>` · `oauth:waiting` / `oauth:done` · `update:ready {version, notesURL}` · `update:error {code}` · `file:dropped {paths}`

## 12. Fáze implementace

Postup v každém kroku: implementace → `go vet ./internal/... && go test ./internal/...` (+ `npm run check`) → ověření v `wails dev` (prohlížeč na `localhost:34115`) → commit → `docs/PROGRESS.md`.
Testy: hlavní cesta + nejdůležitější edge case. Texty UI rovnou přes `t()` v obou jazycích.

### F0 – Bootstrap
1. Wails CLI (`go install github.com/wailsapp/wails/v2/cmd/wails@latest`, `wails doctor`). `wails init -n minor-rest -t svelte-ts` v dočasném adresáři → přenést do repa (nepřepsat `docs/`, `CLAUDE.md`, `README.md`, `LICENSE`, `.gitignore`); frontend nahradit čistým Vite + Svelte 5 + TS; `go.mod` modul, `wails.json` (name `MinorREST`, outputfilename `MinorREST`, info, bundle ID). **Hotovo:** `wails build` vytvoří `build/bin/MinorREST.app`, která se spustí.
2. `main.go`: okno a menu dle 1.1 (App, Soubor, Úpravy = EditMenu, Request, Zobrazení, Okno, Nápověda; položky zatím jen emitují `menu:*`). Frontend: `tokens.css`, `fonts.css`, i18n helper + oba JSON, základní komponenty (Button, Modal, Toast), prázdný layout se třemi panely a měnitelnými děliči. **Hotovo:** Cmd+C/V funguje v inputu; světlé/tmavé téma dle systému; na ne-retina Menlo 13, na retina systémový font.
3. `Makefile` (`dev`, `build`, `test`, `check`), `ci.yml`. **Hotovo:** `make test` a `make check` zelené.

### F1 – Model, úložiště, proměnné (jen Go, bez UI)
1. `internal/model` (kap. 2, yaml + json tagy, `omitempty`, ukazatele u dědičných nastavení), slugify, YAML roundtrip. Testy: roundtrip requestu s diakritikou a víceřádkovým tělem; slugify tabulka (vč. kolizí a prázdného výsledku).
2. `internal/storage`: `CreateProject`, `OpenProject`, `LoadTree`, `CreateFolder`, `CreateRequest`, `LoadRequest`, `SaveRequest`, `Rename`, `Move`, `Duplicate` (nové ID, název „… kopie“), `Delete` (Koš), folder/project config, atomický zápis, přečíslování `seq`. Testy v `t.TempDir()`: vytvoření → strom, přejmenování s diakritikou, přesun + pořadí, duplikace.
3. `internal/vars` (kap. 3) + `encodeQuery` + sestavení URL. Testy: priorita scope, rekurze a cyklus, neznámá proměnná, path params, zachování `%XX`, diakritika v query.

### F2 – Sidebar a projekty
1. `internal/settings` (workspace), bindingy projektů a stromu (11.1), `ProjectSwitcher`, načtení stromu, obnovení projektů po startu.
2. `Tree`/`TreeNode`: rozbalování, výběr, kontextové menu, inline přejmenování, vytvoření/duplikace/smazání, Zobrazit ve Finderu.
3. Drag & drop + hledání.
4. Watcher + `tree:changed`.
**Hotovo:** vnořené složky a requesty lze vytvořit, přejmenovat (s diakritikou), přesunout, smazat do Koše; změna ve Finderu se do 1 s projeví.

### F3 – Editor requestu
1. Store tabů (otevřít, zavřít, dirty, obnovení ze workspace), načtení/uložení requestu, `MethodSelect`, `VarInput` (zatím jen syntaktické zvýraznění `{{}}`), URL bar.
2. `KvEditor` + Bulk edit; záložka Params (query ↔ URL, path params), Headers s našeptávačem.
3. Body: `CodeEditor` (CodeMirror wrapper: json/xml/html/markdown/text, read-only režim, téma), všechny typy těla, `FormatJSON`, výběr souborů.
4. Záložky Nastavení a Dokumentace, dialog neuložených změn (tab i `OnBeforeClose`), reakce na `request:changedOnDisk`.
**Hotovo:** request jde kompletně upravit, uložit a po restartu je identický; YAML na disku odpovídá 2.5.

### F4 – HTTP engine a odeslání
1. `internal/httpclient` jádro: metody, hlavičky, těla (raw, form, multipart, binary), HTTP verze, TLS, redirecty, timeout/cancel, chybové kódy + testy.
2. Metriky: timing, adresy, odeslané hlavičky, velikosti, dekomprese, charset, limity těla + testy.
3. `internal/prepare`: dědičnost (hlavičky projekt → složky → request, pozdější přepisuje dle názvu case-insensitive; nastavení request → projekt → globální), proměnné, sestavení URL; auth zatím jen `none` (ostatní typy ignorovat). Bindingy `Send`, `Cancel`, `GetRunBody`. UI: Odeslat/Zrušit, dočasné jednoduché zobrazení (status + raw tělo).
4. Cookie jar, proxy, zápis historie.
**Hotovo:** všech 7 metod proti lokálnímu testovacímu serveru; vynucení HTTP/1.1 vs HTTP/2 je vidět v `Proto`; redirect on/off; zrušení funguje.

### F5 – Zobrazení odpovědi
1. Meta bar (status badge + tooltip, čas + vodopád, velikost + rozpad, protokol, IP), záložka Tělo (Pretty/Raw/Náhled, hledání), stavy panelu.
2. Záložky Hlavičky, Cookies, Časování, Odesláno, Redirecty; i18n popisy status kódů.
3. JSONPath filtr, velká/binární těla, kopírování a uložení těla, chybové stavy.
**Hotovo:** 5 MB JSON se zobrazí bez zamrznutí; odpověď ve windows-1250 má správnou diakritiku; chyba DNS/timeout je srozumitelná.

### F6 – Prostředí, proměnné, tajemství
1. `internal/secrets`, CRUD prostředí a globálních, výběr prostředí, zapojení do `prepare`.
2. Modál Prostředí / Proměnné projektu / Globální; nastavení složky a projektu (vars, headers, HTTP nastavení).
3. `ExplainVars` → `VarInput`: známá/neznámá, hover, našeptávač; „oko“; varování nevyhodnocených.
**Hotovo:** přepnutí prostředí změní `{{baseUrl}}`; secret není v YAML (`grep`), je v Keychain (`security find-generic-password -s MinorREST`).

### F7 – Autorizace
1. `internal/auth`: inherit, none, basic, bearer, apikey + záložka Auth (request, složka, projekt), zdroj zdědění, varování na literál + „Převést na tajnou proměnnou“.
2. OAuth2 client_credentials a password + cache a refresh + panel tokenu. Testy proti `httptest` token serveru.
3. OAuth2 authorization_code + PKCE (listener, prohlížeč, zrušení).
**Hotovo:** každý typ pošle správnou hlavičku (ověřit v „Odesláno“); expirovaný token se obnoví sám.

### F8 – Ukládání odpovědí, verze, historie
1. `internal/responses` (uložit, seznam, načíst, popisek, smazat, maskování), tlačítko Uložit odpověď, záložka Verze, otevření uložené verze, `.gitignore` projektu.
2. Diff dvou verzí (`@codemirror/merge`: tělo; hlavičky jako text `Name: value`).
3. `extract` (JSONPath / hlavička → runtime proměnná, běží po **každé** úspěšné odpovědi), editor v záložce „Proměnné“ requestu.
4. Záložka Historie v sidebaru.
**Hotovo:** tři uložení = `v0001`–`v0003` s úplnými metadaty; diff ukáže změny; login → token → další request funguje přes `extract`.

### F9 – Kopírování jako cURL, import cURL
1. `internal/export` + golden testy; tlačítko ⧉ s výběrem formátu, kontextové menu stromu, uložené verze.
2. `internal/importer/curl` + nabídka v URL baru.
**Hotovo:** zkopírovaný příkaz spuštěný v zsh i bash proti testovacímu serveru doručí bajtově stejné tělo a hlavičky jako aplikace (včetně diakritiky).

### F10 – Import OpenAPI / Swagger
1. Parsování → `Spec` → generátor + testy na fixtures.
2. Průvodce importem (soubor, URL, drop do okna).
3. (volitelné) Postman v2.1.
**Hotovo:** Petstore 2.0 i 3.0 → složky dle tagů, `baseUrl` v prostředí, ukázková těla, auth projektu.

### F11 – Nastavení a i18n
1. Modál Nastavení (kap. 9), okamžitá aplikace, napojení globálních výchozích do `prepare`.
2. Kontrola úplnosti překladů (skript porovná klíče cs/en), překlad nativního menu, přepnutí jazyka za běhu.

### F12 – Auto-update a release
1. `internal/updater` + testy (porovnání verzí, platný/neplatný podpis, parsování odpovědi API z fixture, detekce translokace).
2. UI (toast, sekce v Nastavení).
3. `scripts/sign-update`, `release.yml`, README (instalace, první spuštění, build ze zdrojů).
**Vyžaduje uživatele:** vygenerovat klíč (`go run ./scripts/sign-update -gen`), privátní vložit do GitHub Secrets, veřejný do `pubkey.go`; schválit push a tag. **Hotovo:** lokální build s nižší verzí najde release, ověří, nainstaluje a restartuje se.

### F13 – Dotažení
Command palette (Cmd+K: requesty napříč projekty + akce), prázdné stavy, ukázkový projekt při prvním spuštění, ikona aplikace, a11y (fokus, aria), virtualizace stromu nad 500 položek, QA checklist.

## 13. QA checklist (před v1.0)
- [ ] 7 metod, všechny typy těla, multipart se souborem s diakritikou v názvu.
- [ ] HTTP/1.1, HTTP/2 (TLS), h2c; redirect on/off/limit; timeout; zrušení; self-signed s vypnutým ověřením.
- [ ] Metriky: součet fází ≈ total, IP správná, velikosti sedí s `curl -w '%{size_header} %{size_download}'`.
- [ ] Proměnné ve všech polích, priorita, secret v Keychain, runtime z `extract`.
- [ ] Auth: basic, bearer, apikey (header/query), OAuth2 tři granty + refresh.
- [ ] Uložení odpovědi, verze, diff, historie.
- [ ] Kopírování cURL (víceřádkový i jednořádkový) → Terminál (zsh i bash) → stejný výsledek.
- [ ] Import Petstore 2.0 / 3.0 / 3.1, import cURL.
- [ ] Ne-retina: Menlo 13; retina: systémový font; přesun okna mezi monitory.
- [ ] Světlý/tmavý režim, cs/en včetně menu.
- [ ] Auto-update end-to-end.
- [ ] Změna souborů přes `git pull`/Finder se projeví.

## 14. Rizika a otevřené body
- **Fonty:** ne-retina = Menlo 13 všude (potvrzeno). Retina = SF Pro pro UI, SF Mono pro kód; pokud má být i kód proporcionálně, změnit `--font-code`.
- **Bez notarizace:** první spuštění vyžaduje ruční povolení (kap. 10). Lze doplnit později (Developer ID + `notarytool`).
- **Keychain přes `security`:** tajemství může bez dotazu přečíst jakýkoli proces uživatele spuštěním `security`; přijatelné pro dev nástroj, lepší izolace až s Developer ID.
- **Literály v auth polích** končí v YAML (a tedy v gitu) – řeší jen varování a převod na secret proměnnou.
- **Wails v2 vs v3:** logika je v `internal/`, případná migrace se týká jen `main.go`, `app*.go` a bindingů.
- **OAuth2 authorization code:** servery vyžadující přesnou redirect URI → pole `redirectPort`.
- **HTTP/2 hlavičky:** zobrazujeme nekomprimovanou velikost (na drátě HPACK).
- **Mimo rozsah v1:** skripty, testy/asserty, runner, mock server, WebSocket/GraphQL/gRPC, mTLS, Digest, PAC proxy, markdown náhled.

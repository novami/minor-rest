# Analýza podobných nástrojů → co si vezme MinorREST

Cíl: jednoduchý, přehledný, rychlý nativní REST klient pro macOS (Apple Silicon) v Go.
Neděláme „druhý Postman“ — bereme jen to, co se osvědčilo, a vynecháváme balast.

## 1. Postman

**Silné stránky (převzít):**
- Rozložení: sidebar se stromem kolekcí → editor requestu (záložky Params / Authorization / Headers / Body / Settings) → panel odpovědi. Lidé ho znají, nemá smysl vymýšlet jiné.
- Záložky otevřených requestů nahoře, tečka u neuložených změn.
- Key-value editor s checkboxem (zapnuto/vypnuto), popisem a **Bulk Edit** (textový režim `klíč: hodnota`).
- Obousměrná synchronizace Query params ↔ URL.
- **Auth dědění** – request „Inherit auth from parent“ (složka/kolekce).
- „Hidden / auto-generated headers“ (User-Agent, Content-Type, Content-Length, Host) zobrazené šedě, dají se vypnout.
- Zvýraznění proměnných v URL (zelená = známá, červená = neznámá), hover ukáže hodnotu a zdroj.
- Panel odpovědi: status + čas + velikost, hover nad časem = rozpad (DNS, TCP, TLS, TTFB, download), hover nad velikostí = headers vs body.
- „Code snippet“ – export do cURL.
- Import OpenAPI/Swagger: tagy → složky.
- Ukládání odpovědí jako „Examples“.

**Slabiny (vyhnout se):**
- Povinný cloud účet, synchronizace do cloudu, pomalé Electron UI (stovky MB RAM).
- Data v proprietárním formátu, špatně verzovatelné v gitu.
- Přeplácané UI (Flows, Mock servery, Monitory, AI…).
- Uložené odpovědi („Examples“) se nedají verzovat ani porovnat.

## 2. Bruno (The Git-Native API Client)

**Silné stránky (převzít):**
- **Offline, bez účtu, kolekce = adresář na disku**, složka = podadresář, request = soubor. Ideální pro git a code review.
- Čitelný textový formát (původně `.bru`, nově i YAML „OpenCollection“) → my použijeme rovnou YAML.
- Proměnné na více úrovních (globální, kolekce, složka, request, prostředí, runtime) s jasnou prioritou.
- Tajné proměnné („secret“) se neukládají do souboru v plaintextu.
- `folder.bru` / `collection.bru` – nastavení (auth, headers) na úrovni složky/kolekce, dědí se dolů.
- Post-response „vars“: vytažení hodnoty z odpovědi do proměnné bez psaní skriptu (řetězení requestů, např. login → token).
- Pořadí položek ve složce (`seq`).
- Watcher souborů – změny z gitu (`git pull`) se hned projeví v UI.

**Slabiny (vyhnout se):**
- Také Electron (pomalejší start, velká paměť).
- Názvy souborů = názvy requestů včetně mezer a diakritiky → problémy s Unicode normalizací (NFC/NFD) na macOS a v gitu.
- Ukládání odpovědí a jejich historie je slabé.
- Skriptovací JS sandbox zvyšuje složitost (pro v1 nepotřebujeme).

## 3. Insomnia / Hoppscotch / HTTPie Desktop / RapidAPI (Paw)

- **Insomnia**: chainování přes „Response tag“ (hodnota z jiné odpovědi), přehledný Timeline (přesný „wire log“ toho, co se poslalo). → převzít **Timeline/„Odesláno“** záložku.
- **Hoppscotch**: minimalismus, rychlá klávesová obsluha, command palette. → převzít **Cmd+K**.
- **HTTPie Desktop**: velmi čisté UI, vizuální odlišení metod barvami. → barevné badge metod.
- **RapidAPI / Paw (nativní macOS)**: ukazuje, jak má vypadat nativní Mac aplikace (HiddenInset titlebar, systémový font, rychlost). Dynamické hodnoty (`{{$uuid}}`, `{{$timestamp}}`). → převzít dynamické proměnné a nativní vzhled.

## 4. Co MinorREST udělá lépe / jinak

| Oblast | MinorREST |
|---|---|
| Výkon | Go + nativní WKWebView (Wails), žádný Chromium, ~15 MB, start < 1 s |
| Data | YAML soubory v adresáři projektu, git-friendly, ASCII názvy souborů (slug), diakritika jen v `name` |
| Organizace | Libovolný počet projektů → složky (i vnořené) → requesty, řazení drag & drop |
| Odpovědi | Uložení jedním kliknutím, **automatické verzování** (v1, v2, …), **diff mezi verzemi**, metadata (čas, IP, velikosti, protokol) |
| Metriky | Rozpad času (DNS/TCP/TLS/TTFB/download), vzdálená IP:port, protokol, TLS verze, velikost headers vs body (přenesená i dekomprimovaná) |
| Export | Jedna ikona → kopírování jako cURL (1 řádek / víceřádkový) nebo bash skript, plně vyhodnocené proměnné, správné escapování UTF-8 |
| Tajemství | tajné proměnné v macOS Keychain (v YAML jen název); literál v auth poli → varování a převod na tajnou proměnnou |
| Updaty | Automaticky z GitHub Releases, ověření podpisu ed25519 |
| Fonty | Ne-retina: Menlo 13; retina: systémový font macOS (SF Pro / SF Mono) |

## 5. Vědomě mimo rozsah v1 (backlog)

Skriptování (pre/post-request JS), testy/asserty, collection runner, mock server, WebSocket/GraphQL/gRPC,
klientské certifikáty (mTLS), sdílení přes cloud, Windows/Linux, Intel Mac.

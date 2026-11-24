# MinorREST

Jednoduchý a přehledný REST klient pro macOS (Apple Silicon), napsaný ve Swiftu (SwiftUI).

- Projekty → složky → requesty, uložené jako čitelné YAML soubory (git-friendly)
- GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS; body raw / form-urlencoded / multipart / binary
- Proměnné a prostředí, tajné hodnoty v macOS Keychain
- Autorizace: Basic, Bearer, API Key, OAuth2
- HTTP/1.1 / HTTP/2 (dle serveru), redirecty, detailní časování, IP adresy, velikosti hlaviček a těla
- Ukládání odpovědí s automatickým verzováním a porovnáním verzí
- Import OpenAPI 3.x / Swagger 2.0, kopírování requestu jako cURL jedním klikem
- Automatické aktualizace z GitHub Releases

## Požadavky
- macOS 26 nebo novější, **pouze Apple Silicon (arm64)**.
- Závislosti: [minor-swift-core](https://github.com/novami/minor-swift-core) (logování, Keychain, updater) a [Yams](https://github.com/jpsim/Yams) (YAML, výslovně povolená výjimka). Vše ostatní jsou systémové frameworky.

## Sestavení a testy
```bash
xcodebuild test -scheme MinorREST -destination 'platform=macOS,arch=arm64'
swiftlint lint --strict
python3 Scripts/check-i18n.py
```
Debug build je podepsaný „to run locally“ (bez certifikátu), updater je v něm vypnutý. Struktura a pravidla: [CONTRIBUTING.md](CONTRIBUTING.md).

## Citlivá data
Tajné proměnné, hesla, tokeny, API klíče a hodnoty `Authorization` / `Cookie` v requestech se ukládají do macOS Keychain (služba `MinorREST`); v YAML souborech zůstává jen značka `{{keychain}}`. Stávající projekty se při otevření automaticky zmigrují. Do logů se hlavičky ani těla nezapisují.

## Distribuce a aktualizace
Developer ID + notarizace, aktualizace z GitHub Releases (`MinorUpdater`; ověřuje SHA-256, podpis Developer ID se stejným Team ID, Bundle ID a vyšší verzi). Release vznikne tagem `X.Y.Z` na `main` (`git tag 1.2.3 && git push origin 1.2.3`) a asset se jmenuje `MinorREST-X.Y.Z.zip`.

**Release workflow bez repozitářových secrets selže:** `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (lint a testy fungují i bez nich). Do `Config/App.xcconfig` je třeba doplnit `DEVELOPMENT_TEAM`.

Stav: ve vývoji, první vydání zatím neexistuje (viz [CHANGELOG](CHANGELOG.md)).

## Licence

[MIT](LICENSE)

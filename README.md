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
- macOS 15 nebo novější, **pouze Apple Silicon (arm64)**; Intel / Universal Binary se nepodporuje.
- Závislosti: jediná externí – [Yams](https://github.com/jpsim/Yams) (YAML). Vše ostatní jsou systémové frameworky (SwiftUI, AppKit, URLSession, Security).

## Sestavení a testy
```bash
brew install xcodegen
make test    # testy jádra (swift test)
make build   # xcodegen + xcodebuild
make run     # sestaví a spustí
```
Podrobnosti a struktura projektu: [CONTRIBUTING.md](CONTRIBUTING.md).

## Distribuce a aktualizace
Release zatím nevznikají. Plánované: GitHub Releases + automatické aktualizace přes Sparkle (výchozí zapnuto, vypnutelné v Nastavení), podpis EdDSA; zatím bez Apple Developer ID (ad-hoc podpis) – viz [docs/PLAN.md](docs/PLAN.md), kap. 10. Aktualizace dosud implementovány nejsou.

Stav: ve vývoji – viz [docs/PLAN.md](docs/PLAN.md) a [docs/PROGRESS.md](docs/PROGRESS.md).

## Licence

[MIT](LICENSE)

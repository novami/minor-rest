# MinorREST

Jednoduchý a přehledný REST klient pro macOS (Apple Silicon), napsaný v Go (Wails).

- Projekty → složky → requesty, uložené jako čitelné YAML soubory (git-friendly)
- GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS; body raw / form-urlencoded / multipart / binary
- Proměnné a prostředí, tajné hodnoty v macOS Keychain
- Autorizace: Basic, Bearer, API Key, OAuth2
- HTTP/1.1 / HTTP/2, redirecty, detailní časování, IP adresy, velikosti hlaviček a těla
- Ukládání odpovědí s automatickým verzováním a porovnáním verzí
- Import OpenAPI 3.x / Swagger 2.0, kopírování requestu jako cURL jedním klikem
- Automatické aktualizace z GitHub Releases

Stav: ve vývoji – viz [docs/PLAN.md](docs/PLAN.md) a [docs/PROGRESS.md](docs/PROGRESS.md).

## Licence

[MIT](LICENSE)

# Stav projektu

## Aktuálně
- **Fáze:** F0 hotová.
- **Další krok:** F1, krok 1 – `internal/model` + slugify + YAML roundtrip (viz `docs/PLAN.md` → `### F1`, kap. 2 a 3).
- **Prostředí:** Go 1.27.4 darwin/arm64, Node 26, Wails CLI v2.17.1 (`~/go/bin/wails`), gh CLI. Příkazy přes `make dev|build|test|check`.

## Co existuje (F0)
- `main.go` (okno 1280×800, HiddenInset titlebar, About), `menu.go` (nativní menu cs/en dle systému, položky emitují `menu:<akce>`), `app.go` (`SetDirty`, `GetVersion`, potvrzení zavření při neuložených změnách).
- Frontend Svelte 5 + Vite 8 + TS: `src/styles/{tokens,fonts,base}.css`, i18n (`src/lib/i18n`), komponenty `Button`, `Modal`, `Toasts`, `Splitter`, util `events.ts`, layout titlebar + sidebar + request/response se splittery. Neimplementované akce menu ukazují toast.
- `Makefile`, `.github/workflows/ci.yml`, bundle ID `com.github.novami.minorrest`, min. macOS 13.
- Ověřeno: `wails build` → `build/bin/MinorREST.app` se spustí; v `wails dev` (localhost:34115) na ne-retina Menlo 13px, čeština, tmavé téma, binding `GetVersion` funguje.

## Log
| Datum | Fáze | Commit | Poznámka |
|---|---|---|---|
| 2026-11-16 | plán | 55207d9 | analýza, plán, pokyny |
| 2026-11-16 | plán rev. 2 | 7679efe | kontrakt bindingů, kroky fází |
| 2026-11-16 | plán | ee7e752, 8c3ec77 | veřejné repo, Menlo, jen cURL |
| 2026-11-16 | F0 | (viz git log) | bootstrap Wails + Svelte 5, menu, layout, CI |

## Rozhodnutí uživatele
- Wails v2 + Svelte 5, YAML soubory, UI cs+en, zatím bez Apple Developer ID (ad-hoc podpis), MIT, auto-update výchozí zapnuto.
- Repozitář i releasy jsou veřejné (updater bez tokenu).
- Ne-retina displej: Menlo 13 (UI i kód). Retina: SF Pro (UI) + SF Mono (kód).
- Kopírování requestu: jen cURL (víceřádkový + jednořádkový), bez bash skriptu.

## Otevřené body / známé problémy
- Retina větev fontů ověřena jen syntakticky (media query platná), vizuálně ne – ověřit na retina displeji.
- Rozměry panelů se zatím neukládají (přijde s workspace v F2).
- F12 vyžaduje od uživatele ed25519 klíč v GitHub Secrets (`UPDATE_SIGNING_KEY`).

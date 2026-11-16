# Stav projektu

## Aktuálně
- **Fáze:** plán hotový, implementace nezačala.
- **Další krok:** F0 – Bootstrap (viz `docs/PLAN.md` → `### F0`). Wails CLI zatím není nainstalované (`go install github.com/wailsapp/wails/v2/cmd/wails@latest`).
- **Prostředí:** Go 1.27.4 darwin/arm64, Node 26, gh CLI k dispozici.

## Log
| Datum | Fáze | Commit | Poznámka |
|---|---|---|---|
| 2026-11-16 | plán | (viz git log) | analýza (`docs/ANALYZA.md`), plán (`docs/PLAN.md`), pokyny (`CLAUDE.md`) |

## Rozhodnutí uživatele
- Wails v2 + Svelte 5, YAML soubory, UI cs+en, zatím bez Apple Developer ID (ad-hoc podpis), MIT, auto-update výchozí zapnuto.

## Otevřené body / známé problémy
- Výklad fontu na retina (SF Pro UI + SF Mono pro kód) – potvrdit s uživatelem při F0.
- F12 vyžaduje od uživatele ed25519 klíč v GitHub Secrets (`UPDATE_SIGNING_KEY`).

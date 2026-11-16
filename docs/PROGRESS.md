# Stav projektu

## Aktuálně
- **Fáze:** plán hotový, implementace nezačala.
- **Další krok:** F0, krok 1 (viz `docs/PLAN.md` → `### F0`, předtím přečíst kap. 1.1). Wails CLI zatím není nainstalované (`go install github.com/wailsapp/wails/v2/cmd/wails@latest`).
- **Prostředí:** Go 1.27.4 darwin/arm64, Node 26, gh CLI k dispozici.

## Log
| Datum | Fáze | Commit | Poznámka |
|---|---|---|---|
| 2026-11-16 | plán | (viz git log) | analýza (`docs/ANALYZA.md`), plán (`docs/PLAN.md`), pokyny (`CLAUDE.md`) |

| 2026-11-16 | plán rev. 2 | (viz git log) | revize: kontrakt bindingů (kap. 11), kroky fází, opravy formátu dat a HTTP enginu |

## Rozhodnutí uživatele
- Wails v2 + Svelte 5, YAML soubory, UI cs+en, zatím bez Apple Developer ID (ad-hoc podpis), MIT, auto-update výchozí zapnuto.
- Repozitář i releasy jsou veřejné (updater bez tokenu).
- Ne-retina displej: Menlo 13 (UI i kód). Retina: SF Pro (UI) + SF Mono (kód).
- Kopírování requestu: jen cURL (víceřádkový + jednořádkový), bez bash skriptu.

## Otevřené body / známé problémy
- F12 vyžaduje od uživatele ed25519 klíč v GitHub Secrets (`UPDATE_SIGNING_KEY`).

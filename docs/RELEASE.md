# Vydání a aktualizace

## Jak aktualizace fungují
- Aplikace volá `GET https://api.github.com/repos/novami/minor-rest/releases/latest` (10 s po startu, pak co 24 h, ETag v paměti). Nabídne jen vyšší verzi `MAJOR.MINOR.PATCH`; prerelease a drafty ignoruje. Vývojový build `0.0.0` se neaktualizuje.
- Assety release: `MinorREST-<verze>-macos-arm64.zip`, `….zip.sig` (base64 ed25519 podpis zipu), `….dmg` (ruční instalace).
- Zip se stáhne přes HTTPS, ověří se podpis veřejným klíčem z `Info.plist` (`MRUpdatePublicKey`), rozbalí se a zkontroluje `CFBundleIdentifier` + verze. Bez platného podpisu se nic neinstaluje (`UPDATE_BAD_SIGNATURE`).
- Instalace: při „Restartovat“ nebo při dalším ukončení se bundle vymění za nový (původní se při chybě vrátí) a aplikace se případně znovu spustí. Z `AppTranslocation` ani z nezapisovatelného umístění se neaktualizuje.
- Nastavení (výchozí obě **zapnuto**, uloženo v `UserDefaults`): `updates.autoCheck`, `updates.autoDownload`. Bez auto-kontroly se nic neděje na pozadí; bez auto-stahování uživatel stahuje ručně v Nastavení.
- Podpis chrání integritu a původ i bez Apple Developer ID; Gatekeeper/notarizace se neobcházejí (aplikace stažená přes URLSession nemá karanténu).

## Jednorázová příprava (vyžaduje majitele repozitáře)
1. `swift scripts/sign-update.swift --gen` → privátní klíč do GitHub Secret `UPDATE_SIGNING_KEY`, veřejný do `project.yml` (`MRUpdatePublicKey`) a commit.
2. Bez veřejného klíče build aktualizace nestáhne (`UPDATE_NOT_CONFIGURED`).

## Vydání
Tag `0.3.5` (bez `v`) → `release.yml` spustí testy, `scripts/release.sh`, vytvoří release s assety. Lokálně: `UPDATE_SIGNING_KEY=… scripts/release.sh 0.3.5`.

## První instalace
Aplikace není notarizovaná: po přetažení do Programů `xattr -dr com.apple.quarantine /Applications/MinorREST.app` nebo Nastavení systému → Soukromí a zabezpečení → „Přesto otevřít“.

## Ověřeno / neověřeno
Ověřeno testy: porovnání verzí, výběr release a assetů, podpis, výměna bundlu a rollback. Neověřeno: celý cyklus proti skutečnému release (vyžaduje klíč a první release), `release.yml` na GitHubu.

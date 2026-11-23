# Vydání a aktualizace

Aktualizace používají **sdílený klíč MinorUpdate** (ed25519) společný pro aplikace Minor* (MinorIDE, MinorREST, MinorDLNA). Privátní klíč je jen v přihlašovacím Keychainu vydavatele (service `MinorUpdate`), nikdy v souboru, repozitáři ani CI – vydání se podepisuje lokálně.

## Jak aktualizace fungují
- Feed: `https://github.com/novami/minor-rest/releases/latest/download/appcast.json` (asset posledního releasu): `{version, url, sha256, signature, notes}`. Kontrola 10 s po startu a pak co 24 h; vývojový build `0.0.0` se neaktualizuje.
- Nabídne se jen vyšší verze `MAJOR.MINOR.PATCH`; URL archivu musí být HTTPS.
- Ověření: sha256 staženého zipu musí sedět a podpis musí platit pro zprávu `minorupdate-v1\n<bundle ID>\n<verze>\n<sha256>` (veřejný klíč v `Info.plist`, `MRUpdatePublicKey`). Podpis je tedy vázaný na aplikaci, verzi a obsah. Poté se zip rozbalí a zkontroluje `CFBundleIdentifier` a verze. Bez platného podpisu se nic neinstaluje (`UPDATE_BAD_SIGNATURE`).
- Instalace: při „Restartovat“ nebo při dalším ukončení se bundle vymění za nový (při chybě se vrátí původní) a aplikace se případně znovu spustí. Z `AppTranslocation` ani z nezapisovatelného umístění se neaktualizuje.
- Nastavení (výchozí obě **zapnuto**, `UserDefaults`): `updates.autoCheck`, `updates.autoDownload`. Bez auto-kontroly se nic neděje na pozadí; bez auto-stahování uživatel stahuje ručně v Nastavení.
- Gatekeeper/notarizace se neobcházejí; aplikace stažená přes URLSession nemá karanténu.

## Jednorázová příprava
1. `swift scripts/minorupdate.swift keygen` – vypíše veřejný klíč (existuje-li klíč MinorUpdate v Keychainu, jen ho vypíše).
2. Veřejný klíč vložit do `project.yml` (`MRUpdatePublicKey`) a commitnout. Bez něj build aktualizace nestáhne (`UPDATE_NOT_CONFIGURED`).

## Vydání
1. Poznámky (volitelně) do `docs/release-notes/<verze>.md`, čistý strom, tag `X.Y.Z` (bez `v`).
2. `scripts/release.sh X.Y.Z` → `dist/MinorREST-X.Y.Z.zip` + podepsaný `dist/appcast.json`.
3. Publikace (push, tag, `gh release create …`) jen na výslovný pokyn.

## První instalace
Aplikace není notarizovaná: po přetažení do Programů `xattr -dr com.apple.quarantine /Applications/MinorREST.app` nebo Nastavení systému → Soukromí a zabezpečení → „Přesto otevřít“.

## Ověřeno / neověřeno
Testy: porovnání verzí, feed, otisk + podpis (vč. podpisu pro jinou aplikaci a záměny verze), výměna bundlu a rollback. Neověřeno: `scripts/release.sh` a celý cyklus proti skutečnému release (vyžaduje klíč a první release).

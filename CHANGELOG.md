# Changelog

Formát dle [Keep a Changelog](https://keepachangelog.com/cs/1.1.0/), verze `MAJOR.MINOR.PATCH`.

## [Nevydáno]
- Migrace na `minor-swift-core` a šablonu `minor-swift-starter` (xcconfig, CI, release, updater, logování, Keychain).
- macOS 26+, hardened runtime, Bundle ID `cz.novami.minor.rest`.
- Hesla, tokeny a hodnoty `Authorization`/`Cookie` v requestech jsou v Keychainu; stávající projekty se zmigrují.
- OAuth2 `authorization_code` odstraněn (žádný lokální listener).
- Projekt je ve vývoji; žádné vydání zatím neexistuje.

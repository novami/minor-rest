# Zabezpečení

## Nahlášení zranitelnosti

Zranitelnosti nehlaste veřejným issue. Použijte
[Private vulnerability reporting](https://github.com/novami/minor-rest/security/advisories/new)
na GitHubu (záložka Security → Report a vulnerability).

Podporována je vždy poslední vydaná verze.

## Principy

- Tajné hodnoty (hesla, tokeny) se ukládají do macOS Keychain, ne do YAML souborů projektu.
- Aplikace nemá žádnou telemetrii; síťový provoz tvoří jen requesty, které uživatel odešle.
- Do repozitáře nepatří klíče, certifikáty ani provisioning profily. Podpisové klíče vydání patří do GitHub Secrets.
- Aktualizace stahuje `MinorUpdater` z GitHub Releases a ověřuje SHA-256, podpis Developer ID (stejné Team ID), Bundle ID a vyšší verzi.

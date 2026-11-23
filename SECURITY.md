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
- Aktualizace budou ověřovány podpisem (viz [docs/PLAN.md](docs/PLAN.md), kap. 10); jsou implementovány vlastním updaterem (docs/RELEASE.md).

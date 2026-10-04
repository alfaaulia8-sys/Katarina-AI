# Stage 07 — GitHub Fallback Reference Notes

These references were reviewed while hardening MT5 localhost permission automation. They are **not freeze evidence**; Katarina's own run `37209799384` is authoritative.

Useful patterns found through GitHub code search:

- `DEVfancybear/MarketLens`: MT5 WebRequest allow-list tooling and direct `config/common.ini` handling while the terminal is stopped.
- `xyVar/KLDAFinTech`: Python repair pattern for `WebRequestUrl` in MT5 `common.ini`.
- `IanIT/PortableMT5Dev`: portable MT5 detection via `config/common.ini`.
- `EA31337/EA31337-classes`: socket abstraction supporting `localhost` / `127.0.0.1`.

Katarina keeps direct INI editing only as an operational fallback. Preferred validation is official UI configuration plus authoritative runtime `SocketConnect` proof.

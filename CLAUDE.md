# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

"Power Control" — a self-hosted remote shutdown/reboot/sleep control panel for a Windows PC, accessed from a phone/tablet browser over the local WiFi network as an installable PWA. There is no build system, package manager, or test suite; it's a handful of scripts and static files run directly.

## Running

- `shutdown_server.ps1` is the real server (Windows, uses `System.Net.HttpListener` + WMI/CIM for live stats). Launch via `start.bat`, which also opens the required firewall port (8765) before invoking it.
- `shutdown_server.py` is a minimal standalone Python fallback (stdlib `http.server` only) that serves just the shutdown/reboot buttons with a single shared `TOKEN` — it does not implement pairing, `/stats`, or serve `web/`. Launch via `start.sh`.
- `setup_autostart.ps1` / `remove_autostart.ps1` register/unregister the PS1 server as a Windows Scheduled Task that runs at login (must be run as Administrator).

There is no build step for `web/` — those files are served as-is by the PS1 server.

## Architecture

- `shutdown_server.ps1` is the source of truth for server behavior. It's a single-file HTTP request loop (no framework) serving both API routes and static files out of `web/`:
  - `GET /`, `/pair`, `/qr` — serve `web/index.html`, `web/pair.html`, `web/qr.html`
  - `GET /manifest.json`, `/icon.svg`, `/sw.js`, `/qrcode.min.js` — static PWA assets
  - `POST /pair` — exchanges the 6-digit `$pairCode` (regenerated each server start, written to `pair_code.txt`) for a persistent bearer token, stored in `paired_devices.json`
  - `GET /info`, `GET /stats`, `POST /action`, `POST /unpair` — all require a valid token via the `X-Token` header; `/action` executes `shutdown`/`reboot`/`sleep` on the host and can stop the listener loop
- `web/index.html` is the control panel: polls `/stats` every 3s, renders CPU/RAM/disk/uptime/network/process widgets (configurable via localStorage), and posts to `/action` with a confirm modal for each power command.
- `web/pair.html` collects the 6-digit code and stores the returned token in `localStorage` (`pc_token`), then redirects to `/`.
- Auth model: a single per-server-run pairing code gates issuance of long-lived per-device tokens; there is no user/password auth beyond that. `paired_devices.json` and `pair_code.txt` are runtime state, not app config — treat them as local/sensitive rather than something to hand-edit.

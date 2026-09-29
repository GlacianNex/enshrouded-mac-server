# Changelog

## 0.1.6 (Candidate)

- Show named update stages, an animated progress bar, elapsed time, long-wait explanations, and an Open Update Log button in both installer and in-app updates.
- Save and stop the game, then request normal guest shutdown before stopping the hosting environment. This avoids waiting indefinitely on an exhausted old networking process.
- Bound the environment-stop wait and report a clear error instead of leaving the update window indefinitely.

## 0.1.5 (Candidate)

- Fix UDP forwarding exhaustion and restart environments during manager upgrades so updated networking tools take effect.
- Keep the menu-bar light live while its dropdown is open; preserve speed readings across temporary metrics failures.
- Make Open Server Folder a button; move full server-file uninstall into the global menu.
- Add per-server deletion with saved-data archives and reusable installations; share setup downloads between servers.

## 0.1.4 — Candidate

Fix missing runtime helper files during manager updates with a running VM. Keep helper generations immutable, reopen the installed manager after a failed update, and retain installer diagnostics. Includes the 0.1.3 candidate changes.

## 0.1.3 — Candidate

Explain download components and disk-space requirements before setup. Show installation steps, elapsed time, reported bytes and progress, and the server-data destination. Add server-file uninstall that removes the VM and compatibility tools while preserving worlds, settings and backups.

## 0.1.2 — 2026-09-29

Fix installation relaunching into the installer. Transfer Valheim reliability safeguards for verified manager downloads, scheduling, backups, profile recovery, settings errors, log viewing, and monitoring. Preserve rollback data and server-resume markers after failures. Harden signing and release checks.

See the [0.1.2 release notes](docs/RELEASE-NOTES-0.1.2.md).

## 0.1.1 — 2026-09-29

Fix the “app is damaged” error after extracting the download. Release ZIPs now omit macOS metadata sidecar files that could invalidate the app signature. Packaging checks verify both metadata-aware and ordinary ZIP extraction.

See the [full 0.1.1 release notes](docs/RELEASE-NOTES-0.1.1.md).

## 0.1.0

First public release of Enshrouded Server Manager for Mac.

Automatic setup, multiple servers, World Rules, performance and ping monitoring, roles, backups, scheduled maintenance, and signed manager upgrades.

See the [0.1 Release Notes](docs/RELEASE-NOTES-0.1.md).

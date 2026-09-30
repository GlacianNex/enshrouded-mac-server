# Changelog

## 0.1.11 (Candidate)

- Keep installer buttons responsive while waiting for update and relaunch work.
- Allow creating another server during startup; queue server version checks until the busy server is ready.
- Download the pinned Ubuntu image directly over HTTPS, avoiding the archive redirect rejected by macOS.
- Make the whole download-details title row clickable and fit the setup window to its current content.
- Show Installation Pending without player lookup text until setup completes; preserve pending state after failed setup.
- Add regression tests for each correction, plus an opt-in fresh image download and checksum check.

## 0.1.10 (Candidate)

- Combine new-server identity, port, world import and startup choices into one form. Create & Set Up starts installation directly and shows progress in the same window.
- Use native AppKit name/password/port fields, preserving active editing and selection during view updates.
- Retry failed setup on the same profile and reopen setup progress from the menu bar.

## 0.1.9 (Candidate)

- Keep hosting and pending operations alive when management or progress windows close. Settings and New Server use independent windows with retained drafts.
- Separate server login startup from opening the manager; preserve sleep protection outside the UI and recover unexpected game exits with throttled retries.
- Show server update stages, elapsed time and reported download progress; refresh menu update availability in place and clean successful manager replacements.
- Add stopped-server UDP port editing with conflict checks and rollback, protect stale settings drafts, improve read-only inspection, and expose server deletion in management.
- Add skip-or-wait scheduled restart policy, current-player ping filtering, telemetry during operations, accurate report-age handling, and fresh installer/activity logs.
- Accept validated save files, folders and ZIPs for world import.
- Record a new Valheim behavior audit, implementation plan and explicit verification limits.

## 0.1.8 (Candidate)

- Replace the blocking generic quit warning with a live notice naming the server and active operation.
- Close the notice automatically when work ends, reuse it for repeated quit requests, and honor the manager-update relaunch bypass.

## 0.1.7 (Candidate)

- Open logs in an independent movable, resizable window; keep line numbers inside the log pane.
- Keep server-update checks in the open menu with live stages, elapsed time, results, and bounded waits.
- Refresh menu controls in place after stopping; keep unrelated actions available during a stop.
- Reuse one management window and improve New Server field sizing, focus, port entry, and validation.
- Show speed reports as measured one-minute intervals with the age of the latest report; explain that the game can skip reports for several minutes.

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

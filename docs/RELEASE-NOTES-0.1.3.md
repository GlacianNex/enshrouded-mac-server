# 0.1.3 — Setup Progress and Server Uninstall

Candidate · Changes since 0.1.2

## What Changed

- Match Valheim’s manager-update menu with an update badge, version/check status, and a manual manager-update check. Checks run at launch and every five minutes; this is a menu indication, not a macOS notification banner.

- Setup lists every component and its source before downloading.
- Explains that 30 GB is free disk space for installation and updates, not the download size.
- Shows setup steps, elapsed time, reported download bytes, and current-step progress. Download totals remain unknown until the source provides them. Valve reports file progress and final downloaded bytes; Ubuntu reports completed package batches.
- Shows the server-data folder with an Open Folder button. Downloads stay outside the signed manager app.
- Adds **Server Files → Uninstall Server Files…**. Stops one server and removes its VM, Wine, Box64, download tools, server binaries, and setup cache. Keeps worlds, settings, logs, backups, the manager, and other servers. Reinstall through Set Up Server.

## Verification

102 Swift tests and four offline HTTP download tests pass. Cases include truncated downloads, bad checksums, cached downloads, progress parsing, saved-data preservation, failed stops, failed VM deletion, and linked folders. A real component download verified streaming byte counts and SHA-256. An isolated native UI preview verified the component list, destination, and current-step progress using a fake runtime.

Full fresh provisioning with these changes has not been repeated on another Mac. The public 0.1.2 release remains unchanged.

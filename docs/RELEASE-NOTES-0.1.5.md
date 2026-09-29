# 0.1.5 — Hosting and Server Management Fixes

Candidate · Includes the earlier candidate fixes

- Fixes a UDP forwarding connection leak that eventually made running servers disappear from discovery. Idle forwarding connections now expire; active traffic stays connected.
- Manager upgrades save and stop running servers and their environments, then resume those servers with the updated networking tools. Stopped servers stay stopped.
- The menu-bar light keeps updating while the dropdown is open, without rebuilding its rows.
- Server-speed history is independent of CPU/memory probes. A temporary metrics failure no longer clears a valid speed reading or splits its graph.
- Open Server Folder is a button. Uninstall Server Files is a global menu action for all managed and retained installations, including shared downloads. Worlds, settings, backups and the manager app are kept.
- Delete Server removes one server’s entry and settings, archives its saved data, and retains reusable installation files. Creating a replacement on the same port reuses that environment and checks Valve for the latest server build during setup.
- Additional servers reuse downloaded environment images, verified compatibility archives, cached packages, and server binaries. Each server still has independent settings, worlds and an environment. Valve validation downloads missing or changed files.

## Readings and Storage

The manager polls once a second. Enshrouded reports speed as approximately one-minute averages. Real restarts and missed reports remain visible; overdue readings are labeled.

Shared downloads live in `~/Library/Application Support/Enshrouded Manager/downloads`. Deleted server data is archived beside them in `deleted-server-data`; each archive preserves its folder structure and profile information. Per-server environments remain at their existing locations. Reusing a different UDP port may require another environment; cached files are still reused. Old environments without a shared cache mount keep their existing compatibility tools. Missing system packages may still need a download.

## Verification

Isolated tests cover deletion, registry-write rollback, saved-data preservation, binary-only reuse, symlink rejection, shared-cache locking, manager-update environment shutdown, speed cadence, transient probe failures, stale readings, restarts and history retention. The networking patch includes race-tested UDP deadline refresh, clearing, close handling and real gRPC cancellation propagation. No live server or world was restarted or changed during verification.

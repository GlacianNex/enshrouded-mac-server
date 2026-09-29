# Valheim Reliability Audit

Audited 2026-09-29 against Valheim's public history through `b02b951` (1.3.0), its release documentation, tests, and local manager implementation. This checklist records applicable reliability fixes; it does not claim that the two games expose identical controls.

## Transferred in 0.1.2

- **Installation and replacement:** normalize resolved paths; clear quarantine only on a validated installed copy; preserve the previous app and recover from failed moves; retain restart markers until servers resume successfully. Covered by `InstallationTests` and isolated signed-app installation checks.
- **Manager updates:** check stable GitHub releases, verify the exact repository asset, size, SHA-256, archive paths and links, expected publisher, version, and Gatekeeper assessment before replacement. Covered by `ManagerReleaseTests`, `ManagerArchiveTests`, and a real download/verification of public 0.1.1 without installing it.
- **Scheduled restarts:** preserve pending schedules across unrelated edits; skip stale events that were never observed; retain events waiting for an empty server; handle calendar/DST transitions. Covered by `AutomationPolicyTests`.
- **Runtime maintenance:** refresh bundled guest helpers when starting, stopping, or updating existing environments. Covered by `EngineTests`.
- **Bounded monitoring:** time-limit diagnostic subprocesses, including inherited-pipe and ignored-termination cases. Lifecycle operations retain their own stop/start safeguards. Covered by `DiagnosticCommandTests`.
- **Profile isolation:** validate loaded registries, reject overlapping/aliased server folders, and resolve profiles before creating startup models. Isolated previews do not register login startup. Covered by `ProfileStoreTests` plus source review of startup wiring.
- **Safe removal:** hold the operation lock through shutdown, recovery-folder relocation, and registry commit; restore the original home if registry persistence fails. Covered by `ServerRecoveryTests`.
- **Settings and setup:** retain drafts and show errors when saving or provisioning fails; close only after success. Reject password collisions across custom roles. Covered by `ManagerTests`, source review, and an isolated native settings failure/retry check.
- **Backups:** record and verify file hashes before restore; reject corrupted, missing, extra, and malformed entries; identify legacy backups without integrity records. Covered by `BackupIntegrityTests` and existing restore tests.
- **Graphs:** read log text and file identity from one snapshot; recognize identical repeated reports; handle partial lines, CRLF, rotation, truncation, stale data, and gaps between runs. Covered by `LogSnapshotTests` and `PerformanceHistoryTests`.
- **Logs:** persist bounded manager activity, guard log-file symlinks, preserve copied line breaks, provide wrapping, filtering, line numbers, and optional follow mode; refresh during operations. Covered by `ManagerActivityLogTests` and isolated native filtering/source-switch checks.
- **Publishing:** check signing prerequisites, require accepted notarization, preserve failure diagnostics, render checked-in release notes with valid links, reject existing tags, and target the intended commit explicitly. Both ZIP extraction methods retain the 0.1.1 signature checks.

## Existing Safeguards Retained

Operation locks; clean server shutdown; fresh empty-player checks for game updates and scheduled maintenance; backups before restore/update; startup readiness checks; occupied-server manager upgrades; quit handling with an open settings sheet; stable/experimental version ordering; three-hour monitoring history; prevention of idle sleep while hosting; and separation of server data from the app bundle.

## Game-Specific Differences

Enshrouded uses its own query protocol, role/password configuration, world-save format, game rules, and Windows compatibility environment. Valheim's console commands, administration protocol, world controls, and runtime packaging cannot be copied directly. Enshrouded emits simulation-speed reports approximately once per minute; memory sampling remains every five seconds. The UI does not invent five-second simulation readings.

## Verification Boundary

The automated suite contains 93 passing tests. Native checks use a disposable profile and fake runtime; no production server or installed manager is replaced. Real release download validation uses the public signed artifact. Automation's native UI check encountered a computer-use transport failure; its policies are tested automatically, but that interactive check is not counted as passed.

A second macOS version, factory-fresh hardware, sustained multiplayer load, logout/login behavior, and power-loss recovery are not established by these checks. Keep these limits separate from verified regressions. Future changes should run the relevant regression tests and final archive checks instead of relying on user reports to rediscover known defects.

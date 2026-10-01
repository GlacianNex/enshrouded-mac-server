# Verification

## Release 0.1.18

- Documentation review covered every tracked Markdown file: current README/setup, contributor/security/third-party guidance, distribution/release instructions, dependency inventory, verification, historical notes and parity audit/plan. Corrected obsolete setup, uninstall, experimental replacement, storage and update instructions. Historical records retain their evidence and now point to current guidance; all local documentation links resolve. Release notes follow the Valheim release structure and cover changes since public 0.1.2.
- Full local suite: **221 Swift tests**, zero failures, one optional large-download test skipped; **13 Python tests** passed, plus shell syntax and documentation-link checks. The new native-menu regression verifies version-row states, retained row identity, unavailable/failed checks and busy gating.
- Signed release packaging passed the macOS dependency gate and both ordinary ZIP and metadata-aware extraction checks. Build **261001.2254.14** received Apple acceptance (`6403b855-fbaa-4630-b06e-372b6a6836f6`); stapling, Gatekeeper and both extracted-archive validations passed. The app-only delivery copy also passed `syspolicy_check distribution`. Tested build source is `96aee434aaab721b8a4ea3e197dfa075df78fb2d`. [GitHub CI](https://github.com/GlacianNex/enshrouded-mac-server/actions/runs/36937944932) passed script checks, tests, clean Apple Silicon packaging and artifact upload. The release includes a subsequent documentation-only verification commit.
- Published [v0.1.18](https://github.com/GlacianNex/enshrouded-mac-server/releases/tag/v0.1.18) against `5053d1fe6e3de17f6722cc01a56321ca08bb64da`. The uploaded ZIP was downloaded again and matched the local archive byte-for-byte and its SHA-256 (`5dd066245ae4c2f2a82819c5177f8dd8369e3a288d9c3068d0821cfd0a0d34ff`); extracted app version, strict signature, stapled ticket and Gatekeeper checks passed. The release contains only the app ZIP and checksum file.
- Earlier candidate sections retain the precise integration checks and limits. Another physical Mac, older macOS hosting, sustained multiplayer and full login/sleep testing remain pending. The delete-checkbox report remains unconfirmed. Production servers and the installed manager were not changed for release preparation.

## Candidate 0.1.17

Manual-install artifact: `dist/Fresh-Mac-0.1.17-261001.1543.10/Enshrouded Server Manager.app`. Source commit: `2a35cc9`. Developer ID signing, Apple notarization, stapling, strict signature verification, Gatekeeper, pre-distribution checks and both archive extraction checks passed. The final copied candidate also passed the new runtime-dependency gate. No public release or production app replacement was performed.

- The [installation dependency audit](INSTALLATION-DEPENDENCIES.md) traces the macOS runtime, bundled files, Ubuntu base and packages, compatibility tools, downloader, Steam support files, resource/network prerequisites and contributor-only tools. It records the fresh isolated VM test and remaining older-macOS coverage limits.
- The gate reproduced and rejected the pre-fix launcher's macOS 27 minimum. The corrected launcher targets macOS 14 even when built with SDK 27. It also rejected upstream's unused macOS-26 Krunkit driver, which is now omitted. All three remaining Mach-O files have Apple Silicon code, system-only library dependencies and minimum OS versions no higher than the advertised macOS 14 requirement. Five Python regressions cover the gate.
- A fresh isolated Ubuntu VM booted, installed its dependencies, compiled Box64, ran Wine 11.18 and launched the self-contained DepotDownloader with an empty host home, system-only PATH and developer-tool execution blocked. Direct DepotDownloader ELF dependencies all resolved. It used no shared component/package cache. The VM was stopped and deleted afterward; production servers and caches were untouched. A full game download/start was not repeated, and no actual macOS 14/15/26 machine was available for an end-to-end compatibility test.
- The deleted-server menu regression failed before the fix and passes afterward. Menu membership now refreshes while open, while normal state refreshes preserve row identity. Delete actions recheck current registration before and after confirmation, preventing stale popups. Deletion completion refreshes the status menu immediately.
- Delete Server is on the same action row as the other management buttons, and the Checked timestamp is removed. A real queued mouse click at that row dispatches the delete callback. An isolated native preview confirmed the row fits and the timestamp is absent. Log viewers now use Close.
- The reported delete-data checkbox opening Server Management was not reproduced. A native checkbox click kept the alert active. An additional regression invokes the actual menu action and toggles the checkbox with management absent and minimized; neither creates or restores management, and cancellation preserves registration. This does not establish the cause of the user's observed behavior or prove the post-confirmation path on their running app.
- Full final local suite: 220 Swift tests, zero failures, one opt-in large-download test skipped. The five new Python dependency-gate tests passed. [GitHub CI](https://github.com/GlacianNex/enshrouded-mac-server/actions/runs/36886501993) passed script validation, tests, the clean Apple Silicon build with the dependency gate and artifact upload.

## Candidate 0.1.16

Manual-install artifact: `dist/Server-Workflow-0.1.16-261001.1416.37/Enshrouded Server Manager.app`. Source commit: `7dbe83b`. Developer ID signing, Apple notarization, stapling, strict signature verification, Gatekeeper, pre-distribution checks and both ZIP extraction checks passed. The copied candidate also passed signature, stapling and distribution checks. No public release was created, and the installed app, production servers and user caches were not changed.

- Server operations show their stage, elapsed time and available percentage directly in Server Management. Start/stop no longer open progress windows; Show Progress and Uninstall Server Files have been removed. An isolated native app verified inline startup and failure status without a popup, and a layout fitting the management window.
- Installation logs are available while installation is pending, running or failed. Successful installation removes that tab and switches an open viewer to Server. Regression tests exercise the rendered viewer, refresh, retry and completion; the isolated installed-server viewer showed only Server and Manager Activity.
- Startup uses a shared cross-process lock through VM startup and game readiness. A waiting server reports Waiting to Start, then proceeds when the active start succeeds or fails. Tests cover waiting, failure release, timeout, linked-lock rejection and the actual Engine entry point. The user's exact connection-refused failure was not reproduced; serial startup is the selected mitigation, not a proven diagnosis of its network cause. No parallel production VM start was performed.
- Delete Server removes the entire per-server installation and VM. Its unchecked checkbox says “Also delete game data and backups.” Leaving it unchecked archives that data before removal. Tests cover both choices, other-server preservation, registry-failure rollback, unsafe paths, shutdown failure and explicit cleanup-failure reporting. The native dialog was inspected without deleting a production server.
- Clear Download Cache asks for confirmation and clears reusable shared downloads, legacy per-server host download caches, downloaded manager updates and URLSession cached responses. Installed server files, VMs, settings, game data and backups remain intact. Tests verify cache removal and installed-data preservation; existing VM working files are not purged.
- Full local suite: 217 Swift tests, zero failures, one opt-in large-download test skipped. [GitHub CI](https://github.com/GlacianNex/enshrouded-mac-server/actions/runs/36875094296) passed script validation, unit tests, the clean Apple Silicon build and artifact upload. A fresh full installation and a second-Mac install were not repeated.

## Candidate 0.1.15

Manual-install artifact: `dist/Startup-Menu-Fix-0.1.15-260930.1729.21/Enshrouded Server Manager.app`. Source commit: `588a6ef`. Developer ID signing, Apple notarization, stapling, strict signature verification, Gatekeeper, pre-distribution checks, and both ZIP extraction checks passed. No public release or changes to the installed application or running servers. [GitHub CI](https://github.com/GlacianNex/enshrouded-mac-server/actions/runs/36751699025) passed script validation, unit tests, the clean Apple Silicon build and artifact upload.

- The post-manager-update restart branch previously called a generic operation with no action type. Fleet/menu rules treated it as maintenance, disabling New Server, automatic-update preferences and server-version requests. The new regression reproduces those disabled native menu items before the fix.
- Automatic resume now uses the same typed start operation as manual startup, with its progress window suppressed. This preserves menu-bar-only update relaunch while recording startup output and providing Show Progress on demand. Successful startup removes the resume marker; failure retains it.
- The regression exercises the actual resume-marker branch, native menu enablement, invoking Server Management, queuing a server-version check, operation progress, quiet launch and failed-restart marker preservation. Conflicting uninstall/cache-clear/quit actions remain disabled during startup. Existing manual-start/create-second-server coverage also passes.
- Full local suite: 204 Swift tests, zero failures, one opt-in large-download test skipped. No production server restart or full manager replacement was performed during verification. Server deletion and cache retention behavior were not changed.

## Candidate 0.1.14

Manual-install artifact: `dist/Setup-and-Menu-Fixes-0.1.14-260930.1636.58/Enshrouded Server Manager.app`. Source commit: `53385d3`. Developer ID signing, Apple notarization, stapling, strict signature verification, Gatekeeper, pre-distribution checks, and both ZIP extraction checks passed. No public release was created and Applications was not changed. [GitHub CI](https://github.com/GlacianNex/enshrouded-mac-server/actions/runs/36745502391) passed for this source commit.

- Update relaunch uses the existing predecessor-PID flag to start with only the menu bar. The delegate retains the fleet and creates management on demand. A native AppKit application lifetime avoids SwiftUI creating a management or empty Settings window implicitly. Normal launch still opens management.
- Regression tests verify menu creation without management, explicit menu opening/reuse, close without termination, and normal launch. An isolated app launch with the update flag stayed running with no windows; ordinary launch opened management. Native settings editing and Command-A worked, and closing management left the app running. Production app and servers were not changed.
- Setup writes a separate bounded installation log, including command output and failures. Open Logs selects Installation during setup and switches an already-open game-log viewer. Live refresh and retry reset are tested. Server logs and this server's manager activity remain separate; unrelated manager-installer history is no longer appended.
- Clear Installation Downloads holds the shared-download lock, preserves the mounted folder, clears its contents, and records existing installations that must not refill the cache. New server creation bypasses those retained environments. Subsequent fresh installations and their downloads remain reusable. Tests cover lock contention, preservation of installed binaries, absence of donor reseeding, publishing new reusable downloads, and fresh-profile creation.
- Full local suite: 203 Swift tests, zero failures, one opt-in large-download test skipped; eight offline Python tests passed. A full multi-gigabyte install was not repeated, and the user's cache was not cleared.

## Candidate 0.1.13

Manual-install artifact: `dist/Install-Progress-0.1.13-260930.1556.03/Enshrouded Server Manager.app`. Developer ID signing, Apple notarization, stapling, strict signature verification, Gatekeeper, pre-distribution checks, and both ZIP extraction checks passed. No public release was created. [GitHub CI](https://github.com/GlacianNex/enshrouded-mac-server/actions/runs/36740619633) passed for source commit `9031cbf`.

- A bundled guest helper streams CMake output and reports configuration/build/install phase, actual compiler percentage, process state, elapsed time, last-output age and sampled descendant CPU activity every five seconds. No percentage is invented for configure/install. Missing heartbeats are reported after 15 seconds without asserting that the build is stuck.
- Four offline Python tests cover quiet-process heartbeats, split progress lines, invalid/regressing percentages, unchanged failures/exit codes, phase separation and descendant CPU sampling. They run in CI alongside the existing downloader tests.
- Swift regressions cover phase/percentage resets, preserving download history without labelling build work as downloads, quiet heartbeat handling, stale status and failure evidence. Full suite: 198 tests, zero failures, one opt-in large-download test skipped.
- Linux smoke checks passed for actual CPU activity and a temporary CMake project configured, compiled to a reported 100%, then installed into its temporary directory. The full Box64 build was not repeated. Existing server configuration, runtime files and service state were not changed.
- The new guest monitor applies to subsequent setup runs using this manager; it cannot add heartbeats to a build already running an older helper.

## Candidate 0.1.12

Manual-install artifact: `dist/Log-Viewer-0.1.12-260930.1543.15/Enshrouded Server Manager.app`. Developer ID signing, Apple notarization, stapling, strict signature verification, Gatekeeper, pre-distribution checks, and both ZIP extraction checks passed. No public release was created. [GitHub CI](https://github.com/GlacianNex/enshrouded-mac-server/actions/runs/36738838366) passed for source commit `baeb5e3`.

- Open Update Log now uses the existing LogsView and native text pane, with filtering, readable formatting, line numbers, wrap, auto-scroll and one-second refresh. Standalone installation reads its exact log URL without constructing a server Model or FleetModel.
- The queued-mouse-event regression now invokes the actual default button action and asserts that the built-in, resizable update-log window opens and is reused. A second regression starts with no log file, verifies the empty state, creates the file, then verifies live updates after atomic replacement and cleanup on close.
- Full suite: 196 tests, zero failures, one opt-in network test skipped. The remaining log entry points were inspected and already use the built-in viewer; explicit folder buttons continue to open folders. Production installation and server processes were not changed.

## Candidate 0.1.11

Manual-install artifact: `dist/Setup-Fixes-0.1.11-260930.1531.53/Enshrouded Server Manager.app`. Developer ID signing, Apple notarization, stapling, strict signature verification, Gatekeeper, pre-distribution checks, and both ZIP extraction checks passed. No public release was created. [GitHub CI](https://github.com/GlacianNex/enshrouded-mac-server/actions/runs/36737548811) passed for source commit `792e466`.

- Installer input regression reproduced before the fix: a queued click on Open Update Log was never dispatched by the Foundation-only run loop. The AppKit event loop now dispatches the click while still processing worker completion; the regression passes.
- Startup regression covers creating a second profile and queuing a version check while the first is busy, then dispatching that check when startup completes. Fleet maintenance still blocks profile changes.
- Download disclosure regression clicks the actual title row away from the arrow to expand and collapse it. Window sizing regression verifies shrinking to shorter content and screen-height bounds; an isolated native preview verified expansion, collapse and compact layout.
- Installation state regression covers unconfigured, installing, failed and completed states, persisted pending markers, and suppression of player-count lookup text before setup finishes.
- The old Ubuntu URL returned an HTTP redirect to its archive website. The replacement HTTPS S3 endpoint serves the same pinned archive image. A fresh 615,630,848-byte download through SetupDownload/URLSession succeeded and matched the unchanged SHA-256 checksum.
- Full suite: 195 tests, zero failures, one opt-in network test skipped in the offline run. That network test passed separately with a fresh download. No production app replacement, server restart or full VM/server installation was performed.

## Candidate 0.1.10

Manual-install artifact: `dist/Unified-Setup-0.1.10-260930.1508.28/Enshrouded Server Manager.app`. Developer ID signing, Apple notarization, stapling, strict signature verification, Gatekeeper, pre-distribution checks, and both ZIP extraction checks passed. No public release was created. [GitHub CI](https://github.com/GlacianNex/enshrouded-mac-server/actions/runs/36734486106) passed for source commit `e196617`.

- New Server now collects identity, UDP port, world selection and startup preference once. Create & Set Up creates one profile and immediately starts setup, with progress and retry in the same window.
- Native AppKit fields replace SwiftUI focus-state fields. Forty rapid field-editor switches and text replacements complete in under one second in the regression test; active text and selection survive a model refresh.
- Isolated native UI checks passed for rapid clicks across all four inputs, name typing, Tab navigation, invalid-form validation without losing the draft, opening/cancelling the world picker, download-detail expansion, scrolling and cancellation.
- Integration tests cover immediate setup dispatch, invalid port rejection before profile creation, failed setup retry without duplicate profiles, and clearing old setup progress before a different operation.
- All 187 Swift tests pass (177 core, 10 manager). The production app and server were not replaced or restarted. No fresh full server download or second-Mac test was performed for this UI change.
- The original intermittent 1–2 second delay was not conclusively attributed by stack sampling; the replacement native controls passed the focus checks above.

## Candidate 0.1.9

See the [dated behavior audit](VALHEIM-PARITY-AUDIT-2026-09-30.md) and [implementation/evidence record](PARITY-IMPLEMENTATION-PLAN.md) for the complete comparison, corrections, current test counts and verification limits. This candidate is delivered for manual installation; it is not a public GitHub release.

## Release 0.1.2

93 automated tests and GitHub CI pass. The signed, notarized, stapled app passes Gatekeeper and pre-distribution checks; both ZIP extraction methods pass validation. Separate-Mac validation remains pending. See the [Valheim audit](VALHEIM-PARITY.md) for transferred fixes, isolated UI checks, real release-download validation, and coverage limits.

## Release 0.1.1

- Reproduced the 0.1.0 signature failure with ordinary ZIP extraction.
- Release ZIPs now reject AppleDouble metadata sidecars.
- Both `ditto` and `unzip` extractions pass strict signature, stapled ticket, and Gatekeeper checks.
- Downloaded the uploaded GitHub artifact and verified its checksum, extracted signature, and notarization.
- All 44 tests and GitHub CI passed. Confirmation on the affected second Mac remains pending.

## Release 0.1

- Core tests cover server start/readiness, player-query parsing, three-hour/five-second memory history, configuration preservation, world imports, backup/restore, schedules, and safe app replacement.
- Scheduled-backup tests cover stopped/running servers, occupied or unknown player counts, failed stops, and resuming after a copy failure.
- Manager-update tests cover normal quit, concurrent replacement, failure preservation, and stopping running servers without requiring an empty-player query.
- Real hosting was exercised on an Apple Silicon M4 Mac mini; the user joined and reported successful gameplay.
- A separate server-data environment on the same Mac completed first setup, download, startup, query readiness, a staged update, restart, and shutdown. Host download caches may have been reused.
- Isolated UI previews verified grouped World Rules, full-row expansion, editable multiplier fields, automatic Custom selection, and the help popover. The management window's two performance graphs fit without scrolling.
- An isolated process reproduced quit failing with an open Settings sheet. The corrected Apple-event handler exited normally with the sheet open.
- Public artifacts are Developer ID signed, Apple-notarized, stapled, and checked with Gatekeeper. Release checks include extracting and validating the final ZIP.

## Coverage Limits

A separate factory-fresh Mac, Intel hosting, sustained multiplayer load, multiple simultaneous live servers, logout/login startup, interrupted provisioning, and power-loss recovery have not been fully verified. UI inspection of Automation encountered a computer-use tool failure; schedule/workflow coverage comes from automated tests and source review, not a complete interactive UI pass.

The displayed public address and internal readiness query are not external port-forwarding tests. Server speed and player availability depend on the game and query responses; unavailable values must not be treated as zero.

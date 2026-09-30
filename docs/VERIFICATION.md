# Verification

## Candidate 0.1.11

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

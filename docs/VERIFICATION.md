# Verification

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

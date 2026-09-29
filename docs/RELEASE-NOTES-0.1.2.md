# 0.1.2 — Installation and Reliability Improvements

Candidate · Changes since 0.1.1

## TL;DR

Fixes installation reopening the installer and brings across Valheim's proven update, scheduling, backup, and logging safeguards.

## What Changed

- Installation correctly reopens the verified copy in Applications. Failed replacements preserve the previous app, and failed server resumes retain their retry markers.
- The menu checks for stable manager updates. Downloads are verified before installation.
- Scheduled restarts survive unrelated automation changes and handle missed events and clock changes more reliably.
- Backups include integrity checks. A corrupted backup is rejected before replacing the world.
- Settings and setup retain your entries when an operation fails.
- Logs support wrapping, filtering, line numbers, and automatic scrolling. Manager activity persists between launches.
- Monitoring handles stalled queries, rotated logs, repeated reports, and gaps between server runs.
- Profile validation and server removal better protect separate server folders and recovery data.
- Existing environments receive updated runtime helpers from the manager.
- Release packaging retains the fix for the “app is damaged” error. The app and menu use the Enshrouded icon instead of the custom flame.

## Install or Update

Open the downloaded app and choose **Install & Open**. To replace an existing manager, choose **Stop, Update & Relaunch**.

Updating the manager will stop all running servers. They will start back up once the update finishes.

## Verification

93 automated tests pass. Isolated native checks verified settings failure/retry, log filtering, and separate activity logs. A public GitHub release was downloaded and validated through the new updater without installing it. Installation quarantine behavior was verified with a signed app in an isolated destination.

See the [audit checklist](VALHEIM-PARITY.md) for coverage and remaining platform-testing limits.

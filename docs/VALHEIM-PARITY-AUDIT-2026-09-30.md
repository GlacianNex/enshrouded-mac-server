# Valheim / Enshrouded Behavior Audit — 2026-09-30

> Historical record. Later behavior and verification are documented in [0.1.18 release notes](RELEASE-NOTES-0.1.18.md) and the current setup guide. Earlier candidate descriptions are not current instructions.

## Outcome

**Enshrouded 0.1.8 does not have full behavioral parity with Valheim.** Earlier reliability work transferred useful safeguards, but the old audit did not establish complete native-window, menu, or background-service behavior. In particular, changing SwiftUI's management scene from WindowGroup to Window introduced last-window termination without an explicit stay-running delegate policy. The subsequent quit-warning fix treated the symptom without covering the underlying close-window workflow.

This audit compares Enshrouded commit `ab9e8a1` with Valheim's current public main `b02b951` (1.3). The reference checkout was fetched and confirmed current on September 30. Paths below refer to this repository; `V/` means `.development/valheim-public-template/Sources/`. That reference checkout is not shipped. Findings describe the pre-implementation baseline, so line numbers can change during repairs.

### Evidence and limits

Three independent source reviews covered lifecycle, installation/updates, and management features. Both implementations, related tests, release scripts, and Valheim's relevant fix history were examined. Enshrouded's existing 121 tests and latest GitHub CI passed before this work; that does **not** prove native interaction parity. A disposable build with the proposed last-window delegate fix stayed alive after closing its actual SwiftUI management window; startup completion and reopening still need end-to-end proof.

No production game was stopped, no world was changed, and no candidate was installed during this audit. Fresh hardware, a second macOS version, actual logout/login, external player connectivity, and power-loss recovery are not newly verified. Source inspection is labeled separately from executed tests in the implementation record.

## Findings requiring implementation

### Lifecycle and background operation

- **L01 / P1 — Closing management can quit the app.** Enshrouded `Sources/EnshroudedManager/App.swift:8` uses a single SwiftUI Window without `applicationShouldTerminateAfterLastWindowClosed`. Valheim owns a persistent AppKit application (`V/ValheimServerMonitor/main.swift:588`) and separate windows (`ServerManagement.swift:74`). Closing UI must not invoke quit protection or end the fleet, polling, schedules, or a pending start. A proposed delegate fix exists but is not yet packaged.
- **L02 / P1 — Login startup also runs on ordinary manager launches.** `ServerModel.swift:243` treats `startAtLogin` as a launch condition every time the manager opens. Valheim `V/ServerCore/LoginItems.swift:48` distinguishes login services from the UI. A manually stopped server must stay stopped after Finder/menu relaunch; update-resume receipts must continue working.
- **L03 / P1 — Sleep protection ends when the manager quits.** `ServerModel.swift:205` owns the IOKit assertion in the UI process. Valheim `V/ServerCore/Lifecycle.swift:210` owns it in the server service. Protection must follow the running server, survive UI exit, and end when hosting stops.
- **L04 / P2 — Manager and server login preferences are coupled.** `ServerModel.swift:338` registers the main app to implement server login startup; deleting the last autostart profile can unregister it (`FleetModel.swift:288`). Valheim `LoginItems.swift:68` and `main.swift:265` provide an independent manager-login choice. All four manager/server preference combinations need correct behavior.
- **L05 / P2 — Unexpected game exits are not recovered.** `Runtime/guest.sh:119` creates a transient service without restart recovery. Valheim's service uses failure-only KeepAlive and throttling (`LoginItems.swift:27,43`). Recovery must distinguish crashes from intentional stop/update/delete and avoid rapid restart loops.
- **L06 / P2 — No real host UDP occupancy check before start.** Enshrouded checks profile uniqueness but not unrelated listeners (`FleetModel.swift:91`, `Engine.swift:278`). Valheim binds the actual ports before start (`Lifecycle.swift:136`). Reject conflicts without touching the other process; recognize the manager's own existing Lima forwarder.

### Updates and menu state

- **U01 / P1 — Failed discovery leaves stale automatic-update eligibility.** `ServerModel.swift:235` retains the earlier release and timestamp after a failed check; the automatic predicate at `:290` ignores the failure. Valheim `main.swift:484` requires a successful latest check. Failure must invalidate eligibility until a later successful check.
- **U02 / P2 — Server updates have logs instead of a proper progress presentation.** `ManagementView.swift:25,66` routes to raw logs. Valheim `ServerUpdate.swift:37–72` shows phases, elapsed time, and available percentages. Enshrouded already emits structured download events and has `SetupProgress`; reuse them for save, download, verification, and restart. Closing progress must not cancel work.
- **U03 / P2 — Successful manager upgrades retain old app transactions indefinitely.** `ManagerInstallation.swift:52`, `FleetModel.swift:205`, and `LaunchInstallation.swift:84` do not clean up after confirmed relaunch. Valheim `AppLocation.swift:95–100` does. Preserve recovery on failure; remove only the transaction from a confirmed successful launch.
- **U04 / P2 — Stable can overwrite experimental unexpectedly.** `BuildInfo.swift:25` allows it; Valheim `AppInstallation.swift:39` explicitly protects experimental installs. Match the precedence and explain how to deliberately leave experimental.
- **M01 / P2 — Update badge is absent from the closed menu-bar item.** `StatusMenu.swift:27` shows only hosting state/count. Valheim `main.swift:180` includes an update badge after the count. Preserve player count and busy indication while signaling either supported update.
- **M02 / P3 — Manager release row becomes stale during menu tracking.** `StatusMenu.swift:102` captures title/enabled state at rebuild, unlike its live check action. Make result, action, icon, and help update without rebuilding hovered rows.

### Management, settings, and automation

- **S01 / P2 — Settings and New Server remain attached sheets.** `ManagementView.swift:63`, `SettingsAndLogsViews.swift:73`, `FleetModel.swift:126`; Valheim `Editor.swift:59–69` uses owned movable/resizable editors. Preserve drafts, one editor per context, focus, and predictable closing/reopening.
- **S02 / P2 — Read-only inspection is obstructed.** Enshrouded disables Show Passwords and leaves a disabled Save plus Cancel. Valheim `Editor.swift:167–172` hides Save, offers Close, and permits inspection. Disable mutations, not safe inspection and help.
- **S03 / P2 — Existing servers cannot change host UDP port.** Creation exposes it, settings do not. Valheim `Editor.swift:136` does. Add a stopped-only transaction that validates fleet/listener conflicts, updates the profile and VM forwarding, and rolls back failure. Do not merely change a text field while leaving forwarding stale.
- **S04 / P2 — Management actions lack parity.** The Delete Server callback is passed but unused (`ManagementView.swift:9`); its start/stop button stays labeled Start/Stop during transitions (`:49`). Valheim `ServerManagement.swift:192,324–337` provides Delete and pending-action labels. Reuse existing safe deletion and actual operation state.
- **S05 / P3 — General settings help is sparse.** Rules have good help; name, slots, passwords, chat, and port lack comparable explanation. Valheim `Editor.swift:112` consistently attaches field help. Add concise, accessible explanations.
- **A01 / P2 — Scheduled restarts lack Skip if Players Are Online.** Enshrouded supports only waiting (`Automation.swift:59–68`); Valheim `RestartScheduleWindow.swift:32–34` offers skip/wait/warn. Implement skip/wait with backward-compatible wait default. Do not simulate unsupported in-game warnings.

### Monitoring, logs, and world transfer

- **P01 / P2 — Ping cards can represent departed players or empty history.** `ManagementView.swift:132–140` renders every retained key; `ServerModel.swift:150` keeps expired keys. Valheim `PlayerPingGraphs.swift:35–48` renders current connections. Separate stopped, unavailable, and confirmed empty; preserve useful history without showing stale players as current.
- **P02 / P2 — All monitoring is suspended during operations.** `ServerModel.swift:109` exits whenever busy, unlike Valheim's independent `PerformanceRecorder.swift:25–55`. Read-only telemetry should continue where safe. It must not boot/shutdown environments or race state-changing work. Expose unavailable readings honestly.
- **P03 / P2 — Speed-report age can be misleading on manager launch.** `ServerSpeedHistory.swift` timestamps the last report when first observed, even if it was already in an old log. Irregular game reports explain some gaps; they do not justify labeling an old report fresh. Use authoritative report timing when available, otherwise disclose unknown age. Do not fabricate five-second speed measurements.
- **D01 / P2 — Activity omits externally written installation/update diagnostics.** `LogsView` uses in-process activity; Valheim `LogViewer.swift:17–36` collects relevant named logs. Include fresh external activity and discoverable installer logs, preserving per-server boundaries and credential protection.
- **D02 / P2 — World import only accepts a primary file.** Enshrouded `Backups.swift:145–179` imports its valid native save family, but Valheim `Editor.swift:123–125` also accepts folder/ZIP convenience. Add safe folder/ZIP selection for Enshrouded's format, with ambiguity, traversal, symlink, size, and corruption checks before touching existing worlds.
- **T01 / P1 — Acceptance tests missed the requested window lifecycle.** Unit counts and signatures were treated as broader proof. Add repeatable isolated close/reopen during start/stop, explicit-quit behavior, draft focus, and menu-tracking checks. Record unexecuted cases instead of marking them passed.
- **T02 / P2 — Existing parity documentation is stale and over-broad.** `docs/VALHEIM-PARITY.md` describes 93 tests and approximately minute-cadence speed reporting. Replace its implied parity conclusion with this audited baseline, plan, and actual verification record.

## Confirmed corresponding behavior to preserve

Source comparison found matching intent and concrete safeguards in the following workflows:

- App installation into Applications, signed-copy validation, old-instance coordination, and relaunch from the installed location.
- Latest public game files fetched during first setup, validated staging before replacement, world/settings preservation, and recovery after replacement failure.
- Manager download size/digest, expected version and publisher checks, Gatekeeper validation, public-release discovery disabled for experimental builds.
- Persistent per-server update-resume markers; stopped servers remain stopped through normal manager updates. Do not remove these while fixing login behavior.
- Clean game shutdown with bounded save/stop checks and no force-kill fallback; server remains independent of UI process.
- Per-server start/stop gating rather than blocking unrelated servers; immediate operation state exists even though one button omits it.
- Stable menu item identity during tracking, timer delivery in common run-loop modes, and independent log windows with native text selection, wrapping, filtering, and copy without line numbers.
- Stopped-only settings writes, draft cancellation, errors retained for retry, preservation of unknown game settings/custom roles/bans, and automatic Custom rules selection.
- Named backups, confirmation before restore, a recovery backup before destructive replacement, and preservation of original saves. Enshrouded's integrity manifests and symlink checks are additional safeguards worth retaining.
- Per-server local-time schedules, DST-aware date calculation, stopped servers staying stopped, and receipt-based handling of missed versus already-waiting restarts.
- App-owned in-memory performance history independent of management windows. Neither current recorder persists history across full manager exit; that is not a parity gap. Enshrouded's app-lifetime bug currently defeats the window-independence guarantee.
- App-only release archives, signing/notarization/stapling, failure diagnostics, draft publication, and cleanup of signing material. Enshrouded additionally verifies both ZIP extraction paths, exact source targets, immutable versions, and documentation links.

These are source-confirmed matches, not a claim that every integration path was executed today.

## Differences justified by game/runtime capabilities

- Enshrouded distributes a Windows dedicated-server executable. Its private VM/Wine/Box64 environment, larger setup allowance, boot stages, and guest-to-host UDP forwarding differ from Valheim's native macOS runtime. They do not justify poorer progress or window behavior. See [official installation guidance](https://enshrouded.zendesk.com/hc/en-us/articles/16051370691485-Dedicated-Server-Installation-on-Steam).
- Enshrouded exposes its own roles, query port, slot count, chat and gameplay settings rather than Valheim's options. Preserve game-native names and limits. See [official dedicated-server configuration](https://enshrouded.zendesk.com/hc/en-us/articles/16055441447709-Dedicated-Server-Configuration).
- Valheim's management companion supplies live simulation metrics, named-player controls, broadcasts, raid/time commands, and BepInEx/Jötunn integrations. The current Enshrouded runtime does not expose an equivalent supported bridge. Keep native game configuration and in-game administration; do not add dead controls or Valheim binaries. This audit does not establish that every possible community extension is impossible.
- Enshrouded speed reports are irregular minute aggregates; actual local logs include multi-minute omissions. Its graph must label the source and real report age. Memory and ping also have different underlying measurements and must be labeled honestly.
- Without a supported warning/broadcast bridge, Enshrouded's confirmed-empty maintenance requirement is appropriate. Valheim also falls back to empty-server behavior when its bridge is unavailable. Skip-versus-wait policy does not require a bridge and is a real gap above.
- World file formats differ. Importing the correct save family is game-specific; convenient folder/ZIP selection is not.

## Explicit user preferences retained

These intentional differences were directly requested and must not be accidentally reverted by copying the template: three-hour history; five-second memory averages; five-minute manager-update checks; automatically saved automation settings; daily scheduled backups in Automation; categorized World Rules inside Server Settings; no separate World Controls or Join/Hosting window; global full-file uninstall and per-server deletion; app-only local delivery folder; no automatic installation of the candidate onto the user's Mac.

## Acceptance

The implementation plan must cover every actionable finding above and report each as fixed and tested, fixed with a named verification limit, or unresolved with a concrete reason. A green test count alone is not acceptance. No new public GitHub release is authorized by this audit request; provide a signed/notarized candidate for manual installation after the work is verified.

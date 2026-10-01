# Parity Implementation Plan — 2026-09-30

> Historical record. Later behavior and verification are documented in [0.1.18 release notes](RELEASE-NOTES-0.1.18.md) and the current setup guide. Earlier candidate descriptions are not current instructions.

Based on [the full audit](VALHEIM-PARITY-AUDIT-2026-09-30.md). Status at creation: audit complete; implementation not started, except the unshipped L01 delegate fix already under investigation. Findings retain their baseline IDs throughout implementation.

## 1. Protect lifecycle and update decisions

L01, U01, U04, T01. Finish last-window-close policy; test closing during startup and explicit quit separately. Invalidate failed update discovery; enforce experimental precedence. Add regression tests before packaging.

Acceptance: close-window never quits or interrupts startup; reopening reuses the manager; explicit idle quit still exits; failed discovery cannot authorize update; experimental installation is not silently replaced by stable.

## 2. Separate background hosting from UI lifecycle

L02–L06, L04. Add actual login startup handling independent of manager launch; separate manager/server preferences. Move host sleep protection to an owned background lifetime, preserve update resume receipts, add throttled game-crash recovery that cannot undo an intentional stop, and validate host UDP ownership before start. Use isolated LaunchAgent generation and process/socket fixtures; never register test jobs in the user's production login domain.

Acceptance: manually stopped server stays stopped on manager relaunch; actual login launch follows configured servers; manager-login preference is independent; assertion survives manager exit and ends with hosting; crash recovery is throttled; stop/update/delete suppress restart; foreign UDP listener is not disturbed. Actual logout/login remains a named external validation limit unless safely performed by the user.

## 3. Bring updates and menus into alignment

U02, U03, M01, M02. Reuse structured installation progress for server updates, with readable stages/elapsed time/log access and non-cancelling window close. Clean only confirmed-success manager transactions. Update menu badges and rows in place.

Acceptance: update progress remains understandable through save/download/verify/restart/failure; closing progress preserves the operation; failed relaunch preserves recovery; successful relaunch cleans its own transaction; update availability is visible with the menu closed and becomes actionable while the menu remains open.

## 4. Align settings and management interactions

S01–S05. Use independent owned settings/new-server editors with draft retention and predictable single-window identity. Improve read-only inspection/help, expose safe stopped-only UDP port changes with rollback, wire management deletion, and display pending start/stop labels.

Acceptance: focus, drag, resize, scroll and help work; closing management cannot destroy a draft or quit; edits cannot mutate a running server; a port change updates both stored identity and forwarding or leaves the original intact; deletion targets the selected server and preserves downloaded installation/world archive.

## 5. Complete scheduling and telemetry/log parity

A01, P01–P03, D01. Add backward-compatible skip/wait policy. Filter ping UI to current fresh connections. Continue safe read-only monitoring during operations without letting stale reads override operation state. Correct speed-report freshness and refresh externally written activity/installer diagnostics.

Acceptance: occupied/unknown/empty and missed schedule cases are tested; disconnected/stopped players do not appear current; long operations do not freeze all readable telemetry; old log reports do not appear new; logs show current applicable sources without leaking credentials.

## 6. Complete world-import convenience

D02. Accept an Enshrouded primary file, an unambiguous save folder, or safe ZIP; reuse existing validated atomic import and backup behavior.

Acceptance: valid native save families import consistently; ambiguous archives ask for a specific world; traversal, links, oversized/invalid archives fail before changing existing data; no Valheim file assumptions are introduced.

## 7. Record verification and build the candidate

T01, T02 and all findings. Update the old parity document to link to the authoritative audit and results. Run the expanded unit suite and shell/Python checks, isolated native workflow tests, signed build, notarization, both archive extractions, copied-app signature/ticket/distribution checks, and GitHub CI. Record source-only versus executed evidence and outstanding hardware/network/login limits.

Deliver an app-only folder for manual installation. Do not install it into Applications, stop the production game for tests, or publish a GitHub Release as part of this request.

## Implementation record

Implementation completed in the 0.1.9 candidate. The original audit remains the unchanged record of the starting state. Packaging and CI results are recorded below.

### Lifecycle: L01–L06

- **L01 fixed.** Closing the last window never requests app termination. Explicit quit still refuses during an operation and dismisses its notice when work finishes. `QuitWarningTests` verifies idle/startup closing, nonmodal quit handling and updater bypass. An isolated actual app retained a typed settings draft after management closed and stayed alive with every window closed. A second native run closed progress and then the last management window while its controlled 60-second startup was still pending; the same process remained alive and recorded completion of the wait and its intentional startup error with all windows closed. The fixture deliberately reports a startup error instead of launching a real game.
- **L02/L04 fixed.** Per-server LaunchAgents launch a headless login entry point. Ordinary manager startup only honors update-resume receipts. Open Manager at Login uses its own setting, independently of each server's login setting. Enabling server login does not bootstrap or immediately start a stopped server. `BackgroundHostingTests` verifies configuration, isolation and rollback; `WorkflowParityTests` opens a login-enabled stopped fixture and proves no start command occurs. Actual logout/login and all four OS login combinations have not been exercised on this Mac.
- **L03 fixed.** A separate, uniquely locked helper owns idle-sleep protection through UI exit and crash recovery. Confirmed stop/disabled protection releases it. `BackgroundHostingTests` executes a helper that outlives its launching process and verifies duplicate exclusion/cleanup; injected assertion callbacks verify running/recovering/unknown/stopped transitions. A separate isolated process check confirmed the real helper’s `PreventUserIdleSystemSleep` assertion in `pmset`, then confirmed its exit and assertion removal after fixture shutdown. Actual sleep was not induced.
- **L05 fixed.** The game service retries unexpected exits after 30 seconds, capped at five starts in five minutes. A serialized deliberate-stop marker prevents pending recovery from launching another game. `RuntimeRecoveryTests` executes the guest wrapper against controlled game/service fixtures, covering failure, unexpected clean exit, intentional stop and pending recovery. Recovery is visible and stoppable. Manager replacement saves resume intent and shuts down recovering environments; game maintenance refuses to race recovery. Real systemd recovery after a game crash was not induced on the production VM.
- **L06 fixed.** Initial installation/start and stopped-server port edits check real UDP occupancy. An existing forwarder is exempted only after executable/argv/process-lifetime validation and exclusive local socket ownership. `HostPortAvailabilityTests`, `EngineTests` and `ProfilePortChangeTests` cover foreign listeners, forged receipts and unchanged state on rejection. A read-only probe against this Mac's existing Lima forwarder recognized it and passed without changing it.

### Updates and menus: U01–U04, M01–M02

- **U01 fixed.** A failed check clears successful freshness; automatic updates also require no check error. A fake downloader failure in `WorkflowParityTests` proves stale cached availability cannot issue update/start commands.
- **U02 fixed.** Server operations show current phase, elapsed time, actual available download percentage/byte detail, errors and log access. Progress-window closure leaves work running. `ServerOperationProgressTests` covers chunk boundaries, stage changes, percentage reset, failure and completion; isolated native startup showed elapsed progress and continued after its progress window closed. Fleet updates queue behind in-flight probes instead of silently ignoring a click.
- **U03 fixed.** Both installer paths clean only their own validated replacement transaction after successful relaunch. Failed relaunch keeps recovery. `InstallationTests` verifies successful cleanup, first-install cleanup, unknown/linked-path rejection and failure preservation.
- **U04 fixed.** Stable updates cannot silently replace experimental installations. Tests cover both channels and same/newer stable versions; the error explains deliberate Finder replacement.
- **M01/M02 fixed.** Closed-menu update badge preserves hosting status/count. The manager update row refreshes title, enabled state, icon and help in place. Existing common-mode menu refresh and stable row identity remain. This result is source-reviewed; live download-completion while hovering a production menu was not exercised in this pass.

### Editors and management: S01–S05

- **S01 fixed.** Settings and New Server have separately owned windows, one per context. `WorkflowParityTests` proves reuse, state-container retention across management closure, release/recreation on editor closure and deletion cleanup. Native typing, section expansion and retained draft text were exercised in the isolated app. Creation from the menu opens the new server's management/setup; deletion closes its retained windows. Free dragging/resizing and menu-only management reopening were not fully exercised because the computer-use transport could not inspect the windowless app.
- **S02 fixed.** Read-only is fixed for the editor's lifetime; Close replaces Save/Cancel, password reveal and selectable displayed values remain available. A stopped editor becoming temporarily busy retains its draft. Reopen after stopping to obtain an editable view.
- **S03 fixed.** UDP editing is stopped-only and rejects fleet/foreign-listener conflicts before shutdown. It updates host forwarding, profile and registry together with byte-for-byte rollback; the guest's port stays 15637. Tests cover shutdown ordering, rollback, isolation, links, missing registration and locks. Default/legacy primary servers without a per-home profile also migrate safely; failure removes only the transaction-created profile. No production port was changed.
- **S04 fixed.** Management exposes its existing safe deletion workflow and accurate pending start/stop labels. Deletion still archives server-specific data and retains reusable downloads/environment.
- **S05 fixed.** General name, port, slot, role/password and chat controls now explain their effects. Existing rule descriptions and tooltips remain. Additional review found and fixed stale drafts: `WorldSettingsTests` proves conflicting on-disk settings/rules cannot be overwritten by an older editor, including formatting-only changes. The editor also initializes its draft/rules from the exact current configuration bytes used as its conflict baseline, rather than a cached model.

### Scheduling, monitoring and diagnostics: A01, P01–P03, D01

- **A01 fixed.** Skip or wait is configurable in Automation; legacy settings default to wait. Policy tests cover occupied/unknown/invalid/empty counts, schedule reconciliation and missed events. No unsupported in-game broadcast option was added.
- **P01 fixed.** Ping cards require a current running server, a fresh native report and a currently reported connection. Confirmed empty/stopped and unavailable readings are distinguished; expired history keys are removed. Native elapsed timestamps also prevent old peer reports looking newly observed.
- **P02 fixed.** Independent read-only log/metrics probes continue during long operations when the server was running. Probes never start a VM; operation epochs discard results that complete after their operation ends. Normal state/automation refresh remains serialized. This integration is source-reviewed; it was not load-tested against a production update.
- **P03 fixed.** Speed samples use native elapsed timing plus the same file snapshot's modification time. Unknown-age reports are labeled unknown and are not placed at a fabricated current graph time. `LogSnapshotTests` and `ServerSpeedHistoryTests` cover old logs, current appends, incomplete lines, duplicate values, rotation, restart and expiry. This Mac's actual native stats format was checked read-only. Reports remain irregular game measurements; five-second speed values are not invented.
- **D01 fixed.** Logs reread persisted server-manager and separately labeled global installer activity every second, including external writers. The folder buttons use the same native/stdout source selection as the viewer. Existing bounded-log and filter/copy safeguards remain. Isolated previews do not read the production installer log.

### World transfer: D02

- **D02 fixed.** Both setup and later import accept a primary save, unambiguous folder or validated ZIP. Preparation feeds the existing atomic import/backup workflow. `WorldImportSourceTests` covers native families, nested folders, stored/deflated archives, ambiguity, traversal, links, collisions, corrupt/encrypted/unsupported archives and cleanup. Existing world tests verify recovery backup and native save-family import. ZIP decoding uses bundled macOS tools; it adds no Python dependency to the Mac app.

### Verification: T01/T02

- **T01 addressed with explicit limits.** The suite has 177 core tests and 8 manager/AppKit tests, all passing. Four Python downloader tests and shell/Python syntax checks pass. Native checks used the actual debug manager executable in a separate app with fake Lima and an isolated home. No production server, settings, login job or installed app was changed.
- **T02 fixed.** The old broad parity checklist now points to the dated baseline audit and this implementation/evidence record.
- Remaining verification limits are actual logout/login, induced macOS sleep, a real VM crash/recovery, fresh hardware/another macOS version, remote multiplayer connectivity/load, complete native drag/resize/reopen/menu-hover scenarios and a live game update under load. These are not reported as passed. No remaining known implementation finding from this audit is intentionally deferred.

### Candidate and CI

- Candidate: **0.1.9**, build **260930.1426.47**, stable channel, for manual installation.
- App-only delivery folder: `dist/Parity-Audit-0.1.9-260930.1426.47/`.
- Developer ID signature, hardened runtime, Apple notarization acceptance (`6ae80169-f5ec-4d1b-8ad1-92684bdf443e`), stapled ticket and Gatekeeper assessment passed.
- Both `ditto` and ordinary `unzip` extractions passed signature/ticket/Gatekeeper validation. The copied delivery app passed `codesign --verify --deep --strict`, `stapler validate` and `syspolicy_check distribution`.
- Final local suite: **185 Swift tests** (177 core, 8 manager), **4 Python tests**, shell/Python syntax checks and clean diff whitespace validation.
- GitHub macOS CI passed for implementation commit `05b37d5`: [Build and Test run 36729395841](https://github.com/GlacianNex/enshrouded-mac-server/actions/runs/36729395841), including tests, script validation, Apple Silicon app build and artifact upload. Subsequent edits only record verification results; candidate code is unchanged.
- No GitHub release or automatic installation performed.

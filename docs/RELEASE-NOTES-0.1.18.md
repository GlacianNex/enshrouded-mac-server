# 0.1.18 — Clearer Setup, Reliable Updates, and Simpler Management

2026-10-01 · Changes since public release 0.1.2

## TL;DR

A simpler first-install experience, visible setup and update progress, more responsive menus and editors, and fixes for hosting, server deletion and Mac compatibility. Includes the improvements tested in candidates 0.1.3–0.1.17.

## Features

- Create a server in one form: name, passwords, UDP port, optional world import and startup preference. Review downloads before setup; follow installation steps, reported bytes, actual compilation progress and activity indicators.
- Read server, manager and installation output in the built-in log viewer. Update logs use the same viewer. Windows are movable and resizable, with filtering, wrapping and line numbers.
- See manager update status in the top version row and click it when an update is available. The game-build row separately offers Enshrouded server updates. The redundant update button is removed.
- Configure scheduled restart skip/wait policy, daily backups and login startup in Automation. Import a world file, an unambiguous folder or a ZIP.
- Delete one server’s complete installation and VM, with an optional checkbox to also delete game data and backups. Otherwise saved data is archived. Clear Download Cache separately removes reusable downloads after confirmation and preserves existing installations.

## Bug Fixes

- Closing management or setup windows leaves the manager and its work running in the menu bar. Manager updates return to the menu bar without opening the first server’s window.
- Startup and shutdown show status in management without progress popups. Unrelated menu actions remain available; server startups are queued to avoid overlapping environment startup.
- Fix unresponsive setup fields and installer buttons, stale deleted-server entries and incomplete-install player status. Pending servers show Installation Pending.
- Explain manager-update stages and long waits, preserve recovery after failures, and keep runtime helpers available to running environments. Quit protection names the active operation and updates as it finishes.
- Fix UDP forwarding connection exhaustion, keep menu status live, and retain valid speed history across temporary probe failures. Speed gaps remain visible when the game supplies no measurement.
- Bundle a VM launcher targeting macOS 14 instead of inheriting the developer’s newer OS requirement. Packaging now checks every bundled executable for Apple Silicon support, minimum OS and external library dependencies.
- Remove obsolete uninstall/progress commands, keep Delete Server on the management action row and use Close in log windows.

## Install or Update

Download the app from the [latest release](https://github.com/GlacianNex/enshrouded-mac-server/releases/latest), unzip into a fresh folder and open it. Choose **Install & Open**, or **Stop, Update & Relaunch** for an existing manager.

**Updating the manager stops all running servers and starts them again when the update finishes.** Connected players are disconnected. Stopped servers stay stopped. Existing game data, settings and backups are preserved.

Requires **Apple Silicon, macOS 14 or later, internet and at least 30 GB free space**. Each server allocates four CPU cores and 8 GiB RAM; 16 GB Mac memory is recommended for one server. The 30 GB requirement is storage headroom, not a download size. The app bundles its launcher and automatically downloads Ubuntu, compatibility tools and the latest public game server. No separate Xcode, Command Line Tools, Homebrew, Wine, CrossOver, Rosetta or Steam installation is needed. Forward a separate UDP port for each internet-facing server.

## Verification and Limits

**221 Swift tests and 13 Python tests passed**, with one optional large-download test skipped. The Developer ID signed app is Apple-notarized and stapled; both ZIP extraction methods passed signature and Gatekeeper checks. GitHub CI passed the clean build and tests. Exact results are recorded in [Verification](VERIFICATION.md). The dependency audit exercised a fresh isolated Ubuntu environment with host developer tools blocked. Earlier isolated tests cover setup, updates, deletion, cache preservation, menus and window lifecycle; the user also verified real gameplay on Apple Silicon.

Full installation on a separate fresh Mac and end-to-end hosting on older supported macOS releases remain unverified. Sustained multiplayer load, real login/sleep recovery and concurrent live-server scenarios are not fully covered. The reported delete-checkbox window behavior was not reproduced; it is not claimed resolved. Server-speed samples depend on the game’s irregular reports. Live time/weather/spawn commands are not supported.

See [Setup and Recovery](SETUP.md), [Installation Dependencies](INSTALLATION-DEPENDENCIES.md) and the [behavior audit](VALHEIM-PARITY.md).

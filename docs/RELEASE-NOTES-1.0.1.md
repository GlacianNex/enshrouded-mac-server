# Enshrouded Server Manager for Mac 1.0.1

October 18, 2026 · Previous public release: 0.1.18

## What’s New

- **Reliable server version detection.** Fixes “Server Build Unavailable” after updates that reuse cached downloads, so the manager can correctly compare the installed server with Valve’s latest release.
- **Complete speed history.** Retains every available report after delayed polling and restores recent reports when the manager reopens. Readings connect within each server run, with breaks across restarts.
- **Install stable over experimental.** Open the stable app and use the normal update workflow to switch back from an experimental manager.
- **Clear empty-server status.** A manager with no registered servers shows “No Servers”; real servers awaiting setup show “Installation Pending.”

## Install or Update

[Download for Mac](https://github.com/GlacianNex/enshrouded-mac-server/releases/latest), unzip, and open the app. Choose **Install & Open** for a first installation or **Stop, Update & Relaunch** to update. Updating saves and stops running servers, replaces the manager in Applications, then restarts those servers. Server data is preserved.

Requires Apple Silicon, macOS 14 or later, internet access for setup, and 30 GB of free space. At least 16 GB of RAM is recommended. Setup downloads the latest official server and its required tools automatically.

## Verification

228 Swift tests completed with zero failures and one optional test skipped; all 13 Python tests passed. Developer ID signed and Apple-notarized. Signature, stapled ticket, Gatekeeper and archive extraction checks passed. Automated regressions cover installed-build detection, cached downloads, speed-history recovery and experimental-to-stable installation.

Enshrouded can leave several minutes between speed reports; the graph does not invent fresh measurements. Separate-Mac testing of this build remains unperformed. See [verification details](VERIFICATION.md).

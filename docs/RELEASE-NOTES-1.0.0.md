# Enshrouded Server Manager for Mac 1.0.0 — Reliable Speed History

Prepared October 18, 2026 · Previous public version: 0.1.18

## TL;DR

Server speed readings form a connected history, and the manager retains every available report after delayed polls or reopening. An empty manager now correctly says **No Servers**.

## What Changed

- Connect speed reports within each server run, preserving breaks across restarts.
- Collect every complete speed report in the recent log instead of discarding all but the newest.
- Keep report ages visible: Enshrouded can leave minutes between speed reports.

- The menu bar shows **No Servers** when there are no registered servers.
- The server version row shows **No Servers Installed**, replacing the misleading **Build Unavailable** message.
- Actual registered servers awaiting setup still show **Installation Pending**. Choose **New Server…** to create one.

## Install or Update

Download the app from the [1.0.0 release](https://github.com/GlacianNex/enshrouded-mac-server/releases/tag/v1.0.0).

Requires Apple Silicon and macOS 14 or later. Manager updates save and stop running servers, then resume them after installation. Existing server data is preserved.

## Verification

224 Swift tests completed with zero failures and one optional test skipped; all 13 Python tests passed.

The regression covers an empty registry, the available New Server action, and a real pending installation. Existing version-row behavior is also tested. See [verification details](VERIFICATION.md).

Developer ID signing, Apple notarization, stapling, Gatekeeper, and archive validation with both ditto and unzip passed. GitHub CI passed. This build has not been tested on another physical Mac.

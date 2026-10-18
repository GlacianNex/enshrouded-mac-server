# Enshrouded Server Manager for Mac 1.0.0 — Clear Empty-Server Status

Prepared October 18, 2026 · Previous public version: 0.1.18

## TL;DR

An empty manager now says **No Servers** instead of appearing stuck in installation.

## What Changed

- The menu bar shows **No Servers** when there are no registered servers.
- The server version row shows **No Servers Installed**, replacing the misleading **Build Unavailable** message.
- Actual registered servers awaiting setup still show **Installation Pending**. Choose **New Server…** to create one.

## Install or Update

Download the app from the [1.0.0 release](https://github.com/GlacianNex/enshrouded-mac-server/releases/tag/v1.0.0).

Requires Apple Silicon and macOS 14 or later. Manager updates save and stop running servers, then resume them after installation. Existing server data is preserved.

## Verification

222 Swift tests completed with zero failures and one optional test skipped; all 13 Python tests passed.

The regression covers an empty registry, the available New Server action, and a real pending installation. Existing version-row behavior is also tested. See [verification details](VERIFICATION.md).

Developer ID signing, Apple notarization, stapling, Gatekeeper, and archive validation with both ditto and unzip passed. GitHub CI passed. This build has not been tested on another physical Mac.

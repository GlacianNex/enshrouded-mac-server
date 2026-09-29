# 0.1.1 — Fix Opening the Downloaded App

Released September 29, 2026 · Changes since 0.1.0

## TL;DR

Fixes the “app is damaged” error when opening an extracted download. Download the corrected release and extract it into a fresh folder. Existing worlds and settings are preserved.

## What Changed

The ZIP now omits hidden macOS metadata files that some extractors left inside the app, invalidating its signature. Packaging checks now reject these files and verify both metadata-aware and ordinary ZIP extraction.

## Install or Update

Download **Enshrouded-Server-Manager-for-Mac.zip** from the [latest release](https://github.com/GlacianNex/enshrouded-mac-server/releases/latest), extract it into a fresh folder, and open the app. Discard any previous 0.1.0 download first.

For a new installation, choose **Install & Open**. For an existing installation, choose **Stop, Update & Relaunch**. Existing worlds and settings are preserved.

The app is Developer ID signed and Apple-notarized. Requires Apple Silicon and macOS 14 or later.

## Verification

44 tests passed, GitHub CI passed, and signature, notarization ticket, and Gatekeeper checks passed after both metadata-aware and ordinary ZIP extraction. The uploaded GitHub archive was downloaded again and verified. Confirmation on the affected second Mac remains pending.

See [Setup and Recovery](SETUP.md), [Verification](VERIFICATION.md), and the [original 0.1 features](RELEASE-NOTES-0.1.md).

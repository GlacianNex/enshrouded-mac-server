# 0.1.4 — Reliable Updates with a Running Server

> Historical record. Later behavior and verification are documented in [0.1.18 release notes](RELEASE-NOTES-0.1.18.md) and the current setup guide. Earlier candidate descriptions are not current instructions.

Candidate · Includes the 0.1.3 candidate changes

## What Changed

Fix an update failure that could report a missing file after the previous manager closed. Replacing helper files in a running VM's shared folder could leave its file cache pointing at removed files. Each helper version now has its own immutable folder, so updating the manager does not replace files already visible to the VM.

Failed installations reopen the installed manager after the error is acknowledged. Installer diagnostics are saved under `~/Library/Logs/Enshrouded Manager/Installer/`.

This candidate uses 0.1.4 so it can replace already-installed 0.1.3 candidates without weakening downgrade protection. It also includes [setup progress, server-file uninstall, and five-minute manager-update checks](RELEASE-NOTES-0.1.3.md).

## Verification

A live VM probe reproduced three missing-file reads after atomic file replacement. The fixed implementation passed six reads across three helper versions without restarting the VM or changing the running server. The 102-test Swift suite passes, including helper generation, installation rollback, and server recovery tests.

# 0.1.2 — Fix Installation Relaunch

Candidate · Changes since 0.1.1

## TL;DR

Fixes an installation path that can reopen the installer and incorrectly report that the same stable version is already installed.

## What Changed

The installer now uses the Valheim manager’s handling of download quarantine: after validating the staged app’s signature, it clears quarantine only from that approved installed copy. The original download is unchanged. This prevents another temporary-location launch from sending the installed manager back into its installer.

The app and menu bar again use the Enshrouded icon instead of the custom flame.

Version checks still prevent downgrades. Existing worlds and settings are preserved. The download packaging correction from 0.1.1 remains included.

## Install or Update

Open the downloaded app and choose **Install & Open**. If a previous copy exists in Applications, choose **Stop, Update & Relaunch**; running servers stop and restart after the update.

## Verification

The new regression test fails before the fix and passes afterward. All 45 tests pass. The test verifies that quarantine is removed from the installed copy and its executable, retained on the download, and the installed signature remains valid.

An isolated launch check installed a quarantined, signed release using the corrected copy routine and verified that it launched from its installed location without App Translocation. The original download retained quarantine and the installed signature remained valid.

Installation and reopening on the affected second Mac remain unverified. Keep this release a candidate until that check succeeds.

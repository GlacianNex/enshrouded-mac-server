# Enshrouded Server Manager for Mac 1.0.1

Fixes **Server Build Unavailable** after updates that reuse a cached download. The manager reads DepotDownloader’s installed-build record and can correctly compare it with Valve’s latest release.

The installer also records cached builds correctly. Existing servers and saved data are preserved.

Open the app and choose **Stop, Update & Relaunch** to update an existing manager. Running servers restart after the update.

All 33 relevant installation, workflow and build-detection tests passed, including cached manifests, stale receipts, corrupt records and update comparisons. See [verification details](VERIFICATION.md).

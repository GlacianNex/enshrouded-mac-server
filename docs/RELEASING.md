# Releasing

Public releases follow the same process as the Valheim Mac manager: build, test, sign, notarize, verify the extracted archive, push source, wait for CI, and publish a release with a ZIP and checksums.

## Build and Notarize

Update the version default in `scripts/build.sh`, changelog, and release notes, then run on Apple Silicon:

```sh
swift test
VERSION=0.1.1 SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' bash scripts/build.sh
NOTARY_PROFILE=ESM_NOTARY bash scripts/notarize.sh
```

Configure your Developer ID certificate and a Keychain notarization profile as described in [Apple Distribution](APPLE-DISTRIBUTION.md). No signing keys belong in the repository.

The scripts create `dist/Enshrouded-Server-Manager-for-Mac.zip` and `dist/SHA256SUMS.txt`. The ZIP contains only the `.app`, including its internal licenses. The runtime image and game server are downloaded during setup.

The notarization script requires Apple's Accepted status, staples and validates the ticket, checks Gatekeeper, and recreates the ZIP and checksum. Diagnostics stay in `dist/notarization`. If submission times out, inspect the existing submission before resubmitting.

Both scripts reject ZIPs containing AppleDouble (`._`) metadata files and verify signatures after extracting with both `ditto` and `unzip`. The notarization script also verifies the extracted tickets and Gatekeeper acceptance. Keep `--norsrc` on every ZIP creation command: metadata sidecars can become unsigned files inside the app when extracted.

For a manual check, extract the final ZIP into a fresh directory and run:

```sh
codesign --verify --deep --strict '/path/to/Enshrouded Server Manager.app'
xcrun stapler validate '/path/to/Enshrouded Server Manager.app'
spctl --assess --type execute --verbose '/path/to/Enshrouded Server Manager.app'
```

Review the exact staged source for private data. Commit, push, and wait for CI. Create a draft release for `v<version>` against that commit, upload the ZIP and `SHA256SUMS.txt`, then publish it as latest. Do not replace existing release binaries silently.

## GitHub Workflow

The manual **Prepare Release** workflow creates a draft. Signed drafts require these repository secrets:

- `APPLE_CERTIFICATE_P12`: base64-encoded Developer ID certificate with private key.
- `APPLE_CERTIFICATE_PASSWORD`: export password.
- `APPLE_SIGNING_IDENTITY`: Developer ID identity.
- `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD`: notarization credentials.

The workflow uses a temporary keychain and removes signing material afterward. Without these secrets, select an unsigned development draft. CI artifacts and unsigned drafts are not the notarized public download.

Local signing does not require storing Apple credentials on GitHub. Experimental builds use `bash scripts/build-experimental.sh`; do not publish them as stable releases.

## Release Notes and Links

Follow the Valheim dedicated-server manager's published notes: lead with what changes for the user, then explain the changes and verification. Keep patch notes short; use grouped Features and Bug Fixes for larger releases.

1. Write versioned notes in `docs/RELEASE-NOTES-<version>.md`. Include a descriptive title, release date and previous version, TL;DR, What Changed (or Features and Bug Fixes), Install or Update, and Verification. Omit empty sections. State actual requirements, server restart effects, data preservation, and meaningful limits.
2. Add a dated changelog entry linking to those notes. Update the README's What's New label and link in the same commit. Review setup and verification documentation for changed behavior.
3. Keep general download links on `https://github.com/GlacianNex/enshrouded-mac-server/releases/latest`. Historical notes remain versioned; mark a broken release superseded and link to the corrected download.
4. Use the checked-in release notes for the GitHub body. Convert relative documentation links to absolute GitHub links. The workflow's generic draft text is only a placeholder and must be replaced before publication.
5. Preserve stable asset names: `Enshrouded-Server-Manager-for-Mac.zip` and `SHA256SUMS.txt`. The ZIP contains the app only. A local handoff folder contains only the app, without a separate README.

## Publication Checklist

- Update source version, changelog, versioned notes, README, setup guidance, and verification together.
- Run appropriate tests, sign, notarize, staple, and verify both ZIP extraction methods. Preserve notarization diagnostics, including submission IDs after timeouts.
- Commit the exact release source and documentation, push, and wait for successful CI. Create the draft against that exact commit, not an implicit moving default branch.
- Download the candidate through a browser on another supported Mac, keeping quarantine intact. Test first open, installation, quit/reopen, and upgrade from the previous manager. Use disposable server data for start/save/stop/restart checks. Record the tested Mac and macOS version and any uncovered cases. Local signing checks do not substitute for this test.
- Confirm the uploaded ZIP's checksum, app version, signature, ticket, asset names, and release notes. Keep the candidate a draft until required validation is complete.
- Publish a regular release as Latest. Verify `/releases/latest` resolves to its tag, the README's What's New opens the corresponding notes, and setup/release links resolve. Confirm only the intended ZIP and checksum assets are present.
- Never silently replace a published binary. Ship a new patch version for corrections. Mark broken older releases superseded without erasing their history.

## Stable, Experimental, and Game Updates

Valheim separates stable releases, Experimental builds, and official game-server updates. Enshrouded follows that separation: Experimental builds are explicitly labeled, unsigned CI artifacts remain development builds, and official game-server versions are independent of the manager version.

Valheim also checks GitHub for manager updates and validates the downloaded size, digest, version, signing identity, and Gatekeeper acceptance before installation. Enshrouded currently uses manual manager downloads; automatic manager-update discovery remains a separate implementation gap. Do not describe it as present in release notes.

The packaging implementation must stay Enshrouded-specific: Apple Silicon only, bundled Lima tools with internal symbolic links, and runtime/server downloads during setup. Retain the metadata-sidecar exclusion and both extraction checks added in 0.1.1.

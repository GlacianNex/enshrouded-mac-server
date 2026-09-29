# Releasing

Public releases follow the same process as the Valheim Mac manager: build, test, sign, notarize, verify the extracted archive, push source, wait for CI, and publish a release with a ZIP and checksums.

## Build and Notarize

Update the version default in `scripts/build.sh`, changelog, and release notes, then run on Apple Silicon:

```sh
swift test
VERSION=0.1.0 SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' bash scripts/build.sh
NOTARY_PROFILE=ESM_NOTARY bash scripts/notarize.sh
```

Configure your Developer ID certificate and a Keychain notarization profile as described in [Apple Distribution](APPLE-DISTRIBUTION.md). No signing keys belong in the repository.

The scripts create `dist/Enshrouded-Server-Manager-for-Mac.zip` and `dist/SHA256SUMS.txt`. The ZIP contains only the `.app`, including its internal licenses. The runtime image and game server are downloaded during setup.

The notarization script requires Apple's Accepted status, staples and validates the ticket, checks Gatekeeper, and recreates the ZIP and checksum. Diagnostics stay in `dist/notarization`. If submission times out, inspect the existing submission before resubmitting.

Extract the final ZIP into a fresh directory and run:

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

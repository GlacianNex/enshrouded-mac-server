# Apple Distribution

Public downloads use Developer ID signing and Apple notarization. Local development builds use ad-hoc signing.

1. Enroll in the Apple Developer Program and install a Developer ID Application certificate in Keychain.
2. Set `SIGNING_IDENTITY` when running `scripts/build.sh`. The script signs the manager and nested executables, preserving virtualization entitlements.
3. Store notarization credentials in Keychain using `xcrun notarytool store-credentials ESM_NOTARY` and its interactive prompts.
4. Run `NOTARY_PROFILE=ESM_NOTARY bash scripts/notarize.sh`.
5. Verify the extracted final archive before publishing, as described in [Releasing](RELEASING.md).

Never put certificates, passwords, API keys, or exported keychains in source control. GitHub signing is optional; a locally notarized release can be uploaded from the maintainer's Mac.

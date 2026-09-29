#!/bin/bash
set -euo pipefail
for tool in codesign security ditto shasum; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
xcrun --find notarytool >/dev/null
xcrun --find stapler >/dev/null
: "${SIGNING_IDENTITY:?Set a Developer ID Application signing identity}"
identities="$(security find-identity -v -p codesigning)"
selected="$(printf '%s\n' "$identities" | SIGNING_SELECTION="$SIGNING_IDENTITY" python3 -c 'import os,sys; value=os.environ["SIGNING_SELECTION"]; print("\n".join(line for line in sys.stdin if value in line and "Developer ID Application:" in line))')"
[[ -n "$selected" ]] || { echo 'The selected Developer ID Application identity and private key are unavailable.' >&2; exit 1; }
echo 'Developer ID identity and notarization tools are available.'

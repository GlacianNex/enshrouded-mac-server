#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app='dist/Enshrouded Server Manager.app'
channel=$(/usr/libexec/PlistBuddy -c 'Print :ESMReleaseChannel' "$app/Contents/Info.plist")
archive="dist/Enshrouded-Server-Manager-for-Mac.zip"
mkdir -p dist/notarization
codesign --verify --deep --strict "$app"
signature="$(codesign -dv --verbose=4 "$app" 2>&1)"
[[ "$signature" == *'Authority=Developer ID Application:'* && "$signature" == *'runtime'* ]] || { echo 'Build with SIGNING_IDENTITY before notarizing.' >&2; exit 1; }
ditto -c -k --norsrc --keepParent "$app" "$archive"
xcrun notarytool submit "$archive" --keychain-profile "${NOTARY_PROFILE:-ESM_NOTARY}" --wait --timeout 20m --output-format json > dist/notarization/submission.json
status=$(/usr/bin/plutil -extract status raw -o - dist/notarization/submission.json)
id=$(/usr/bin/plutil -extract id raw -o - dist/notarization/submission.json)
xcrun notarytool log "$id" --keychain-profile "${NOTARY_PROFILE:-ESM_NOTARY}" dist/notarization/apple-log.json
[[ "$status" == Accepted ]] || { echo 'Notarization not accepted; inspect submission.json.' >&2; exit 1; }
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
ditto -c -k --norsrc --keepParent "$app" "$archive"
(cd dist && shasum -a 256 Enshrouded-Server-Manager-for-Mac.zip > SHA256SUMS.txt)

bash scripts/verify-archive.sh --notarized

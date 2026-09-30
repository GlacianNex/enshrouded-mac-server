#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
channel="${RELEASE_CHANNEL:-stable}"
[[ "$channel" == stable || "$channel" == experimental ]] || { echo 'RELEASE_CHANNEL must be stable or experimental' >&2; exit 1; }
version="${VERSION:-0.1.10}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'VERSION must use major.minor.patch' >&2; exit 1; }
build_version="$(date -u +%y%m%d.%H%M.%S)"
build_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then bash scripts/apple-preflight.sh; fi
bash scripts/prepare-tools.sh
swift build -c release --arch arm64
binary_dir=$(swift build -c release --arch arm64 --show-bin-path)
mkdir -p "$PWD/dist"
staging=$(mktemp -d "$PWD/dist/.build-XXXXXX")
trap 'rm -rf "$staging"' EXIT
app="$staging/Enshrouded Server Manager.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Runtime" "$app/Contents/Resources/Lima"
cp "$binary_dir/EnshroudedManager" "$app/Contents/MacOS/EnshroudedManager"
cp Runtime/guest.sh Runtime/stop-server.py Runtime/download.py "$app/Contents/Resources/Runtime/"
rm -f "$app/Contents/Resources/Runtime/stop-server.c"
cp -R .tools/lima/. "$app/Contents/Resources/Lima/"
# This app only boots Linux guests; omit Lima's unused macOS guest payload.
rm -f "$app/Contents/Resources/Lima/share/lima/lima-guestagent.Darwin-aarch64.gz"
cp Assets/game-rules.json Assets/Enshrouded.png Assets/Enshrouded.icns "$app/Contents/Resources/"
cp THIRD-PARTY.md LICENSE "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>EnshroudedManager</string>
<key>CFBundleIdentifier</key><string>com.glaciannex.enshrouded-manager</string>
<key>CFBundleName</key><string>Enshrouded Server Manager</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$build_version</string>
<key>ESMReleaseChannel</key><string>$channel</string>
<key>ESMBuildDate</key><string>$build_date</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>CFBundleIconFile</key><string>Enshrouded</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
# Sign nested Mach-O tools first, preserving Lima's virtualization entitlements.
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    python3 - "$app" "$SIGNING_IDENTITY" <<'PY_SIGN'
import pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1])
magic={b'\xcf\xfa\xed\xfe',b'\xfe\xed\xfa\xcf',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca'}
for p in root.rglob('*'):
    if not p.is_file() or p.is_symlink(): continue
    with p.open('rb') as f: header=f.read(4)
    if header in magic:
        subprocess.run(['codesign','--force','--options','runtime','--timestamp','--preserve-metadata=entitlements','--sign',sys.argv[2],str(p)],check=True)
PY_SIGN
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$app"
else
    codesign --force --sign - "$app/Contents/MacOS/EnshroudedManager"
    codesign --force --sign - "$app"
fi
codesign --verify --deep --strict "$app"
ditto -c -k --norsrc --keepParent "$app" "$PWD/dist/Enshrouded-Server-Manager-for-Mac.zip"
destination="$PWD/dist/Enshrouded Server Manager.app"
if [ -d "$destination" ]; then mv "$destination" "$staging/previous.app"; fi
mv "$app" "$destination"
printf 'Built %s\n' "$destination"
(cd dist && shasum -a 256 Enshrouded-Server-Manager-for-Mac.zip > SHA256SUMS.txt)

bash scripts/verify-archive.sh

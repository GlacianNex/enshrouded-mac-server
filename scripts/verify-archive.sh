#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
archive="$PWD/dist/Enshrouded-Server-Manager-for-Mac.zip"
# AppleDouble sidecars may be restored as ordinary, unsigned bundle files.
python3 - "$archive" <<'PY'
import pathlib, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    unwanted = [name for name in archive.namelist()
                if any(part.startswith('._') or part == '__MACOSX'
                       for part in pathlib.PurePosixPath(name).parts)]
    if unwanted:
        sys.exit('Release ZIP contains macOS metadata sidecars: ' + unwanted[0])
PY
staging=$(mktemp -d "${TMPDIR:-/tmp}/esm-archive-check.XXXXXX")
trap 'rm -rf "$staging"' EXIT
for extractor in ditto unzip; do
    destination="$staging/$extractor"
    mkdir -p "$destination"
    if [[ "$extractor" == ditto ]]; then
        ditto -x -k "$archive" "$destination"
    else
        unzip -q "$archive" -d "$destination"
    fi
    app="$destination/Enshrouded Server Manager.app"
    codesign --verify --deep --strict "$app"
    if [[ "${1:-}" == --notarized ]]; then
        xcrun stapler validate "$app"
        spctl --assess --type execute --verbose=2 "$app"
    fi
done
echo 'Release archive verified with ditto and unzip.'

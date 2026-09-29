#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .cache .tools
archive=.cache/lima.tar.gz
sha=bbdef91774885a0d05f7b048c4eb89ae2bcf3a0c252ae7ca7934e63df76d93c3
if ! test -f "$archive" || ! echo "$sha  $archive" | shasum -a 256 -c --status; then
  curl -fL --retry 3 https://github.com/lima-vm/lima/releases/download/v2.2.0/lima-2.2.0-Darwin-arm64.tar.gz -o "$archive.partial"
  echo "$sha  $archive.partial" | shasum -a 256 -c
  mv "$archive.partial" "$archive"
fi
mkdir -p .tools/lima
tar -xzf "$archive" -C .tools/lima

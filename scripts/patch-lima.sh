#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Build-only toolchain; users install no Go compiler or external tools.
case "$(uname -m)" in
  arm64) arch=arm64; go_sha=ff18369ffad05c57d5bed888b660b31385f3c913670a83ef557cdfd98ea9ae1b;;
  x86_64) arch=amd64; go_sha=bf5050a2152f4053837b886e8d9640c829dbacbc3370f913351eb0904cb706f5;;
  *) echo 'Unsupported build host' >&2; exit 1;;
esac
fetch() {
  if ! test -f "$2" || ! echo "$3  $2" | shasum -a 256 -c --status; then
    curl -fL --retry 3 "$1" -o "$2.partial"
    echo "$3  $2.partial" | shasum -a 256 -c
    mv "$2.partial" "$2"
  fi
}
mkdir -p .cache .tools/lima-build
patch_hash=$(shasum -a 256 scripts/lima-udp-idle.patch | cut -d' ' -f1)
recipe_hash=$(shasum -a 256 scripts/patch-lima.sh | cut -d' ' -f1)
artifact="$PWD/.tools/lima-build/limactl-$patch_hash-$recipe_hash"
if ! test -f "$artifact"; then
  fetch "https://go.dev/dl/go1.25.7.darwin-$arch.tar.gz" ".cache/go1.25.7-$arch.tar.gz" "$go_sha"
  fetch https://github.com/lima-vm/lima/archive/refs/tags/v2.2.0.tar.gz .cache/lima-source-v2.2.0.tar.gz cdba3804df7d8c00a2af674a3fe0b24c19673a0e846e5f75ac9badf227ce52f5
  stage=$(mktemp -d "$PWD/.tools/lima-build/source-XXXXXX")
  trap 'rm -rf "$stage"' EXIT
  tar -xzf ".cache/go1.25.7-$arch.tar.gz" -C "$stage"
  mkdir "$stage/lima"
  tar -xzf .cache/lima-source-v2.2.0.tar.gz -C "$stage/lima" --strip-components=1
  patch -d "$stage/lima" -p1 < scripts/lima-udp-idle.patch
  (
    cd "$stage/lima"
    export GOTOOLCHAIN=local CGO_ENABLED=1
    # A new build SDK must not silently raise the app's minimum macOS version.
    export MACOSX_DEPLOYMENT_TARGET=14.0
    export CGO_CFLAGS='-O2 -g -mmacosx-version-min=14.0'
    export CGO_LDFLAGS='-O2 -g -mmacosx-version-min=14.0'
    "$stage/go/bin/go" test -race ./pkg/portfwd
    GOOS=darwin GOARCH=arm64 "$stage/go/bin/go" build -trimpath \
      -ldflags='-s -w -X github.com/lima-vm/lima/v2/pkg/version.Version=v2.2.0-esm.1' \
      -o "$artifact.partial" ./cmd/limactl
  )
  mv "$artifact.partial" "$artifact"
fi
cp "$artifact" .tools/lima/bin/limactl
# The upstream executable has Apple virtualization entitlements. Preserve them
# when replacing it with the locally patched build, before final app signing.
codesign --force --sign - --entitlements scripts/lima.entitlements .tools/lima/bin/limactl

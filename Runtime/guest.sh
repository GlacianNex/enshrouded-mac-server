#!/usr/bin/env bash
set -euo pipefail
umask 077
ROOT=/opt/esm
DATA=/mnt/esm-data
RUNTIME_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export WINEPREFIX="$ROOT/prefix"
export WINEDEBUG=-all
export WINEDLLOVERRIDES="mscoree,mshtml="
export BOX64_NOBANNER=1
export BOX64_DYNAREC_STRONGMEM=1
export BOX64_LD_LIBRARY_PATH="$ROOT/x86-libs"
export PATH="$ROOT/wine/bin:/usr/local/bin:$PATH"

stage() {
  printf '[ESM_SETUP] {"stage":"%s","message":"%s"}\n' "$1" "$2"
}
fetch() {
  local cached="$3"
  if test -d /mnt/esm-downloads/components; then
    cached="/mnt/esm-downloads/components/$2"
  fi
  python3 "$RUNTIME_DIR/download.py" "$1" "$2" "$cached" "$4"
  if test "$cached" != "$3"; then cp --reflink=auto "$cached" "$3"; fi
}
prepare() {
  test ! -f "$ROOT/ready-v1" || return 0
  if test -d /mnt/esm-downloads/packages; then
    # Share downloaded packages, keeping each VM's installed system independent.
    sudo mkdir -p /etc/apt/apt.conf.d
    printf 'Dir::Cache::archives "/mnt/esm-downloads/packages";\nBinary::apt::APT::Keep-Downloaded-Packages "true";\n' | sudo tee /etc/apt/apt.conf.d/99-esm-cache >/dev/null
  fi
  stage packages 'Downloading and installing Ubuntu system packages…'
  sudo env DEBIAN_FRONTEND=noninteractive apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends build-essential cmake curl ca-certificates unzip xz-utils xvfb xauth python3 libx11-6 libxext6 libxinerama1 libxcomposite1 libxi6 libxkbregistry0 libxcursor1 libxfixes3 libxrandr2 libxrender1 libegl1 libfreetype6 libfontconfig1 libasound2t64 libpulse0 libgnutls30t64 libgl1 libvulkan1 libunwind8 libicu74
  sudo mkdir -p "$ROOT"
  sudo chown "$(id -u):$(id -g)" "$ROOT"
  mkdir -p "$ROOT/cache" "$DATA/logs" "$DATA/server" "$DATA/backups"
  stage box64 'Downloading processor compatibility tools…'
  fetch https://github.com/ptitSeb/box64/archive/refs/tags/v0.4.4.tar.gz 99c6de4f509e46ab1de15df740d0e0ea338a7790efa3f67510dfbb975cc24029 "$ROOT/cache/box64.tar.gz" box64
  tar -xzf "$ROOT/cache/box64.tar.gz" -C "$ROOT"
  stage box64 'Building processor compatibility tools; no download during this step…'
  cmake -S "$ROOT/box64-0.4.4" -B "$ROOT/box64-build" -DARM_DYNAREC=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo
  cmake --build "$ROOT/box64-build" -j4
  sudo cmake --install "$ROOT/box64-build"
  sudo systemctl restart systemd-binfmt
  stage wine 'Downloading Windows compatibility tools…'
  fetch https://github.com/Kron4ek/Wine-Builds/releases/download/11.18/wine-11.18-amd64-wow64.tar.xz f899879b8c37e0b20adca19d147cf77436f3f1a37bf16d08d27fa7137a52b9ba "$ROOT/cache/wine.tar.xz" wine
  stage wine 'Extracting Windows compatibility tools…'
  mkdir -p "$ROOT/wine"
  tar -xJf "$ROOT/cache/wine.tar.xz" -C "$ROOT/wine" --strip-components=1
  stage downloader 'Downloading the server download tool…'
  fetch https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_3.4.0/DepotDownloader-linux-arm64.zip d9fb612ccebc1db8eeea3b4045d2221ec70431381393ce908fb72f01d4f9c812 "$ROOT/cache/downloader.zip" downloader
  mkdir -p "$ROOT/downloader"
  unzip -qo "$ROOT/cache/downloader.zip" -d "$ROOT/downloader"
  chmod +x "$ROOT/downloader/DepotDownloader"
  # Box64's source includes the required minimal x86 support libraries.
  mkdir -p "$ROOT/x86-libs"
  cp -a "$ROOT/box64-0.4.4/x64lib/." "$ROOT/x86-libs/"
  box64 "$ROOT/wine/bin/wine" --version
  touch "$ROOT/ready-v1"
}
case "${1:-}" in
  install)
    if sudo systemctl is-active --quiet esm-server || { test ! -f "$DATA/server-stop-request" && test "$(sudo systemctl show esm-server --property=SubState --value 2>/dev/null || true)" = auto-restart; }; then echo 'Stop the server before installing.' >&2; exit 1; fi
    prepare
    if test -d "$DATA/server/savegame"; then
      tar -czf "$DATA/backups/before-install-$(date -u +%Y%m%dT%H%M%SZ).tar.gz" -C "$DATA/server" savegame enshrouded_server.json
    fi
    target="$DATA/server"
    if test -f "$DATA/server/enshrouded_server.exe"; then
      echo 'Staging the server update; the current installation is preserved…'
      target="$DATA/.server-update-$(date -u +%Y%m%dT%H%M%SZ)-$$"
      mkdir -p "$target"
      trap 'if test "$target" != "$DATA/server"; then rm -rf -- "$target"; fi' EXIT
      cp -a --reflink=auto "$DATA/server/." "$target/"
    fi
    stage server 'Connecting to Valve and downloading the latest public server…'
    "$ROOT/downloader/DepotDownloader" -app 2278520 -os windows -osarch 64 -dir "$target" -validate | tee "$DATA/logs/latest-install.log"
    test -f "$target/enshrouded_server.exe"
    stage steam 'Checking Steam support files; downloading only if needed…'
    if ! test -f "$target/steamclient64.dll"; then
      "$ROOT/downloader/DepotDownloader" -app 1007 -os windows -osarch 64 -dir "$ROOT/steam-redist" -validate
      for dll in steamclient64.dll tier0_s64.dll vstdlib_s64.dll; do
        src=$(find "$ROOT/steam-redist" -name "$dll" -print -quit)
        test -n "$src" && cp "$src" "$target/$dll"
      done
    fi
    test -f "$target/steamclient64.dll"
    if test "$target" != "$DATA/server"; then
      # Keep one previous complete installation for recovery. World backups are
      # separate and are never removed by this runtime-retention step.
      rm -rf -- "$DATA/previous-install"
      if test -f "$DATA/installed-manifest.txt"; then cp "$DATA/installed-manifest.txt" "$DATA/server/.esm-manifest.txt"; fi
      mv "$DATA/server" "$DATA/previous-install"
      if ! mv "$target" "$DATA/server"; then
        mv "$DATA/previous-install" "$DATA/server"
        exit 1
      fi
    fi
    game_manifest=$(sed -n 's/.*for depot 2278521 from app 2278520, manifest \([0-9]*\),.*/\1/p' "$DATA/logs/latest-install.log" | head -1)
    if test -n "$game_manifest" && test -f "$DATA/server/.DepotDownloader/2278521_$game_manifest.manifest"; then
      printf '%s\n' "$game_manifest" > "$DATA/installed-manifest.txt"
      printf '%s\n' "$game_manifest" > "$DATA/server/.esm-manifest.txt"
    fi
    echo 'Installation complete.'
    ;;
  run)
    # Serialize the launch boundary with stop's marker. A pending recovery must
    # never undo a deliberate stop, update, deletion or environment shutdown.
    exec 9>"$DATA/server-launch.lock"
    flock -x 9
    if test -f "$DATA/server-stop-request"; then exit 0; fi
    cd "$DATA/server"
    test -f enshrouded_server.exe
    export SteamAppId=2278520 SteamGameId=2278520
    printf '2278520\n' > steam_appid.txt
    xvfb-run -a box64 "$ROOT/wine/bin/wine" ./enshrouded_server.exe 9>&- &
    child=$!
    flock -u 9
    exec 9>&-
    result=0
    wait "$child" || result=$?
    if test -f "$DATA/server-stop-request"; then exit 0; fi
    echo "Server exited unexpectedly (code $result). Recovery retries in 30 seconds." >&2
    exit 1
    ;;
  start)
    test -f "$ROOT/ready-v1"
    if sudo systemctl is-active --quiet esm-server; then echo 'Server already running.'; exit 0; fi
    if test "$(sudo systemctl show esm-server --property=SubState --value 2>/dev/null || true)" = auto-restart; then
      if test -f "$DATA/server-stop-request"; then
        # The marker prevents any game launch while canceling this old retry.
        sudo systemctl stop esm-server
      else
        echo 'Server recovery is already pending.'; exit 0
      fi
    fi
    rm -f -- "$DATA/server-stop-request"
    if test -f "$DATA/logs/server.log"; then mv "$DATA/logs/server.log" "$DATA/logs/server-$(date -u +%Y%m%dT%H%M%SZ).log"; fi
    sudo systemd-run --unit=esm-server --collect --uid="$(id -u)" --gid="$(id -g)" \
      --property=KillMode=control-group --property=TimeoutStopSec=infinity \
      --property=Restart=on-failure --property=RestartSec=30 \
      --property=StartLimitIntervalSec=300 --property=StartLimitBurst=5 \
      --property="StandardOutput=append:$DATA/logs/server.log" \
      --property="StandardError=append:$DATA/logs/server.log" \
      /bin/bash "$RUNTIME_DIR/guest.sh" run
    for ((i=0;i<90;i++)); do
      if grep -q "'HostOnline' (up)" "$DATA/logs/server.log" 2>/dev/null; then echo 'Server reports online. Player connection still needs verification.'; exit 0; fi
      if ! sudo systemctl is-active --quiet esm-server; then tail -30 "$DATA/logs/server.log"; exit 1; fi
      sleep 1
    done
    echo 'Server is running but did not report online within 90 seconds. Check logs.' >&2
    exit 1
    ;;
  stop)
    exec 9>"$DATA/server-launch.lock"
    flock -x 9
    touch "$DATA/server-stop-request"
    flock -u 9
    exec 9>&-
    if ! sudo systemctl is-active --quiet esm-server; then echo 'Server is stopped.'; exit 0; fi
    python3 "$RUNTIME_DIR/stop-server.py"
    for ((i=0;i<120;i++)); do
      if ! sudo systemctl is-active --quiet esm-server; then echo 'Server stopped.'; exit 0; fi
      sleep 1
    done
    echo 'Clean stop did not complete. Server has NOT been force-killed.' >&2
    exit 1
    ;;
  status)
    if sudo systemctl is-active --quiet esm-server; then echo RUNNING;
    elif test ! -f "$DATA/server-stop-request" && test "$(sudo systemctl show esm-server --property=SubState --value 2>/dev/null || true)" = auto-restart; then echo RECOVERING;
    elif test -f "$DATA/server/enshrouded_server.exe"; then echo INSTALLED;
    else echo NOT_INSTALLED; fi
    ;;
  *) echo 'Expected install, start, stop, status or run' >&2; exit 2;;
esac

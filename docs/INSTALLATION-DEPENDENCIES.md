# Installation Dependencies

Audit date: October 1, 2026. Applies to the 0.1.17 candidate and its pinned runtime. This describes installing the downloaded app, not building the project from source.

## What the User Needs

- An Apple Silicon Mac, macOS 14 or later, and a writable Applications destination and user Library. The installer may need macOS authorization if the Applications destination is not writable by that user.
- Internet access for first setup and updates. Downloads come from Canonical's Ubuntu archive, Ubuntu package mirrors, GitHub release/CDN endpoints and Valve's Steam services. DNS, HTTPS and Ubuntu package-repository access must work. A proxy, captive portal or network policy can prevent setup even when the required software is available.
- At least 30 GB free storage for setup, extraction and updates, plus room for growing backups. This is not the download size. Each server uses four virtual CPU cores, 8 GiB guest RAM and a growing 40 GiB virtual disk. A Mac with at least 16 GB physical memory is recommended for one server; additional servers need additional resources.
- For internet players: an available UDP port per server, router forwarding/public reachability and firewall permission. No relay service is included. The host does not need a Steam account or Steam client; players need their own game.

The downloadable app does not require Xcode, Command Line Tools, Homebrew, MacPorts, Python, Go, CMake, a C/C++ compiler, .NET, Steam, Wine, CrossOver, Rosetta, Docker, QEMU or macFUSE to be installed separately on macOS. The game itself remains proprietary; the open-source manager downloads it from Valve.

## Supplied by macOS

The manager links Apple system frameworks and Swift runtime libraries supplied by macOS. The audited Mach-O load commands include Foundation, AppKit, SwiftUI, Charts, Combine, CryptoKit, IOKit and ServiceManagement. The bundled Lima launcher also uses Apple's Virtualization framework and system libraries. Neither executable links Homebrew, MacPorts or Xcode-private libraries.

The runtime command search path is `/usr/bin:/bin:/usr/sbin:/sbin`. Lima uses macOS OpenSSH (`ssh`, `ssh-keygen`; SCP for copy paths), system inspection utilities such as `sw_vers`, `sysctl`, `ioreg` and `system_profiler`, and the bundled guest agent. The Linux VZ disk path uses Lima's native QCOW2 reader/converter rather than `qemu-img`. Optional Lima drivers, container tooling and macOS-guest operations are not part of server setup.

Manager installation/update and ancillary features use built-in `codesign`, `spctl`, `ditto`, `unzip`, `launchctl` and `lsof`. These are macOS utilities, not an Xcode installation requirement. The host does not run the bundled Python scripts: they execute inside Ubuntu. Remote Login does not need to be enabled on the Mac; SSH connects to the private guest.

## Included in the App

- Native Apple Silicon manager executable, game-rules metadata and UI assets.
- Lima 2.2.0 with the ESM UDP forwarding fix, its ARM64 Linux guest agent, runtime resources and third-party notices.
- `guest.sh`, `download.py`, `build-progress.py` and `stop-server.py`, copied into each server's runtime directory for execution inside its VM.

The VM uses Apple's VZ driver, VirtioFS mounts and Lima networking. Containerd and Rosetta are explicitly disabled. No separately installed virtualization product or kernel extension is required.

## Downloaded and Installed Automatically

1. **Ubuntu 24.04 ARM64 cloud image**, pinned to the July 5, 2026 archive with SHA-256 verification. Ubuntu supplies Linux, systemd, cloud-init, OpenSSH, sudo, APT and base shell/file/process utilities. Lima bootstraps its guest agent and any required guest packages, including rsync and DNS-related iptables where applicable.
2. **Ubuntu packages** requested by `Runtime/guest.sh`: `build-essential`, `cmake`, `curl`, `ca-certificates`, `unzip`, `xz-utils`, `xvfb`, `xauth`, `python3`, `libx11-6`, `libxext6`, `libxinerama1`, `libxcomposite1`, `libxi6`, `libxkbregistry0`, `libxcursor1`, `libxfixes3`, `libxrandr2`, `libxrender1`, `libegl1`, `libfreetype6`, `libfontconfig1`, `libasound2t64`, `libpulse0`, `libgnutls30t64`, `libgl1`, `libvulkan1`, `libunwind8` and `libicu74`. APT resolves their transitive dependencies from signed Ubuntu repository metadata. Package versions and total download size vary with Ubuntu security updates. These compilers, headers, Python, graphics/font/audio libraries and virtual display tools live inside the VM; no macOS development libraries are used.
3. **Box64 0.4.4** source archive from its upstream GitHub repository, SHA-256 checked and compiled inside Ubuntu. Its included minimal x86-64 support libraries are copied to `/opt/esm/x86-libs`.
4. **Wine 11.18 AMD64 WOW64** from Kron4ek's GitHub release, SHA-256 checked and extracted inside Ubuntu. Box64 executes its x86-64 code. Wine's prefix stays in the VM; a virtual display is supplied by Xvfb. Wine Mono and Gecko are disabled for this server workflow.
5. **DepotDownloader 3.4.0 Linux ARM64** release archive, SHA-256 checked. This is the self-contained executable, not the framework-only archive; no separate .NET SDK/runtime install is requested from the user.
6. **Latest public Enshrouded Windows dedicated server**, Steam app 2278520, obtained anonymously through DepotDownloader with validation. Game files are not prebundled in the manager.
7. **Steam support DLLs**, app 1007, only if the downloaded server lacks `steamclient64.dll`. This fetch supplies `steamclient64.dll`, `tier0_s64.dll` and `vstdlib_s64.dll` as needed. It does not install the desktop Steam client.

Ubuntu, compatibility-component and game download progress appears during installation. Compilation and extraction run locally in the VM; lack of network traffic during those stages is expected. Exact transitive package inventories belong to each VM's dpkg database rather than a fixed download-size promise.

## Storage and Permissions

The signed manager and Lima stay in the app bundle. Each registered server has an independent home directory, normally `~/Library/ESM/<id>/` for new profiles, with its own VM disk under `lima/engine/`, runtime helpers under `runtime/`, and game installation/configuration/saves/backups under `data/`. The original legacy server can use a different configured home. Wine, Box64, compilers and Linux packages live in `/opt/esm` and system directories inside that server's VM disk.

Reusable host downloads live under `~/Library/Application Support/Enshrouded Manager/downloads/`; downloaded manager updates use the user Caches directory. Setup does not add files to the signed app bundle or install packages into `/opt/homebrew`, `/usr/local` or macOS system directories. Ubuntu's `sudo` acts inside the guest; it is not a request for the Mac's administrator password.

## Portability Defect and Release Protection

The pre-audit locally built Lima executable declared `LC_BUILD_VERSION minos 27.0`, although the app declared macOS 14.0. The CGO build had inherited the developer SDK's deployment default. The build now explicitly targets macOS 14.0, and the cached launcher key includes the build recipe so an old incompatible binary cannot silently be reused.

The gate also found that upstream's optional Krunkit executable requires macOS 26. That unused driver is now omitted from the app; the server uses Lima's built-in VZ driver exclusively.

`scripts/check-runtime-dependencies.py` now gates every build. It verifies required bundled files, Apple Silicon architecture, minimum OS metadata on every Mach-O slice, and system-only dynamic library dependencies. The app currently ships no private dylibs, so unresolved `@rpath` and developer-machine paths fail the gate. Its regressions reject the actual 27.0 deployment mistake, missing metadata, foreign platforms, weak external dependencies and incompatible universal slices. A newer SDK number is allowed when the deployment minimum remains supported.

This audit does not retroactively repair already downloaded releases. Use a candidate built with the corrected launcher. One Apple Silicon download targets macOS 14 and newer; a separate macOS-27-only download is unnecessary.

## Source-Build Requirements

Only contributors/release builders need an Apple Silicon development Mac with a Swift/Xcode toolchain, command-line build tools and Python 3. The build downloads a pinned Go toolchain and Lima source to rebuild the patched launcher. Public signing/notarization additionally needs the publisher's Developer ID credentials and Apple's release tools. None of those development credentials or build tools are prerequisites for users of the packaged app.

## Verification Limits

A fresh isolated Ubuntu VM successfully booted with an empty host home and a system-only PATH while a macOS process sandbox denied execution from Xcode, Command Line Tools, Homebrew and `/usr/local`, plus host `python3`, `git`, `clang` and `xcrun`. It had no shared component/package cache. The actual `prepare` function installed Ubuntu packages, downloaded and compiled Box64, downloaded Wine and DepotDownloader, and wrote its readiness marker. Wine reported version 11.18. DepotDownloader launched and reported its expected missing-app argument error; `ldd` resolved all of its direct ELF libraries. The exact guest package inventory was captured locally. The isolated VM was then shut down normally. This test used two virtual CPUs and 3 GiB RAM to avoid competing with production servers; it tested the dependency path, not game hosting, and did not download the full game or change existing servers.

Binary metadata and source inspection do not prove every older macOS release boots a server successfully. A physical Mac without developer tools and an actual macOS 14/15/26 install remain separate compatibility checks. Network availability, future Valve game changes and future Ubuntu package updates are external dependencies and cannot be guaranteed by packaging.

Upstream references: [Lima installation requirements](https://lima-vm.io/docs/installation/), [pinned Lima VZ implementation](https://github.com/lima-vm/lima/tree/v2.2.0/pkg/driver/vz), [Lima native image conversion](https://github.com/lima-vm/lima/tree/v2.2.0/pkg/imgutil/nativeimgutil), [DepotDownloader release](https://github.com/SteamRE/DepotDownloader/releases/tag/DepotDownloader_3.4.0).

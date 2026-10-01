# Third-Party Components

The manager source is MIT licensed. The Enshrouded icon in `Assets/Enshrouded.png` and `Assets/Enshrouded.icns` is game artwork, restored from the existing experimental app, and is not covered by the MIT license. Enshrouded artwork and trademarks belong to their respective owners. This is an unofficial community tool, not affiliated with Keen Games, Valve, or Apple.

## Bundled

- **Lima 2.2.0 with the ESM UDP idle-timeout patch** — Apache-2.0. [Source and notices](https://github.com/lima-vm/lima/tree/v2.2.0). Upstream licenses and documentation are retained in the app under `Contents/Resources/Lima/share/doc/lima`. The host executable is rebuilt with `scripts/lima-udp-idle.patch` to release idle UDP forwarding streams; its build and regression tests are in `scripts/patch-lima.sh`. The unused macOS guest payload and Krunkit driver are omitted; this app uses Linux guests with Apple's VZ driver.

## Downloaded During Setup

- **Ubuntu 24.04 ARM64 and packages** — individual package licenses. Copyright notices are retained under `/usr/share/doc` in the environment. [Ubuntu images](https://cloud-images.ubuntu.com/).
- **Box64 0.4.4** — MIT. [Source](https://github.com/ptitSeb/box64/tree/v0.4.4). Built during setup; its source archive remains in `/opt/esm/cache`.
- **Wine 11.18 WOW64** — Wine LGPL and component licenses. [Build provider](https://github.com/Kron4ek/Wine-Builds/releases/tag/11.18), [Wine source](https://gitlab.winehq.org/wine/wine).
- **DepotDownloader 3.4.0** — GPL-2.0. [Source](https://github.com/SteamRE/DepotDownloader/tree/DepotDownloader_3.4.0).
- **Enshrouded dedicated server and Steam runtime** — proprietary publisher software downloaded from Valve. They are not bundled or relicensed.

The release does not redistribute a prebuilt guest image or game binaries. macOS and Apple's virtualization framework provide the host platform. CrossOver, Docker Desktop, and Rosetta are not required.

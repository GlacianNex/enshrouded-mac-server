# 0.1 — Enshrouded Hosting from Your Mac

First public release. **Superseded by [0.1.1](RELEASE-NOTES-0.1.1.md), which fixes a download packaging error. Use the [latest release](https://github.com/GlacianNex/enshrouded-mac-server/releases/latest).**

## Highlights

- One app to install and manage Enshrouded dedicated servers on Apple Silicon.
- Automatic first-run setup and download of the current public game-server release.
- Multiple servers with separate worlds, settings, ports, and backups.
- Native menu-bar status, Start/Stop controls, and copyable connection details.
- World Rules in Server Settings: six groups, 37 rules, clear inputs, help popovers, and automatic Custom difficulty selection.
- Three-hour performance history with memory, server speed, and ping views.
- Login startup, scheduled restarts, daily backups, and optional automatic game-server updates.
- Named backups, recovery before restore, role permissions, saved bans, and searchable logs.
- Signed and notarized app installation and manager upgrades that save, stop, and resume running servers.

## Install

Download **Enshrouded-Server-Manager-for-Mac.zip**, unzip it, and open the app. Choose **Install & Open**, then complete setup. The ZIP contains only the app; **SHA256SUMS.txt** is available separately for verification.

Requires Apple Silicon, macOS 14+, internet for setup, and at least 30 GB free disk space. Each server environment allocates 8 GB RAM and four CPU cores. Forward UDP 15637 (or your chosen port) for internet players. No separate compatibility-tool installation is required.

## Updating from Experimental

Open this release and choose **Stop, Update & Relaunch**. Running servers save and stop, then restart after the update. This disconnects connected players. Existing worlds and settings are preserved.

## Known Limits

- Apple Silicon only; no Intel hosting build.
- First setup downloads the runtime and server; this is not an offline package.
- Router forwarding is manual. There is no relay service.
- Server speed uses the game's approximately one-minute reports; memory uses five-second averages.
- Automated game-server maintenance waits for confirmed empty servers. Manager app updates can restart occupied servers.
- Keep the manager open for monitoring and schedules. Backups do not have automatic retention pruning.
- Live kicks and bans use Enshrouded's Social tab. No mod catalog or in-game remote-command interface is included.
- Download manager updates from GitHub; automatic manager-release discovery is not included yet.

See [Setup and Recovery](SETUP.md) and [Verification](VERIFICATION.md) for details.

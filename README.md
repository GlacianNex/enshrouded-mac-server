# Enshrouded Server Manager for Mac

Host Enshrouded worlds for your friends from your Mac. This native macOS menu bar app downloads the dedicated server, creates or imports worlds, and manages multiple servers without Terminal setup.

**[Download for Mac](https://github.com/GlacianNex/enshrouded-mac-server/releases/latest)** · [What's New in 0.1.18](docs/RELEASE-NOTES-0.1.18.md) · [Setup and Recovery](docs/SETUP.md)

Requires **Apple Silicon and macOS 14 Sonoma or later**, internet access for setup, and **30 GB of free space**. Each server environment allocates 8 GB of RAM and four CPU cores; a Mac with at least 16 GB of RAM leaves room for macOS. The release is Developer ID signed and Apple-notarized.

No separate Xcode, Command Line Tools, Python, Steam client, Steam login, CrossOver, Wine, Docker, Homebrew, or Rosetta installation is needed. The manager automatically downloads its free compatibility tools and the official server during setup. Compilers and Linux libraries are installed inside the server's VM, not on macOS. The game server runs through a compatibility environment; it is not a native Mac port. See the [installation dependency audit](docs/INSTALLATION-DEPENDENCIES.md) for the full inventory and verification limits.

## What It Does

- **Set up servers automatically.** Download the current public Enshrouded dedicated server directly from Valve.
- **Create or import worlds.** Keep each server's world, settings, ports, and backups separate.
- **Adjust World Rules.** Edit 37 rules in six groups, with clear input boxes, help popovers, and automatic switching to Custom difficulty.
- **Watch performance.** View server speed, memory, uptime, player count, and connection ping history.
- **Schedule maintenance.** Configure login startup, scheduled restarts, and daily backups in Automation.
- **Keep servers current.** Check for official game-server updates or enable automatic updates.
- **Manage access.** Configure password-based roles and saved bans. Live kicks and bans use Enshrouded's Social tab.

## Get Started

1. Download **Enshrouded-Server-Manager-for-Mac.zip** from the [latest release](https://github.com/GlacianNex/enshrouded-mac-server/releases/latest) and unzip it into a fresh folder. Open the app and choose **Install & Open** to install it in Applications. macOS may show its normal first-open confirmation.
2. Choose **New Server…** in the menu bar. Enter a name, different player/admin passwords of at least eight characters, and an available UDP port. Optionally import a world file, folder, or ZIP.
3. Choose **Create & Set Up**. The app prepares the environment and downloads the latest public server. Setup shows download sizes when available, installation steps, build progress and logs. Leave the manager running; closing a window does not stop setup.
4. Forward **UDP 15637** on your router to this Mac. Allow incoming traffic if your firewall asks. Each additional server needs its own forwarded UDP port.
5. Start the server, then share its name or public address/port and player password. Connection details and password copying are in the server's menu-bar submenu.

Router forwarding is required for internet hosting. The app does not configure your router or provide a relay. A ready server or displayed public address does not prove internet reachability. See [network setup](docs/SETUP.md#internet-hosting).

## Server Management

Open a server's submenu and choose **Server Management**:

- **Performance:** Server Speed and Server Memory graphs, plus a Ping tab. History covers three hours while the manager is open. Memory uses five-second averages; speed uses the game's reported one-minute averages, which can arrive several minutes apart. Missing data is not shown as zero.
- **Automation:** start at login, schedule restarts by day/time, and enable daily backups. Changes save automatically. Keep the manager open for schedules to run.
- **Moderation:** inspect reported connections and edit roles or saved bans while stopped.
- **Backups:** create named backups, open the backup folder, and restore a selected backup while stopped. Restoration first creates a recovery backup.

**Server Settings** contains server name, player limit, World Rules, passwords, chat, and world import. Click any section title row to expand it. Editing a rule automatically selects Custom. Stop the server before editing settings. These apply on the next start; live time, weather and spawn commands are not supported.

The manager prevents idle sleep while hosting by default. Quitting it leaves running servers active but stops monitoring, schedules, and automatic updates. Closing its window keeps it in the menu bar. Login startup occurs after sign-in; shutdown, logout, and laptop lid closure can interrupt hosting.

## Restarts, Backups, and Updates

**Scheduled restarts** can wait for an empty server or skip an occupied/unavailable one, as configured in Automation. **Scheduled backups** wait until a fresh query confirms the server is empty. Unknown player counts defer backups. Backups save and stop a running server, copy its world and settings, and restart it. Stopped servers stay stopped. Missed backups run when the manager is available. Backups are retained until removed; a failed attempt is reported and retried at the next daily run.

**Official Enshrouded server updates** are checked every ten minutes while the server environment is on. Manual checks can temporarily start a stopped environment. Updates stage and validate files before replacing them, preserve settings and worlds, and retain the previous installation. Running servers must be confirmed empty. Automatic server updates are optional.

**Manager app updates** are separate. Download a release, open the app, and choose **Stop, Update & Relaunch**. This saves and stops all running servers, installs the manager, and restarts those servers afterward—even if players are connected. Stopped servers stay stopped. The top version row checks at launch and every five minutes, shows Up to Date after a successful check, and becomes clickable when a verified stable manager update is available. Installation requires confirmation. Update progress and logs explain each stage; the manager returns to the menu bar afterward. The separate game-build row offers game-server updates when available.

## Data and Runtime

Worlds and settings live outside the app, so manager upgrades preserve them:

```text
~/Library/EnshroudedServer/                         # legacy/default server
~/Library/ESM/<profile>/                           # new server profiles
~/Library/Application Support/Enshrouded Manager/  # profile registry
```

Inside a server's folder, `data/server/savegame` holds the world and `data/backups/worlds` holds manager backups. Configuration and backups include passwords; keep them private.

The app bundles Lima and provisions Ubuntu ARM64, Box64, Wine, and DepotDownloader. The official Enshrouded server and Steam runtime are downloaded from Valve, not bundled. See [third-party components](THIRD-PARTY.md).

The manager and compatibility tools are free and open source. Enshrouded's server remains proprietary. Testing includes real hosting on Apple Silicon, isolated setup/update checks, and unit tests; a separate fresh Mac and sustained multiplayer load testing remain pending. See [verification](docs/VERIFICATION.md).

**Delete Server…** removes one server’s installation and VM. Its confirmation optionally deletes game data and backups; otherwise those are archived. **Clear Download Cache…** removes reusable downloads after confirmation without removing installed servers. See [storage and cleanup](docs/SETUP.md#storage-and-cleanup).

## Build and Contribute

Use an Apple Silicon Mac with macOS 14+ and a current Xcode/Swift toolchain:

```sh
swift test
bash scripts/build.sh
```

Builds go to `dist/`. Source builds are ad-hoc signed development artifacts unless you configure Developer ID signing and notarization. See [Contributing](CONTRIBUTING.md) and [Releasing](docs/RELEASING.md).

For local experimental builds, use `bash scripts/build-experimental.sh`. These display **Experimental** instead of a public version. Stable downloads do not automatically replace experimental installations; see [Setup and Recovery](docs/SETUP.md#experimental-builds).

## License and Attribution

The manager source is MIT licensed. Third-party components retain their licenses. The Enshrouded icon identifies the supported game and is excluded from the MIT license; game artwork and trademarks belong to their respective owners. No game binaries are included in the release.

This is an unofficial community tool, not affiliated with Keen Games, Valve, or Apple.

The [Valheim behavior audit](docs/VALHEIM-PARITY.md) and [verification record](docs/VERIFICATION.md) distinguish tested workflows from remaining coverage limits.

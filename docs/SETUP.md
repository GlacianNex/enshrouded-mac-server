# Setup and Recovery

## First Installation

Download the app from [Latest Release](https://github.com/GlacianNex/enshrouded-mac-server/releases/latest), unzip it into a fresh folder, and open it. Choose **Install & Open**, then choose **New Server…** from the menu bar. Enter a name and different player/admin passwords of at least eight characters. Choose a world file, folder or ZIP to import, or create a new world. Choose **Create & Set Up** to begin. An existing pending profile uses **Set Up Server** in Server Management.

Setup automatically downloads Ubuntu, the compatibility tools, and the latest public dedicated server. There is no separate Xcode, Command Line Tools, Python, Wine, Steam, Homebrew or Rosetta installation. Build tools and Linux libraries are installed inside the private VM. First setup requires an Apple Silicon Mac running macOS 14 or later, internet and at least 30 GB free disk space; each server allocates 8 GB RAM, four CPU cores, and a 40 GB virtual disk. Allow more disk space as backups accumulate. See [Installation Dependencies](INSTALLATION-DEPENDENCIES.md) for the complete inventory and verification limits.

Leave **Start the server when setup finishes** enabled to start immediately. Setup progress appears in Server Management, with detailed output in the log viewer's Installation tab while setup is pending.

## Internet Hosting

Forward the configured **UDP port** (15637 by default) to the Mac in your router. Reserve the Mac's local address so the forwarding rule remains valid. Give each additional server a different port. Allow incoming traffic through any firewall you use.

Players can search for the server name in Enshrouded. The server submenu also provides its public address/port and password-copy actions. Steam server favorites can use that address and port. A successful internal readiness check does not test your router from the internet.

If players cannot connect, check the port, firewall, and forwarding destination. If your ISP uses carrier-grade NAT, ordinary router forwarding may not provide an inbound connection; ask your ISP about a public address. The app does not provide relay hosting.

## World Settings and Import

Stop the server, then open **Server Settings**. Change player slots, chat, passwords, or individual World Rules. Editing any rule selects Custom difficulty. Changes apply on the next start.

To import, choose an unambiguous world folder or ZIP, or the world's main file: an eight-character hexadecimal filename without a suffix. The manager copies matching rolling-save files and creates a backup before replacing an existing world. Stop the source game/server first. Imports do not move the original files or import player characters.

## Backups and Restore

Use **Backups** for a named manual backup while stopped. Use **Automation → Scheduled Backups** to enable a daily local time. Scheduled backups wait for an empty server, save and stop it, copy its world and settings, then restart it. Stopped servers stay stopped.

Keep the manager open. One overdue backup runs when available; missed days are not replayed individually. Failures appear in Manager Activity and are tried again at the next scheduled time. Backups remain until removed and consume disk space.

To restore, stop the server, select a backup, and choose **Restore Selected**. This replaces the world and settings, including passwords. The manager backs up the current state first and leaves the server stopped.

## Manager Updates

Use the menu’s top update-available version row, or open a newly downloaded release and choose **Stop, Update & Relaunch**. The manager saves and stops running servers, replaces the app in Applications, and restarts those servers. Connected players will be disconnected during this operation. Stopped servers stay stopped.

Manager checks run at launch and every five minutes. The update window shows stages, elapsed time and **Open Update Log**. After updating, the manager stays in the menu bar and restarts only previously running servers. Cancellation before replacement leaves the installation unchanged. Let conflicting maintenance finish first. The app never force-kills the running manager to replace it.

Successful updates clean their own replacement transaction. Failed relaunches retain the previous app in an `.enshrouded-update-*` folder beside the installed app. If relaunch fails, open the manager from Applications; saved resume markers identify servers to restart. Worlds remain outside the app bundle.

## Game-Server Updates

Use **Check for Server Updates** in the menu, then click the game-build row when it shows **Update Available**. A check keeps the menu open and displays its stage. Checks run every ten minutes while the environment is on; a manual check may start a stopped environment. Manual updates require all running servers to be confirmed empty before proceeding. Optional automatic updates wait for each server to be confirmed empty. Downloads are staged and validated before replacement. An installation failure leaves the server stopped; inspect Manager Activity before retrying.

One previous server installation is retained at `data/previous-install`. It may contain an older world snapshot. Do not copy it over current saves casually; create a current backup before any manual recovery.

## Logs and Data

**Open Log** uses a movable, resizable viewer with server logs, manager activity, filtering, wrapping and line numbers. While setup is pending, running or failed, an Installation tab shows setup output; it disappears after successful setup. **Logs Folder** and **Server Folder** open the relevant files. Do not publish logs or configuration without checking for passwords, public addresses, and player identifiers.

Use **Stop Server** before shutting down the Mac. Closing the management window leaves the manager running. Quitting the manager leaves running game servers active, but monitoring and automation stop. Login startup only occurs after signing in.

## App Reported as Damaged

Version 0.1.0 included hidden metadata files that could invalidate the app signature after extraction. Discard that download and get the [latest release](https://github.com/GlacianNex/enshrouded-mac-server/releases/latest). Extract it into a fresh folder before opening. Existing server data is unaffected.

## Setup Progress

Setup lists Ubuntu, system packages, Box64, Wine, DepotDownloader, the official server, and optional Steam support libraries before installation. The 30 GB requirement is free disk space for extracted files, the private VM, and updates—not a 30 GB download. The VM has a 40 GiB virtual disk that grows as used; its capacity is not a download size.

Setup shows current and upcoming steps, elapsed time, and reported download sizes. Ubuntu-image and compatibility-component downloads report live bytes and totals when available. Valve reports file progress and final compressed download bytes; Ubuntu reports package-batch download sizes. Compilation reports actual build-step percentages. Configuration and quiet build stages show elapsed time and activity heartbeats; extraction and startup show stages without invented percentages.

The destination is shown with an Open Folder button. New profiles use `~/Library/ESM/<profile>/`; a legacy/default server may use `~/Library/EnshroudedServer/`. Wine, Box64, system packages, and DepotDownloader live inside that server's VM. The app contains the manager and bundled Lima launcher tools. Downloads are not added to the signed app bundle.

## Storage and Cleanup

The global menu's **Clear Download Cache…** confirms removal of shared downloads, older per-server download caches and downloaded manager updates, while keeping existing servers and their VM installations. Create a new server afterward to test a fresh installation. **Delete Server…** stops one server and removes its entire installation, including its VM. The confirmation offers **Also delete game data and backups**, unchecked by default. When unchecked, saved data is archived under `~/Library/Application Support/Enshrouded Manager/deleted-server-data/`; otherwise it is deleted with the installation. Other servers and shared downloads are kept. There is no global Uninstall Server Files command.

## Experimental Builds

Experimental builds are separate from stable manager releases and game-server versions. A stable installer refuses to silently replace an experimental app. To switch deliberately, quit the manager when idle and replace only the manager app in Applications with the signed stable app using Finder. Keep server folders and saved data.

## Live World Controls

World Rules, including weather frequency and day/night duration, apply after restarting the server. The manager does not provide live set-time, force-weather, spawn or remote-console commands. In-game moderation remains in Enshrouded’s Social tab.

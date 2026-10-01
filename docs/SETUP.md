# Setup and Recovery

## First Installation

Download the app from [Latest Release](https://github.com/GlacianNex/enshrouded-mac-server/releases/latest), unzip it into a fresh folder, and open it. Choose **Install & Open**, then **Set Up Server**. Enter a name and different player/admin passwords of at least eight characters. Choose a world to import or create a new one.

Setup automatically downloads Ubuntu, the compatibility tools, and the latest public dedicated server. There is no separate Wine, Steam, or Homebrew installation. First setup requires internet and at least 30 GB free disk space; each server allocates 8 GB RAM, four CPU cores, and a 40 GB virtual disk. Allow more disk space as backups accumulate.

Leave **Start the server when setup finishes** enabled to start immediately. Setup progress appears in Manager Activity.

## Internet Hosting

Forward the configured **UDP port** (15637 by default) to the Mac in your router. Reserve the Mac's local address so the forwarding rule remains valid. Give each additional server a different port. Allow incoming traffic through any firewall you use.

Players can search for the server name in Enshrouded. The server submenu also provides its public address/port and password-copy actions. Steam server favorites can use that address and port. A successful internal readiness check does not test your router from the internet.

If players cannot connect, check the port, firewall, and forwarding destination. If your ISP uses carrier-grade NAT, ordinary router forwarding may not provide an inbound connection; ask your ISP about a public address. The app does not provide relay hosting.

## World Settings and Import

Stop the server, then open **Server Settings**. Change player slots, chat, passwords, or individual World Rules. Editing any rule selects Custom difficulty. Changes apply on the next start.

To import, choose the world's main file: an eight-character hexadecimal filename without a suffix. The manager copies matching rolling-save files and creates a backup before replacing an existing world. Stop the source game/server first. Imports do not move the original files or import player characters.

## Backups and Restore

Use **Backups** for a named manual backup while stopped. Use **Automation → Scheduled Backups** to enable a daily local time. Scheduled backups wait for an empty server, save and stop it, copy its world and settings, then restart it. Stopped servers stay stopped.

Keep the manager open. One overdue backup runs when available; missed days are not replayed individually. Failures appear in Manager Activity and are tried again at the next scheduled time. Backups remain until removed and consume disk space.

To restore, stop the server, select a backup, and choose **Restore Selected**. This replaces the world and settings, including passwords. The manager backs up the current state first and leaves the server stopped.

## Manager Updates

In 0.1.2, use the menu’s update-available version row, or open a newly downloaded release and choose **Stop, Update & Relaunch**. The manager saves and stops running servers, replaces the app in Applications, and restarts those servers. Connected players will be disconnected during this operation. Stopped servers stay stopped.

Cancellation leaves the installation unchanged. If server maintenance is already running, let it finish. If an older manager will not quit, close its Settings/Logs window and try again. The app never force-kills the running manager to replace it.

The previous app is retained in an `.enshrouded-update-*` folder beside the installed app. If relaunch fails, open the manager from Applications; saved resume markers identify servers to restart. Worlds remain outside the app bundle.

## Game-Server Updates

Use **Check for Server Updates** in the menu, then update when offered. These updates wait for confirmed empty servers. Automatic updates are optional. Downloads are staged and validated before replacement. An installation failure leaves the server stopped; inspect Manager Activity before retrying.

One previous server installation is retained at `data/previous-install`. It may contain an older world snapshot. Do not copy it over current saves casually; create a current backup before any manual recovery.

## Logs and Data

**Open Log** separates server logs and manager activity, with a text filter. **Logs Folder** and **Server Folder** open the relevant files. Do not publish logs or configuration without checking for passwords, public addresses, and player identifiers.

Use **Stop Server** before shutting down the Mac. Closing the management window leaves the manager running. Quitting the manager leaves running game servers active, but monitoring and automation stop. Login startup only occurs after signing in.

## App Reported as Damaged

Version 0.1.0 included hidden metadata files that could invalidate the app signature after extraction. Discard that download and get the [latest release](https://github.com/GlacianNex/enshrouded-mac-server/releases/latest). Extract it into a fresh folder before opening. Existing server data is unaffected.

## Setup Progress and Uninstalling (0.1.3 Candidate)

Setup lists Ubuntu, system packages, Box64, Wine, DepotDownloader, the official server, and optional Steam support libraries before installation. The 30 GB requirement is free disk space for extracted files, the private VM, and updates—not a 30 GB download. The VM has a 40 GiB virtual disk that grows as used; its capacity is not a download size.

Setup shows current and upcoming steps, elapsed time, and reported download sizes. Ubuntu-image and compatibility-component downloads report live bytes and totals when available. Valve reports file progress and final compressed download bytes; Ubuntu reports package-batch download sizes. Building, extraction, and startup use an indeterminate indicator rather than an invented percentage.

The destination is shown with an Open Folder button. The default is `~/Library/EnshroudedServer/`; extra profiles use `~/Library/ESM/<profile>/`. Wine, Box64, system packages, and DepotDownloader live inside that server's VM. The app contains the manager and bundled Lima launcher tools. Downloads are not added to the signed app bundle.

The global menu's **Clear Download Cache…** confirms removal of shared downloads, older per-server download caches and downloaded manager updates, while keeping existing servers and their VM installations. Create a new server afterward to test a fresh installation. **Delete Server…** stops one server and removes its entire installation, including its VM. The confirmation offers **Also delete game data and backups**, unchecked by default. When unchecked, saved data is archived under `~/Library/Application Support/Enshrouded Manager/deleted-server-data/`; otherwise it is deleted with the installation. Other servers and shared downloads are kept. There is no global Uninstall Server Files command.

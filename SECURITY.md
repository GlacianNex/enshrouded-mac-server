# Security and Data Safety

Report exploitable vulnerabilities privately through GitHub's private vulnerability reporting. Do not post passwords, player identifiers, world saves, or unredacted logs in public issues.

Configuration files and backups include server passwords. The app uses private data directories and writes configuration with owner-only permissions. It is not a security boundary against software running as the same macOS user.

The runtime mounts only its scripts and server data into a private virtual machine. Enshrouded's UDP port is exposed on the Mac for hosting. Router forwarding is controlled by the user.

World imports copy source data. Restore creates a recovery backup. Server shutdown requests a clean save/stop and does not force-kill a timed-out server. Manager replacement checks package signatures and uses an operation lock; it aborts if the previous manager or server cannot stop safely.

Pinned runtime archives are checksum-verified. Ubuntu packages and game files are downloaded from their publishers. Game files, credentials, and signing keys are not part of the repository or release ZIP.

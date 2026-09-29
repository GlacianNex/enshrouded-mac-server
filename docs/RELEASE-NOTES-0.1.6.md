# 0.1.6 — Clear Update Progress

Candidate · Includes the earlier candidate fixes

Manager updates now show the current stage, an animated progress bar, elapsed time, and an Open Update Log button. This appears for both downloaded installers and in-app updates. Each stage explains what is happening, including saving worlds, stopping the hosting environment, replacing the app, and reopening the manager. Long waits show a stage-specific explanation instead of silently displaying the same generic message.

An exhausted older networking process could hang while the updater waited for the environment to shut down. The updater now saves and stops the game, requests normal operating-system shutdown inside the guest, and then waits for the host environment to finish. The final wait has a 60-second timeout with a clear error. It does not force-kill the game or VM.

Verified the recovery on the affected Mac: the game had already saved and exited; normal guest shutdown unblocked the installer, the manager reopened, and the server answered queries through the Mac’s hosting port. Regression coverage checks shutdown ordering, absence of forced shutdown, timeout wording, elapsed time, and long-wait stage explanations. The candidate is separately signed and notarized for manual installation.

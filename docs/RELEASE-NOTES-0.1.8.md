# 0.1.8 — Clear Quit Protection

Candidate · Includes the earlier candidate fixes

The old “Server maintenance is still running” warning used a blocking modal dialog and did not track completion. The replacement names the server and active operation, updates when it changes, and automatically closes when work ends. It does not block asynchronous operation completion or force-stop the server. Repeated quit requests reuse the same notice; successful manager-update relaunches can exit normally.

Regression tests cover nonmodal presentation, the displayed operation, repeated quit requests, automatic dismissal after asynchronous completion, and the update-relaunch bypass. All 121 tests pass. The app is signed and notarized for manual installation.

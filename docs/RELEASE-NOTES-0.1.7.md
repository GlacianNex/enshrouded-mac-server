# 0.1.7 — Logs, Menus, and Server Creation

Candidate · Includes the earlier candidate fixes

Server Logs opens in its own movable, resizable window. Reopening logs brings the same server’s window forward. Closing it stops its polling. The line-number gutter is confined to the log text pane.

Checking for Server Updates keeps the menu open and shows the current stage, elapsed seconds, and result. Valve checks now have a 40-second guest timeout and a 45-second host timeout. Starting or closing a stopped environment has separate bounded waits. A live check on the affected Mac completed in 2.8 seconds without stopping the game.

Menu rows refresh in place as operations finish. New Server, automation options, management, and other unrelated actions remain available while a server saves and stops. Conflicting operations remain disabled until the save finishes.

The manager reuses one Server Management window. New Server has larger labeled fields, keyboard focus, direct port entry, and immediate validation.

Speed reports contain minute averages, but the actual game logs sometimes omit reports for several minutes. The graph now shows each measured interval and the age of the last report instead of implying a steady reporting cadence. This does not create new simulation measurements when the game provides none.

Validated with isolated UI checks and 119 core tests. No production server was stopped for these tests. The app is separately signed and notarized for manual installation.

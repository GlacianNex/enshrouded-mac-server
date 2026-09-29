"""Deliver Ctrl+C through Wine's Unix handler to our one owned server only."""
import os
import pathlib
import signal
import subprocess

group = subprocess.check_output(
    ["systemctl", "show", "esm-server", "--property=ControlGroup", "--value"], text=True
).strip()
if not group.startswith("/system.slice/esm-server.service"):
    raise SystemExit("Cannot verify server service ownership; refusing to signal.")
targets = []
for item in pathlib.Path("/sys/fs/cgroup", group.lstrip("/")).joinpath("cgroup.procs").read_text().split():
    pid = int(item)
    try:
        # Acquire a stable process handle before examining its identity.
        handle = os.pidfd_open(pid)
        proc = pathlib.Path("/proc", item)
        args = proc.joinpath("cmdline").read_bytes().split(b"\0")
        if proc.stat().st_uid == os.getuid() and args[0] == b"enshrouded_server.exe":
            targets.append(handle)
        else:
            os.close(handle)
    except ProcessLookupError:
        continue
if len(targets) != 1:
    for handle in targets:
        os.close(handle)
    raise SystemExit("Cannot identify exactly one owned Enshrouded process; refusing to signal.")
try:
    signal.pidfd_send_signal(targets[0], signal.SIGINT)
finally:
    os.close(targets[0])
print("Requested a clean server shutdown.")

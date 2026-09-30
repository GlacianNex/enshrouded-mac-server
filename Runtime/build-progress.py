#!/usr/bin/env python3
"""Stream a local build unchanged and report liveness without fake percentages."""
import codecs
import json
import os
import pathlib
import re
import selectors
import signal
import subprocess
import sys
import time

MESSAGES = {
    'configure': 'Configuring processor compatibility tools…',
    'build': 'Compiling processor compatibility tools…',
    'install': 'Installing processor compatibility tools…',
}


def cpu_snapshot(root_pid, proc=pathlib.Path('/proc')):
    """CPU ticks for the command and descendants; unavailable outside Linux."""
    if not proc.is_dir():
        return None
    processes = {}
    try:
        entries = list(proc.iterdir())
    except OSError:
        return None
    for entry in entries:
        if not entry.name.isdigit():
            continue
        try:
            fields = (entry / 'stat').read_text().rsplit(')', 1)[1].split()
            processes[int(entry.name)] = (int(fields[1]), int(fields[11]) + int(fields[12]))
        except (OSError, ValueError, IndexError):
            continue
    descendants = {root_pid}
    while True:
        added = {pid for pid, (parent, _) in processes.items() if parent in descendants} - descendants
        if not added:
            break
        descendants.update(added)
    return {pid: processes[pid][1] for pid in descendants if pid in processes}


def run(phase, command, interval=5, emit=print):
    started = last_output = time.monotonic()
    percent = None
    pending = ''
    decoder = codecs.getincrementaldecoder('utf-8')(errors='replace')
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
    previous_cpu = cpu_snapshot(process.pid)
    previous_handler = signal.getsignal(signal.SIGTERM)

    def terminate(signum, frame):
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, terminate)

    def report(running, cpu_active=None):
        now = time.monotonic()
        event = dict(stage='box64', phase=phase, message=MESSAGES[phase],
                     elapsedSeconds=int(now - started), outputAgeSeconds=int(now - last_output),
                     running=running)
        if percent is not None:
            event['percent'] = percent
        if cpu_active is not None:
            event['cpuActive'] = cpu_active
        emit('[ESM_SETUP] ' + json.dumps(event), flush=True)

    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    next_report = started + interval
    try:
        report(True)
        while selector.get_map():
            for key, _ in selector.select(max(0, next_report - time.monotonic())):
                data = os.read(key.fileobj.fileno(), 65536)
                if not data:
                    selector.unregister(key.fileobj)
                    continue
                last_output = time.monotonic()
                chunk = decoder.decode(data)
                emit(chunk, end='', flush=True)
                pending += chunk.replace('\r', '\n')
                while '\n' in pending:
                    line, pending = pending.split('\n', 1)
                    match = re.match(r'^\s*\[\s*(\d{1,3})%\]', line)
                    if phase == 'build' and match and int(match[1]) <= 100:
                        percent = max(percent or 0, int(match[1]))
                        report(True)
                pending = pending[-16384:]
            if time.monotonic() >= next_report:
                current_cpu = cpu_snapshot(process.pid)
                active = None if current_cpu is None or previous_cpu is None else any(
                    ticks > previous_cpu.get(pid, 0) for pid, ticks in current_cpu.items())
                report(process.poll() is None, active)
                previous_cpu = current_cpu
                next_report = time.monotonic() + interval
        result = process.wait()
        report(False)
        return result if result >= 0 else 128 - result
    finally:
        selector.close()
        process.stdout.close()
        signal.signal(signal.SIGTERM, previous_handler)
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()


if __name__ == '__main__':
    if len(sys.argv) < 3 or sys.argv[1] not in MESSAGES:
        sys.exit('Usage: build-progress.py configure|build|install command [arguments...]')
    sys.exit(run(sys.argv[1], sys.argv[2:]))

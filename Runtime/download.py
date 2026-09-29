#!/usr/bin/env python3
"""Verified component download with structured byte progress; runs inside the VM."""
import hashlib
import json
import os
import pathlib
import sys
import time
import urllib.request


def report(stage, message, received=None, total=None):
    print('[ESM_SETUP] ' + json.dumps(dict(stage=stage, message=message, received=received, total=total)), flush=True)


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def fetch(url, checksum, target, stage):
    target = pathlib.Path(target)
    if target.is_file() and digest(target) == checksum:
        report(stage, 'Using the verified download already in this environment.')
        return
    temporary = target.with_name(target.name + '.partial')
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=60) as response, temporary.open('wb') as output:
                total = int(response.headers.get('Content-Length', '0')) or None
                received = 0
                last = 0
                report(stage, 'Downloading component…', 0, total)
                while True:
                    block = response.read(256 * 1024)
                    if not block:
                        break
                    output.write(block)
                    received += len(block)
                    if time.monotonic() - last >= 0.5:
                        report(stage, 'Downloading component…', received, total)
                        last = time.monotonic()
                if total is not None and received != total:
                    raise RuntimeError('Incomplete component download')
            report(stage, 'Checking downloaded files…', received, total)
            if digest(temporary) != checksum:
                raise RuntimeError('Component download failed its integrity check')
            os.replace(temporary, target)
            return
        except Exception:
            temporary.unlink(missing_ok=True)
            if attempt == 2:
                raise
            report(stage, 'Download interrupted; retrying…', 0)
            time.sleep(attempt + 1)


if __name__ == '__main__':
    fetch(*sys.argv[1:])

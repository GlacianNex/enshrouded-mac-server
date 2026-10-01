#!/usr/bin/env python3
"""Build-time gate: shipped Mac binaries must run without developer libraries."""
import pathlib
import plistlib
import re
import subprocess
import sys

MACH_MAGICS = {bytes.fromhex(h) for h in (
    'cffaedfe', 'feedfacf', 'cefaedfe', 'feedface',
    'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')}


def version(value):
    parts = tuple(int(p) for p in value.split('.'))
    return (parts + (0, 0, 0))[:3]


def validate_load_commands(text, minimum):
    """Fail closed if minimum-version metadata is absent or too new."""
    blocks = re.split(r'Load command \d+', text)
    versions = []
    dependencies = []
    for block in blocks:
        if re.search(r'cmd LC_BUILD_VERSION\b', block):
            if not re.search(r'platform (?:1|macos)\b', block):
                raise ValueError('contains a non-macOS binary')
            match = re.search(r'\bminos ([0-9.]+)', block)
            if match:
                versions.append(match[1])
        elif 'cmd LC_VERSION_MIN_MACOSX' in block:
            match = re.search(r'\bversion ([0-9.]+)', block)
            if match:
                versions.append(match[1])
        if re.search(r'cmd LC_(?:LOAD_DYLIB|LOAD_WEAK_DYLIB|REEXPORT_DYLIB|LOAD_UPWARD_DYLIB)\b', block):
            match = re.search(r'\bname (.+) \(offset \d+\)', block)
            if not match:
                raise ValueError('unreadable library dependency')
            dependencies.append(match[1])
    if not versions:
        raise ValueError('missing minimum macOS version')
    if any(version(v) > version(minimum) for v in versions):
        raise ValueError(f'requires macOS {max(versions, key=version)}; app promises {minimum}')
    # This app currently ships no private dylibs. Reject unresolved @rpath and
    # developer-machine paths, including weak dependencies, rather than trusting
    # that a user's Homebrew/Xcode installation will supply them.
    for dependency in dependencies:
        if not dependency.startswith(('/System/Library/', '/usr/lib/')):
            raise ValueError(f'non-system library dependency: {dependency}')
    return versions, dependencies


def check(app):
    app = pathlib.Path(app)
    with (app / 'Contents/Info.plist').open('rb') as f:
        minimum = plistlib.load(f)['LSMinimumSystemVersion']
    required = [
        'MacOS/EnshroudedManager', 'Resources/Lima/bin/limactl',
        'Resources/Lima/share/lima/lima-guestagent.Linux-aarch64.gz',
        'Resources/Runtime/guest.sh', 'Resources/Runtime/download.py',
        'Resources/Runtime/build-progress.py', 'Resources/Runtime/stop-server.py',
        'Resources/game-rules.json',
    ]
    for relative in required:
        if not (app / 'Contents' / relative).is_file():
            raise ValueError(f'missing bundled runtime file: {relative}')
    count = 0
    for path in sorted(app.rglob('*')):
        if not path.is_file() or path.is_symlink():
            continue
        with path.open('rb') as f:
            if f.read(4) not in MACH_MAGICS:
                continue
        archs = subprocess.check_output(['/usr/bin/lipo', '-archs', str(path)], text=True).split()
        if 'arm64' not in archs:
            raise ValueError(f'{path.relative_to(app)}: missing Apple Silicon binary')
        commands = subprocess.check_output(['/usr/bin/otool', '-l', str(path)], text=True)
        try:
            versions, libraries = validate_load_commands(commands, minimum)
        except ValueError as error:
            raise ValueError(f'{path.relative_to(app)}: {error}') from error
        print(f'{path.relative_to(app)}: macOS {max(versions, key=version)}, {len(libraries)} system libraries')
        count += 1
    if count < 2:
        raise ValueError('manager or VM launcher is not a native executable')
    print(f'Runtime dependency check passed: {count} Mach-O files, macOS {minimum} minimum.')


if __name__ == '__main__':
    try:
        check(sys.argv[1])
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))

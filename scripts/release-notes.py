#!/usr/bin/env python3
"""Render the checked-in release notes for GitHub; never publish placeholder text."""
import pathlib
import re
import sys
version = sys.argv[1]
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    raise SystemExit('Use major.minor.patch')
root = pathlib.Path(__file__).resolve().parent.parent
notes = root / 'docs' / f'RELEASE-NOTES-{version}.md'
text = notes.read_text()
def link(match):
    target = match.group(1)
    if '://' in target or target.startswith('#'):
        return match.group(0)
    path, _, fragment = target.partition('#')
    file = (notes.parent / path).resolve()
    if not file.is_file() or not file.is_relative_to(root):
        raise SystemExit(f'Broken documentation link: {target}')
    return '](https://github.com/GlacianNex/enshrouded-mac-server/blob/main/' + file.relative_to(root).as_posix() + ('#' + fragment if fragment else '') + ')'
print(re.sub(r'\]\(([^)]+)\)', link, text))

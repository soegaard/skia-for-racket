#!/usr/bin/env python3
"""Check the reviewed package boundaries, approved data and installed helpers."""
from __future__ import annotations
import json
from pathlib import Path
import re
from native_packages import ROOT, check_font_input, need, read_json
from repository_layout import SOURCE_PACKAGES

HELPERS = ('native_abi.py', 'native_packages.py', 'windows_native.py',
           'install-native-windows.py', 'install-native-windows.ps1', 'repository_layout.py')


def check(root=ROOT):
    lib, doc, meta = (root / name for name in ('skia-lib', 'skia-doc', 'skia'))
    lock = read_json(root / 'packaging/native-assets.json')
    for name in SOURCE_PACKAGES:
        info = (root / name / 'info.rkt').read_text()
        need(re.findall(r'\(define version "([^"]+)"\)', info) == ['0.79'], 'package version drift: ' + name)
    info = (lib / 'info.rkt').read_text()
    need('(define collection "skia")' in info, 'public collection changed')
    for dependency in ('skia-doc', 'skia-fonts-1', 'scribble-lib', 'racket-index'):
        need('"' + dependency + '"' not in info, 'documentation dependency in library: ' + dependency)
    need('(define build-deps \'())' in info, 'library acquired build dependencies')
    need('(define collection \'multi)' in (meta / 'info.rkt').read_text(), 'meta-package is not multi')
    for dependency in ('skia-lib', 'skia-doc'):
        need('("' + dependency + '" #:version "0.79")' in (meta / 'info.rkt').read_text(), 'missing meta dependency')
    need('(define collection "skia-doc")' in (doc / 'info.rkt').read_text(), 'documentation collection changed')
    need('("skia-lib" #:version "0.79")' in (doc / 'info.rkt').read_text(), 'docs do not depend on library')
    fonts = {f['filename']: f for f in lock['documentation_fonts']['files']}
    observed = set()
    for package in SOURCE_PACKAGES:
        for path in (root / package).rglob('*'):
            if not path.is_file() or set(path.relative_to(root / package).parts) & {'compiled','doc','html','__pycache__','native'}:
                continue  # Developer outputs are independently excluded by archive assembly.
            need(not path.is_symlink(), 'symlink in package source')
            need(path.suffix.lower() not in ('.dll','.dylib','.so','.nupkg','.exe','.pyc','.zo'), 'native/generated source member')
            if path.suffix.lower() in ('.ttf','.otf','.ttc'):
                need(package == 'skia-doc' and path.parent == doc / 'fonts' and path.name in fonts,
                     'font outside approved documentation payload')
                check_font_input(path, fonts[path.name]); observed.add(path.name)
    need(observed == set(fonts), 'missing approved font')
    for filename in ('noto-ofl.txt', 'cjk-ofl.txt', 'COPYRIGHTS.json'):
        need((doc / 'licenses' / filename).is_file(), 'missing documentation notice')
    notice = (root / 'NOTICE.md').read_bytes()
    need(b'skia-doc' in notice and b'skia-fonts-1' not in notice, 'obsolete font-package attribution')
    for package in (lib, doc):
        need((package / 'NOTICE.md').read_bytes() == notice, 'installed project notice drift')
    for name in HELPERS:
        need((lib / 'tools' / name).read_bytes() == (root / 'tools' / name).read_bytes(), 'installed helper drift: ' + name)
    # The installed doctor's helpers and the pure reflection fixture have one
    # canonical maintenance source. Only their collection-relative imports differ.
    for path in (lib / 'tools').glob('*.rkt'):
        canonical = root / 'tools' / path.name
        if canonical.is_file():
            need(path.read_text() == canonical.read_text().replace('../skia-lib/', '../'), 'installed Racket helper drift: ' + path.name)
    need((lib / 'tests/public-api-reflect.rkt').read_bytes() == (root / 'tools/public-api-reflect.rkt').read_bytes(),
         'reflection fixture drift')
    for path in (root / 'packaging').rglob('*'):
        if path.is_file() and not set(path.parts) & {'__pycache__', 'prototypes'}:
            need(path.read_bytes() == (lib / path.relative_to(root)).read_bytes(), 'installed lock/notice drift: ' + path.name)
    catalog = read_json(doc / 'scribblings/tutorials/support/catalog.json')
    assets = {name for row in catalog['tutorials'] for name in row['files']}
    need(len(assets) == 43, 'advertised editable asset inventory changed')
    for name in assets:
        relative = 'scribblings/' + (name if name.startswith('quick/') else 'tutorials/' + name)
        need((doc / relative).is_file(), 'missing editable asset: ' + name)
    return dict(source_packages=list(SOURCE_PACKAGES), fonts=len(fonts), editable_assets=len(assets), installed_helpers='synchronized')


if __name__ == '__main__':
    print(json.dumps(check(), indent=2))

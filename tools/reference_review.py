"""Package independently checkable sources, optionally with validated Reference HTML.

This module does not render documents or manufacture xref evidence. It rechecks
real build outputs before copying and rechecks the extracted ZIP before publishing.
Companion-page diagnostics never stand in for complete-site acceptance.
"""
from __future__ import annotations

import hashlib
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlsplit
import zipfile

from reference_support import (MANIFEST, REFERENCE, Page, check_evidence, check_targets,
                               check_source, internal_redirect, need, prepare_site, safe_file)


FONT_SUFFIXES = {'.ttf', '.otf', '.ttc', '.otc', '.woff', '.woff2'}


def source_hashes(root: Path, *, review_inputs: bool = False) -> dict[str, str]:
    paths = {MANIFEST, Path('info.rkt'), Path('docs/REFERENCE-DEVELOPMENT.md')}
    paths.update(path.relative_to(root) for path in (root / REFERENCE).rglob('*')
                 if path.is_file() and path.suffix in {'.rkt', '.scrbl'}
                 and 'compiled' not in path.relative_to(root).parts)
    paths.update(path.relative_to(root) for path in (root / 'tools').glob('*reference*')
                 if path.suffix in {'.py', '.rkt'})
    manifest = json.loads(safe_file(root, str(MANIFEST)).read_text(encoding='utf-8'))
    paths.update(Path(row['source_copy']) for row in manifest.get('source_verified_additions', []))
    if review_inputs:
        paths.update(Path(row['file']) for row in manifest['snapshots'])
        paths.update(Path(row['manual']) for row in manifest.get('tutorial_links', []))
        # These are the actual imports of the ordinary non-native checker.
        paths.update(Path('tools') / name for name in
                     ('check-reference.py', 'reference_support.py', 'reference_review.py'))
    return {path.as_posix(): hashlib.sha256(safe_file(root, path.as_posix()).read_bytes()).hexdigest()
            for path in sorted(paths)}


def validate_source_copy(root: Path, output: Path, expected: dict) -> dict:
    """Run the ordinary checker from outside the copy, without checkout/PYTHONPATH help."""
    root, output = root.resolve(), output.resolve()
    need(not output.is_relative_to(root), 'source-check output must be outside the copied sources')
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [sys.executable, '-E', '-s', '-B', str(root / 'tools/check-reference.py'),
               '--output', str(output)]
    with tempfile.TemporaryDirectory(prefix='reference-check-cwd-') as unrelated:
        completed = subprocess.run(command, cwd=unrelated, capture_output=True, text=True,
                                   timeout=120, check=False)
    need(completed.returncode == 0,
         'copied source checker failed: ' + completed.stdout + completed.stderr)
    report = json.loads((output / 'validation.json').read_text(encoding='utf-8'))
    result = json.loads((output / 'source.json').read_text(encoding='utf-8'))
    need(report.get('status') == 'passed' and result.get('inventory_checked') is True,
         'copied source checker did not validate the pinned inventories')
    need(result.get('documents_only') is False and report.get('commands') == [],
         'expected ordinary source validation without runtime commands')
    need(result == expected, 'copied source-check result differs from the original')
    return dict(status='passed', inventory_checked=True, documents_only=False,
                definitions=len(result['definitions']),
                documented_exports=result['documented_exports'],
                inventory_exports=result['inventory_exports'])


def write_archive(stage: Path, destination: Path) -> dict[str, str]:
    """Write deterministic bytes and a manifest; the caller still has to validate extraction."""
    files = sorted(path for path in stage.rglob('*') if path.is_file())
    sums = {path.relative_to(stage).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in files if path != stage / 'SHA256SUMS.txt'}
    (stage / 'SHA256SUMS.txt').write_text(
        ''.join(f'{digest}  {name}\n' for name, digest in sums.items()), encoding='utf-8')
    with zipfile.ZipFile(destination, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(path for path in stage.rglob('*') if path.is_file()):
            info = zipfile.ZipInfo(path.relative_to(stage).as_posix(), (1980, 1, 1, 0, 0, 0))
            info.external_attr = 0o100644 << 16
            archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED)
    return sums


def extract_checked(archive_path: Path, destination: Path, sums: dict[str, str]) -> None:
    with zipfile.ZipFile(archive_path) as archive:
        names = archive.namelist()
        need(len(names) == len(set(names)) and set(names) == {*sums, 'SHA256SUMS.txt'},
             'review ZIP inventory differs from its staging tree')
        need(archive.testzip() is None, 'review ZIP integrity failure')
        # Every entry was built by write_archive from our own safe staging tree.
        archive.extractall(destination)
    expected = ''.join(f'{digest}  {name}\n' for name, digest in sums.items())
    need((destination / 'SHA256SUMS.txt').read_text(encoding='utf-8') == expected,
         'review ZIP checksum inventory changed')
    for name, digest in sums.items():
        need(hashlib.sha256((destination / name).read_bytes()).hexdigest() == digest,
             f'review ZIP checksum mismatch: {name}')


def copy_source_inputs(root: Path, destination: Path, hashes: dict[str, str]) -> None:
    for relative, digest in hashes.items():
        path = safe_file(root, relative)
        need(path.suffix.lower() not in FONT_SUFFIXES, 'font files are not included in review ZIPs')
        data = path.read_bytes()
        need(hashlib.sha256(data).hexdigest() == digest, 'source input changed while copying')
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)


def package_source_review(root: Path, destination: Path, expected_hashes: dict) -> dict:
    """Publish a source-only review only after its extracted ordinary checker passes."""
    root, destination = root.resolve(), destination.resolve()
    need(not destination.is_relative_to(root), 'keep the review ZIP outside the source checkout')
    need(not destination.exists(), 'review ZIP already exists')
    need(source_hashes(root, review_inputs=True) == expected_hashes,
         'Reference sources changed during the build')
    source = check_source(root)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='reference-src-', dir=destination.parent) as temporary:
        work = Path(temporary)
        stage = work / 'stage'
        copy_source_inputs(root, stage / 'sources', expected_hashes)
        checked = validate_source_copy(stage / 'sources', work / 'stage-check', source)
        evidence = stage / 'evidence'
        evidence.mkdir()
        (evidence / 'source-validation.json').write_text(
            json.dumps(dict(checked, source_sha256=expected_hashes), indent=2) + '\n',
            encoding='utf-8')
        (stage / 'README.txt').write_text(SOURCE_REVIEW_README, encoding='utf-8')
        archive = work / 'sources.zip'
        sums = write_archive(stage, archive)
        extracted = work / 'extracted'
        extract_checked(archive, extracted, sums)
        check = validate_source_copy(extracted / 'sources', work / 'extracted-check', source)
        need(source_hashes(root, review_inputs=True) == expected_hashes,
             'sources changed while packaging the review')
        os.link(archive, destination)
        digest = hashlib.sha256(destination.read_bytes()).hexdigest()
        return dict(path=str(destination), sha256=digest,
                    entries=len(sums) + 1, extracted_zip_checked=True,
                    extracted_source_check=check)


SOURCE_REVIEW_README = (
    'The sources/ directory contains all inputs for the ordinary non-native source checker.\n'
    'From sources/, run: python3 -B tools/check-reference.py --output ../source-check\n'
    'Use a fresh output path. No --documents-only flag or adjacent checkout is needed.\n'
    'The pinned inventory JSON files are copied verbatim and checked by Git blob hash.\n'
    'Any source-signature additions have separate pinned source evidence; they are not reflection.\n'
    'This is not a complete Skia installation or tutorial-rendering bundle.\n'
    'Source consistency is not native, Scribble, GUI, GPU, or complete-site acceptance.\n'
)


class Resources(HTMLParser):
    def __init__(self, text: str):
        super().__init__()
        self.urls = []
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in {'img', 'script'} and attrs.get('src'):
            self.urls.append(attrs['src'])
        if tag in {'a', 'link'} and attrs.get('href'):
            self.urls.append(attrs['href'])


def check_review_html(site: Path) -> dict:
    """Check all local Reference links and HTML-level assets in the relocated tree."""
    site = site.resolve()
    pages = sorted((site / 'skia-reference').rglob('*.html'))
    need(pages, 'review has no Reference HTML')
    count = 0
    for page in pages:
        text = page.read_text(encoding='utf-8')
        need(Page(text).badlinks == 0, f'unresolved review Reference: {page.name}')
        for url in Resources(text).urls:
            parts = urlsplit(url)
            need(parts.scheme != 'file', 'review contains a machine-specific file link')
            if parts.scheme or parts.netloc:
                continue
            target = (page.parent / unquote(parts.path)).resolve() if parts.path else page
            need(target.is_relative_to(site), 'review link escapes the packaged site')
            if target.is_dir():
                target = target / 'index.html'
            need(target.is_file(), f'missing review resource: {url}')
            if parts.fragment and target.suffix == '.html':
                need(Page(target.read_text(encoding='utf-8')).anchors[unquote(parts.fragment)] == 1,
                     f'missing or duplicate review anchor: {url}')
            count += 1
    return dict(reference_pages=len(pages), checked_local_urls=count)


def inspect_link_scopes(site: Path) -> dict:
    """Report unresolved markup independently of existing hyperlinks, by manual scope."""
    site = site.resolve()
    scopes = {}
    for scope in ('reference', 'companions'):
        scopes[scope] = dict(pages=0, checked_local_links=0, broken_local_links=0,
                             unresolved_references=0, unlinked_identifiers=0,
                             external_links_not_checked=0, machine_local_links=0, problems=[])
    cache = {}

    def read(path):
        if path not in cache:
            cache[path] = Page(path.read_text(encoding='utf-8'))
        return cache[path]

    for directory in sorted(site.iterdir()):
        if not directory.is_dir() or not re.fullmatch(
                r'skia-reference|skia-tutorials|skia-tutorial-[a-z-]+', directory.name):
            continue
        scope = scopes['reference' if directory.name == 'skia-reference' else 'companions']
        for page in sorted(directory.rglob('*.html')):
            parsed = read(page)
            scope['pages'] += 1
            scope['unresolved_references'] += parsed.unresolved_references
            scope['unlinked_identifiers'] += parsed.unlinked_identifiers
            for href, _ in parsed.links:
                parts = urlsplit(href)
                redirect = internal_redirect(href)
                if parts.scheme == 'file':
                    scope['machine_local_links'] += 1
                    scope['problems'].append(dict(page=page.relative_to(site).as_posix(),
                                                  href=href, reason='machine-local link'))
                    continue
                if redirect:
                    name, path, fragment = redirect
                    target = (site / name / path).resolve()
                    fragment = unquote(fragment)
                elif parts.scheme or parts.netloc:
                    scope['external_links_not_checked'] += 1
                    continue
                else:
                    target = (page.parent / unquote(parts.path)).resolve() if parts.path else page
                    fragment = unquote(parts.fragment)
                scope['checked_local_links'] += 1
                reason = None
                if not target.is_relative_to(site):
                    reason = 'outside the packaged tree'
                else:
                    if target.is_dir():
                        target = target / 'index.html'
                    if not target.is_file():
                        reason = 'missing target file'
                    elif (fragment and target.suffix == '.html'
                          and read(target).anchors[fragment] != 1):
                        reason = 'missing or duplicate fragment'
                if reason:
                    scope['broken_local_links'] += 1
                    scope['problems'].append(dict(page=page.relative_to(site).as_posix(),
                                                  href=href, reason=reason))
    for scope in scopes.values():
        incomplete = any(scope[key] for key in ('broken_local_links', 'unresolved_references',
                                                'unlinked_identifiers', 'machine_local_links'))
        scope['status'] = ('incomplete' if incomplete
                           else ('passed' if scope['pages'] else 'not-present'))
    return dict(scope='packaged-pages-only', complete_site_checked=False, **scopes)


def package_review(root: Path, site: Path, source: dict, evidence: dict,
                   destination: Path, expected_hashes: dict, *, quick: bool = False) -> dict:
    """Refuse stale sources, failed links, or an existing ZIP. Publish only after extraction tests."""
    root, site, destination = root.resolve(), site.resolve(), destination.resolve()
    need(not destination.is_relative_to(root), 'keep the review ZIP outside the source checkout')
    need(not destination.exists(), 'review ZIP already exists')
    need(source_hashes(root, review_inputs=True) == expected_hashes,
         'Reference sources changed during the build')
    need(source == check_source(root), 'review requires the full current source-check result')
    check_evidence(source, evidence)
    check_targets(site, evidence, quick=site / 'skia-tutorial-quick/index.html' if quick else None)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='reference-review-', dir=destination.parent) as temporary:
        work = Path(temporary)
        stage = work / 'stage'
        html = stage / 'html'
        html.mkdir(parents=True)
        required = {'skia-reference', *(row['directory'] for row in source['tutorial_links'])}
        if quick:
            required.add('skia-tutorial-quick')
        # Installed checks can supply the complete tutorial collection. Do not discard it.
        directories = {path.name for path in site.iterdir() if path.is_dir()
                       and re.fullmatch(r'skia-reference|skia-tutorials|skia-tutorial-[a-z-]+',
                                        path.name)}
        need(required <= directories, 'missing companion manual in review build')

        def copy(path: Path, relative: str):
            need(not path.is_symlink(), 'symlink in review input')
            need(path.suffix.lower() not in FONT_SUFFIXES,
                 'font files are not included in review ZIPs')
            target = stage / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)

        for name in sorted(directories):
            base = safe_file(site, name)
            for path in sorted(base.rglob('*')):
                need(not path.is_symlink(), 'symlink in review manual')
                if path.is_file():
                    # Native xrefs may contain absolute paths and are not needed to view HTML.
                    if path.suffix not in {'.sxref', '.rktd', '.sqlite', '.zo', '.dep'}:
                        copy(path, 'html/' + path.relative_to(site).as_posix())
        for path in sorted(site.iterdir()):
            if path.is_file() and path.suffix in {'.css', '.js', '.png', '.svg'}:
                copy(path, 'html/' + path.name)
        prepare_site(html, source_root=site)
        quick_page = html / 'skia-tutorial-quick/index.html' if quick else None
        links = check_targets(html, evidence, quick=quick_page)
        inspection = check_review_html(html)
        copy_source_inputs(root, stage / 'sources', expected_hashes)
        source_validation = validate_source_copy(stage / 'sources', work / 'stage-check', source)
        scopes = inspect_link_scopes(html)
        evidence_dir = stage / 'evidence'
        evidence_dir.mkdir()
        for name, data in [('source.json', source), ('runtime.json', evidence),
                           ('review.json', dict(source_sha256=expected_hashes, links=links,
                                                html=inspection, link_scopes=scopes,
                                                source_validation=source_validation,
                                                status='passed'))]:
            (evidence_dir / name).write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
        (stage / 'README.txt').write_text(
            'Open html/skia-reference/index.html. The sources/ tree matches this build.\n'
            'The three outgoing Reference links and local Reference assets were checked.\n'
            'Companion-page diagnostics are separate in evidence/review.json.\n'
            'The partial bundle does not certify a complete installed or published site.\n'
            + SOURCE_REVIEW_README,
            encoding='utf-8')
        temporary_zip = work / 'review.zip'
        sums = write_archive(stage, temporary_zip)
        extracted = work / 'extracted'
        extract_checked(temporary_zip, extracted, sums)
        extracted_source = validate_source_copy(
            extracted / 'sources', work / 'extracted-check', source)
        extracted_html = extracted / 'html'
        check_targets(extracted_html, evidence,
                      quick=extracted_html / 'skia-tutorial-quick/index.html' if quick else None)
        check_review_html(extracted_html)
        need(inspect_link_scopes(extracted_html) == scopes, 'extracted link diagnostics changed')
        for relative, digest in expected_hashes.items():
            packaged = (extracted / 'sources' / relative).read_bytes()
            need(hashlib.sha256(packaged).hexdigest() == digest,
                 'packaged sources do not match the pre-build snapshot')
        need(source_hashes(root, review_inputs=True) == expected_hashes,
             'sources changed while packaging the review')
        # A hard link publishes atomically without replacing an existing path.
        os.link(temporary_zip, destination)
        digest = hashlib.sha256(destination.read_bytes()).hexdigest()
        return dict(path=str(destination), sha256=digest,
                    entries=len(sums) + 1, extracted_zip_checked=True,
                    extracted_source_check=extracted_source, link_scopes=scopes, **inspection)

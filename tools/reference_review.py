"""Package only validated Reference HTML and its matching source snapshot.

This module does not render documents or manufacture xref evidence. It rechecks
real build outputs before copying and rechecks the extracted ZIP before publishing.
"""
from __future__ import annotations

import hashlib
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
from urllib.parse import unquote, urlsplit
import zipfile

from reference_support import (MANIFEST, REFERENCE, Page, check_evidence, check_targets,
                               need, prepare_site, safe_file)


FONT_SUFFIXES = {'.ttf', '.otf', '.ttc', '.otc', '.woff', '.woff2'}


def source_hashes(root: Path) -> dict[str, str]:
    paths = {MANIFEST, Path('info.rkt'), Path('docs/REFERENCE-DEVELOPMENT.md')}
    paths.update(path.relative_to(root) for path in (root / REFERENCE).rglob('*')
                 if path.is_file() and path.suffix in {'.rkt', '.scrbl'}
                 and 'compiled' not in path.relative_to(root).parts)
    paths.update(path.relative_to(root) for path in (root / 'tools').glob('*reference*')
                 if path.suffix in {'.py', '.rkt'})
    return {path.as_posix(): hashlib.sha256(safe_file(root, path.as_posix()).read_bytes()).hexdigest()
            for path in sorted(paths)}


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


def package_review(root: Path, site: Path, source: dict, evidence: dict,
                   destination: Path, expected_hashes: dict, *, quick: bool = False) -> dict:
    """Refuse stale sources, failed links, or an existing ZIP. Publish only after extraction tests."""
    root, site, destination = root.resolve(), site.resolve(), destination.resolve()
    need(not destination.is_relative_to(root), 'keep the review ZIP outside the source checkout')
    need(not destination.exists(), 'review ZIP already exists')
    need(source_hashes(root) == expected_hashes, 'Reference sources changed during the build')
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
        for relative in expected_hashes:
            copy(safe_file(root, relative), 'sources/' + relative)
        evidence_dir = stage / 'evidence'
        evidence_dir.mkdir()
        for name, data in [('source.json', source), ('runtime.json', evidence),
                           ('review.json', dict(source_sha256=expected_hashes, links=links,
                                                html=inspection, status='passed'))]:
            (evidence_dir / name).write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
        (stage / 'README.txt').write_text(
            'Open html/skia-reference/index.html. The sources/ tree matches this build.\n'
            'The three outgoing Reference links and local Reference assets were checked.\n'
            'External websites and links outside the Reference are not certified by this check.\n',
            encoding='utf-8')
        files = sorted(path for path in stage.rglob('*') if path.is_file())
        sums = {path.relative_to(stage).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in files}
        (stage / 'SHA256SUMS.txt').write_text(
            ''.join(f'{digest}  {name}\n' for name, digest in sums.items()), encoding='utf-8')
        temporary_zip = work / 'review.zip'
        with zipfile.ZipFile(temporary_zip, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(path for path in stage.rglob('*') if path.is_file()):
                info = zipfile.ZipInfo(path.relative_to(stage).as_posix(), (1980, 1, 1, 0, 0, 0))
                info.external_attr = 0o100644 << 16
                archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED)
        extracted = work / 'extracted'
        with zipfile.ZipFile(temporary_zip) as archive:
            need(archive.testzip() is None, 'review ZIP integrity failure')
            archive.extractall(extracted)  # Entries were constructed from the safe staging tree.
        for name, digest in sums.items():
            need(hashlib.sha256((extracted / name).read_bytes()).hexdigest() == digest,
                 f'review ZIP checksum mismatch: {name}')
        extracted_html = extracted / 'html'
        check_targets(extracted_html, evidence,
                      quick=extracted_html / 'skia-tutorial-quick/index.html' if quick else None)
        check_review_html(extracted_html)
        for relative, digest in expected_hashes.items():
            packaged = (extracted / 'sources' / relative).read_bytes()
            need(hashlib.sha256(packaged).hexdigest() == digest,
                 'packaged sources do not match the pre-build snapshot')
        need(source_hashes(root) == expected_hashes, 'sources changed while packaging the review')
        # A hard link publishes atomically without replacing an existing path.
        os.link(temporary_zip, destination)
        digest = hashlib.sha256(destination.read_bytes()).hexdigest()
        return dict(path=str(destination), sha256=digest,
                    entries=len(sums) + 1, extracted_zip_checked=True, **inspection)

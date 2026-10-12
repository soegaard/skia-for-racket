#!/usr/bin/env python3
"""Check tutorial navigation/catalog structure; opt in to source files or rendered HTML.

This checker does not compile Racket, render Scribble, or run a native example.
Use reader-test.rkt and support/reader-smoke.scrbl for those independent checks.
"""
from __future__ import annotations

import argparse
from html.parser import HTMLParser
import json
from pathlib import Path, PurePosixPath
import re
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
CATALOG = Path('scribblings/tutorials/support/catalog.json')
MARKERS = {'skia-reader-prerequisites', 'skia-reader-next', 'skia-reader-sources'}
VOID = {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta',
        'param', 'source', 'track', 'wbr'}


def need(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def safe_relative(text: str) -> PurePosixPath:
    need(bool(re.fullmatch(r'[a-zA-Z0-9_./-]+', text)), f'unsafe path: {text!r}')
    need(all(part not in ('', '.', '..') for part in text.split('/')),
         f'unsafe path: {text!r}')
    return PurePosixPath(text)


def source_path(root: Path, relative: str) -> Path:
    path = safe_relative(relative)
    return root / 'scribblings' / (path if path.parts[0] == 'quick' else 'tutorials' / path)


def check_structure(root: Path) -> dict:
    data = json.loads((root / CATALOG).read_text(encoding='utf-8'))
    rows = data['tutorials']
    ids = [row['id'] for row in rows]
    need(len(ids) == 22 and len(set(ids)) == 22, 'expected 22 distinct lessons')
    by_id = {row['id']: row for row in rows}
    for row in rows:
        id_ = row['id']
        need(row['entry'] in row['files'], f'{id_}: entry missing from file set')
        need(len(row['files']) == len(set(row['files'])), f'{id_}: duplicate files')
        for name in row['files']:
            safe_relative(name)
        for target in row['prerequisites'] + row['next']:
            need(target in by_id and target != id_, f'{id_}: unknown/self link: {target}')
        text = (root / safe_relative(row['manual'])).read_text(encoding='utf-8')
        title = re.search(r'@title(?:\[[^\]]*\])?\{([^}]+)\}', text)
        need(title is not None and title[1] == row['title'], f'{id_}: title drift')
        for helper in ('tutorial-entry', 'tutorial-next', 'tutorial-sources'):
            need(text.count(f'@{helper}["{id_}"]') == 1, f'{id_}: missing/duplicate {helper}')
        for tag in ('try-it', 'next-steps', 'example-source'):
            need(text.count(f'#:tag "{tag}"') == 1, f'{id_}: missing/duplicate {tag}')
        need(text.index('#:tag "try-it"') < text.index('#:tag "example-source"'),
             f'{id_}: complete source precedes exercises')
        need(not re.search(r'\bTutorial\s+\d+\b', text), f'{id_}: bare tutorial number')
        need(not re.search(r'@tt\{[^{}]*--', text), f'{id_}: decoded inline option')
        for target in re.findall(r'@tutorial-link\["([^"]+)"\]', text):
            need(target in by_id, f'{id_}: unknown body link {target}')
        need(row['commands'][0].startswith(f'racket {row["entry"]}'),
             f'{id_}: first command does not run entry')
    def visit(id_: str, path: tuple[str, ...] = ()) -> None:
        need(id_ not in path, f'cyclic prerequisites: {path + (id_,)}')
        for dependency in by_id[id_]['prerequisites']:
            visit(dependency, path + (id_,))
    for id_ in ids:
        visit(id_)
    covered = set()
    for route in data['routes']:
        need(bool(route['lessons']), 'empty route')
        need(all(id_ in by_id for id_ in route['lessons']), 'unknown route destination')
        covered.update(route['lessons'])
    need(covered == set(ids), 'a tutorial has no index route')
    index = (root / 'scribblings/tutorials/index.scrbl').read_text(encoding='utf-8')
    rendered_routes = [re.findall(r'"([^"]+)"', route)
                       for route in re.findall(r"@tutorial-route\['\(([^)]*)\)\]", index)]
    need(rendered_routes == [route['lessons'] for route in data['routes']],
         'index routes differ from catalog routes')
    need(index.count('#:tag "running-examples"') == 1, 'missing running-examples destination')
    for id_ in ('sprites', 'squadron'):
        need(set(by_id[id_]['files']) >= {
            'support/sprite-assets.rkt', 'support/sprite-window.rkt', 'support/sprite-math.rkt'
        }, f'{id_}: incomplete shared sprite dependencies')
    return dict(lessons=len(ids), routes=len(data['routes']),
                source_files=len({file for row in rows for file in row['files']}))


def check_files(root: Path) -> dict:
    rows = json.loads((root / CATALOG).read_text(encoding='utf-8'))['tutorials']
    checked = set()
    for row in rows:
        files = {source_path(root, relative).resolve() for relative in row['files']}
        for relative in row['files']:
            file = source_path(root, relative)
            need(file.is_file(), f'missing source or fixture: {file}')
            checked.add(relative)
            if file.suffix == '.rkt':
                text = file.read_text(encoding='utf-8')
                # Conservative literal-module-path check, not a Racket dependency analyzer.
                for name in re.findall(r'"([^"\n]+\.rkt)"', text):
                    target = (file.parent / name).resolve()
                    need(target in files,
                         f'{row["id"]}: local Racket path outside copied set: {file}: {name}')
    return dict(files_found=len(checked), dependency_check='literal relative .rkt strings only')


class Page(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.commands = []
        self.markers = set()
        self.anchors = set()
        self.nav_links = []
        self.source_links = []
        self.nav_badlinks = 0
        self.file_links = self.badlinks = self.rkt_errors = 0

    def handle_starttag(self, tag: str, attrs: list) -> None:
        values = dict(attrs)
        classes = set(values.get('class', '').split())
        self.markers.update(classes & MARKERS)
        self.badlinks += int('badlink' in classes)
        self.rkt_errors += int('RktErr' in classes)
        for key in ('id', 'name'):
            if values.get(key):
                self.anchors.add(values[key])
        command = 'skia-command' in classes
        if command:
            self.commands.append('')
        nav = bool(classes & {'skia-reader-navigation', 'skia-reader-next',
                              'skia-reader-prerequisites'})
        parent_nav = any(item[2] for item in self.stack)
        source = 'skia-reader-source-link' in classes
        parent_source = any(item[3] for item in self.stack)
        self.nav_badlinks += int('badlink' in classes and (nav or parent_nav))
        href = values.get('href', '')
        self.file_links += int(href.startswith('file:'))
        if tag == 'a' and (source or parent_source):
            self.source_links.append(href)
        if tag == 'a' and (nav or parent_nav):
            self.nav_links.append(href)
        if tag not in VOID:
            self.stack.append((tag, len(self.commands) - 1 if command else None, nav, source))

    def handle_startendtag(self, tag: str, attrs: list) -> None:
        self.handle_starttag(tag, attrs)
        if tag not in VOID:
            self.handle_endtag(tag)

    def handle_endtag(self, tag: str) -> None:
        for index in range(len(self.stack) - 1, -1, -1):
            if self.stack[index][0] == tag:
                del self.stack[index:]
                break

    def handle_data(self, data: str) -> None:
        for _, command, _, _ in reversed(self.stack):
            if command is not None:
                self.commands[command] += data
                break


def read_page(path: Path) -> Page:
    page = Page()
    page.feed(path.read_text(encoding='utf-8'))
    return page


def check_commands(page: Page) -> None:
    need(bool(page.commands), 'no literal command spans were rendered')
    for command in page.commands:
        need(not re.search(r'[\u2010-\u2015\u2212](?:renderer|count|snapshot|list|backend)', command),
             f'command option has a non-ASCII hyphen: {command!r}')


def check_smoke(path: Path) -> dict:
    page = read_page(path)
    check_commands(page)
    expected = ['--renderer raster', '--renderer gpu', '--count 300',
                '--snapshot picture.png', 'raco skia-examples --list']
    need(page.commands == expected, f'literal command mismatch: {page.commands!r}')
    return dict(literal_command_fragments=len(expected))


def check_html(directory: Path) -> dict:
    pages = {p.resolve(): read_page(p) for p in directory.rglob('*.html')}
    lessons = {p: page for p, page in pages.items() if page.markers}
    need(len(lessons) == 22, f'expected 22 rendered reader entries, got {len(lessons)}')
    for path, page in lessons.items():
        need(page.markers == MARKERS, f'missing reader section in {path}')
        need(page.nav_badlinks == 0, f'unresolved reader reference in {path}')
        need(bool(page.nav_links), f'no resolved reader navigation in {path}')
        need(bool(page.source_links), f'no complete-example source links in {path}')
        for href in page.source_links:
            url = urlsplit(href)
            need(not url.scheme and not url.netloc, f'non-local example resource: {href}')
            need((path.parent / unquote(url.path)).is_file(), f'missing example resource: {href}')
        for href in page.nav_links:
            url = urlsplit(href)
            if url.scheme or url.netloc:
                continue  # Report file URLs separately; do not call them resolved local links.
            target = (path.parent / unquote(url.path)).resolve() if url.path else path
            need(target in pages, f'missing navigation destination: {path}: {href}')
            if url.fragment:
                need(unquote(url.fragment) in pages[target].anchors,
                     f'missing navigation anchor: {path}: {href}')
        if page.commands:
            check_commands(page)
    return dict(rendered_lessons=len(lessons),
                file_links=sum(p.file_links for p in pages.values()),
                unresolved_references=sum(p.badlinks for p in pages.values()),
                racket_error_elements=sum(p.rkt_errors for p in pages.values()))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--files', action='store_true', help='require the complete example sources')
    parser.add_argument('--html-root', type=Path, help='check an actual 22-lesson rendered tree')
    parser.add_argument('--smoke-html', type=Path, help='check rendered reader-smoke.html')
    args = parser.parse_args()
    report = dict(structure=check_structure(args.root),
                  files='not requested', rendered_manuals='not requested',
                  racket_compilation='not performed', native_tests='not performed')
    if args.files:
        report['files'] = check_files(args.root)
    if args.html_root:
        report['rendered_manuals'] = check_html(args.html_root)
    if args.smoke_html:
        report['rendered_command_smoke'] = check_smoke(args.smoke_html)
    print(json.dumps(report, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

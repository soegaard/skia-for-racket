#!/usr/bin/env python3
"""Check the shared Skia documentation navigation in a complete HTML site.

The checker intentionally treats collection navigation as a separate concern
from Reference API-link coverage.  It validates every emitted manual page,
the neutral landing page, the catalog-derived Tutorials panel, and local asset
targets after a build or staged-site relocation.
"""
from __future__ import annotations

import argparse
from html.parser import HTMLParser
import json
from pathlib import Path
import sys
from urllib.parse import parse_qs, unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'scribblings' / 'tutorials' / 'support' / 'catalog.json'


class CheckError(ValueError):
    pass


def need(condition, message):
    if not condition:
        raise CheckError(message)


def class_tokens(attrs):
    return set(attrs.get('class', '').split())


class NavigationParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.depth = 0
        self.navigation_depths = []
        self.navigations = []

    def handle_starttag(self, tag, attrs):
        self.depth += 1
        attrs = dict(attrs)
        if attrs.get('role') == 'navigation' and attrs.get('data-skia-doc-section'):
            self.navigation_depths.append(self.depth)
            self.navigations.append(dict(attrs=attrs, anchors=[], buttons=[], panels=[], collections=[]))
        if not self.navigation_depths:
            return
        navigation = self.navigations[-1]
        if tag == 'a':
            navigation['anchors'].append(attrs)
        elif tag == 'button':
            navigation['buttons'].append(attrs)
        elif attrs.get('data-skia-doc-nav-panel') == 'tutorials':
            navigation['panels'].append(attrs)
        if ('skia-doc-nav__collection-link' in class_tokens(attrs)
                and 'data-skia-doc-nav-all' not in attrs):
            navigation['collections'].append((tag, attrs))

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        self.handle_endtag(tag)

    def handle_endtag(self, tag):
        if self.navigation_depths and self.depth == self.navigation_depths[-1]:
            self.navigation_depths.pop()
        self.depth -= 1


def parse_navigation(page: Path):
    parser = NavigationParser()
    parser.feed(page.read_text(encoding='utf-8'))
    parser.close()
    need(len(parser.navigations) == 1,
         f'{page}: expected one named navigation landmark, found {len(parser.navigations)}')
    return parser.navigations[0]


def load_catalog():
    catalog = json.loads(CATALOG.read_text(encoding='utf-8'))
    tutorials = catalog['tutorials']
    routes = catalog['routes']
    ids = [entry['id'] for entry in tutorials]
    need(len(ids) == len(set(ids)), 'tutorial catalog has duplicate ids')
    seen = set()
    shortcut_ids = []
    for route in routes:
        for identifier in route['lessons']:
            need(identifier in ids, f'route has unknown tutorial: {identifier}')
            if identifier not in seen:
                seen.add(identifier)
                shortcut_ids.append(identifier)
    need(set(shortcut_ids) == set(ids), 'tutorial catalog has uncategorized tutorials')
    return catalog, tutorials, routes, shortcut_ids


def nav_collection(navigation, class_name):
    matches = [(tag, attrs) for tag, attrs in navigation['collections']
               if class_name in class_tokens(attrs)]
    need(len(matches) == 1,
         f'expected exactly one navigation item with class {class_name}, found {len(matches)}')
    return matches[0]


def installed_redirect_target(root: Path, href: str):
    """Return a known package-local Racket redirect target, if this is one."""
    split = urlsplit(href)
    if not (split.scheme in ('http', 'https')
            and split.path.endswith('/local-redirect/index.html')):
        return None
    query = parse_qs(split.query)
    documents, relatives = query.get('doc', []), query.get('rel', [])
    if len(documents) != 1 or len(relatives) != 1:
        return None
    document, relative = documents[0], unquote(relatives[0])
    if not (document == 'skia-reference'
            or document == 'skia-tutorials'
            or document.startswith('skia-tutorial-')):
        return None
    candidate = (root / document / relative).resolve()
    return candidate if candidate.is_relative_to(root.resolve()) else None


def local_target(root: Path, page: Path, href: str):
    split = urlsplit(href)
    redirected = installed_redirect_target(root, href)
    if redirected is not None:
        candidate = redirected
    else:
        need(not split.scheme and not split.netloc,
             f'{page}: navigation link is not a portable local target: {href!r}')
        relative = unquote(split.path)
        if not relative:
            return page
        candidate = (page.parent / relative).resolve()
    need(candidate.is_relative_to(root.resolve()),
         f'{page}: navigation link escapes staged site: {href!r}')
    if candidate.is_dir():
        candidate = candidate / 'index.html'
    need(candidate.is_file(), f'{page}: missing navigation target: {href!r}')
    return candidate


def check_assets(root: Path, page: Path):
    text = page.read_text(encoding='utf-8')
    for asset in ('skia-doc-nav.css', 'skia-doc-nav.js'):
        need(asset in text, f'{page}: missing navigation asset reference: {asset}')
        local_target(root, page, asset)


def check_page(root: Path, page: Path, *, section: str, index: bool, tutorial_id: str | None,
               shortcut_ids: list[str]):
    navigation = parse_navigation(page)
    attrs = navigation['attrs']
    need(attrs.get('aria-label') == 'Skia documentation',
         f'{page}: navigation landmark has the wrong accessible name')
    need(attrs.get('data-skia-doc-section') == section,
         f'{page}: expected {section!r} active section, got {attrs.get("data-skia-doc-section")!r}')
    check_assets(root, page)

    reference_tag, reference = nav_collection(navigation, 'skia-doc-nav__collection-link--reference')
    guide_tag, guide = nav_collection(navigation, 'skia-doc-nav__collection-link--guide')
    tutorials_tag, tutorials = nav_collection(navigation, 'skia-doc-nav__collection-link--tutorials')
    need(reference_tag == 'a', f'{page}: Reference must be a link')
    need(tutorials_tag == 'a', f'{page}: Tutorials must be a link')
    need(guide_tag == 'span' and guide.get('aria-disabled') == 'true' and 'href' not in guide,
         f'{page}: unavailable Guide must be an inert visible label')
    local_target(root, page, reference.get('href', ''))
    local_target(root, page, tutorials.get('href', ''))
    all_tutorials = [anchor for anchor in navigation['anchors']
                     if anchor.get('data-skia-doc-nav-all') == 'tutorials']
    need(len(all_tutorials) == 1, f'{page}: expected one All tutorials shortcut')
    local_target(root, page, all_tutorials[0].get('href', ''))

    for collection, anchor in (('reference', reference), ('tutorials', tutorials)):
        expected_current = (collection == section)
        actual_current = anchor.get('aria-current')
        if expected_current:
            need(actual_current == ('page' if index else 'location'),
                 f'{page}: incorrect current state for {collection}')
        else:
            need(actual_current is None,
                 f'{page}: inactive {collection} link must not have aria-current')

    need(not navigation['buttons'], f'{page}: Tutorials shortcuts must not use a persistent button')
    need(len(navigation['panels']) == 1, f'{page}: expected one Tutorials shortcut panel')
    panel = navigation['panels'][0]
    need(panel.get('id') == 'skia-doc-nav-tutorials' and 'hidden' not in panel,
         f'{page}: tutorial panel visibility must be controlled by its Tutorials region')

    shortcuts = [anchor for anchor in navigation['anchors']
                 if 'skia-doc-nav__tutorial-link' in class_tokens(anchor)]
    need(len(shortcuts) == len(shortcut_ids),
         f'{page}: expected {len(shortcut_ids)} tutorial shortcuts, found {len(shortcuts)}')
    shortcut_targets = []
    for anchor in shortcuts:
        target = local_target(root, page, anchor.get('href', ''))
        shortcut_targets.append(target.parent.name)
    expected_targets = {tutorial_directory(identifier) for identifier in shortcut_ids}
    need(len(shortcut_targets) == len(set(shortcut_targets)),
         f'{page}: tutorial shortcuts contain duplicate targets')
    need(set(shortcut_targets) == expected_targets,
         f'{page}: tutorial shortcuts do not match the catalog')
    current_shortcuts = [anchor for anchor in shortcuts if anchor.get('aria-current') == 'page']
    if tutorial_id:
        need(len(current_shortcuts) == 1,
             f'{page}: current tutorial must be marked exactly once')
        current_target = local_target(root, page, current_shortcuts[0].get('href', ''))
        need(current_target.parent.name == tutorial_directory(tutorial_id),
             f'{page}: the current tutorial marker identifies the wrong lesson')
    else:
        need(not current_shortcuts,
             f'{page}: only an individual tutorial page may mark a shortcut current')


def tutorial_directory(identifier: str):
    return f'skia-tutorial-{identifier}'


def check_site(root: Path):
    root = root.resolve()
    need(root.is_dir(), f'HTML site does not exist: {root}')
    _catalog, tutorials, _routes, shortcut_ids = load_catalog()
    landing = root / 'index.html'
    need(landing.is_file(), f'missing neutral landing page: {landing}')
    check_page(root, landing, section='landing', index=False, tutorial_id=None,
               shortcut_ids=shortcut_ids)

    reference = root / 'skia-reference'
    pages = sorted(reference.glob('*.html'))
    need(pages, f'missing Reference HTML pages under {reference}')
    for page in pages:
        check_page(root, page, section='reference', index=page.name == 'index.html',
                   tutorial_id=None, shortcut_ids=shortcut_ids)

    tutorial_index = root / 'skia-tutorials' / 'index.html'
    need(tutorial_index.is_file(), f'missing Tutorials index: {tutorial_index}')
    check_page(root, tutorial_index, section='tutorials', index=True, tutorial_id=None,
               shortcut_ids=shortcut_ids)

    for entry in tutorials:
        identifier = entry['id']
        page = root / tutorial_directory(identifier) / 'index.html'
        need(page.is_file(), f'missing tutorial page for {identifier}: {page}')
        check_page(root, page, section='tutorials', index=False, tutorial_id=identifier,
                   shortcut_ids=shortcut_ids)

    return dict(
        status='passed',
        site=str(root),
        reference_pages=len(pages),
        tutorials=len(tutorials),
        available_collections=['reference', 'tutorials'],
        landing_checked=True,
    )


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('site', type=Path, help='root of installed or staged documentation HTML')
    parser.add_argument('--output', type=Path, help='write the machine-readable report here')
    args = parser.parse_args(argv)
    try:
        report = check_site(args.site)
    except (CheckError, OSError, UnicodeError, json.JSONDecodeError) as error:
        report = dict(status='failed', site=str(args.site), error=str(error))
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(f'Documentation navigation: {report["status"]}')
    if report['status'] != 'passed':
        print(report['error'], file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

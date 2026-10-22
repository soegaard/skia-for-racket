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
        self.group_depths = []
        self.heading_depths = []
        self.navigations = []

    def handle_starttag(self, tag, attrs):
        self.depth += 1
        attrs = dict(attrs)
        if attrs.get('role') == 'navigation' and attrs.get('data-skia-doc-section'):
            self.navigation_depths.append(self.depth)
            self.navigations.append(
                dict(attrs=attrs, anchors=[], buttons=[], panels=[], collections=[], groups=[]))
        if not self.navigation_depths:
            return
        navigation = self.navigations[-1]
        if tag == 'a':
            navigation['anchors'].append(attrs)
        elif tag == 'button':
            navigation['buttons'].append(attrs)
        elif attrs.get('data-skia-doc-nav-panel') == 'tutorials':
            navigation['panels'].append(attrs)
        if 'skia-doc-nav__tutorial-group' in class_tokens(attrs):
            group = dict(attrs=attrs, heading='', anchors=[])
            navigation['groups'].append(group)
            self.group_depths.append((self.depth, group))
        elif 'skia-doc-nav__group-heading' in class_tokens(attrs) and self.group_depths:
            self.heading_depths.append((self.depth, self.group_depths[-1][1]))
        if ('skia-doc-nav__collection-link' in class_tokens(attrs)
                and 'data-skia-doc-nav-all' not in attrs):
            navigation['collections'].append((tag, attrs))
        if tag == 'a' and self.group_depths:
            self.group_depths[-1][1]['anchors'].append(attrs)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        self.handle_endtag(tag)

    def handle_endtag(self, tag):
        if self.heading_depths and self.depth == self.heading_depths[-1][0]:
            self.heading_depths.pop()
        if self.group_depths and self.depth == self.group_depths[-1][0]:
            self.group_depths.pop()
        if self.navigation_depths and self.depth == self.navigation_depths[-1]:
            self.navigation_depths.pop()
        self.depth -= 1

    def handle_data(self, data):
        if self.heading_depths:
            self.heading_depths[-1][1]['heading'] += data


def parse_navigation(page: Path):
    parser = NavigationParser()
    parser.feed(page.read_text(encoding='utf-8'))
    parser.close()
    need(len(parser.navigations) == 1,
         f'{page}: expected one named navigation landmark, found {len(parser.navigations)}')
    return parser.navigations[0]


def load_catalog():
    catalog = json.loads(CATALOG.read_text(encoding='utf-8'))
    need(catalog.get('schema_version') == 2, 'expected tutorial catalog schema version 2')
    tutorials = catalog['tutorials']
    categories = catalog['categories']
    ids = [entry['id'] for entry in tutorials]
    need(len(ids) == len(set(ids)), 'tutorial catalog has duplicate ids')
    for entry in tutorials:
        need(isinstance(entry.get('menu_title'), str) and entry['menu_title'].strip(),
             f'tutorial has no menu title: {entry["id"]}')
    category_ids = [category.get('id') for category in categories]
    need(all(isinstance(identifier, str) and identifier for identifier in category_ids),
         'tutorial catalog has a category without an id')
    need(len(category_ids) == len(set(category_ids)), 'tutorial catalog has duplicate category ids')
    shortcut_ids = []
    for category in categories:
        need(isinstance(category.get('title'), str) and category['title'].strip(),
             f'tutorial category has no title: {category["id"]}')
        lessons = category.get('lessons')
        need(isinstance(lessons, list) and lessons,
             f'tutorial category has no lessons: {category["id"]}')
        for identifier in lessons:
            need(identifier in ids, f'category has unknown tutorial: {identifier}')
            shortcut_ids.append(identifier)
    need(len(shortcut_ids) == len(set(shortcut_ids)),
         'tutorial catalog assigns a lesson to more than one category')
    need(set(shortcut_ids) == set(ids), 'tutorial catalog has uncategorized tutorials')
    return catalog, tutorials, categories, shortcut_ids


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
            or document == 'skia-guide'
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
               categories: list[dict], shortcut_ids: list[str]):
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
    need(guide_tag == 'a', f'{page}: Guide must be a link')
    need(tutorials_tag == 'a', f'{page}: Tutorials must be a link')
    local_target(root, page, reference.get('href', ''))
    local_target(root, page, guide.get('href', ''))
    local_target(root, page, tutorials.get('href', ''))
    all_tutorials = [anchor for anchor in navigation['anchors']
                     if anchor.get('data-skia-doc-nav-all') == 'tutorials']
    need(len(all_tutorials) == 1, f'{page}: expected one All tutorials shortcut')
    local_target(root, page, all_tutorials[0].get('href', ''))

    for collection, anchor in (('reference', reference), ('guide', guide), ('tutorials', tutorials)):
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
    need(len(navigation['groups']) == len(categories),
         f'{page}: expected {len(categories)} tutorial categories, found {len(navigation["groups"])}')
    for group, category in zip(navigation['groups'], categories):
        need(group['heading'].strip() == category['title'],
             f'{page}: tutorial category heading differs from catalog: {category["id"]}')
        targets = [local_target(root, page, anchor.get('href', '')).parent.name
                   for anchor in group['anchors']]
        expected = [tutorial_directory(identifier) for identifier in category['lessons']]
        need(targets == expected,
             f'{page}: tutorial category differs from catalog: {category["id"]}')
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
    _catalog, tutorials, categories, shortcut_ids = load_catalog()
    landing = root / 'index.html'
    need(landing.is_file(), f'missing neutral landing page: {landing}')
    check_page(root, landing, section='landing', index=False, tutorial_id=None,
               categories=categories, shortcut_ids=shortcut_ids)

    reference = root / 'skia-reference'
    pages = sorted(reference.glob('*.html'))
    need(pages, f'missing Reference HTML pages under {reference}')
    for page in pages:
        check_page(root, page, section='reference', index=page.name == 'index.html',
                   tutorial_id=None, categories=categories, shortcut_ids=shortcut_ids)

    guide_index = root / 'skia-guide' / 'index.html'
    need(guide_index.is_file(), f'missing Guide index: {guide_index}')
    check_page(root, guide_index, section='guide', index=True, tutorial_id=None,
               categories=categories, shortcut_ids=shortcut_ids)

    tutorial_index = root / 'skia-tutorials' / 'index.html'
    need(tutorial_index.is_file(), f'missing Tutorials index: {tutorial_index}')
    check_page(root, tutorial_index, section='tutorials', index=True, tutorial_id=None,
               categories=categories, shortcut_ids=shortcut_ids)

    for entry in tutorials:
        identifier = entry['id']
        page = root / tutorial_directory(identifier) / 'index.html'
        need(page.is_file(), f'missing tutorial page for {identifier}: {page}')
        check_page(root, page, section='tutorials', index=False, tutorial_id=identifier,
                   categories=categories, shortcut_ids=shortcut_ids)

    return dict(
        status='passed',
        site=str(root),
        reference_pages=len(pages),
        tutorials=len(tutorials),
        available_collections=['reference', 'guide', 'tutorials'],
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

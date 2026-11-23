#!/usr/bin/env python3
"""Check the final seven tutorials and the consolidated collection.

The default checks source only. --files also checks the complete example inventory.
--runtime runs Racket presentation/reader tests and two Skia-free Scribble smoke pages.
--render renders tutorials 16–22; --render-all renders all 22 and the index. Both imply
--runtime and --files. --html-root inspects that render layout. --published-root checks
a registered installation's Skia manual directories, source downloads and local links.
No option opens a GUI, performs GPU rendering, or checks external websites.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
SLUGS = ('navigation', 'shaders', 'pixels', 'color-spaces', 'path-ops', 'sprites', 'squadron')
COUNTS = dict(zip(SLUGS, (6, 12, 7, 5, 10, 5, 8)))


def load_checker(name: str):
    path = Path(__file__).with_name(name)
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f'cannot load checker: {path}')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = load_checker('check-3b.py')
figures = load_checker('check-3c.py')
middle = load_checker('check-3d.py')
need = figures.need
ALL_SLUGS = (*figures.SLUGS, *middle.SLUGS, *SLUGS)
manual_path = figures.manual_path


def check_source(root: Path) -> dict:
    rows = {}
    sources = {}
    for slug in SLUGS:
        text = manual_path(root, slug).read_text(encoding='utf-8')
        sources[slug] = text
        alternatives = figures.source_alternatives(text)
        need(len(alternatives) == COUNTS[slug], f'{slug}: missing or extra described figure')
        need('"../support/accessible-figures.rkt"' in text, f'{slug}: missing figure import')
        need(text.index('@(tutorial-figure') < text.index(f'@tutorial-entry["{slug}"]'),
             f'{slug}: setup precedes the finished result')
        for helper in ('tutorial-entry', 'tutorial-next', 'tutorial-sources'):
            need(text.count(f'@{helper}["{slug}"]') == 1, f'{slug}: lost reader navigation')
        for tag in ('finished-result', 'try-it', 'next-steps', 'example-source'):
            need(text.count(f'#:tag "{tag}"') == 1, f'{slug}: missing or duplicate {tag}')
        calls = re.findall(r'^@\(([\w-]+)', text, re.M)
        need(all(name in ('require', 'define-runtime-path', 'tutorial-figure',
                         'tutorial-navigation') for name in calls),
             f'{slug}: figure bypasses descriptive markup')
        need(not re.search(r'documentation build|real Skia renderings|not screenshots|'
                           r'hand-chosen gray|independent color constants', text),
             f'{slug}: production commentary remains')
        need(not re.search(r'Tutorial \d+|@tt\{[^}]*--', text),
             f'{slug}: numbered prerequisite or nonliteral command option')
        rows[slug] = dict(described_figures=len(alternatives), alternatives=alternatives)

    shaders = sources['shaders']
    first = middle.section(shaders, 'Start with a Constant Color')
    for code in ('(define solid-surface (make-surface 320 180))',
                 '(define solid-paint (make-paint #:shader solid-shader))',
                 '(draw-rect (surface-canvas solid-surface) 0 0 320 180 solid-paint)'):
        need(code in first, f'missing first-shader drawing step: {code}')
    need(first.index('solid-paint') < first.index('@(tutorial-figure'), 'late shader/paint bridge')
    need("SkSL is Skia's shading language" in shaders, 'SkSL is not introduced')
    bands = middle.section(shaders, 'Make Repeating Bands')
    need('from -1 to 1' in bands and '0.5 + 0.5 * sin(...)' in bands,
         'sine range and remapping are not distinguished')
    need('Hue shifts the highlights' in shaders and 'angle-dependent lighting' in shaders,
         'hue control still implies color-only changes')
    need('upload' not in sources['pixels'].lower(), 'CPU writes still called uploads')
    for term in ('primaries', 'transfer function', 'tagged image'):
        need(f'@emph{{{term}}}' in sources['color-spaces'], f'undefined color-space term: {term}')
    sprites = sources['sprites']
    need(sprites.index('(reflect-axis 9 4 0 10 1)')
         < sprites.index("(source-definition model-source 'reflect-axis)"),
         'reflection formula precedes the one-bounce explanation')
    need('@subsection{The Supplied Motion Helper}' in sprites, 'motion helper is not distinguished')
    for rule in ('must not be retained', 'different context is rejected',
                 'then closes its', '1/120-second'):
        need(rule in sprites, f'lost sprite ownership or clock rule: {rule}')
    squadron = sources['squadron']
    need('uniform scale' in squadron and 'uncompressed' not in squadron,
         'dive diagram still needs mental rescaling')
    diagram = (root / 'scribblings/tutorials/squadron/eval.rkt').read_text(encoding='utf-8')
    need('(canvas-scale! canvas diagram-scale diagram-scale)' in diagram,
         'dive paths and sprites do not share a uniform scale')
    need('(make-atlas-transform x y' in diagram and '(* y 0.66)' not in diagram,
         'dive sprite positions retain a different vertical scale')
    need('#:rotation (enemy-angle sprite 0)' in diagram, 'game heading calculation changed')
    return rows


def check_collection(root: Path, *, files: bool = False) -> dict:
    structure = reader.check_structure(root)
    early = figures.check_source(root)
    central = middle.check_source(root)
    late = check_source(root)
    total = sum(row['described_figures'] for row in (*early.values(), *central.values(),
                                                    *late.values()))
    need(total == 161, 'collection lost an original described figure')
    report = dict(navigation=structure, early=early, middle=central, late=late,
                  described_original_figures=total, expected_rendered_placements=total + 8)
    if files:
        report['example_files'] = reader.check_files(root)
    return report


def expected_alternatives(root: Path, slug: str) -> list[str]:
    alts = figures.source_alternatives(manual_path(root, slug).read_text(encoding='utf-8'))
    if slug in figures.SLUGS:
        alts = [alts[figures.FINISHED[slug] - 1], *alts]
    return alts


def inspect_tree(root: Path, directory: Path, *, all_lessons: bool = False,
                 strict_links: bool = False) -> dict:
    slugs = ALL_SLUGS if all_lessons else SLUGS
    return {slug: middle.inspect_html(directory / slug / (slug + '.html'),
                                      expected_alternatives(root, slug), strict_links=strict_links)
            for slug in slugs}


def local_target(page: Path, href: str) -> tuple[Path, str] | None:
    """Resolve a local HTML/resource link; do not claim to check external destinations."""
    url = urlsplit(href)
    if url.scheme or url.netloc:
        return None
    target = (page.parent / unquote(url.path)).resolve() if url.path else page.resolve()
    return target, unquote(url.fragment)


def inspect_publication(root: Path, directory: Path, *, strict_links: bool = False) -> dict:
    """Inspect only Skia manuals, plus local destinations reached by their reader links."""
    rows = json.loads((root / reader.CATALOG).read_text(encoding='utf-8'))['tutorials']
    pages = {row['id']: directory / ('skia-tutorial-' + row['id']) / 'index.html' for row in rows}
    index = directory / 'skia-tutorials/index.html'
    need(index.is_file(), f'missing registered tutorial index: {index}')
    parsed = {path.resolve(): reader.read_page(path) for path in [index, *pages.values()]}
    index_targets = {target[0] for href in parsed[index.resolve()].nav_links
                     if (target := local_target(index, href)) is not None}
    need({page.resolve() for page in pages.values()} <= index_targets,
         'tutorial index does not link to all 22 lessons')
    results = {}
    for row in rows:
        slug = row['id']
        path = pages[slug]
        page = parsed[path.resolve()]
        need(page.markers == reader.MARKERS, f'{slug}: missing rendered reader section')
        need(page.nav_badlinks == 0 and bool(page.nav_links), f'{slug}: unresolved reader links')
        need(len(page.source_links) == len(row['files']), f'{slug}: incomplete source download set')
        for href, relative in zip(page.source_links, row['files']):
            target = local_target(path, href)
            need(target is not None, f'{slug}: non-local source download: {href}')
            source = reader.source_path(root, relative)
            need(target[0].is_file(), f'{slug}: missing source download: {href}')
            need(target[0].read_bytes() == source.read_bytes(), f'{slug}: stale source: {relative}')
        results[slug] = middle.inspect_html(path, expected_alternatives(root, slug),
                                            strict_links=strict_links)
        reader.check_commands(page) if page.commands else None
    # Include links leaving the index as well as prerequisites and next steps in each lesson.
    for path, page in list(parsed.items()):
        for href in page.nav_links:
            resolved = local_target(path, href)
            if resolved is None:
                need(not strict_links or not href.startswith('file:'), f'machine-local link: {href}')
                continue
            target, fragment = resolved
            need(target.is_file(), f'missing reader destination: {path}: {href}')
            if fragment:
                if target not in parsed:
                    parsed[target] = reader.read_page(target)
                need(fragment in parsed[target].anchors, f'missing reader anchor: {path}: {href}')
    if strict_links:
        index_page = parsed[index.resolve()]
        need(index_page.badlinks == 0 and index_page.file_links == 0,
             'index has unresolved or machine-specific links')
    return dict(lessons=results, source_downloads='byte-verified',
                reader_links='local targets checked',
                strict_links=strict_links, external_websites='not checked')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--files', action='store_true')
    parser.add_argument('--runtime', action='store_true')
    parser.add_argument('--render', action='store_true')
    parser.add_argument('--render-all', action='store_true')
    parser.add_argument('--racket', default='racket')
    parser.add_argument('--html-root', type=Path)
    parser.add_argument('--all-lessons', action='store_true', help='inspect all 22 with --html-root')
    parser.add_argument('--published-root', type=Path, help='parent of registered manual directories')
    parser.add_argument('--strict-links', action='store_true', help='reject badlink and file: links')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    if args.output is None:
        (root / 'output').mkdir(exist_ok=True)
        output = Path(tempfile.mkdtemp(prefix='tutorials-3e-', dir=root / 'output'))
    else:
        output = args.output.resolve()
        need(not output.exists() or (output.is_dir() and not any(output.iterdir())),
             'use a fresh output directory; do not mix evidence from different runs')
        output.mkdir(parents=True, exist_ok=True)
    report = dict(status='failed', commands=[], runtime='not executed', full_manuals='not executed',
                  native_examples='not executed separately', gui_gpu='not executed',
                  installed_documentation='not executed', external_websites='not checked')

    def run(name: str, command: list[str], timeout: int = 240) -> None:
        log = output / (name + '.log')
        record = dict(name=name, command=command, status='running', log=log.name)
        report['commands'].append(record)
        try:
            result = subprocess.run(command, cwd=root, capture_output=True, text=True,
                                    encoding='utf-8', errors='replace', timeout=timeout)
            log.write_text(result.stdout + result.stderr, encoding='utf-8')
            record['returncode'] = result.returncode
            need(result.returncode == 0, f'{name} failed; see {log}')
            record['status'] = 'passed'
        except Exception as error:
            record.update(status='failed', error=str(error))
            if not log.exists():
                log.write_text(str(error) + '\n', encoding='utf-8')
            raise

    try:
        report['source'] = check_collection(root)
        wants_render = args.render or args.render_all
        wants_runtime = args.runtime or wants_render
        racket = None
        if wants_runtime:
            racket = shutil.which(args.racket)
            need(racket is not None, f'Racket executable not found: {args.racket}')
        if args.files or wants_render or args.published_root:
            report['example_files'] = reader.check_files(root)
        if args.html_root:
            report['supplied_html'] = inspect_tree(root, args.html_root,
                                                   all_lessons=args.all_lessons,
                                                   strict_links=args.strict_links)
        if args.published_root:
            report['installed_documentation'] = inspect_publication(
                root, args.published_root.resolve(), strict_links=args.strict_links)
        if wants_runtime:
            raco = [racket, '-l', 'raco', '--']
            tutorials = root / 'scribblings/tutorials'
            support = tutorials / 'support'
            run('racket-version', [racket, '--version'])
            run('helper-tests', [*raco, 'test', str(tutorials / 'reader-test.rkt'),
                                 str(tutorials / 'registration-test.rkt'),
                                 str(support / 'accessible-figures-test.rkt')])
            for name, inspect in (('reader-smoke', reader.check_smoke),
                                  ('early-figures-smoke', figures.check_smoke)):
                folder = output / name
                folder.mkdir()
                run(name, [*raco, 'scribble', '--html', '--dest', str(folder),
                           str(support / (name + '.scrbl'))])
                report[name] = inspect(folder / (name + '.html'))
            report['runtime'] = 'passed: helper tests and Skia-free smoke pages'
        if wants_render:
            slugs = ALL_SLUGS if args.render_all else SLUGS
            docs = output / 'html'
            for slug in slugs:
                manual = manual_path(root, slug)
                folder = docs / slug
                folder.mkdir(parents=True)
                run(slug + '-compile', [*raco, 'make', str(manual)])
                run(slug + '-render', [*raco, 'scribble', '--html', '--dest', str(folder),
                                       '--redirect-main', 'https://docs.racket-lang.org/',
                                       str(manual)])
            if args.render_all:
                folder = docs / 'tutorials'
                folder.mkdir()
                run('index-render', [*raco, 'scribble', '--html', '--dest', str(folder),
                                     str(root / 'scribblings/tutorials/index.scrbl')])
            report['rendered_html'] = inspect_tree(root, docs, all_lessons=args.render_all,
                                                    strict_links=args.strict_links)
            report['full_manuals'] = f'passed: {len(slugs)} manuals'
        report['status'] = 'passed'
    except Exception as error:
        report['error'] = str(error)
        print(f'FAILED: {error}')
    finally:
        (output / 'validation.json').write_text(json.dumps(report, indent=2) + '\n',
                                                encoding='utf-8')
        print(f'Validation record: {output}')
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())

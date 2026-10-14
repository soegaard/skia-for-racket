#!/usr/bin/env python3
"""Validate Reference sources, real bindings, and fresh or installed links.

Default: check sources against pinned export inventories. --documents-only is a
limited check for a partial source fixture. No mode silently skips requested Racket work.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import uuid

from reference_support import CheckError, check_evidence, check_source, check_targets, prepare_site
from reference_review import (check_review_html, inspect_link_scopes, package_review,
                              package_source_review, source_hashes)

ROOT = Path(__file__).resolve().parents[1]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--documents-only', action='store_true')
    modes.add_argument('--render', action='store_true',
                       help='render Reference, its three linked tutorials, and binding-link probe')
    modes.add_argument('--installed', type=Path, help='check a freshly built installed doc directory')
    modes.add_argument('--site', type=Path, help='relocate and check the staged Pages site')
    parser.add_argument('--targets', type=Path,
                        help='runtime.json from the installed check, for --site')
    parser.add_argument('--site-source', type=Path,
                        help='original installed doc root for file: links')
    parser.add_argument('--quick', action='store_true', help='also render the actual Quick tutorial')
    parser.add_argument('--native', action='store_true', help='also execute CPU resource/PNG tests')
    parser.add_argument('--require-complete', action='store_true', help='reject any deferred export')
    parser.add_argument('--racket', default='racket')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--review-zip', type=Path,
                        help='package checked HTML and sources after --render or --installed')
    parser.add_argument('--source-zip', type=Path,
                        help='package all inputs for the non-native source checker')
    args = parser.parse_args(argv)
    if args.source_zip and (args.documents_only or args.render or args.installed or args.site
                            or args.quick or args.native or args.review_zip):
        parser.error('--source-zip requires ordinary source-only validation')
    if args.review_zip and not (args.render or args.installed):
        parser.error('--review-zip requires --render or --installed')
    if args.quick and not args.render:
        parser.error('--quick requires --render; installed and site modes always check Quick')
    if args.site and args.native:
        parser.error('--native cannot be combined with --site')
    if args.site and (not args.targets or not args.site_source):
        parser.error('--site requires --targets and --site-source')
    if not args.site and (args.targets or args.site_source):
        parser.error('--targets and --site-source require --site')
    if args.documents_only and (args.native or args.require_complete):
        parser.error('documents-only is not runtime or complete-inventory validation')
    output = (args.output or ROOT.parent / ('skia-reference-check-' + uuid.uuid4().hex)).resolve()
    if output == ROOT or ROOT in output.parents:
        parser.error('keep validation output outside the source checkout')
    output.mkdir(parents=True, exist_ok=False)
    before = None
    report = dict(source_sha256={}, status='running', commands=[],
                  native_executed=False, gpu_executed=False,
                  racket_executed=False, scribble_rendered=False, quick_rendered=False,
                  reference_html_checked=False,
                  installed_checked=False, site_checked=False, tutorial_manuals_rendered=[])

    def save():
        (output / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')

    def run(label, command):
        entry = dict(label=label, command=list(map(str, command)), status='running', executed=False)
        report['commands'].append(entry)
        save()
        log = output / (label + '.log')
        try:
            with log.open('w', encoding='utf-8') as out:
                out.write('$ ' + repr(entry['command']) + '\n')
                out.flush()
                result = subprocess.run(entry['command'], cwd=ROOT, stdout=out,
                                        stderr=subprocess.STDOUT, timeout=600, check=False)
            entry['executed'] = True
            entry['returncode'] = result.returncode
            entry['status'] = 'passed' if result.returncode == 0 else 'failed'
            if result.returncode:
                raise CheckError(f'{label} failed; see {log}')
        except subprocess.TimeoutExpired:
            entry['executed'] = True
            entry['status'] = 'failed'
            raise
        except Exception:
            entry['status'] = 'failed'
            raise
        finally:
            report['racket_executed'] = any(item['executed'] for item in report['commands'])
            report['native_executed'] = (
                any(item['label'] == 'native-cpu' and item['executed'] for item in report['commands'])
                or any(name != 'skia-tutorials' for name in report['tutorial_manuals_rendered'])
                or report['quick_rendered'])
            save()

    try:
        review_inputs = bool(args.review_zip or args.source_zip)
        before = source_hashes(ROOT, review_inputs=review_inputs)
        report['source_sha256'] = before
        source = check_source(ROOT, documents_only=args.documents_only,
                              require_complete=args.require_complete)
        report['source'] = {k: v for k, v in source.items() if k not in ('definitions', 'deferred')}
        specs = output / 'source.json'
        specs.write_text(json.dumps(source, indent=2) + '\n')
        save()
        if args.site:
            report['redirects_relocated'] = prepare_site(args.site, source_root=args.site_source)
            targets = json.loads(args.targets.read_text(encoding='utf-8'))
            check_evidence(source, targets, installed=True)
            report['links'] = check_targets(
                args.site, targets, quick=args.site / 'skia-tutorial-quick/index.html')
            report['site_checked'] = True
        elif args.render or args.installed or args.native:
            racket = shutil.which(args.racket)
            if racket is None:
                raise CheckError('Racket executable not found: ' + args.racket)
            run('racket-version', [racket, '--version'])
            report['racket_executed'] = True
            runtime = [racket, ROOT / 'tools/reference-runtime.rkt', '--specs', specs]
            run('bindings', [*runtime, '--output', output / 'bindings.json'])
            run('render-driver-tests', [racket, '-l', 'raco', '--', 'test',
                                        ROOT / 'tools/reference-render.rkt'])
            run('color-tests', [racket, '-l', 'raco', '--', 'test',
                                ROOT / 'tools/reference-color-test.rkt'])
            run('blob-value-tests', [racket, '-l', 'raco', '--', 'test',
                                    ROOT / 'tools/reference-blob-values-test.rkt'])
            run('text-pure-tests', [racket, '-l', 'raco', '--', 'test',
                                    ROOT / 'tools/reference-text-pure-test.rkt'])
            run('effects-pure-tests', [racket, '-l', 'raco', '--', 'test',
                                       ROOT / 'tools/reference-effects-pure-test.rkt'])
            run('color-management-pure-tests',
                [racket, '-l', 'raco', '--', 'test',
                 ROOT / 'tools/reference-color-management-pure-test.rkt'])
            run('output-pure-tests', [racket, '-l', 'raco', '--', 'test',
                                      ROOT / 'tools/reference-output-pure-test.rkt'])
            run('io-pure-tests', [racket, '-l', 'raco', '--', 'test',
                                  ROOT / 'tools/reference-io-pure-test.rkt'])
            run('matrix-tests', [racket, '-l', 'raco', '--', 'test',
                                 ROOT / 'tools/reference-matrix-test.rkt'])
            if args.render or args.installed:
                site = args.installed.resolve() if args.installed else output
                reference = site / 'skia-reference'
                scribble = [racket, ROOT / 'tools/reference-render.rkt', '+m']
                xref = output / 'reference.sxref'
                tutorial_xrefs = []
                if args.render:
                    # The seed supplies Reference targets to companion tutorials. Their
                    # real xrefs then resolve the three outgoing links in the final build.
                    seed = output / 'reference-seed.sxref'
                    reference_command = [*scribble, '--htmls', '--dest', output,
                                         '--dest-name', 'skia-reference', '--redirect-main',
                                         'https://docs.racket-lang.org/']
                    document = 'skia/scribblings/reference/reference.scrbl'
                    run('reference-seed', [*reference_command, '--info-out', seed, '--lib', document])
                    for link in source['tutorial_links']:
                        name = link['directory']
                        destination = output / name
                        destination.mkdir()
                        saved = output / (name + '.sxref')
                        run(name, [*scribble, '++info-in', seed, '--html', '--dest', destination,
                                   '--dest-name', 'index', '--redirect-main',
                                   'https://docs.racket-lang.org/', '--info-out', saved, '--lib',
                                   'skia/' + link['manual']])
                        tutorial_xrefs.append(saved)
                        report['tutorial_manuals_rendered'].append(name)
                        if name != 'skia-tutorials':
                            report['native_executed'] = True
                        save()
                    imports = [part for file in tutorial_xrefs for part in ('++info-in', file)]
                    run('reference', [*reference_command, *imports, '--info-out', xref,
                                      '--lib', document])
                    report['scribble_rendered'] = True
                inputs = [] if args.installed else ['++info-in', xref]
                probe = output / 'probe'
                probe.mkdir()
                run('link-probe', [*scribble, *inputs, '--html', '--dest', probe,
                                   '--dest-name', 'links',
                                   '--redirect-main', 'https://docs.racket-lang.org/', '--lib',
                                   'skia/scribblings/reference/tests/links.scrbl'])
                evidence = output / 'runtime.json'
                options = (['--installed'] if args.installed else
                           ['--xref-file', xref, *[arg for file in tutorial_xrefs
                                                   for arg in ('--tutorial-xref', file)]])
                run('xref', [*runtime, '--output', evidence, '--reference-dir', reference, *options])
                quick = site / 'skia-tutorial-quick/index.html' if args.installed else None
                if args.quick:
                    quick = output / 'skia-tutorial-quick/index.html'
                    quick.parent.mkdir()
                    run('quick', [*scribble, *inputs, '--html', '--dest', quick.parent,
                                  '--dest-name', 'index', '--redirect-main',
                                  'https://docs.racket-lang.org/', '--lib',
                                  'skia/scribblings/quick/quick.scrbl'])
                    report['quick_rendered'] = True
                targets = json.loads(evidence.read_text())
                check_evidence(source, targets, installed=bool(args.installed))
                report['links'] = check_targets(site, targets,
                                                smoke=probe / 'links.html', quick=quick)
                report['installed_checked'] = bool(args.installed)
            if args.native:
                run('native-cpu', [racket, '-l', 'raco', '--', 'test',
                                    ROOT / 'tools/reference-native-test.rkt',
                                    ROOT / 'tools/reference-core-test.rkt',
                                    ROOT / 'tools/reference-text-test.rkt',
                                    ROOT / 'tools/reference-blobs-test.rkt',
                                    ROOT / 'tools/reference-effects-test.rkt',
                                    ROOT / 'tools/reference-color-management-test.rkt',
                                    ROOT / 'tools/reference-output-test.rkt',
                                    ROOT / 'tools/reference-io-test.rkt'])
                report['native_executed'] = True
        if source_hashes(ROOT, review_inputs=review_inputs) != before:
            raise CheckError('Reference sources changed during validation')
        if args.render or args.installed or args.site:
            html_site = args.site if args.site else site
            report['html_link_scopes'] = inspect_link_scopes(html_site)
            # Installed manuals may link outside this package to other local manuals.
            # Their existing xref check remains separate from portable publication.
            if args.render or args.site:
                report['reference_html'] = check_review_html(html_site)
                report['reference_html_checked'] = True
        if args.source_zip:
            report['source_zip'] = package_source_review(ROOT, args.source_zip, before)
        if args.review_zip:
            report['review_zip'] = package_review(
                ROOT, site, source, targets, args.review_zip, before,
                quick=bool(args.quick or args.installed))
        report['status'] = 'passed'
    except Exception as error:
        report['status'] = 'failed'
        report['error'] = f'{type(error).__name__}: {error}'
        print(report['error'], file=sys.stderr)
    finally:
        save()
    print(f'Reference checks: {report["status"]}; evidence: {output}')
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())

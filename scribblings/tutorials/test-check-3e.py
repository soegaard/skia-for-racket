#!/usr/bin/env python3
"""Source and synthetic-HTML regressions; these tests do not execute Racket or Skia."""
from __future__ import annotations

import html
import importlib.util
import json
import math
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('check_3e', Path(__file__).with_name('check-3e.py'))
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
legacy = checker.load_checker('check-21-22.py')
ROOT = checker.ROOT


def png(path: Path) -> None:
    # A synthetic PNG header, sufficient for the resource inspector, not a rendered PNG.
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR'
                     + struct.pack('>II', 12, 8))


def images(alternatives: list[str]) -> str:
    return ''.join('<img class="skia-tutorial-figure" src="panel.png" width="12" '
                   'height="8" alt="' + html.escape(text, quote=True) + '">'
                   for text in alternatives)


class SourceChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'source'
        shutil.copytree(ROOT / 'scribblings', self.root / 'scribblings',
                        ignore=shutil.ignore_patterns('__pycache__', 'compiled'))

    def change(self, slug: str, old: str, new: str):
        path = checker.manual_path(self.root, slug)
        text = path.read_text(encoding='utf-8')
        self.assertIn(old, text)
        path.write_text(text.replace(old, new, 1), encoding='utf-8')

    def reject(self):
        with self.assertRaises(ValueError):
            checker.check_source(self.root)

    def test_all_22_sources(self):
        result = checker.check_collection(self.root)
        self.assertEqual(result['navigation']['lessons'], 22)
        self.assertEqual(result['navigation']['source_files'], 43)
        self.assertEqual(result['described_original_figures'], 161)
        self.assertEqual(result['expected_rendered_placements'], 169)

    def test_seven_expected_counts(self):
        result = checker.check_source(self.root)
        self.assertEqual([row['described_figures'] for row in result.values()],
                         [6, 12, 7, 5, 10, 5, 8])

    def test_missing_paint_bridge(self):
        self.change('shaders', '(define solid-paint (make-paint #:shader solid-shader))', '')
        self.reject()

    def test_missing_surface_bridge(self):
        self.change('shaders', '(define solid-surface (make-surface 320 180))', '')
        self.reject()

    def test_sine_range_regression(self):
        self.change('shaders', 'from -1 to 1', 'from 0 to 1')
        self.reject()

    def test_missing_remapping(self):
        self.change('shaders', '0.5 + 0.5 * sin(...)', 'sin(...)')
        self.reject()

    def test_hue_qualification(self):
        self.change('shaders', 'Hue shifts the highlights', 'Hue changes only color')
        self.reject()

    def test_unexplained_sksl(self):
        self.change('shaders', "SkSL is Skia's shading language", 'A shader is a program')
        self.reject()

    def test_cpu_upload_regression(self):
        self.change('pixels', 'The write copies', 'The upload copies')
        self.reject()

    def test_missing_color_definition(self):
        self.change('color-spaces', '@emph{primaries}', 'primaries')
        self.reject()

    def test_bounce_example_before_formula(self):
        self.change('sprites', '@subsection{The Supplied Motion Helper}', '@subsection{Formula}')
        self.reject()

    def test_missing_figure(self):
        self.change('navigation', '@(tutorial-figure', '@(undescribed-figure')
        self.reject()

    def test_missing_opening_tag(self):
        self.change('navigation', '#:tag "finished-result"', '#:tag "other"')
        self.reject()

    def test_missing_navigation(self):
        self.change('path-ops', '@tutorial-next["path-ops"]', '')
        self.reject()

    def test_production_commentary(self):
        self.change('shaders', 'The three pictures show', 'The real Skia renderings show')
        self.reject()

    def test_numbered_prerequisite(self):
        self.change('navigation', '@tutorial-link["interaction"]', 'Tutorial 15')
        self.reject()

    def test_nonliteral_option(self):
        self.change('sprites', '@command-text["--renderer raster"]', '@tt{--renderer raster}')
        self.reject()

    def test_anisotropic_dive_rejected(self):
        path = self.root / 'scribblings/tutorials/squadron/eval.rkt'
        text = path.read_text().replace('canvas diagram-scale diagram-scale',
                                        'canvas 1 diagram-scale')
        path.write_text(text)
        self.reject()

    def test_heading_rewrite_rejected(self):
        path = self.root / 'scribblings/tutorials/squadron/eval.rkt'
        path.write_text(path.read_text().replace('(enemy-angle sprite 0)', '0'))
        self.reject()

    def test_early_preview_reuses_final_alternative(self):
        for slug in checker.figures.SLUGS:
            original = checker.figures.source_alternatives(
                checker.manual_path(self.root, slug).read_text())
            expected = checker.expected_alternatives(self.root, slug)
            self.assertEqual(expected[0], original[checker.figures.FINISHED[slug] - 1])
            self.assertEqual(expected[1:], original)


class HtmlChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.page = self.root / 'test.html'
        self.alt = ['A synthetic panel with one described shape.']
        png(self.root / 'panel.png')

    def write(self, text: str) -> Path:
        self.page.write_text(text, encoding='utf-8')
        return self.page

    def inspect(self, body: str, *, strict: bool = False):
        return checker.middle.inspect_html(self.write(body), self.alt, strict_links=strict)

    def test_marked_resource_with_nonlegacy_name(self):
        result = legacy.inspect_html(self.write(images(self.alt)), 1)
        self.assertEqual(result['figures'][0]['file'], 'panel.png')

    def test_marked_duplicate_placements_counted(self):
        self.assertEqual(len(legacy.inspect_html(self.write(images(self.alt * 2)), 2)['figures']), 2)

    def test_legacy_names_still_work(self):
        png(self.root / 'pict.png')
        result = legacy.inspect_html(self.write('<img src="pict.png">'), 1)
        self.assertEqual(len(result['figures']), 1)

    def test_unmarked_arbitrary_png_not_a_figure(self):
        with self.assertRaises(ValueError):
            legacy.inspect_html(self.write('<img src="panel.png">'), 1)

    def test_marker_must_be_complete_class_token(self):
        with self.assertRaises(ValueError):
            legacy.inspect_html(self.write(images(self.alt).replace('figure"', 'figure-extra"')), 1)

    def test_external_marked_image_does_not_count(self):
        with self.assertRaises(ValueError):
            legacy.inspect_html(self.write(images(self.alt).replace('panel.png',
                                'https://example.invalid/panel.png')), 1)

    def test_image_count_regression(self):
        with self.assertRaises(ValueError):
            legacy.inspect_html(self.write(images(self.alt)), 2)

    def test_correct_alternative_and_size(self):
        self.assertEqual(self.inspect(images(self.alt))['figures'], 1)

    def test_missing_resource(self):
        (self.root / 'panel.png').unlink()
        with self.assertRaises(ValueError):
            self.inspect(images(self.alt))

    def test_wrong_alternative(self):
        with self.assertRaises(ValueError):
            self.inspect(images(['Another unrelated synthetic figure.']))

    def test_bad_dimension(self):
        for value in ('0', '-1', 'nan', 'inf', 'not-a-size'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.inspect(images(self.alt).replace('width="12"', f'width="{value}"'))

    def test_evaluation_errors_are_not_badlinks(self):
        with self.assertRaises(ValueError):
            self.inspect(images(self.alt) + '<span class="RktErr">error</span>')
        result = self.inspect(images(self.alt) + '<span class="badlink">reference</span>')
        self.assertEqual(result['unresolved_references'], 1)
        self.assertEqual(result['racket_error_elements'], 0)

    def test_strict_links(self):
        with self.assertRaises(ValueError):
            self.inspect(images(self.alt) + '<span class="badlink">reference</span>', strict=True)

    def test_file_links_reported_separately(self):
        body = images(self.alt) + '<a href="file:///tmp/reference.html">reference</a>'
        self.assertEqual(self.inspect(body)['machine_local_links'], 1)
        with self.assertRaises(ValueError):
            self.inspect(body, strict=True)

    def test_all_tree_169_placements(self):
        for slug in checker.ALL_SLUGS:
            folder = self.root / slug
            folder.mkdir()
            png(folder / 'panel.png')
            (folder / (slug + '.html')).write_text(
                images(checker.expected_alternatives(ROOT, slug)), encoding='utf-8')
        result = checker.inspect_tree(ROOT, self.root, all_lessons=True)
        self.assertEqual(sum(row['figures'] for row in result.values()), 169)
        (self.root / 'squadron/squadron.html').unlink()
        with self.assertRaises(FileNotFoundError):
            checker.inspect_tree(ROOT, self.root, all_lessons=True)

    def test_local_target_handles_encoded_anchor(self):
        target = checker.local_target(self.page, 'other.html#x%20y')
        self.assertEqual(target, (self.root / 'other.html', 'x y'))
        self.assertIsNone(checker.local_target(self.page, 'https://example.invalid/'))


class PublicationChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'source'
        self.docs = Path(self.temp.name) / 'docs'
        shutil.copytree(ROOT / 'scribblings', self.root / 'scribblings',
                        ignore=shutil.ignore_patterns('__pycache__', 'compiled'))
        rows = json.loads((self.root / checker.reader.CATALOG).read_text())['tutorials']
        for row in rows:
            folder = self.docs / ('skia-tutorial-' + row['id'])
            folder.mkdir(parents=True)
            png(folder / 'panel.png')
            links = []
            for index, relative in enumerate(row['files']):
                source = checker.reader.source_path(self.root, relative)
                source.parent.mkdir(parents=True, exist_ok=True)
                source.write_bytes(('Synthetic fixture: ' + relative).encode())
                name = f'asset-{index}.txt'
                (folder / name).write_bytes(source.read_bytes())
                links.append(f'<span class="skia-reader-source-link"><a href="{name}">'
                             f'{relative}</a></span>')
            body = images(checker.expected_alternatives(self.root, row['id']))
            body += '<p class="skia-reader-prerequisites"><a '
            body += 'href="../skia-tutorials/index.html#top">Index</a></p>'
            body += '<p class="skia-reader-next">Next steps</p>'
            body += '<p class="skia-reader-sources">' + ''.join(links) + '</p>'
            (folder / 'index.html').write_text(body, encoding='utf-8')
        index = self.docs / 'skia-tutorials/index.html'
        index.parent.mkdir()
        index_links = ''.join(f'<a href="../skia-tutorial-{row["id"]}/index.html">'
                              f'{row["id"]}</a>' for row in rows)
        index.write_text('<h1 id="top">Index</h1><span class="skia-reader-navigation">'
                         + index_links + '</span>')

    def inspect(self, strict=False):
        return checker.inspect_publication(self.root, self.docs, strict_links=strict)

    def test_registered_layout_with_source_bytes(self):
        result = self.inspect(strict=True)
        self.assertEqual(len(result['lessons']), 22)
        self.assertEqual(result['source_downloads'], 'byte-verified')
        self.assertEqual(result['external_websites'], 'not checked')

    def test_stale_download(self):
        (self.docs / 'skia-tutorial-quick/asset-0.txt').write_text('stale')
        with self.assertRaisesRegex(ValueError, 'stale source'):
            self.inspect()

    def test_missing_download(self):
        (self.docs / 'skia-tutorial-images/asset-0.txt').unlink()
        with self.assertRaisesRegex(ValueError, 'missing source download'):
            self.inspect()

    def test_missing_anchor(self):
        index = self.docs / 'skia-tutorials/index.html'
        index.write_text(index.read_text().replace('id="top"', 'id="other"'))
        with self.assertRaisesRegex(ValueError, 'missing reader anchor'):
            self.inspect()

    def test_unresolved_navigation(self):
        page = self.docs / 'skia-tutorial-quick/index.html'
        text = page.read_text().replace('class="skia-reader-prerequisites"',
                                       'class="skia-reader-prerequisites badlink"')
        page.write_text(text)
        with self.assertRaisesRegex(ValueError, 'unresolved reader links'):
            self.inspect()

    def test_incomplete_index(self):
        index = self.docs / 'skia-tutorials/index.html'
        index.write_text(index.read_text().replace('../skia-tutorial-quick/index.html', '#top'))
        with self.assertRaisesRegex(ValueError, 'index does not link'):
            self.inspect()

    def test_strict_index_reference_failure(self):
        index = self.docs / 'skia-tutorials/index.html'
        index.write_text(index.read_text() + '<span class="badlink">missing API</span>')
        with self.assertRaisesRegex(ValueError, 'index has unresolved'):
            self.inspect(strict=True)


class ArithmeticChecks(unittest.TestCase):
    def test_remapped_sine(self):
        # Arithmetic evidence only; this does not execute the shader.
        self.assertAlmostEqual(0.5 + 0.5 * math.sin(-math.pi / 2), 0)
        self.assertAlmostEqual(0.5 + 0.5 * math.sin(0), 0.5)
        self.assertAlmostEqual(0.5 + 0.5 * math.sin(math.pi / 2), 1)

    def test_uniform_scale_preserves_directions(self):
        for degrees in range(360):
            angle = math.radians(degrees)
            dx, dy = math.cos(angle), math.sin(angle)
            self.assertAlmostEqual(math.atan2(0.66 * dy, 0.66 * dx), math.atan2(dy, dx))


class RunnerChecks(unittest.TestCase):
    def test_missing_runtime_is_not_reported_as_executed(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'evidence'
            result = subprocess.run([sys.executable, '-B', str(Path(checker.__file__)),
                                     '--runtime', '--racket', str(Path(directory) / 'no-racket'),
                                     '--output', str(output)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            report = json.loads((output / 'validation.json').read_text())
            self.assertEqual(report['commands'], [])
            self.assertEqual(report['runtime'], 'not executed')
            self.assertIn('Racket executable not found', report['error'])

    def test_output_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            sentinel = Path(directory) / 'keep.txt'
            sentinel.write_text('keep')
            result = subprocess.run([sys.executable, '-B', str(Path(checker.__file__)),
                                     '--output', directory], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(sentinel.read_text(), 'keep')
            self.assertFalse((Path(directory) / 'validation.json').exists())


if __name__ == '__main__':
    unittest.main()

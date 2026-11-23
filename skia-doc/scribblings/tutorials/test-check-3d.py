#!/usr/bin/env python3
"""Python regressions for the middle-tutorial source and HTML checker.

HTML and PNG headers below are synthetic fixtures, not Scribble or Skia output.
"""
import importlib.util
from html import escape
from pathlib import Path
import shutil
import struct
import tempfile
import unittest

_spec = importlib.util.spec_from_file_location('check3d', Path(__file__).with_name('check-3d.py'))
checker = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(checker)


class SourceChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for slug in checker.SLUGS:
            target = checker.manual_path(self.root, slug)
            target.parent.mkdir(parents=True)
            shutil.copyfile(checker.manual_path(checker.ROOT, slug), target)

    def reject(self, slug, old, new):
        path = checker.manual_path(self.root, slug)
        text = path.read_text(encoding='utf-8')
        self.assertIn(old, text)
        path.write_text(text.replace(old, new, 1), encoding='utf-8')
        with self.assertRaises(ValueError):
            checker.check_source(self.root)

    def test_all_seven_sources(self):
        rows = checker.check_source(self.root)
        self.assertEqual(list(rows), list(checker.SLUGS))
        self.assertEqual(sum(row['described_figures'] for row in rows.values()), 39)

    def test_missing_figure(self):
        self.reject('effects', '@(tutorial-figure', '@(other-figure')

    def test_missing_reader_entry(self):
        self.reject('pictures', '@tutorial-entry["pictures"]', '@tutorial-entry["effects"]')

    def test_missing_source_access(self):
        self.reject('pictures', '@tutorial-sources["pictures"]', '')

    def test_missing_next_steps(self):
        self.reject('pdf-svg', '@tutorial-next["pdf-svg"]', '')

    def test_missing_finished_tag(self):
        self.reject('gpu', '#:tag "finished-result"', '#:tag "other"')

    def test_production_commentary(self):
        self.reject('effects', 'The main idea is:', 'The documentation build draws this figure.')

    def test_nonliteral_option(self):
        self.reject('animation', '@command-text["--renderer raster"]', '@tt{--renderer raster}')

    def test_recording_limit(self):
        self.reject('pictures', 'recording does not turn those pixels into vector geometry',
                    'recording converts all pixels into vector geometry')

    def test_recording_link(self):
        self.reject('pictures', '@tutorial-link["vector-raster"]', 'another tutorial')

    def test_linux_save_scope(self):
        self.reject('gpu', 'while\n@racket[linux-image] is in scope', 'after the program exits')

    def test_windows_exercise(self):
        self.reject('gpu', '@racket[windows-image] on Windows', 'the Metal image on Windows')

    def test_backend_selection_preserved(self):
        self.reject('animation', '(define (preferred-gpu-backend)', '(define (other-backend)')

    def test_borrowed_frame_rule(self):
        self.reject('animation', 'GPU canvas is borrowed and expires', 'GPU canvas never expires')

    def test_close_order_rule(self):
        self.reject('animation', 'stop the timer before retiring', 'retire without stopping')

    def test_small_client_exercise(self):
        self.reject('interaction', 'a label is hidden', 'all labels are drawn')


class HtmlChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.expected = ['The first panel shows geometry.', 'The second panel shows stored pixels.']
        # Only a minimal header: these bytes are never described as a rendered image.
        (self.root / 'figure.png').write_bytes(
            b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR' + struct.pack('>II', 100, 80))

    def image(self, alt, **overrides):
        values = dict(src='figure.png', alt=alt, width='50', height='40')
        values['class'] = 'skia-tutorial-figure'
        values.update(overrides)
        attrs = ' '.join(f'{key}="{escape(value, quote=True)}"' for key, value in values.items())
        return '<img ' + attrs + '>'

    def html(self, text):
        path = self.root / 'test.html'
        path.write_text(text, encoding='utf-8')
        return path

    def normal(self):
        return ''.join(self.image(text) for text in self.expected)

    def test_descriptions_and_resources(self):
        result = checker.inspect_html(self.html(self.normal()), self.expected)
        self.assertEqual(result['figures'], 2)
        self.assertEqual(result['unresolved_references'], 0)

    def test_reordered_alternatives(self):
        with self.assertRaises(ValueError):
            checker.inspect_html(self.html(self.normal()), list(reversed(self.expected)))

    def test_generic_alternative(self):
        with self.assertRaises(ValueError):
            checker.inspect_html(self.html(self.normal().replace(self.expected[0], 'image')),
                                  self.expected)

    def test_extra_unwrapped_figure(self):
        with self.assertRaises(ValueError):
            checker.inspect_html(self.html(self.normal() + '<img src="pict.png" alt="image">'),
                                  self.expected)

    def test_missing_resource(self):
        with self.assertRaises(ValueError):
            checker.inspect_html(self.html(self.normal().replace('figure.png', 'missing.png')),
                                  self.expected)

    def test_external_resource(self):
        with self.assertRaises(ValueError):
            html = self.normal().replace('figure.png', 'https://x.test/a.png')
            checker.inspect_html(self.html(html), self.expected)

    def test_bad_png_header(self):
        (self.root / 'figure.png').write_bytes(b'not a PNG')
        with self.assertRaises(ValueError):
            checker.inspect_html(self.html(self.normal()), self.expected)

    def test_invalid_display_size(self):
        for value in ('0', '-1', 'nan', 'inf', 'bad'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                text = self.image(self.expected[0], width=value) + self.image(self.expected[1])
                checker.inspect_html(self.html(text), self.expected)

    def test_code_before_opening(self):
        with self.assertRaises(ValueError):
            checker.inspect_html(self.html('<div class="RktBlk"></div>' + self.normal()),
                                  self.expected)

    def test_error_elements_fail(self):
        with self.assertRaises(ValueError):
            checker.inspect_html(self.html(self.normal() + '<span class="RktErr">failure</span>'),
                                  self.expected)

    def test_reference_diagnostics_are_not_hidden(self):
        text = self.normal() + '<a class="extra badlink" href="file:///local/doc">name</a>'
        result = checker.inspect_html(self.html(text), self.expected)
        self.assertEqual(result['unresolved_references'], 1)
        self.assertEqual(result['machine_local_links'], 1)
        self.assertEqual(result['racket_error_elements'], 0)
        with self.assertRaises(ValueError):
            checker.inspect_html(self.html(text), self.expected, strict_links=True)

    def test_literal_hyphens_unicode_and_ampersand(self):
        expected = ['Bézier -- origin & scale.']
        html = self.image(expected[0]).replace(' & ', ' &amp; ')
        self.assertEqual(checker.inspect_html(self.html(html), expected)['figures'], 1)

    def test_other_interface_icon_is_not_a_tutorial_figure(self):
        html = '<img class="navigation" alt="next" src="next.svg">' + self.normal()
        self.assertEqual(checker.inspect_html(self.html(html), self.expected)['figures'], 2)


if __name__ == '__main__':
    unittest.main()

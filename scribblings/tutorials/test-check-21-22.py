#!/usr/bin/env python3
"""Pure Python regression tests for the batch checker's file inspections."""
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('checker', Path(__file__).with_name('check-21-22.py'))
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class Checks(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def png(self, name='pict.png', width=100, height=50):
        # A minimal header fixture, not a rendered image or a complete PNG.
        path = self.root / name
        path.write_bytes(b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR'
                         + struct.pack('>II', width, height))
        return path

    def html(self, body):
        path = self.root / 'test.html'
        path.write_text(body, encoding='utf-8')
        return path

    def test_dimensions(self):
        self.assertEqual(checker.png_size(self.png()), (100, 50))

    def test_bad_signature(self):
        path = self.root / 'bad.png'
        path.write_bytes(b'not a png file')
        with self.assertRaises(ValueError):
            checker.png_size(path)

    def test_missing_image(self):
        with self.assertRaises(ValueError):
            checker.inspect_html(self.html('<img src="pict.png">'), 1)

    def test_figure_count(self):
        self.png()
        with self.assertRaises(ValueError):
            checker.inspect_html(self.html('<img src="pict.png">'), 2)

    def test_zero_sized_image(self):
        self.png(width=0)
        with self.assertRaises(ValueError):
            checker.inspect_html(self.html('<img src="pict.png">'), 1)

    def test_two_placements_are_counted(self):
        self.png()
        self.png('pict_2.png')
        result = checker.inspect_html(self.html('<img src="pict.png"><img src="pict_2.png">'), 2)
        self.assertEqual(len(result['figures']), 2)

    def test_external_images_do_not_masquerade_as_figures(self):
        with self.assertRaises(ValueError):
            checker.inspect_html(self.html('<img src="https://example.com/pict.png">'), 1)

    def test_link_problems_are_disclosed(self):
        self.png()
        result = checker.inspect_html(self.html('<a href="file:///tmp/doc">x</a>'
                                                '<span class="RktErr">x</span>'
                                                '<img src="pict.png">'), 1)
        self.assertEqual(result['machine_local_links'], 1)
        self.assertEqual(result['unresolved_markers'], 0)
        self.assertEqual(result['evaluation_error_markers'], 1)

    def test_unresolved_reference_is_not_an_evaluation_error(self):
        self.png()
        result = checker.inspect_html(self.html('<span class="badlink">x</span>'
                                                '<img src="pict.png">'), 1)
        self.assertEqual(result['unresolved_markers'], 1)
        self.assertEqual(result['evaluation_error_markers'], 0)

    def test_class_tokens_count_elements_not_substrings(self):
        self.png()
        result = checker.inspect_html(self.html(
            '<span class="other badlink badlink extra">x</span>'
            '<span class="other RktErr extra">y</span>'
            '<span class="not-badlink RktErr-like">z</span>'
            '<!-- badlink RktErr -->'
            '<script>const text = "badlink RktErr";</script>'
            '<p>badlink RktErr</p><img src="pict.png">'), 1)
        self.assertEqual(result['unresolved_markers'], 1)
        self.assertEqual(result['evaluation_error_markers'], 1)

    def test_both_classes_and_self_closing_elements(self):
        self.png()
        result = checker.inspect_html(self.html(
            '<span class="badlink RktErr"/>'
            '<span class="badlink">second occurrence</span>'
            '<img src="pict.png"/>'), 1)
        self.assertEqual(result['unresolved_markers'], 2)
        self.assertEqual(result['evaluation_error_markers'], 1)

    def test_missing_or_empty_class(self):
        self.png()
        result = checker.inspect_html(self.html(
            '<span class>x</span><span class="">y</span><img src="pict.png">'), 1)
        self.assertEqual(result['unresolved_markers'], 0)
        self.assertEqual(result['evaluation_error_markers'], 0)


if __name__ == '__main__':
    unittest.main()

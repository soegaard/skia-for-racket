#!/usr/bin/env python3
"""Python-only source and synthetic-HTML tests; no Racket or native rendering occurs here."""
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('check_3c', Path(__file__).with_name('check-3c.py'))
checker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checker)


class SourceChecks(unittest.TestCase):
    def test_eight_complete_revisions(self):
        result = checker.check_source(checker.ROOT)
        self.assertEqual(len(result), 8)
        self.assertEqual(sum(row['described_figures'] for row in result.values()), 69)
        self.assertEqual(sum(row['expected_rendered_placements'] for row in result.values()), 77)

    def test_literal_description(self):
        text = '(tutorial-figure "A marked point on the baseline." (sample))'
        self.assertEqual(checker.source_alternatives(text), ['A marked point on the baseline.'])

    def test_joined_description(self):
        text = '(tutorial-figure (string-append "A marked point " "on the baseline.") (sample))'
        self.assertEqual(checker.source_alternatives(text), ['A marked point on the baseline.'])

    def test_generic_description_fails(self):
        with self.assertRaises(ValueError):
            checker.source_alternatives('(tutorial-figure "image" (sample))')

    def test_dynamic_description_is_not_silently_accepted(self):
        with self.assertRaises(ValueError):
            checker.source_alternatives('(tutorial-figure (get-alt) (sample))')

    def test_delimiters_inside_strings_and_comments(self):
        text = '(sample ") ]" ; ignored closing )\n [1 2]) trailing'
        self.assertEqual(text[:checker.form_end(text, 0)], text[:-9])

    def test_mismatched_delimiters_fail(self):
        with self.assertRaises(ValueError):
            checker.form_end('(sample [1 2))', 0)

    def test_missing_delimiter_fails(self):
        with self.assertRaises(ValueError):
            checker.form_end('(sample 1', 0)

    def test_advance_interval_both_signs(self):
        # Independent arithmetic witness, not execution of the Racket helper.
        for edge in (0, 100, 570):
            for advance in (-180, -1, 0, 1, 180):
                origin = edge if advance < 0 else edge - advance
                self.assertEqual(max(origin, origin + advance), edge)


class HTMLChecks(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.alt = 'One described figure with a marked origin.'
        self.png()

    def png(self, name='figure.png', width=64, height=40):
        # Only a header fixture: this is not a complete PNG or a native rendering.
        path = self.root / name
        path.write_bytes(b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR'
                         + struct.pack('>II', width, height))
        return path

    def html(self, body):
        path = self.root / 'test.html'
        path.write_text(body, encoding='utf-8')
        return path

    def image(self, alt=None, source='figure.png', classes=checker.MARKER):
        return f'<img class="{classes}" src="{source}" alt="{alt or self.alt}">'

    def test_valid_figure(self):
        report = checker.inspect_html(self.html(self.image()), [self.alt])
        self.assertEqual(report['figures'], 1)

    def test_multiple_class_tokens(self):
        tag = self.image(classes='extra ' + checker.MARKER + ' another')
        self.assertEqual(checker.inspect_html(self.html(tag), [self.alt])['figures'], 1)

    def test_self_closing_tag(self):
        tag = self.image()[:-1] + '/>'
        self.assertEqual(checker.inspect_html(self.html(tag), [self.alt])['figures'], 1)

    def test_generic_alt_fails(self):
        with self.assertRaises(ValueError):
            checker.inspect_html(self.html(self.image('image')), [self.alt])

    def test_missing_figure_fails(self):
        with self.assertRaises(ValueError):
            checker.inspect_html(self.html('<p>No image</p>'), [self.alt])

    def test_extra_figure_fails(self):
        with self.assertRaises(ValueError):
            checker.inspect_html(self.html(self.image() * 2), [self.alt])

    def test_wrong_order_fails(self):
        with self.assertRaises(ValueError):
            checker.inspect_html(self.html(self.image()), ['A different described figure.'])

    def test_missing_file_fails(self):
        with self.assertRaises(ValueError):
            checker.inspect_html(self.html(self.image(source='missing.png')), [self.alt])

    def test_remote_file_fails(self):
        with self.assertRaises(ValueError):
            page = self.html(self.image(source='https://example.com/f.png'))
            checker.inspect_html(page, [self.alt])

    def test_bad_png_fails(self):
        (self.root / 'figure.png').write_bytes(b'not an image')
        with self.assertRaises(ValueError):
            checker.inspect_html(self.html(self.image()), [self.alt])

    def test_zero_dimension_fails(self):
        self.png(width=0)
        with self.assertRaises(ValueError):
            checker.inspect_html(self.html(self.image()), [self.alt])

    def test_opening_after_code_fails(self):
        page = self.html('<table class="RktBlk"></table>' + self.image())
        with self.assertRaises(ValueError):
            checker.inspect_html(page, [self.alt])

    def test_reference_diagnostics_are_separate(self):
        page = self.html(self.image() + '<span class="badlink other">x</span>'
                         + '<a href="file:///tmp/doc">link</a>')
        report = checker.inspect_html(page, [self.alt])
        self.assertEqual(report['unresolved_references'], 1)
        self.assertEqual(report['racket_error_elements'], 0)
        self.assertEqual(report['machine_local_links'], 1)

    def test_evaluation_error_fails(self):
        page = self.html(self.image() + '<span class="RktErr">failed</span>')
        with self.assertRaises(ValueError):
            checker.inspect_html(page, [self.alt])

    def smoke(self, width=32, final_source='figure.png'):
        final = 'Finished panel: Bézier -- origin &amp; scale.'
        self.png('direct.png', width=48, height=32)
        return (f'<img class="{checker.MARKER}" src="figure.png" alt="{final}" '
                f'width="{width}" height="20"><table class="RktBlk"></table>'
                f'<img class="{checker.MARKER}" src="direct.png" '
                'alt="Direct panel: 24 by 16." width="24" height="16">'
                f'<img class="{checker.MARKER}" src="{final_source}" alt="{final}" '
                'width="32" height="20">')

    def test_smoke_unicode_escaping_and_reuse(self):
        self.assertEqual(checker.check_smoke(self.html(self.smoke()))['figures'], 3)

    def test_smoke_wrong_scale_fails(self):
        with self.assertRaises(ValueError):
            checker.check_smoke(self.html(self.smoke(width=64)))

    def test_smoke_different_resource_fails(self):
        self.png('other.png')
        with self.assertRaises(ValueError):
            checker.check_smoke(self.html(self.smoke(final_source='other.png')))


if __name__ == '__main__':
    unittest.main()

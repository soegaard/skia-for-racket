#!/usr/bin/env python3
"""Pure Python regressions, using synthetic HTML and source files (not rendered examples)."""
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('reader_checker', HERE / 'check-3b.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class ReaderChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def catalog_fixture(self):
        data = json.loads((checker.ROOT / checker.CATALOG).read_text(encoding='utf-8'))
        self.data = data
        self.catalog = self.root / checker.CATALOG
        self.catalog.parent.mkdir(parents=True)
        self.write_catalog()
        for row in data['tutorials']:
            dest = self.root / row['manual']
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(checker.ROOT / row['manual'], dest)
        index = self.root / 'scribblings/tutorials/index.scrbl'
        shutil.copyfile(checker.ROOT / 'scribblings/tutorials/index.scrbl', index)
        return data

    def write_catalog(self):
        self.catalog.write_text(json.dumps(self.data), encoding='utf-8')

    def document(self, text, name='smoke.html'):
        dest = self.root / name
        dest.write_text(text, encoding='utf-8')
        return dest

    def lesson_fixture(self):
        self.document('source', 'example.rkt')
        body = ('<p class="skia-reader-prerequisites">Prerequisites</p>'
                '<p class="skia-reader-next"><a href="#try">Try</a></p>'
                '<p class="skia-reader-sources">Sources</p>'
                '<a class="skia-reader-source-link" href="example.rkt">Source</a>'
                '<h2 id="try">Try it</h2>')
        for index in range(22):
            self.document(body, f'{index}.html')
        return self.root / '0.html'

    def test_structure(self):
        self.catalog_fixture()
        self.assertEqual(checker.check_structure(self.root),
                         dict(lessons=22, categories=8, routes=8, source_files=43))

    def test_index_category_drift(self):
        self.catalog_fixture()
        index = self.root / 'scribblings/tutorials/index.scrbl'
        index.write_text(index.read_text().replace('@tutorial-category', '@wrong-category', 1))
        with self.assertRaisesRegex(ValueError, 'index categories'):
            checker.check_structure(self.root)

    def test_index_route_drift(self):
        self.catalog_fixture()
        index = self.root / 'scribblings/tutorials/index.scrbl'
        index.write_text(index.read_text().replace('@tutorial-route', '@wrong-route', 1))
        with self.assertRaisesRegex(ValueError, 'index routes'):
            checker.check_structure(self.root)

    def test_duplicate_lesson(self):
        self.catalog_fixture()
        self.data['tutorials'][1]['id'] = 'quick'
        self.write_catalog()
        with self.assertRaises(ValueError):
            checker.check_structure(self.root)

    def test_missing_menu_title(self):
        self.catalog_fixture()
        del self.data['tutorials'][0]['menu_title']
        self.write_catalog()
        with self.assertRaisesRegex(ValueError, 'menu title'):
            checker.check_structure(self.root)

    def test_categories_must_cover_each_lesson_once(self):
        self.catalog_fixture()
        self.data['categories'][0]['lessons'].append('clock')
        self.write_catalog()
        with self.assertRaisesRegex(ValueError, 'categories'):
            checker.check_structure(self.root)

    def test_routes_need_not_cover_every_tutorial(self):
        self.catalog_fixture()
        self.data['routes'][-1]['lessons'].remove('squadron')
        self.write_catalog()
        index = self.root / 'scribblings/tutorials/index.scrbl'
        index.write_text(index.read_text().replace('"sprites" "squadron"', '"sprites"'))
        self.assertEqual(checker.check_structure(self.root)['lessons'], 22)

    def test_unknown_prerequisite(self):
        self.catalog_fixture()
        self.data['tutorials'][0]['prerequisites'] = ['missing']
        self.write_catalog()
        with self.assertRaises(ValueError):
            checker.check_structure(self.root)

    def test_prerequisite_cycle(self):
        self.catalog_fixture()
        self.data['tutorials'][0]['prerequisites'] = ['clock']
        self.write_catalog()
        with self.assertRaises(ValueError):
            checker.check_structure(self.root)

    def test_missing_entry(self):
        self.catalog_fixture()
        self.data['tutorials'][0]['files'] = []
        self.write_catalog()
        with self.assertRaises(ValueError):
            checker.check_structure(self.root)

    def test_title_drift(self):
        self.catalog_fixture()
        self.data['tutorials'][0]['title'] = 'Wrong title'
        self.write_catalog()
        with self.assertRaises(ValueError):
            checker.check_structure(self.root)

    def test_hidden_shared_dependency(self):
        self.catalog_fixture()
        row = next(r for r in self.data['tutorials'] if r['id'] == 'squadron')
        row['files'].remove('support/sprite-window.rkt')
        self.write_catalog()
        with self.assertRaises(ValueError):
            checker.check_structure(self.root)

    def test_unsafe_paths(self):
        for path in ('/tmp/x', '../x', 'a/../b', 'a//b', 'C:/a', 'a\\b', 'a/./b', 'a/'):
            with self.subTest(path=path), self.assertRaises(ValueError):
                checker.safe_relative(path)

    def test_quick_source_prefix(self):
        self.assertEqual(checker.source_path(self.root, 'quick/moonlight.rkt'),
                         self.root / 'scribblings/quick/moonlight.rkt')

    def test_common_source_prefix(self):
        self.assertEqual(checker.source_path(self.root, 'support/sprite-window.rkt'),
                         self.root / 'scribblings/tutorials/support/sprite-window.rkt')

    def test_all_declared_file_paths_with_synthetic_sources(self):
        self.catalog_fixture()
        for row in self.data['tutorials']:
            for relative in row['files']:
                file = checker.source_path(self.root, relative)
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text('Synthetic file, not a working example.\n', encoding='utf-8')
        self.assertEqual(checker.check_files(self.root)['files_found'], 43)
        entry = checker.source_path(self.root, 'sprites/balls.rkt')
        entry.write_text('(require "../support/missing.rkt")', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'outside copied set'):
            checker.check_files(self.root)

    def test_absent_real_sources_fail(self):
        self.catalog_fixture()
        with self.assertRaisesRegex(ValueError, 'missing source'):
            checker.check_files(self.root)

    def test_exact_command_fragments(self):
        commands = ['--renderer raster', '--renderer gpu', '--count 300',
                    '--snapshot picture.png', 'raco skia-examples --list']
        html = ''.join(f'<span class="skia-command"><tt>{s}</tt></span>' for s in commands)
        path = self.document(html)
        self.assertEqual(checker.check_smoke(path)['literal_command_fragments'], 5)

    def test_en_dash_option_fails(self):
        page = checker.read_page(self.document('<span class="skia-command">–renderer gpu</span>'))
        with self.assertRaises(ValueError):
            checker.check_commands(page)

    def test_missing_command_span_fails(self):
        page = checker.read_page(self.document('<p>--renderer gpu</p>'))
        with self.assertRaises(ValueError):
            checker.check_commands(page)

    def test_nested_command_content(self):
        page = checker.read_page(self.document(
            '<span class="skia-command"><tt>--renderer <b>gpu</b></tt></span><p>Other</p>'))
        self.assertEqual(page.commands, ['--renderer gpu'])

    def test_separate_reference_counters(self):
        page = checker.read_page(self.document(
            '<span class="badlink RktErr">x</span><span class="badlink">y</span>'
            '<a href="file:///tmp/api.html">z</a>'))
        self.assertEqual((page.badlinks, page.rkt_errors, page.file_links), (2, 1, 1))

    def test_synthetic_lesson_tree(self):
        self.lesson_fixture()
        self.assertEqual(checker.check_html(self.root)['rendered_lessons'], 22)

    def test_missing_anchor_fails(self):
        path = self.lesson_fixture()
        path.write_text(path.read_text().replace('id="try"', 'id="other"'))
        with self.assertRaisesRegex(ValueError, 'anchor'):
            checker.check_html(self.root)

    def test_missing_page_fails(self):
        path = self.lesson_fixture()
        path.write_text(path.read_text().replace('href="#try"', 'href="missing.html#try"'))
        with self.assertRaisesRegex(ValueError, 'destination'):
            checker.check_html(self.root)

    def test_missing_download_fails(self):
        self.lesson_fixture()
        (self.root / 'example.rkt').unlink()
        with self.assertRaisesRegex(ValueError, 'resource'):
            checker.check_html(self.root)

    def test_unresolved_reader_link_fails(self):
        path = self.lesson_fixture()
        path.write_text(path.read_text().replace('Prerequisites', '<span class="badlink">X</span>'))
        with self.assertRaisesRegex(ValueError, 'unresolved reader'):
            checker.check_html(self.root)

    def test_all_markers_required(self):
        path = self.lesson_fixture()
        path.write_text(path.read_text().replace('skia-reader-sources', 'other'))
        with self.assertRaisesRegex(ValueError, 'missing reader'):
            checker.check_html(self.root)

    def test_old_or_partial_manual_not_accepted(self):
        self.document('<p>Old manual without reader navigation</p>')
        with self.assertRaisesRegex(ValueError, 'expected 22'):
            checker.check_html(self.root)


if __name__ == '__main__':
    unittest.main()

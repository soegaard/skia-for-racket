#!/usr/bin/env python3
"""Focused parser tests for the documentation-navigation checker."""
from __future__ import annotations

import importlib.util
import hashlib
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    'documentation_navigation', ROOT / 'tools' / 'check-documentation-navigation.py')
navigation = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(navigation)


class NavigationParserTests(unittest.TestCase):
    def test_review_inputs_include_feedback_sources_and_regressions(self):
        from reference_review import source_hashes
        hashes = source_hashes(ROOT, review_inputs=True)
        for name in ('scribblings/support/paragraph-feedback.rkt',
                     'scribblings/support/paragraph-feedback.js',
                     'scribblings/support/paragraph-feedback.css',
                     'tools/test-documentation-navigation.py'):
            self.assertEqual(hashes.get(name), hashlib.sha256((ROOT / name).read_bytes()).hexdigest())

    def test_visits_every_guide_and_tutorial_page(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            _catalog, tutorials, _categories, _shortcuts = navigation.load_catalog()
            directories = ['skia-reference', 'skia-guide', 'skia-tutorials'] + [
                navigation.tutorial_directory(entry['id']) for entry in tutorials]
            pages = [root / 'index.html'] + [
                root / name / page for name in directories for page in ('index.html', 'chapter.html')]
            for page in pages:
                page.parent.mkdir(exist_ok=True)
                page.write_text('', encoding='utf-8')
            with patch.object(navigation, 'check_page') as check:
                navigation.check_site(root)
            self.assertEqual({call.args[1] for call in check.call_args_list},
                             {page.resolve() for page in pages})
            self.assertEqual(check.call_count, len(pages))

    def test_feedback_requires_configuration_and_loadable_assets_on_each_page(self):
        head = '''<meta name="feedback-github" content="soegaard/skia-for-racket"/>
          <script src="paragraph-feedback.js"></script>
          <link rel="stylesheet" href="paragraph-feedback.css"/>'''
        with TemporaryDirectory() as directory:
            root = Path(directory)
            page = root / 'chapter.html'
            for asset in ('paragraph-feedback.js', 'paragraph-feedback.css'):
                (root / asset).write_text('', encoding='utf-8')
            page.write_text(f'<head>{head}</head><body></body>', encoding='utf-8')
            navigation.check_feedback(root, page)
            for invalid in (
                head.replace('name="feedback-github"', 'name="unrelated"'),
                head.replace('soegaard/skia-for-racket', 'another/repository'),
                head + '<meta name="feedback-github" content="soegaard/skia-for-racket"/>',
            ):
                page.write_text(f'<head>{invalid}</head><body></body>', encoding='utf-8')
                with self.assertRaisesRegex(navigation.CheckError, 'feedback configuration'):
                    navigation.check_feedback(root, page)
            page.write_text(f'<head></head><body>{head}</body>', encoding='utf-8')
            with self.assertRaisesRegex(navigation.CheckError, 'feedback configuration'):
                navigation.check_feedback(root, page)
            for asset in ('paragraph-feedback.js', 'paragraph-feedback.css'):
                page.write_text(f'<head>{head.replace(asset, "missing-" + asset)}</head>',
                                encoding='utf-8')
                with self.assertRaisesRegex(navigation.CheckError, 'feedback asset reference'):
                    navigation.check_feedback(root, page)
                page.write_text(f'<head>{head}</head>', encoding='utf-8')
                (root / asset).unlink()
                with self.assertRaisesRegex(navigation.CheckError, 'missing navigation target'):
                    navigation.check_feedback(root, page)
                (root / asset).write_text('', encoding='utf-8')

    def test_pages_staging_includes_code_and_font_stylesheets(self):
        workflow = (ROOT / '.github/workflows/pages.yml').read_text()
        assets = workflow.split('for asset in', 1)[1].split('\n          do', 1)[0].split()
        self.assertIn('racket.css', assets)
        self.assertIn('manual-fonts.css', assets)

    def test_catalog_shortcuts_follow_subject_categories(self):
        _catalog, tutorials, categories, shortcut_ids = navigation.load_catalog()
        self.assertEqual([category['title'] for category in categories], [
            'Getting Started', 'Geometry', 'Paints and Effects', 'Images and Color',
            'Text', 'Recording and Export', 'Windows and Interaction', 'Sprites and Games'])
        self.assertEqual(shortcut_ids,
                         [identifier for category in categories for identifier in category['lessons']])
        self.assertEqual(set(shortcut_ids), {entry['id'] for entry in tutorials})

    def test_requires_one_named_landmark(self):
        parser = navigation.NavigationParser()
        parser.feed('<main>No landmark</main>')
        with self.assertRaisesRegex(navigation.CheckError, 'expected one'):
            # Parse a real temporary file to exercise the public helper.
            from tempfile import TemporaryDirectory
            with TemporaryDirectory() as directory:
                page = Path(directory) / 'index.html'
                page.write_text('<main>No landmark</main>', encoding='utf-8')
                navigation.parse_navigation(page)

    def test_collects_navigation_regions(self):
        parser = navigation.NavigationParser()
        parser.feed('''<div role="navigation" aria-label="Skia documentation"
                         data-skia-doc-section="reference">
          <a class="skia-doc-nav__collection-link skia-doc-nav__collection-link--reference"
             href="index.html">Reference</a>
          <a class="skia-doc-nav__collection-link skia-doc-nav__collection-link--guide"
             href="guide.html">Guide</a>
          <a class="skia-doc-nav__collection-link skia-doc-nav__collection-link--tutorials"
             href="tutorials.html">Tutorials</a>
          <div data-skia-doc-nav-panel="tutorials"></div>
        </div>''')
        self.assertEqual(len(parser.navigations), 1)
        self.assertEqual(len(parser.navigations[0]['anchors']), 3)
        self.assertEqual(len(parser.navigations[0]['buttons']), 0)
        self.assertEqual(len(parser.navigations[0]['collections']), 3)
        self.assertEqual(len(parser.navigations[0]['panels']), 1)

    def test_collects_tutorial_categories_in_document_order(self):
        parser = navigation.NavigationParser()
        parser.feed('''<div role="navigation" aria-label="Skia documentation"
                         data-skia-doc-section="tutorials">
          <div class="skia-doc-nav__tutorial-group">
            <p class="skia-doc-nav__group-heading">Geometry</p>
            <ul><li><a class="skia-doc-nav__tutorial-link" href="clock.html">Clock</a></li></ul>
          </div>
        </div>''')
        groups = parser.navigations[0]['groups']
        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0]['heading'].strip(), 'Geometry')
        self.assertEqual(groups[0]['anchors'][0]['href'], 'clock.html')

    def test_accepts_only_package_local_installed_redirects(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / 'skia-tutorials' / 'index.html'
            target.parent.mkdir()
            target.write_text('<!doctype html>', encoding='utf-8')
            page = root / 'skia-reference' / 'index.html'
            page.parent.mkdir()
            page.write_text('<!doctype html>', encoding='utf-8')
            href = ('https://docs.racket-lang.org/local-redirect/index.html?'
                    'doc=skia-tutorials&rel=index.html')
            self.assertEqual(navigation.local_target(root, page, href), target.resolve())
            with self.assertRaisesRegex(navigation.CheckError, 'portable local target'):
                navigation.local_target(root, page,
                                        'https://example.invalid/local-redirect/index.html?'
                                        'doc=other-manual&rel=index.html')

    def test_accepts_package_local_guide_redirects(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / 'skia-guide' / 'index.html'
            target.parent.mkdir()
            target.write_text('<!doctype html>', encoding='utf-8')
            page = root / 'skia-reference' / 'index.html'
            page.parent.mkdir()
            page.write_text('<!doctype html>', encoding='utf-8')
            href = ('https://docs.racket-lang.org/local-redirect/index.html?'
                    'doc=skia-guide&rel=index.html')
            self.assertEqual(navigation.local_target(root, page, href), target.resolve())


if __name__ == '__main__':
    unittest.main()

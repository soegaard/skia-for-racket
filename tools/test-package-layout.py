#!/usr/bin/env python3
"""Concrete package ownership and prepared public Git-source regressions."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
import dc_validation
from native_packages import ROOT, json_bytes, read_json


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-','_'), ROOT / 'tools' / (name + '.py'))
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


class Layout(unittest.TestCase):
    def test_raster_gates_fingerprint_concrete_split_sources(self):
        # These gates run beside installed packages as well as in a checkout.
        # Reading every required input catches stale collection-root assumptions.
        for module in (dc_validation, load('validate-skia-canvas')):
            with self.subTest(gate=module.__name__):
                hashes = module.source_fingerprint(ROOT)
                self.assertEqual(set(hashes), set(module.SOURCE_PATHS))
                self.assertEqual(len(hashes['dc.rkt']), 64)

    def test_actual_boundary_and_data_inventory(self):
        result = load('check-package-layout').check()
        self.assertEqual(result['fonts'], 4)
        self.assertEqual(result['editable_assets'], 43)
        self.assertEqual(result['source_packages'], ['skia','skia-lib','skia-doc'])

    def test_public_sources_are_five_default_branch_subdirectories(self):
        module = load('prepare-git-catalog')
        self.assertEqual(set(module.SOURCES), {'skia','skia-lib','skia-doc','skia-native-macos-1','skia-native-x86_64-linux-1'})
        for name, url in module.SOURCES.items():
            self.assertTrue(url.endswith('.git?path=' + name))
            self.assertNotIn('#', url)
            self.assertNotIn('releases/download', url)

    def test_git_commit_checksums_are_not_archive_digests(self):
        module = load('prepare-git-catalog')
        rows = module.rows('a'*40, 'b'*40, Path('/prepared/skia-libs'))
        self.assertEqual([r['sha1'] for r in rows], ['a'*40]*3 + ['b'*40]*2)
        self.assertTrue(all('archive' not in r for r in rows))
        for value in ('a'*64, 'main', '../HEAD', ''):
            with self.assertRaises(ValueError): module.commit(value)

    def test_source_builder_rejects_runtime_font_even_with_doc_font_filename(self):
        stage = load('stage-native-catalog')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'skia-lib/fonts').mkdir(parents=True)
            (root / 'packaging').mkdir()
            (root / 'packaging/native-assets.json').write_bytes(json_bytes(read_json(ROOT / 'packaging/native-assets.json')))
            (root / 'skia-lib/info.rkt').write_text('#lang info\n')
            (root / 'skia-lib/LICENSE').write_text('fixture\n')
            (root / 'skia-lib/fonts/NotoSans-Regular.ttf').write_bytes(b'not a font')
            subprocess.run(['git','init','-q',str(root)],check=True)
            with self.assertRaisesRegex(ValueError, 'font outside documentation'):
                stage.source_archive(root, root / 'bad.zip', package='skia-lib', allow_dirty=True)
            self.assertFalse((root / 'bad.zip').exists())


if __name__ == '__main__': unittest.main()

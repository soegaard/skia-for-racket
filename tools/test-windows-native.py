#!/usr/bin/env python3
"""Direct upstream Windows acquisition, ownership and transaction regressions."""
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import subprocess
import unittest
from unittest.mock import patch
import zipfile

import native_packages as n
import windows_native as w

spec = importlib.util.spec_from_file_location('native_fixtures', Path(__file__).with_name('test-native-packages.py'))
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)


def archive(kind):
    package = ('skiasharp' if kind == 'skia' else 'harfbuzzsharp') + '.nativeassets.win32'
    version = n.native_pins()[kind]
    name = 'libSkiaSharp.dll' if kind == 'skia' else 'libHarfBuzzSharp.dll'
    metadata = (f'<package><metadata><id>{package}</id><version>{version}</version>'
                '<license type="expression">MIT</license>'
                '<repository type="git" url="https://github.com/mono/SkiaSharp" commit="fixture" />'
                '</metadata></package>')
    result = io.BytesIO()
    with zipfile.ZipFile(result, 'w') as z:
        z.writestr('package.nuspec', metadata)
        z.writestr('LICENSE.txt', 'original license')
        z.writestr('THIRD-PARTY-NOTICES.txt', 'original component notices')
        z.writestr('runtimes/win-x64/native/' + name, fixtures.pe_delay())
    return result.getvalue()


class Response(io.BytesIO):
    def __init__(self, data, url):
        super().__init__(data)
        self.url = url
    def geturl(self):
        return self.url


class Windows(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='Windows upstream æ ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.source = self.root / 'raw inputs'
        self.source.mkdir()
        self.lock = copy.deepcopy(n.read_json(n.ROOT / 'packaging/native-assets.json'))
        for kind in ('skia', 'harfbuzz'):
            package = ('skiasharp' if kind == 'skia' else 'harfbuzzsharp') + '.nativeassets.win32'
            version = n.native_pins()[kind]
            name = package + '.' + version + '.nupkg'
            (self.source / name).write_bytes(archive(kind))
            self.lock['archives'][name] = n.inspect_input(self.source / name, kind, 'win32', version)
        self.lock_path = self.root / 'lock.json'
        self.lock_path.write_bytes(n.json_bytes(self.lock))
        self.destination = self.root / 'library with spaces æ' / w.DIRECTORY

    def acquire(self):
        path = self.root / 'verified cache'
        return path, w.acquire(self.lock_path, path, source=self.source)

    def test_only_two_locked_official_urls_are_downloaded(self):
        expected = {row['url']: self.source / name for name, row in w.records(self.lock).items()}
        def opened(url, **kwargs):
            return Response(expected[url].read_bytes(), url)
        with patch.object(w.urllib.request, 'build_opener') as factory:
            factory.return_value.open.side_effect = opened
            receipt = w.acquire(self.lock_path, self.root / 'network inputs')
            self.assertEqual({call.args[0] for call in factory.return_value.open.call_args_list}, set(expected))
        self.assertEqual({r['obtained_by'] for r in receipt['archives']}, {'nuget-download'})
        self.assertEqual(len(receipt['archives']), 2)

    def test_bad_hash_never_exposes_a_verified_cache(self):
        name = next(iter(w.records(self.lock)))
        (self.source / name).write_bytes(b'corrupt archive')
        with self.assertRaises(ValueError):
            w.acquire(self.lock_path, self.root / 'rejected', source=self.source)
        self.assertFalse((self.root / 'rejected').exists())

    def test_bad_network_bytes_never_expose_a_verified_cache(self):
        with patch.object(w.urllib.request, 'build_opener') as factory:
            factory.return_value.open.side_effect = lambda url, **kwargs: Response(b'bad', url)
            with self.assertRaises(ValueError):
                w.acquire(self.lock_path, self.root / 'rejected')
        self.assertFalse((self.root / 'rejected').exists())

    def test_network_size_bound_precedes_archive_inspection(self):
        with patch.object(w.urllib.request, 'build_opener') as factory:
            factory.return_value.open.side_effect = lambda url, **kwargs: Response(b'x' * 8192, url)
            with self.assertRaisesRegex(ValueError, 'locked size'):
                w.acquire(self.lock_path, self.root / 'rejected')

    def test_unapproved_or_insecure_redirects_are_rejected(self):
        for url in ('http://api.nuget.org/a', 'https://example.com/a', 'https://api.nuget.org@evil.test/a',
                    'https://user:secret@api.nuget.org/a'):
            with self.subTest(url=url), self.assertRaises(ValueError):
                w.check_url(url)
        w.check_url('https://globalcdn.nuget.org/packages/input.nupkg')

    def test_offline_acquisition_does_not_open_network(self):
        with patch.object(w.urllib.request, 'build_opener', side_effect=AssertionError('network')):
            inputs, receipt = self.acquire()
            manifest = w.install(self.lock_path, inputs, self.destination)
        self.assertEqual(manifest['acquisition']['route'], w.ROUTE)
        self.assertEqual({r['obtained_by'] for r in receipt['archives']}, {'verified-local-archive'})

    def test_notices_and_exact_pair_are_preserved_without_raw_nugets(self):
        inputs, _ = self.acquire()
        manifest = w.install(self.lock_path, inputs, self.destination)
        self.assertEqual(w.owned(self.destination), manifest)
        for kind in ('skia', 'harfbuzz'):
            self.assertEqual((self.destination / 'licenses' / kind / 'LICENSE.txt').read_text(), 'original license')
        self.assertEqual(set(manifest['files']), {'skia', 'harfbuzz'})
        self.assertFalse(list(self.destination.rglob('*.nupkg')))

    def test_bad_second_input_cannot_replace_an_existing_pair(self):
        inputs, _ = self.acquire()
        before = w.install(self.lock_path, inputs, self.destination)
        name = next(name for name, record in w.records(self.lock).items() if record['kind'] == 'skia')
        (inputs / name).write_bytes(b'broken second input')
        with self.assertRaises(ValueError):
            w.install(self.lock_path, inputs, self.destination)
        self.assertEqual(w.owned(self.destination), before)

    def test_compatible_revision_and_explicit_rollback(self):
        inputs, _ = self.acquire()
        original = w.install(self.lock_path, inputs, self.destination)
        update = w.install(self.lock_path, inputs, self.destination, revision='1.1')
        self.assertEqual(update['package_version'], '1.1')
        self.assertEqual(update['files'], original['files'])
        self.assertEqual(w.install(self.lock_path, inputs, self.destination), original)

    def test_failed_pair_activation_restores_the_previous_directory(self):
        inputs, _ = self.acquire()
        original = w.install(self.lock_path, inputs, self.destination)
        rename = Path.rename
        def failed(path, target):
            if path.name == 'payload' and target == self.destination:
                raise PermissionError('simulated Windows sharing violation')
            return rename(path, target)
        with patch.object(Path, 'rename', failed), self.assertRaises(PermissionError):
            w.install(self.lock_path, inputs, self.destination, revision='1.1')
        self.assertEqual(w.owned(self.destination), original)

    def test_removal_preserves_an_unrelated_library(self):
        inputs, _ = self.acquire()
        w.install(self.lock_path, inputs, self.destination)
        sentinel = self.destination.parent / 'unrelated.dll'
        sentinel.write_bytes(b'retain')
        w.remove(self.destination)
        self.assertFalse(self.destination.exists())
        self.assertEqual(sentinel.read_bytes(), b'retain')

    def test_unknown_files_prevent_replacement_or_removal(self):
        inputs, _ = self.acquire()
        w.install(self.lock_path, inputs, self.destination)
        sentinel = self.destination / 'unrelated.dll'
        sentinel.write_bytes(b'retain')
        for operation in (lambda: w.install(self.lock_path, inputs, self.destination), lambda: w.remove(self.destination)):
            with self.assertRaisesRegex(ValueError, 'unowned files'):
                operation()
        self.assertEqual(sentinel.read_bytes(), b'retain')

    def test_owned_corrupt_or_missing_dll_can_be_repaired(self):
        inputs, _ = self.acquire()
        original = w.install(self.lock_path, inputs, self.destination)
        (self.destination / 'libSkiaSharp.dll').write_bytes(b'corrupt')
        (self.destination / 'libHarfBuzzSharp.dll').unlink()
        self.assertEqual(w.install(self.lock_path, inputs, self.destination), original)
        self.assertEqual(w.owned(self.destination), original)

    def test_linked_directory_or_ancestor_is_never_followed(self):
        actual = self.root / 'actual'
        actual.mkdir()
        link = self.root / 'linked'
        if os.name == 'nt':
            subprocess.run(['cmd', '/d', '/c', 'mklink', '/J', str(link), str(actual)], check=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        else:
            link.symlink_to(actual, target_is_directory=True)
        for directory in (link / w.DIRECTORY, self.root / 'wrong directory name'):
            with self.assertRaises(ValueError):
                w.safe_directory(directory)

    def test_runtime_identity_rejects_non_windows_non_cs_and_32_bit(self):
        base = dict(target='win32\\x86_64', vm='chez-scheme', bits=64,
                    user=str(self.root / 'user'), installation=str(self.root / 'installation'))
        with patch.object(w.subprocess, 'check_output', return_value=json.dumps(base)):
            self.assertEqual(w.locations('chosen-racket')['user'], self.root / 'user' / w.DIRECTORY)
        for changes in (dict(target='aarch64-macosx'), dict(vm='racket'), dict(bits=32)):
            with patch.object(w.subprocess, 'check_output', return_value=json.dumps(dict(base, **changes))):
                with self.assertRaises(ValueError):
                    w.locations('chosen-racket')

    def test_python_minimum_precedes_runtime_or_cache_access(self):
        with patch.object(w.sys, 'version_info', (3, 11)), \
                patch.object(w.subprocess, 'check_output', side_effect=AssertionError('runtime access')):
            with self.assertRaisesRegex(ValueError, 'Python 3.12 or later'):
                w.locations('chosen-racket')


if __name__ == '__main__':
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Synthetic installer checks. These do not load a Windows DLL."""
import hashlib
import importlib.util
import io
from pathlib import Path
import struct
import unittest
import zipfile
spec = importlib.util.spec_from_file_location('installer', Path(__file__).with_name('install-native-windows.py'))
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

def fixture(kind='skia', *, package=None, version=None, machine=0x8664, dll_flag=0x2000, member=None, duplicate=False, bad_offset=False):
    pkg, ver, filename = installer.PACKAGES[kind]
    output = io.BytesIO()
    dll = bytearray(256); dll[:2] = b'MZ'
    struct.pack_into('<I', dll, 0x3c, 9999 if bad_offset else 64)
    dll[64:68] = b'PE\0\0'
    struct.pack_into('<H', dll, 68, machine)
    struct.pack_into('<H', dll, 86, dll_flag)
    manifest = f'<package><metadata><id>{package or pkg}</id><version>{version or ver}</version></metadata></package>'
    path = member or f'runtimes/win-x64/native/{filename}'
    with zipfile.ZipFile(output, 'w') as archive:
        archive.writestr('package.nuspec', manifest)
        archive.writestr(path, dll)
        # An irrelevant traversal entry is harmless because we never unpack it.
        archive.writestr('../outside.txt', 'not extracted')
        if duplicate:
            import warnings
            with warnings.catch_warnings():
                warnings.simplefilter('ignore')
                archive.writestr(path, dll)
    return output.getvalue()

class Checks(unittest.TestCase):
    def test_skia(self):
        _, _, info = installer.validate_archive(fixture(), 'skia')
        self.assertEqual(info['rid'], 'win-x64')
        self.assertFalse(info['independent_hash_checked'])
    def test_harfbuzz(self): installer.validate_archive(fixture('harfbuzz'), 'harfbuzz')
    def test_good_hash(self):
        data = fixture()
        self.assertTrue(installer.validate_archive(data, 'skia', hashlib.sha256(data).hexdigest())[2]['independent_hash_checked'])
    def test_bad_hash(self):
        with self.assertRaises(ValueError): installer.validate_archive(fixture(), 'skia', '0' * 64)
    def test_wrong_version(self):
        with self.assertRaises(ValueError): installer.validate_archive(fixture(version='0.0'), 'skia')
    def test_wrong_package(self):
        with self.assertRaises(ValueError): installer.validate_archive(fixture(package='unrelated'), 'skia')
    def test_wrong_architecture(self):
        with self.assertRaises(ValueError): installer.validate_archive(fixture(machine=0x14c), 'skia')
    def test_missing_member(self):
        with self.assertRaises(ValueError): installer.validate_archive(fixture(member='../libSkiaSharp.dll'), 'skia')
    def test_duplicate_member(self):
        with self.assertRaises(ValueError): installer.validate_archive(fixture(duplicate=True), 'skia')
    def test_bad_pe_offset(self):
        with self.assertRaises(ValueError): installer.validate_archive(fixture(bad_offset=True), 'skia')
    def test_not_dll(self):
        with self.assertRaises(ValueError): installer.validate_archive(fixture(dll_flag=0), 'skia')
    def test_invalid_archive(self):
        with self.assertRaises(zipfile.BadZipFile): installer.validate_archive(b'not zip', 'skia')
if __name__ == '__main__': unittest.main(verbosity=2)

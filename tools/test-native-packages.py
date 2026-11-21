#!/usr/bin/env python3
"""Adversarial input checks and the Racket archive checksum protocol."""
import importlib.util
import io
from pathlib import Path
import stat
import struct
import tempfile
import unittest
import warnings
import zipfile

import native_packages as n


def archive(entries, *, compression=zipfile.ZIP_STORED):
    data = io.BytesIO()
    with zipfile.ZipFile(data, 'w', compression=compression) as z:
        for name, value in entries:
            with warnings.catch_warnings():
                warnings.simplefilter('ignore', UserWarning)
                z.writestr(name, value)
    data.seek(0)
    return data


def spec(extra='', *, encoding='utf-8'):
    return (f'<package><metadata><id>SkiaSharp.NativeAssets.Linux</id><version>3.119.1</version>'
            f'<license type="expression">MIT</license><repository commit="abc"/>{extra}'
            '</metadata></package>').encode(encoding)


def elf():
    return struct.pack('<16sHHIQQQIHHHHHH', b'\x7fELF\x02\x01' + b'\0' * 10,
                       3, 62, 1, 0, 0, 64, 0, 64, 0, 0, 64, 1, 0) + b'\0' * 64


def nuget_members():
    return {'SkiaSharp.NativeAssets.Linux.nuspec': spec(),
            'runtimes/linux-x64/native/libSkiaSharp.so': elf(),
            'LICENSE.txt': b'fixture license', 'THIRD-PARTY-NOTICES.txt': b'fixture notices'}


class LockedInputs(unittest.TestCase):
    def inspect(self, members, expected_version='3.119.1'):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'input.nupkg'
            path.write_bytes(archive(list(members.items())).getvalue())
            return n.inspect_input(path, 'skia', 'linux', expected_version)

    def test_observation_does_not_approve(self):
        result = self.inspect(nuget_members())
        self.assertEqual(result['inspection']['architectures'], ['x86_64'])
        self.assertNotIn('redistribution_approved', result)
        self.assertEqual(len(result['sha256']), 64)

    def test_wrong_id(self):
        members = nuget_members()
        members['SkiaSharp.NativeAssets.Linux.nuspec'] = spec().replace(b'SkiaSharp.NativeAssets.Linux', b'Other')
        with self.assertRaisesRegex(ValueError, 'identity/version'):
            self.inspect(members)

    def test_wrong_version(self):
        with self.assertRaisesRegex(ValueError, 'identity/version'):
            self.inspect(nuget_members(), '3.119.2')

    def test_wrong_member(self):
        members = nuget_members()
        value = members.pop('runtimes/linux-x64/native/libSkiaSharp.so')
        members['runtimes/linux-arm64/native/libSkiaSharp.so'] = value
        with self.assertRaisesRegex(ValueError, 'missing archive member'):
            self.inspect(members)

    def test_required_notices(self):
        for name in ('LICENSE.txt', 'THIRD-PARTY-NOTICES.txt'):
            members = nuget_members()
            del members[name]
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'missing archive member'):
                self.inspect(members)

    def test_oversized_metadata(self):
        members = nuget_members()
        members['SkiaSharp.NativeAssets.Linux.nuspec'] = b' ' * (n.MAX_METADATA + 1)
        with self.assertRaisesRegex(ValueError, 'oversized'):
            self.inspect(members)

    def test_multiple_nuspecs(self):
        members = nuget_members()
        members['other.nuspec'] = spec()
        with self.assertRaisesRegex(ValueError, 'one root nuspec'):
            self.inspect(members)

    def test_empty_library(self):
        members = nuget_members()
        members['runtimes/linux-x64/native/libSkiaSharp.so'] = b''
        with self.assertRaisesRegex(ValueError, 'empty'):
            self.inspect(members)

    def test_wrong_library_architecture(self):
        members = nuget_members()
        value = bytearray(elf())
        struct.pack_into('<H', value, 18, 183)
        members['runtimes/linux-x64/native/libSkiaSharp.so'] = value
        with self.assertRaisesRegex(ValueError, 'x86-64'):
            self.inspect(members)

    def test_bad_archive_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'input.nupkg'
            path.write_bytes(archive(list(nuget_members().items())).getvalue())
            record = n.inspect_input(path, 'skia', 'linux', '3.119.1')
            record['sha256'] = '0' * 64
            with self.assertRaisesRegex(ValueError, 'differs from lock'):
                n.check_locked_input(path, record)

    def test_bad_member_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'input.nupkg'
            path.write_bytes(archive(list(nuget_members().items())).getvalue())
            record = n.inspect_input(path, 'skia', 'linux', '3.119.1')
            record['members']['LICENSE.txt']['sha256'] = '0' * 64
            with self.assertRaisesRegex(ValueError, 'differs from lock'):
                n.check_locked_input(path, record)

    def test_duplicate_json_keys(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'lock.json'
            for value in ('{"schema": 1, "schema": 2}', '{"value": NaN}'):
                path.write_text(value)
                with self.subTest(value=value), self.assertRaises(ValueError):
                    n.read_json(path)

    def test_bad_elf_section_directory(self):
        for offset in (0xffffffff, 64):
            value = bytearray(elf())
            struct.pack_into('<Q', value, 40, offset)
            struct.pack_into('<H', value, 60, 4097)
            with self.assertRaisesRegex(ValueError, 'section directory'):
                n.inspect_elf(value)


class Archives(unittest.TestCase):
    def test_names(self):
        for name in ('/root', '../x', 'a/../x', 'C:/x', 'a\\x', './a', 'a//b', 'a\0b', 'a\nb'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                n.safe_name(name)

    def test_duplicates_and_case_collisions(self):
        for names in [('A', 'A'), ('A', 'a'), ('dir', 'DIR/')]:
            with self.subTest(names=names):
                with zipfile.ZipFile(archive([(s, b'x') for s in names])) as z:
                    with self.assertRaisesRegex(ValueError, 'duplicate/case'):
                        n.zip_index(z)

    def test_symlink_and_special_file(self):
        for mode in (stat.S_IFLNK, stat.S_IFIFO, stat.S_IFSOCK):
            info = zipfile.ZipInfo('data')
            info.create_system = 3
            info.external_attr = (mode | 0o644) << 16
            with zipfile.ZipFile(archive([(info, b'target')])) as z:
                with self.assertRaisesRegex(ValueError, 'special file'):
                    n.zip_index(z)

    def test_file_as_parent(self):
        with zipfile.ZipFile(archive([('a', b'x'), ('a/b', b'x')])) as z:
            with self.assertRaisesRegex(ValueError, 'below a file'):
                n.zip_index(z)

    def test_bomb(self):
        with zipfile.ZipFile(archive([('bomb', b'\0' * (8 * 1024 * 1024))], compression=zipfile.ZIP_DEFLATED)) as z:
            with self.assertRaisesRegex(ValueError, 'compression ratio'):
                n.zip_index(z)

    def test_member_bound_and_missing_notice(self):
        with zipfile.ZipFile(archive([('library', b'12345')])) as z:
            index = n.zip_index(z)
            with self.assertRaisesRegex(ValueError, 'oversized'):
                n.bounded_member(z, index, 'library', 4)
            with self.assertRaisesRegex(ValueError, 'missing archive member'):
                n.bounded_member(z, index, 'LICENSE.txt')

    def test_empty_member(self):
        with zipfile.ZipFile(archive([('empty', b'')])) as z:
            with self.assertRaisesRegex(ValueError, 'empty'):
                n.bounded_member(z, n.zip_index(z), 'empty')

    def test_crc_corruption(self):
        data = bytearray(archive([('library', b'contents')]).getvalue())
        # Stored member data begins after the local header and filename.
        data[30 + len('library')] ^= 1
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            with self.assertRaises(zipfile.BadZipFile):
                n.bounded_member(z, n.zip_index(z), 'library')

    def test_central_directory_size_bound(self):
        with zipfile.ZipFile(archive([('library', b'x')])) as z:
            z.getinfo('library').file_size = n.MAX_MEMBER + 1
            with self.assertRaisesRegex(ValueError, 'oversized archive member'):
                n.zip_index(z)

    def test_entry_bound(self):
        with zipfile.ZipFile(archive([(str(i), b'x') for i in range(n.MAX_ENTRIES + 1)])) as z:
            with self.assertRaisesRegex(ValueError, 'entry count'):
                n.zip_index(z)

    def test_xml_entities_and_ambiguity(self):
        for data in (b'<!DOCTYPE x [<!ENTITY a "b">]>' + spec(),
                     b'<!ENTITY a "b">' + spec(), spec(encoding='utf-16'),
                     spec('<version>other</version>'), b'<package/>'):
            with self.subTest(data=data[:50]), self.assertRaises(ValueError):
                n.nuspec_metadata(data)
        self.assertEqual(n.nuspec_metadata(spec())['version'], '3.119.1')

    def test_determinism_and_checksum_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            a, b = (Path(directory) / s for s in ('a.zip', 'b.zip'))
            x = n.write_zip(a, {'z': b'last', 'a': b'first'})
            y = n.write_zip(b, {'a': b'first', 'z': b'last'})
            self.assertEqual(x, y)
            self.assertEqual(a.read_bytes(), b.read_bytes())
            checksum = a.with_suffix('.zip.CHECKSUM').read_bytes()
            self.assertEqual(len(checksum), 40)
            self.assertEqual(checksum.decode(), x['sha1'])
            with zipfile.ZipFile(a) as z:
                self.assertEqual(z.namelist(), ['a', 'z'])
                self.assertTrue(all(i.compress_type == zipfile.ZIP_STORED for i in z.infolist()))

    def test_malformed_native_images(self):
        for inspect in (n.inspect_elf, n.inspect_pe, n.inspect_macho):
            for value in (b'', b'\0' * 64, b'MZ' + b'\xff' * 80):
                with self.subTest(inspector=inspect.__name__), self.assertRaises(ValueError):
                    inspect(value)

    def test_wrong_elf_machine(self):
        value = bytearray(64)
        value[:6] = b'\x7fELF\x02\x01'
        struct.pack_into('<HH', value, 16, 3, 183)
        with self.assertRaisesRegex(ValueError, 'x86-64'):
            n.inspect_elf(value)

    def test_lock_does_not_approve_downloads(self):
        p = Path(__file__).with_name('build-native-packages.py')
        spec = importlib.util.spec_from_file_location('builder', p)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = root / 'lock.json'
            lock.write_bytes(n.json_bytes(dict(schema=1, generation=1, directory='skia-native-1', review={})))
            with self.assertRaisesRegex(ValueError, 'review; release assembly refused'):
                mod.build(lock, root, root / 'out')
            self.assertFalse((root / 'out').exists())


if __name__ == '__main__':
    unittest.main()

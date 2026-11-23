"""Bounded, nonexecuting native-package input inspection and offline assembly.

The observed-input report is deliberately different from a reviewed lock. No
downloaded digest or upstream MIT nuspec grants redistribution approval.
"""
from __future__ import annotations
from repository_layout import source_path, library_root, documentation_root

import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import stat
import struct
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
GENERATOR_VERSION = 3
MAX_ARCHIVE = 180 * 1024 * 1024
MAX_MEMBER = 100 * 1024 * 1024
MAX_TOTAL = 600 * 1024 * 1024
MAX_ENTRIES = 2048
MAX_METADATA = 1024 * 1024
MAX_FONT = 32 * 1024 * 1024
TARGETS = {
    'macos': dict(package='skia-native-macos-1', rid='osx', suffix='.dylib',
                  selector='#rx"^(aarch64|x86_64)-macosx$"'),
    'win32': dict(package='skia-native-win32-x86_64-1', rid='win-x64', suffix='.dll',
                  selector='"win32\\\\x86_64"'),
    'linux': dict(package='skia-native-x86_64-linux-1', rid='linux-x64', suffix='.so',
                  selector='#rx"^x86_64-linux(-natipkg)?$"'),
}
DISTRIBUTED_TARGETS = ('macos', 'linux')
DISTRIBUTION = {'macos': 'racket-package', 'linux': 'racket-package', 'win32': 'direct-nuget'}


def need(ok, message):
    if not ok:
        raise ValueError(message)


def unique(pairs):
    result = {}
    for key, value in pairs:
        need(key not in result, 'duplicate JSON key: ' + key)
        result[key] = value
    return result


def read_json(path):
    need(path.is_file() and not path.is_symlink() and path.stat().st_size <= MAX_METADATA,
         'missing/unsafe/oversized JSON: ' + str(path))
    def invalid(value):
        raise ValueError('nonfinite JSON: ' + value)
    return json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique,
                      parse_constant=invalid)


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=True,
                       allow_nan=False) + '\n').encode('utf-8')


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def native_pins(root=ROOT):
    from native_abi import default_version
    hb = (source_path(root, 'private/harfbuzz-default-version.txt')).read_text().strip()
    need(re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+', hb), 'invalid HarfBuzz pin')
    return dict(skia=default_version(root), harfbuzz=hb)


def safe_name(name):
    need(isinstance(name, str) and bool(name) and not name.startswith('/')
         and '\\' not in name and ':' not in name and '\0' not in name
         and not any(ord(c) < 32 for c in name)
         and all(p not in ('', '.', '..') for p in name.rstrip('/').split('/')),
         'unsafe archive member: ' + repr(name))
    return name


def zip_index(archive, *, max_entries=MAX_ENTRIES):
    infos = archive.infolist()
    need(0 < len(infos) <= max_entries, 'invalid archive entry count')
    seen = set()
    total = 0
    for info in infos:
        safe_name(info.filename)
        key = info.filename.rstrip('/').casefold()
        need(key not in seen, 'duplicate/case-colliding archive member: ' + info.filename)
        seen.add(key)
        mode = info.external_attr >> 16
        need(stat.S_IFMT(mode) in (0, stat.S_IFREG, stat.S_IFDIR),
             'special file/symlink in archive: ' + info.filename)
        need(not info.flag_bits & 1, 'encrypted archive member')
        need(info.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED),
             'unapproved archive compression')
        need(0 <= info.file_size <= MAX_MEMBER, 'oversized archive member')
        need(info.file_size <= max(1024 * 1024, info.compress_size * 1000),
             'excessive archive compression ratio')
        total += info.file_size
        need(total <= MAX_TOTAL, 'archive expansion exceeds limit')
    names = {i.filename.rstrip('/'): i for i in infos}
    for name in names:
        for parent in PurePosixPath(name).parents:
            need(str(parent) not in names or names[str(parent)].is_dir(),
                 'archive member below a file: ' + name)
    return {i.filename: i for i in infos}


def bounded_member(archive, index, name, limit=MAX_MEMBER):
    need(name in index and not index[name].is_dir(), 'missing archive member: ' + name)
    info = index[name]
    need(0 < info.file_size <= limit, 'empty/oversized member: ' + name)
    with archive.open(info) as stream:
        value = stream.read(limit + 1)
        need(len(value) == info.file_size, 'member size differs: ' + name)
    return value  # ZipFile checks this member's CRC. Never extractall.


def nuspec_metadata(data):
    need(len(data) <= MAX_METADATA, 'oversized nuspec')
    # Reject UTF-16/32 as well as DTDs; a NUL-padded entity declaration must not
    # bypass the byte check. NuGet's locked metadata is UTF-8.
    need(b'\0' not in data and b'<!DOCTYPE' not in data.upper()
         and b'<!ENTITY' not in data.upper(), 'DTD/entity/non-UTF-8 nuspec')
    root = ET.fromstring(data.decode('utf-8-sig'))
    need(root.tag.rsplit('}', 1)[-1] == 'package', 'invalid nuspec root')
    records = [n for n in root if n.tag.rsplit('}', 1)[-1] == 'metadata']
    need(len(records) == 1, 'ambiguous nuspec metadata')
    result = {}
    for node in records[0]:
        key = node.tag.rsplit('}', 1)[-1]
        if key in ('id', 'version', 'license', 'repository'):
            need(key not in result, 'duplicate nuspec field: ' + key)
            result[key] = dict(node.attrib) if key == 'repository' else (node.text or '').strip()
    need(all(result.get(k) for k in ('id', 'version', 'license', 'repository')),
         'incomplete nuspec provenance')
    return result


def c_string(data, offset):
    need(0 <= offset < len(data), 'string offset outside native image')
    end = data.find(b'\0', offset)
    need(end >= offset, 'unterminated native string')
    return data[offset:end].decode('ascii')


def inspect_elf(data):
    need(len(data) >= 64 and data[:6] == b'\x7fELF\x02\x01', 'expected little-endian ELF64')
    header = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
    need(header[1] == 3 and header[2] == 62, 'expected x86-64 ELF shared library')
    offset, size, count = header[6], header[11], header[12]
    need(size == 64 and 0 < count <= 4096 and offset + size * count <= len(data),
         'invalid ELF section directory')
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, offset + i * size) for i in range(count)]
    needed, rpath, versions = [], [], []
    for section in sections:
        need(section[1] == 8 or section[4] + section[5] <= len(data), 'ELF section outside image')
        if section[1] == 6:
            need(section[6] < count and section[5] % 16 == 0, 'invalid ELF dynamic section')
            strings = sections[section[6]]
            table = data[strings[4]:strings[4] + strings[5]]
            for i in range(0, section[5], 16):
                tag, value = struct.unpack_from('<qQ', data, section[4] + i)
                if tag == 1:
                    needed.append(c_string(table, value))
                elif tag in (15, 29):
                    rpath.append(c_string(table, value))
        elif section[1] == 0x6ffffffe:  # SHT_GNU_verneed: required, not merely present strings.
            need(section[6] < count, 'invalid ELF version string table')
            strings = sections[section[6]]
            table = data[strings[4]:strings[4] + strings[5]]
            pos, end = section[4], section[4] + section[5]
            while pos < end:
                need(pos + 16 <= end, 'truncated ELF version requirement')
                _, num, _, aux, nxt = struct.unpack_from('<HHIII', data, pos)
                a = pos + aux
                for _ in range(num):
                    need(a + 16 <= end, 'truncated ELF version auxiliary record')
                    _, _, _, name, following = struct.unpack_from('<IHHII', data, a)
                    versions.append(c_string(table, name))
                    a += following
                if not nxt:
                    break
                need(nxt >= 16, 'invalid ELF version link')
                pos += nxt
    return dict(format='ELF64', architectures=['x86_64'], needed=needed,
                rpath_runpath=rpath, required_symbol_versions=sorted(set(versions)))


def inspect_pe(data):
    need(len(data) >= 64 and data[:2] == b'MZ', 'expected PE DLL')
    offset = struct.unpack_from('<I', data, 0x3c)[0]
    need(offset + 24 <= len(data) and data[offset:offset + 4] == b'PE\0\0', 'invalid PE signature')
    machine, count, _, _, _, optsize, flags = struct.unpack_from('<HHIIIHH', data, offset + 4)
    need(machine == 0x8664 and flags & 0x2000, 'expected AMD64 PE DLL')
    opt = offset + 24
    need(optsize >= 128 and opt + optsize + count * 40 <= len(data)
         and struct.unpack_from('<H', data, opt)[0] == 0x20b, 'invalid PE32+ header')
    sections = [struct.unpack_from('<8sIIIIIIHHI', data, opt + optsize + i * 40)
                for i in range(count)]
    def file_offset(rva, length):
        for section in sections:
            _, _, start, rawsize, rawpos, *_ = section
            if start <= rva and rva + length <= start + rawsize:
                need(rawpos + rva - start + length <= len(data), 'PE RVA outside image')
                return rawpos + rva - start
        raise ValueError('unmapped PE RVA')
    directories = struct.unpack_from('<I', data, opt + 108)[0]
    need(2 <= directories <= 16 and optsize >= 112 + directories * 8,
         'invalid PE data directory count/size')
    imports, importsize = struct.unpack_from('<II', data, opt + 120)
    names = []
    if imports:
        need(20 <= importsize <= MAX_METADATA, 'invalid PE imports size')
        pos = file_offset(imports, importsize)
        end = pos + importsize
        while pos + 20 <= end:
            row = struct.unpack_from('<IIIII', data, pos)
            if not any(row):
                break
            names.append(c_string(data, file_offset(row[3], 1)))
            pos += 20
        else:
            raise ValueError('unterminated PE imports')
    # PE32+ directory 13 can hide additional runtime DLL requirements. Only
    # modern RVA descriptors are accepted; older VA descriptors need review.
    delay_names = []
    if directories > 13:
        delayed, delayed_size = struct.unpack_from('<II', data, opt + 112 + 13 * 8)
        need(bool(delayed) == bool(delayed_size), 'inconsistent PE delay imports')
        if delayed:
            need(32 <= delayed_size <= MAX_METADATA, 'invalid PE delay imports size')
            pos = file_offset(delayed, delayed_size)
            end = pos + delayed_size
            while pos + 32 <= end:
                row = struct.unpack_from('<IIIIIIII', data, pos)
                if not any(row):
                    break
                need(row[0] == 1, 'unsupported PE delay import attributes')
                delay_names.append(c_string(data, file_offset(row[1], 1)))
                pos += 32
            else:
                raise ValueError('unterminated PE delay imports')
    return dict(format='PE32+', architectures=['x86_64'], imports=names, delay_imports=delay_names)


def inspect_macho(data):
    need(len(data) >= 8 and data[:4] == b'\xca\xfe\xba\xbe', 'expected universal Mach-O')
    count = struct.unpack_from('>I', data, 4)[0]
    need(1 <= count <= 8 and len(data) >= 8 + count * 20, 'invalid Mach-O slice table')
    slices, spans = [], []
    for i in range(count):
        cpu, _, offset, size, _ = struct.unpack_from('>IIIII', data, 8 + i * 20)
        need(size >= 32 and offset >= 8 + count * 20 and offset + size <= len(data),
             'Mach-O slice outside image')
        need(all(offset + size <= lo or offset >= hi for lo, hi in spans), 'overlapping Mach-O slices')
        spans.append((offset, offset + size))
        need(data[offset:offset + 4] == b'\xcf\xfa\xed\xfe', 'expected 64-bit Mach-O slice')
        _, actual, _, kind, ncmds, cmdsize, _, _ = struct.unpack_from('<IIIIIIII', data, offset)
        need(cpu == actual and kind == 6 and ncmds <= 2048 and cmdsize <= size - 32,
             'invalid Mach-O dylib header')
        names, minimum, pos = [], [], offset + 32
        for _ in range(ncmds):
            need(pos + 8 <= offset + 32 + cmdsize, 'truncated Mach-O load command')
            cmd, length = struct.unpack_from('<II', data, pos)
            need(length >= 8 and pos + length <= offset + 32 + cmdsize, 'invalid Mach-O load command')
            if cmd in (0xc, 0xd, 0x80000018, 0x8000001f):
                need(length >= 24, 'truncated Mach-O dylib command')
                name = struct.unpack_from('<I', data, pos + 8)[0]
                names.append(dict(command=hex(cmd), name=c_string(data[pos:pos + length], name)))
            if cmd in (0x24, 0x32):
                need(length >= 16, 'truncated Mach-O minimum version')
                version = struct.unpack_from('<I', data, pos + (12 if cmd == 0x32 else 8))[0]
                minimum.append(f'{version >> 16}.{(version >> 8) & 255}.{version & 255}')
            pos += length
        arch = {0x1000007: 'x86_64', 0x100000c: 'aarch64'}.get(cpu)
        need(arch is not None, 'unapproved Mach-O architecture')
        slices.append(dict(architecture=arch, dylibs=names, minimum_os=minimum))
    need(sorted(s['architecture'] for s in slices) == ['aarch64', 'x86_64'], 'missing/duplicate universal slices')
    return dict(format='Mach-O universal', architectures=['aarch64', 'x86_64'], slices=slices)


def inspect_native(data, target):
    return {'linux': inspect_elf, 'win32': inspect_pe, 'macos': inspect_macho}[target](data)


def inspect_input(path, kind, target, version):
    package = ('skiasharp' if kind == 'skia' else 'harfbuzzsharp') + '.nativeassets.' + target
    need(path.is_file() and not path.is_symlink() and path.stat().st_size <= MAX_ARCHIVE,
         'missing/unsafe/oversized native archive')
    data = path.read_bytes()
    with zipfile.ZipFile(path) as archive:
        index = zip_index(archive)
        specs = [n for n in index if '/' not in n and n.lower().endswith('.nuspec')]
        need(len(specs) == 1, 'expected one root nuspec')
        metadata = nuspec_metadata(bounded_member(archive, index, specs[0], MAX_METADATA))
        need(metadata['id'].lower() == package and metadata['version'] == version,
             'wrong NuGet identity/version')
        target_info = TARGETS[target]
        filename = ('libSkiaSharp' if kind == 'skia' else 'libHarfBuzzSharp') + target_info['suffix']
        member = 'runtimes/' + target_info['rid'] + '/native/' + filename
        library = bounded_member(archive, index, member)
        inspection = inspect_native(library, target)
        members = {}
        for name, value in [(specs[0], bounded_member(archive, index, specs[0], MAX_METADATA)),
                            (member, library),
                            *[(n, bounded_member(archive, index, n, MAX_METADATA))
                              for n in ('LICENSE.txt', 'THIRD-PARTY-NOTICES.txt')]]:
            members[name] = dict(size=len(value), sha256=sha256(value))
    return dict(package=package, version=version, kind=kind, target=target,
                url=f'https://api.nuget.org/v3-flatcontainer/{package}/{version}/{package}.{version}.nupkg',
                size=len(data), sha256=sha256(data), members=members, nuspec=specs[0],
                library_member=member, library_filename=filename, metadata=metadata,
                inspection=inspection)


def check_locked_input(path, record):
    actual = inspect_input(path, record['kind'], record['target'], record['version'])
    need(actual == record, 'input differs from lock: ' + str(path))
    return actual


def inspect_font(data):
    need(12 <= len(data) <= MAX_FONT and data[:4] in (b'OTTO', b'\0\1\0\0'), 'invalid/oversized OpenType font')
    count = struct.unpack_from('>H', data, 4)[0]
    need(0 < count <= 128 and 12 + count * 16 <= len(data), 'invalid font table directory')
    tables = {}
    for i in range(count):
        tag, _, offset, size = struct.unpack_from('>4sIII', data, 12 + 16 * i)
        need(tag not in tables and offset + size <= len(data), 'duplicate/out-of-bounds font table')
        tables[tag] = data[offset:offset + size]
    need(b'name' in tables, 'font has no name/notice table')
    names = tables[b'name']
    need(len(names) >= 6, 'truncated font name table')
    _, count, start = struct.unpack_from('>HHH', names)
    need(count <= 4096 and 6 + count * 12 <= len(names) and start <= len(names), 'invalid font name records')
    values = {}
    for i in range(count):
        platform, _, _, ident, size, offset = struct.unpack_from('>HHHHHH', names, 6 + 12 * i)
        need(start + offset + size <= len(names), 'font name outside table')
        if ident in (0, 1, 5, 13, 14):
            raw = names[start + offset:start + offset + size]
            encoding = 'utf-16-be' if platform in (0, 3) else 'mac_roman'
            values.setdefault(str(ident), set()).add(raw.decode(encoding))
    need(values.get('0') and values.get('1'), 'font copyright/family metadata absent')
    return {k: sorted(v) for k, v in sorted(values.items())}


def validate_observations(lock):
    need(lock.get('schema') == 1 and lock.get('generation') == 1
         and lock.get('directory') == 'skia-native-1', 'unsupported native lock')
    need(lock.get('targets') == TARGETS, 'unreviewed package/platform selectors')
    need(lock.get('upstream_versions') == native_pins(), 'native pin drift')
    need(lock.get('native_package_version') == '1.0', 'unreviewed native package version')
    need(lock.get('transformations') == [], 'unreviewed native transformation')
    records = lock.get('archives', {})
    need(len(records) == 6, 'incomplete/extra native archive set')
    for target in TARGETS:
        for kind, version in native_pins().items():
            package = ('skiasharp' if kind == 'skia' else 'harfbuzzsharp') + '.nativeassets.' + target
            filename = f'{package}.{version}.nupkg'
            record = records.get(filename, {})
            need(record.get('package') == package and record.get('target') == target
                 and record.get('kind') == kind and record.get('version') == version,
                 'wrong locked package pair: ' + filename)
            expected_url = f'https://api.nuget.org/v3-flatcontainer/{package}/{version}/{filename}'
            need(record.get('url') == expected_url, 'unapproved input URL')
            need(isinstance(record.get('sha256'), str)
                 and re.fullmatch('[0-9a-f]{64}', record['sha256']), 'invalid locked archive digest')
    return lock


def validate_distribution_lock(lock, root=ROOT):
    validate_observations(lock)
    need(lock.get('distribution') == DISTRIBUTION, 'unreviewed native distribution/acquisition policy')
    need(lock.get('review', {}).get('redistribution_targets') == list(DISTRIBUTED_TARGETS),
         'redistribution review must explicitly cover the shipped macOS/Linux targets')
    expected_checksums = ''.join(r['sha256'] + '  ' + name + '\n' for name,r in sorted(lock['archives'].items()))
    need((root / 'packaging/native-inputs.sha256').read_text() == expected_checksums,
         'legacy installer checksums differ from the reviewed lock')
    for key, expected_path in (
            ('component_build_evidence', 'packaging/component-build-evidence.json'),
            ('redistribution_review_document', 'packaging/REDISTRIBUTION-REVIEW.md')):
        evidence = lock.get(key, {})
        need(evidence.get('path') == expected_path, 'missing component build evidence: ' + key)
        evidence_path = source_path(root, evidence['path'])
        need(evidence_path.is_file() and not evidence_path.is_symlink()
             and evidence_path.stat().st_size <= MAX_METADATA, 'missing/unsafe component build evidence')
        data = evidence_path.read_bytes()
        need(len(data) == evidence.get('size') and sha256(data) == evidence.get('sha256'),
             'component build evidence differs from lock: ' + key)
    configurations = lock.get('configurations', {})
    need(set(configurations) == {'linux-fontconfig'}, 'incomplete/extra support configuration set')
    configuration = configurations['linux-fontconfig']
    need(configuration.get('path') == 'packaging/fontconfig/fonts.conf.in'
         and configuration.get('filename') == 'fontconfig/fonts.conf.in'
         and configuration.get('license') == 'MIT', 'unreviewed support configuration')
    path = source_path(root, configuration['path'])
    need(path.is_file() and not path.is_symlink() and path.stat().st_size <= 65536,
         'missing/unsafe support configuration')
    data = path.read_bytes()
    need(len(data) == configuration['size'] and sha256(data) == configuration['sha256'],
         'support configuration differs from lock')
    need(all(data.count(placeholder) == 1 for placeholder in (b'@FONT_DIRECTORIES@', b'@CACHE_DIRECTORY@')),
         'invalid configuration template placeholders')
    need(lock.get('review', {}).get('status') in ('technical-review', 'approved'), 'unreviewed distribution lock')
    notices = lock.get('supplemental_notices', {})
    required = {'wuffs', 'd3d12allocator', 'vma', 'spirv-cross', 'skia', 'harfbuzz',
                'freetype', 'expat', 'libwebp', 'spirv-tools', 'spirv-headers',
                'gcc-runtime', 'gcc-gpl3', 'png-license', 'piex-license', 'zlib-license',
                'libjpeg-license', 'libjpeg-ijg', 'dng-LICENSE', 'dng-NOTICE',
                'dng-LICENSE.source_code', 'dng-LICENSE.technology', 'dng-PATENTS', 'noto-ofl', 'cjk-ofl'}
    need(set(notices) == required, 'incomplete/extra supplemental notice set')
    for name, record in notices.items():
        safe_name(record['path'])
        need(record['path'].startswith('packaging/licenses/'), 'notice outside reviewed license directory')
        path = source_path(root, record['path'])
        need(path.is_file() and not path.is_symlink() and path.stat().st_size <= MAX_METADATA,
             'missing/unsafe notice: ' + name)
        data = path.read_bytes()
        need(len(data) == record['size'] and sha256(data) == record['sha256'], 'supplemental notice drift: ' + name)
        need(record.get('source', '').startswith('https://') and record.get('license'), 'missing notice provenance')
    fonts = lock.get('documentation_fonts', {})
    need(fonts.get('name') == fonts.get('collection') == 'skia-doc'
         and fonts.get('version') == '0.79' and fonts.get('directory') == 'fonts' and len(fonts.get('files', [])) == 4, 'invalid documentation font policy')
    for f in fonts['files']:
        need(safe_name(f['filename']) == Path(f['filename']).name and f['license'] == 'OFL-1.1', 'unsafe font record')
        need(f['notice'] in ('noto-ofl', 'cjk-ofl') and 0 < f['size'] <= MAX_FONT
             and re.fullmatch('[0-9a-f]{64}', f['sha256']), 'invalid font digest/notice')
        need(f['url'].startswith('https://raw.githubusercontent.com/notofonts/')
             and '/' + f['source_commit'] + '/' in f['url']
             and re.fullmatch('[0-9a-f]{40}', f['source_commit']), 'font source is not immutable')
    need(lock.get('support_dependencies', {}).get('linux') == [
        {'name': 'draw-x86_64-linux-natipkg-3', 'platform': '"x86_64-linux-natipkg"'},
        {'name': 'draw-ttf-x86_64-linux-natipkg', 'platform': '"x86_64-linux-natipkg"'}], 'unreviewed Linux support dependency')
    return lock


def check_font_input(path, record):
    need(path.is_file() and not path.is_symlink() and path.stat().st_size == record['size'], 'wrong font input size')
    data = path.read_bytes()
    need(sha256(data) == record['sha256'], 'font SHA-256 mismatch')
    need(hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() == record['git_blob_sha1'],
         'font differs from independently inspected Git blob identity')
    need(inspect_font(data) == record['names'], 'font name/copyright metadata drift')
    return data


def write_zip(destination, members):
    need(not destination.exists(), 'refusing to replace archive: ' + str(destination))
    for name in members:
        safe_name(name)
    need(len({n.casefold() for n in members}) == len(members), 'colliding output members')
    with zipfile.ZipFile(destination, 'x', compression=zipfile.ZIP_STORED) as archive:
        for name, data in sorted(members.items()):
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    data = destination.read_bytes()
    checksum = hashlib.sha1(data).hexdigest()
    # Racket compares the companion as an exact string (including whitespace).
    destination.with_suffix(destination.suffix + '.CHECKSUM').write_text(checksum, encoding='ascii')
    return dict(size=len(data), sha1=checksum, sha256=sha256(data))

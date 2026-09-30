"""Required D3D12 validation orchestration and independent evidence checks.

A passing WARP report establishes software functionality, never acceleration,
physical display pixels, or performance. No optional/skip/fallback mode exists.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import struct
import zlib

COUNTS = {'surface': 33, 'image': 42, 'cache': 20}
CYCLES = 3
FRAMES = 180


def require(condition, message):
    if not condition:
        raise ValueError(message)


def png_rgba(path: Path) -> tuple[int, int, bytes]:
    """Bounded PNG verification, including CRCs, row filters and alpha."""
    require(path.stat().st_size <= 1024 * 1024, 'oversized PNG')
    data = path.read_bytes()
    require(data.startswith(b'\x89PNG\r\n\x1a\n'), 'bad PNG signature')
    offset, header, compressed, done = 8, None, bytearray(), False
    saw_idat, idat_ended = False, False
    while offset < len(data):
        require(offset + 12 <= len(data), 'truncated PNG chunk')
        size = struct.unpack_from('>I', data, offset)[0]
        tag = data[offset + 4:offset + 8]
        end = offset + 12 + size
        require(end <= len(data), 'PNG chunk length exceeds file')
        body = data[offset + 8:offset + 8 + size]
        crc = struct.unpack_from('>I', data, offset + 8 + size)[0]
        require(zlib.crc32(tag + body) & 0xffffffff == crc, 'PNG CRC mismatch')
        if header is None:
            require(tag == b'IHDR' and size == 13, 'PNG must start with one IHDR')
            header = struct.unpack('>IIBBBBB', body)
        elif tag == b'IHDR':
            raise ValueError('duplicate IHDR')
        elif tag == b'IDAT':
            require(not idat_ended, 'nonconsecutive IDAT chunks')
            saw_idat = True
            compressed.extend(body)
        elif tag == b'IEND':
            require(size == 0 and saw_idat and end == len(data), 'invalid PNG ending')
            done = True
            break
        else:
            if saw_idat:
                idat_ended = True
            require(bool(tag[0] & 32) or tag == b'PLTE', 'unknown critical PNG chunk')
        offset = end
    require(done and header is not None, 'missing PNG ending')
    width, height, depth, kind, compression, filtering, interlace = header
    require((width, height) == (8, 8) and depth == 8 and kind in (2, 6), 'unexpected PNG format/dimensions')
    require((compression, filtering, interlace) == (0, 0, 0), 'unsupported PNG coding')
    bpp = 4 if kind == 6 else 3
    stride = width * bpp
    expected = height * (1 + stride)
    decoder = zlib.decompressobj()
    raw = decoder.decompress(bytes(compressed), expected + 1)
    require(len(raw) == expected and decoder.eof and not decoder.unconsumed_tail and not decoder.unused_data,
            'PNG inflation length/stream mismatch')
    rows, previous = [], bytes(stride)
    for y in range(height):
        mode = raw[y * (stride + 1)]
        row = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        require(mode <= 4, 'unknown PNG row filter')
        for x in range(stride):
            a = row[x - bpp] if x >= bpp else 0
            b = previous[x]
            c = previous[x - bpp] if x >= bpp else 0
            if mode == 0: value = 0
            elif mode == 1: value = a
            elif mode == 2: value = b
            elif mode == 3: value = (a + b) // 2
            else:
                p = a + b - c
                distances = (abs(p - a), abs(p - b), abs(p - c))
                value = (a, b, c)[distances.index(min(distances))]
            row[x] = (row[x] + value) & 255
        rows.append(bytes(row)); previous = row
    pixels = b''.join(rows)
    if bpp == 3:
        pixels = b''.join(pixels[i:i+3] + b'\xff' for i in range(0, len(pixels), 3))
    return width, height, pixels


def pattern() -> bytes:
    return b''.join(bytes((0, 0, 0, 0) if x == 3 else
                         ((255, 0, 0, 255) if x < 3 else (0, 255, 0, 255)) if y < 4 else
                         ((0, 0, 255, 255) if x < 3 else (255, 255, 0, 255)))
                    for y in range(8) for x in range(8))


def inspect(directory: Path, selection='warp', index=0) -> dict:
    require(selection in ('warp', 'hardware') and type(index) is int and 0 <= index < 0xffffffff, 'unknown adapter selection/index')
    require(selection != 'warp' or index == 0, 'WARP does not accept a hardware index')
    data = json.loads((directory / 'd3d12.diagnostic.json').read_text(encoding='utf-8'))
    require(isinstance(data, dict), 'diagnostic must be an object')
    require(type(data.get('schema')) is int and data['schema'] == 1 and data.get('stage') == '0.48' and data.get('status') == 'passed', 'D3D12 diagnostic did not pass')
    require(data.get('validation_run') == directory.name, 'foreign/stale D3D12 run')
    require(data.get('os') == 'windows' and data.get('architecture') == 'x86_64', 'not Windows x64 execution')
    require(data.get('adapter_selection') == selection, 'adapter selection changed')
    for field in ('window_created', 'presentation_verified', 'hardware_acceleration_verified', 'performance_measured'):
        require(data.get(field) is False, f'unsupported claim: {field}')
    counts = data['test_counts']
    require(isinstance(counts, dict), 'test counts must be an object')
    for name, count in COUNTS.items():
        require(type(counts.get(name)) is int and counts[name] == count, 'missing shared native suite coverage')
        require(type(counts.get(name + '_failures')) is int and counts[name + '_failures'] == 0, 'native test failures')
    cycles = data['cycles']
    require(isinstance(cycles, list) and len(cycles) == CYCLES, 'incomplete context recreation')
    generations, files, evidence = set(), set(), []
    for i, cycle in enumerate(cycles):
        require(isinstance(cycle, dict), 'cycle must be an object')
        require(type(cycle['cycle']) is int and cycle['cycle'] == i, 'cycle order/identity')
        require(type(cycle['frames']) is int and cycle['frames'] == FRAMES, 'stress shortened')
        for first, last in (('initial', 'final'), ('other_initial', 'other_final')):
            a, b = cycle[first], cycle[last]
            require(isinstance(a, dict) and isinstance(b, dict), 'context must be an object')
            generation = a['generation']
            require(type(generation) is int and generation > 0 and generation not in generations, 'reused context generation')
            generations.add(generation)
            for context in (a, b):
                require(context['backend'] == 'direct3d' and context['native_backend'] == 3, 'wrong native backend')
                require(type(context['generation']) is int and context['generation'] == generation, 'context generation changed')
                require(context['adapter_selection'] == selection, 'foreign adapter')
                require(context['api'] == 'D3D12', 'wrong device API')
                require(context['minimum_feature_level'] == 0xb000, 'wrong device feature-level request')
                adapter_index = context['adapter_index']
                require(adapter_index is False if selection == 'warp' else type(adapter_index) is int and adapter_index == index,
                        'adapter index differs from explicit request')
                for field, lo, hi in (('adapter_vendor_id', 0, 0xffffffff), ('adapter_device_id', 0, 0xffffffff),
                                     ('adapter_luid_low', 0, 0xffffffff), ('adapter_luid_high', -0x80000000, 0x7fffffff)):
                    require(type(context[field]) is int and lo <= context[field] <= hi, 'missing/invalid adapter identity')
                require(isinstance(context['adapter_name'], str) and bool(context['adapter_name']), 'missing adapter name')
                for field in ('adapter_name', 'adapter_vendor_id', 'adapter_device_id', 'adapter_luid_low', 'adapter_luid_high'):
                    require(context[field] == a[field], 'adapter identity changed within a context')
                flags = context['adapter_flags']
                require(type(flags) is int and flags >= 0, 'invalid DXGI adapter flags')
                software = bool(flags & 2)
                require(software == (selection == 'warp'), 'adapter is not the selected class')
                require(context['d3d12_warp'] is (selection == 'warp'), 'WARP identity mismatch')
                require(context['renderer_class'] == ('software' if software else 'hardware-reported'), 'renderer class mismatch')
                require(context['command_queue_owned'] is True and context['command_queue_type'] == 'direct', 'wrong queue ownership/type')
                require(context['window_created'] is False and context['requires_gui'] is False, 'unexpected GUI')
                require(context['hardware_acceleration_verified'] is False, 'acceleration is not established by adapter flags')
                for key in ('live_children', 'pending_releases', 'failed_releases'):
                    require(type(context[key]) is int and context[key] == 0, 'resource leak/indeterminate release')
            require(a['state'] == 'ready' and b['state'] == 'closed', 'teardown incomplete')
        target, image = cycle['target'], cycle['image']
        require(isinstance(target, dict) and isinstance(image, dict), 'target/image must be objects')
        generation = cycle['initial']['generation']
        require(target['backend'] == 'direct3d' and target['native_backend'] == 3 and target['context_matches'] is True, 'target is not Direct3D')
        require(type(target['context_generation']) is int and target['context_generation'] == generation, 'foreign surface')
        require((target['width'], target['height']) == (8, 8), 'wrong target dimensions')
        require(image['backend'] == 'direct3d' and type(image['context_generation']) is int and image['context_generation'] == generation, 'foreign image')
        require(image['texture_backed'] is True and image['context_matches'] is True, 'image not GPU-resident')
        require(cycle['detached_encoded_after_teardown'] is True, 'CPU detachment not tested after teardown')
        io = cycle['io']
        require(isinstance(io, list), 'missing raw transfer ledger')
        require(all(isinstance(row, dict) for row in io), 'transfer ledger rows must be objects')
        kinds = [row['kind'] for row in io]
        require(kinds.count('upload') == 1, 'resident stress must use one explicit upload')
        require(kinds.count('gpu-snapshot') == 6 and kinds.count('gpu-subset') == 6, 'incomplete image checkpoints')
        submits = [row for row in io if row['kind'] == 'submit']
        require(all(type(row.get('wait_requested')) is bool for row in submits), 'missing completion policy')
        require(sum(row['wait_requested'] is False for row in submits) == FRAMES, 'normal frames must submit without CPU waits')
        require(kinds.count('readback') >= 8, 'explicit readback evidence incomplete')
        for k, row in enumerate(io):
            if row['kind'] == 'readback':
                require(k + 2 < len(io) and io[k+1]['kind'] == 'flush' and io[k+2]['kind'] == 'submit'
                        and io[k+2]['wait_requested'] is True, 'readback lacks completion boundary')
        for role in ('cpu', 'gpu', 'detached'):
            name = cycle[role + '_png']
            require(name == f'cycle-{i}-{role}.png' and name not in files, 'unsafe/duplicate pixel artifact')
            files.add(name)
            path = directory / name
            require(path.is_file() and not path.is_symlink(), 'missing/unsafe pixel artifact')
            require(png_rgba(path)[2] == pattern(), 'PNG pixels differ from independent asymmetric reference')
            evidence.append({'file': name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    return {'schema': 1, 'stage': '0.48', 'status': 'passed', 'validation_run': directory.name,
            'adapter_selection': selection, 'renderer_class': 'software' if selection == 'warp' else 'hardware-reported',
            'native_cases': sum(COUNTS.values()), 'contexts': len(generations), 'cycles': CYCLES,
            'stress_frames': CYCLES * FRAMES, 'pngs': evidence,
            'hardware_acceleration_verified': False, 'window_created': False,
            'presentation_verified': False, 'performance_measured': False}


def execute(root: Path, racket: str, directory: Path, run, *, selection='warp', index=0) -> dict:
    """Run inside an installed copy or checkout. `run` logs and raises on failure."""
    require(selection in ('warp', 'hardware') and type(index) is int and 0 <= index < 0xffffffff, 'invalid adapter arguments')
    require(selection != 'warp' or index == 0, 'WARP does not accept a hardware index')
    require(directory.is_dir() and not any(directory.iterdir()), 'D3D12 output must be fresh and empty')
    identity = json.loads(run([racket, root / 'tools/ci-identity.rkt']))
    require(isinstance(identity, dict), 'Racket identity must be an object')
    require(identity['os'] == 'windows' and identity['architecture'] == 'x86_64' and type(identity['pointer_bytes']) is int and identity['pointer_bytes'] == 8,
            'D3D12 validation requires Windows x64 Racket')
    build = directory / 'abi'
    run(['cmake', '-S', root / 'tools/d3d12-abi', '-B', build, '-G', 'Visual Studio 17 2022', '-A', 'x64'])
    run(['cmake', '--build', build, '--config', 'Release'])
    run(['ctest', '--test-dir', build, '-C', 'Release', '--output-on-failure'])
    call_report = json.loads(run([racket, root / 'tools/check-d3d12-call.rkt', build / 'Release/d3d12-call-fixture.dll']))
    require(isinstance(call_report, dict), 'call-ABI result must be an object')
    require(call_report.get('status') == 'passed' and call_report.get('by_value_call_verified') is True,
            'Racket by-value ABI call did not pass')
    run([racket, '-l', 'raco', '--', 'make', root / 'tools/gpu-d3d12-doctor.rkt'])
    run([racket, root / 'tools/gpu-d3d12-doctor.rkt', '--directory', directory,
         '--adapter', selection, '--adapter-index', str(index)])
    result = inspect(directory, selection, index)
    result['racket_identity'] = identity
    result['by_value_call_verified'] = True
    result['windows_sdk_abi_verified'] = True
    (directory / 'd3d12.inspection.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    return result

"""DXGI presentation evidence: actual swap-chain pixels, not screen certification.

Windows x64 WARP is required in CI. The old offscreen gate remains independent.
No missing device, occlusion-only run, malformed report, or failed subprocess
may become a successful optional skip.
"""
from __future__ import annotations
import hashlib
import html
import json
import os
from pathlib import Path
import struct
import zlib

CYCLES = 3
WINDOWS = 2
CAPTURES = 3
STRESS_FRAMES = 180
NORMAL_FRAMES = STRESS_FRAMES + CAPTURES
NATIVE_CASES = 28
SIZES = dict(swap_desc=48, rect=16, texture_info=40, transition=32,
             heap_properties=20, resource_desc=56, copy_location=48, range=16)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def integer(value, low=0, high=0x7fffffffffffffff):
    return type(value) is int and low <= value <= high


def read_json(path: Path, maximum=8 * 1024 * 1024):
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= maximum,
            'missing, unsafe or oversized JSON evidence: ' + path.name)
    def unique(pairs):
        result = {}
        for k, v in pairs:
            require(k not in result, 'duplicate JSON key: ' + k)
            result[k] = v
        return result
    return json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique,
                      parse_constant=lambda s: (_ for _ in ()).throw(ValueError('non-finite JSON: ' + s)))


def select(selection, index):
    require(selection in ('warp', 'hardware') and integer(index, 0, 0xfffffffe), 'invalid adapter selection')
    require(selection != 'warp' or index == 0, 'WARP has no adapter index')


def png_rgba(path: Path) -> tuple[int, int, bytes]:
    """Bounded PNG verification, including CRCs, row filters and alpha."""
    require(path.stat().st_size <= 4 * 1024 * 1024, 'oversized PNG')
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
    require(1 <= width <= 2048 and 1 <= height <= 2048 and depth == 8 and kind in (2, 6), 'unexpected PNG format/dimensions')
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


def pattern(w: int, h: int) -> bytes:
    """Independent asymmetric pixel oracle; not copied from the Racket output."""
    require(integer(w, 2, 2048) and integer(h, 2, 2048), 'bad pattern extent')
    red, blue, black, white = (bytes(p) for p in ((255, 0, 0, 255), (0, 0, 255, 255),
                                               (0, 0, 0, 255), (255, 255, 255, 255)))
    top = red * (w // 2) + blue * (w - w // 2)
    bottom = black * (w // 2) + white * (w - w // 2)
    pixels = top * (h // 2) + bottom * (h - h // 2)
    return bytes((255, 255, 0, 255)) + pixels[4:]


def context(c, selection, index, generation, state, children):
    require(isinstance(c, dict), 'missing context')
    require(c.get('backend') == 'direct3d' and type(c.get('native_backend')) is int
            and c['native_backend'] == 3, 'not a native Direct3D context')
    require(integer(c.get('generation'), 1) and c['generation'] == generation, 'foreign context generation')
    require(c.get('state') == state, 'incorrect context lifecycle state')
    require(c.get('adapter_selection') == selection and c.get('api') == 'D3D12', 'wrong adapter API/selection')
    require(c.get('adapter_index') is False if selection == 'warp'
            else type(c.get('adapter_index')) is int and c['adapter_index'] == index, 'wrong adapter index')
    require(c.get('d3d12_warp') is (selection == 'warp'), 'wrong WARP identity')
    flags = c.get('adapter_flags')
    require(integer(flags, 0, 0xffffffff) and bool(flags & 2) == (selection == 'warp'), 'wrong adapter class')
    require(c.get('renderer_class') == ('software' if selection == 'warp' else 'hardware-reported'), 'renderer class mismatch')
    require(c.get('command_queue_owned') is True and c.get('command_queue_type') == 'direct', 'queue not owned/direct')
    require(c.get('hardware_acceleration_verified') is False, 'hardware not independently verified')
    for k, n in (('live_children', children), ('pending_releases', 0), ('failed_releases', 0)):
        require(type(c.get(k)) is int and c[k] == n, 'context reference leak: ' + k)
    require(isinstance(c.get('adapter_name'), str) and bool(c['adapter_name']), 'adapter name absent')
    for k, lo, hi in (('adapter_vendor_id', 0, 0xffffffff), ('adapter_device_id', 0, 0xffffffff),
                      ('adapter_luid_low', 0, 0xffffffff), ('adapter_luid_high', -0x80000000, 0x7fffffff)):
        require(integer(c.get(k), lo, hi), 'invalid adapter identity: ' + k)


def normal_io(rows):
    require(isinstance(rows, list) and 0 < len(rows) <= 18000 and len(rows) % 3 == 0, 'incomplete normal-frame ledger')
    submitted, occluded, indices, prior_fence = 0, 0, set(), 0
    for i in range(0, len(rows), 3):
        group = rows[i:i + 3]
        require(all(isinstance(row, dict) for row in group), 'malformed ledger row')
        require([r.get('kind') for r in group] == ['flush', 'submit', 'present-request'],
                'normal frame has hidden transfer or wrong submission order')
        # Shared flush events deliberately omit wait_requested; submit/present
        # must state it explicitly. Never accept a true/unknown wait request.
        require(group[0].get('wait_requested', False) is False and
                all(r.get('wait_requested') is False for r in group[1:]),
                'normal API requested a CPU completion wait')
        p = group[-1]
        require(p.get('backend') == 'direct3d' and p.get('method') == 'dxgi-same-queue', 'wrong presentation queue')
        require(integer(p.get('buffer_index'), 0, 1) and integer(p.get('swap_chain_generation'), 1)
                and integer(p.get('fence_value'), 1, 0xfffffffffffffffe), 'missing native frame identity')
        require(p['fence_value'] > prior_fence, 'normal frames reuse a fence value')
        prior_fence = p['fence_value']
        require(type(p.get('hresult')) is int, 'invalid Present HRESULT')
        if p.get('result') == 'submitted' and p['hresult'] == 0:
            submitted += 1
            indices.add(p['buffer_index'])
        elif p.get('result') == 'occluded' and p['hresult'] == 0x087a0001:
            occluded += 1
        else:
            raise ValueError('failed/unknown Present cannot count as success')
    require(submitted == NORMAL_FRAMES, 'normal/stress frames shortened or duplicated')
    require(indices == {0, 1}, 'both DXGI back buffers were not used')
    return submitted, occluded, len(rows) // 3


def inspect(directory: Path, selection='warp', index=0) -> dict:
    select(selection, index)
    d = read_json(directory / 'dxgi.diagnostic.json')
    require(isinstance(d, dict) and type(d.get('schema')) is int and d['schema'] == 1
            and d.get('stage') == '0.49' and d.get('status') == 'passed', 'DXGI diagnostic did not pass')
    require(d.get('validation_run') == directory.name, 'foreign/stale DXGI run')
    require(d.get('os') == 'windows' and d.get('architecture') == 'x86_64', 'not Windows x64')
    require(d.get('adapter_selection') == selection, 'selection changed')
    require(d.get('adapter_index') is False if selection == 'warp'
            else type(d.get('adapter_index')) is int and d['adapter_index'] == index, 'adapter index changed')
    for k in ('visible_pixels_verified', 'hardware_acceleration_verified', 'performance_measured'):
        require(d.get(k) is False, 'unsupported claim: ' + k)
    require(d.get('window_created') is True and d.get('presentation_submission_verified') is True, 'no actual window/presentation')
    counts = d.get('test_counts')
    require(isinstance(counts, dict) and type(counts.get('presenter')) is int and counts['presenter'] == NATIVE_CASES
            and type(counts.get('presenter_failures')) is int and counts['presenter_failures'] == 0,
            'shared native presenter coverage/failures')
    cycles = d.get('cycles')
    require(isinstance(cycles, list) and len(cycles) == CYCLES, 'incomplete lifecycle cycles')
    generations, pngs, adapters = set(), [], set()
    total_waits = 0
    for ci, cycle in enumerate(cycles):
        require(isinstance(cycle, dict) and type(cycle.get('cycle')) is int and cycle['cycle'] == ci, 'wrong cycle order')
        windows = cycle.get('windows')
        require(isinstance(windows, list) and len(windows) == WINDOWS, 'two simultaneous windows required')
        for wi, w in enumerate(windows):
            require(isinstance(w, dict) and type(w.get('window')) is int and w['window'] == wi, 'wrong window identity')
            for key, expected in (('stress_frames', STRESS_FRAMES), ('normal_frames', NORMAL_FRAMES)):
                require(type(w.get(key)) is int and w[key] == expected, 'incomplete controlled frame count')
            first, ready, final = w['initial'], w['before_close'], w['final']
            generation = first.get('generation')
            require(integer(generation, 1) and generation not in generations, 'reused context generation')
            generations.add(generation)
            context(first, selection, index, generation, 'ready', 1)
            identity = tuple(first[k] for k in ('adapter_name', 'adapter_vendor_id', 'adapter_device_id', 'adapter_luid_low', 'adapter_luid_high'))
            adapters.add(identity)
            for report, expected_state, children in ((ready, 'ready', 1), (final, 'closed', 0)):
                require(isinstance(report, dict) and report.get('backend') == 'direct3d' and report.get('state') == expected_state, 'presenter not retired/ready')
                require(report.get('visible_pixels_verified') is False and report.get('performance_measured') is False, 'presenter claim inflated')
                host = report['adapter']
                require(host.get('state') == expected_state and host.get('quarantined') is False
                        and type(host.get('quarantined_frames')) is int and host['quarantined_frames'] == 0, 'quarantined host cannot pass')
                context(host['context'], selection, index, generation, expected_state, children)
                require(tuple(host['context'][k] for k in ('adapter_name', 'adapter_vendor_id', 'adapter_device_id', 'adapter_luid_low', 'adapter_luid_high')) == identity, 'adapter changed inside context')
                require(host.get('backend') == 'direct3d' and host.get('window_system') == 'win32-hwnd'
                        and host.get('hwnd_ownership') == 'borrowed-racket-gui'
                        and host.get('queue_ownership') == 'context-driver'
                        and host.get('swap_chain_ownership') == 'presenter', 'ownership contract changed')
                require(host.get('window_created') is True and host.get('visible_pixels_verified') is False
                        and host.get('performance_measured') is False, 'host evidence/claim incorrect')
                require(type(host.get('presentation_context_children')) is int and host['presentation_context_children'] == children, 'missing presenter context pin')
                require(type(host.get('live_drawables')) is int and host['live_drawables'] == 0, 'unretired frame')
                require(type(host.get('live_back_buffers')) is int and host['live_back_buffers'] == (2 if children else 0), 'back-buffer reference leak')
                require(type(host.get('buffer_count')) is int and host['buffer_count'] == 2 and host.get('format') == 'RGBA8888'
                        and host.get('swap_effect') == 'flip-discard' and type(host.get('sync_interval')) is int and host['sync_interval'] == 1, 'swap-chain config changed')
                require(type(host.get('resize_count')) is int and host['resize_count'] == 2
                        and type(host.get('swap_chain_generation')) is int and host['swap_chain_generation'] == 3, 'resize lifecycle not exercised')
            host = ready['adapter']
            submitted, occluded, attempts = normal_io(w['normal_io'])
            require(type(host.get('presents_submitted')) is int and host['presents_submitted'] == NORMAL_FRAMES + CAPTURES,
                    'occlusion was counted as presented or present count incomplete')
            require(type(ready.get('presents_requested')) is int and ready['presents_requested'] == host['presents_submitted'], 'presenter/host success count mismatch')
            require(integer(host.get('validation_readbacks'), CAPTURES, 96), 'capture count missing/unbounded')
            require(type(host.get('frames_acquired')) is int and host['frames_acquired'] == attempts + host['validation_readbacks'], 'acquired buffer count mismatch')
            require(type(host.get('presents_occluded')) is int and host['presents_occluded'] == occluded + host['validation_readbacks'] - CAPTURES, 'unaccounted Present status')
            require(type(host.get('frames_cancelled')) is int and host['frames_cancelled'] == 0, 'controlled frame unexpectedly cancelled')
            require(type(host.get('fence_value')) is int and host['fence_value'] == host['frames_acquired'], 'missing queue fence')
            require(integer(final['adapter'].get('blocking_fence_waits')), 'fence waits unreported')
            total_waits += final['adapter']['blocking_fence_waits']
            # Closing may wait, but it cannot invent additional presented frames.
            for key in ('frames_acquired', 'presents_submitted', 'presents_occluded', 'validation_readbacks', 'fence_value'):
                require(type(final['adapter'].get(key)) is int and final['adapter'][key] == host[key], 'close mutated submission history')
            captures = w['captures']
            require(isinstance(captures, list) and len(captures) == CAPTURES, 'missing captures')
            extents, previous_fence, previous_frame, previous_target_generation = set(), 0, 0, 0
            for si, capture in enumerate(captures):
                require(type(capture.get('ordinal')) is int and capture['ordinal'] == si, 'capture order')
                require(capture.get('encoded_after_context_teardown') is True, 'encoding preceded context teardown')
                r, frame = capture['submission'], capture['frame']
                require(r.get('result') == 'submitted' and type(r.get('hresult')) is int and r['hresult'] == 0, 'capture not presented')
                require(r.get('same_queue') is True and r.get('skia_wrappers_retired_before_transition') is True,
                        'queue/retirement ordering absent')
                require(r.get('state_before_transition') == 'render-target' and r.get('state_at_present') == 'present', 'resource-state protocol changed')
                require(r.get('validation_readback') is True and r.get('visible_pixels_verified') is False, 'readback misrepresented')
                width, height = r['width'], r['height']
                require(integer(width, 2, 2048) and integer(height, 2, 2048), 'invalid capture extent')
                require(type(r.get('readback_row_pitch')) is int and r['readback_row_pitch'] == ((4 * width + 255) // 256) * 256, 'readback pitch mismatch')
                extents.add((width, height))
                require(r.get('format') == 'RGBA8888' and type(r.get('sample_count')) is int and r['sample_count'] == 1
                        and type(r.get('buffer_count')) is int and r['buffer_count'] == 2
                        and r.get('swap_effect') == 'flip-discard', 'capture not from reviewed target')
                require(integer(r.get('buffer_index'), 0, 1) and type(r.get('swap_chain_generation')) is int
                        and r['swap_chain_generation'] == si + 1, 'stale buffer generation')
                require(integer(r.get('fence_value'), previous_fence + 1, 0xfffffffffffffffe), 'reused fence value')
                previous_fence = r['fence_value']
                require(frame.get('backend') == 'direct3d' and frame.get('result') == 'present-requested', 'frame did not present')
                require(integer(frame.get('frame_index'), previous_frame + 1) and integer(frame.get('target_generation'), previous_target_generation + 1), 'expired target/frame reused')
                previous_frame, previous_target_generation = frame['frame_index'], frame['target_generation']
                require(type(frame.get('pixel_width')) is int and type(frame.get('pixel_height')) is int
                        and (frame['pixel_width'], frame['pixel_height']) == (width, height), 'frame size differs from native buffer')
                target = frame['target']
                require(target.get('backend') == 'direct3d' and type(target.get('native_backend')) is int and target['native_backend'] == 3
                        and target.get('context_matches') is True and target.get('target_kind') == 'dxgi-back-buffer', 'not a native DXGI target')
                require(type(target.get('context_generation')) is int and target['context_generation'] == generation, 'foreign target context')
                require((target.get('width'), target.get('height')) == (width, height)
                        and target.get('buffer_index') == r['buffer_index'] and target.get('swap_chain_generation') == si + 1,
                        'native target identity mismatch')
                require(type(target.get('buffer_index')) is int and type(target.get('swap_chain_generation')) is int
                        and type(target.get('actual_sample_count')) is int, 'target counts are not integers')
                require(r['fence_value'] == frame['frame_index'], 'frame/fence identity mismatch')
                require(target.get('target_identity') == f'dxgi-{generation}-{si + 1}'
                        and target.get('actual_sample_count') == 1 and target.get('render_path') == 'sk_surface_new_backend_render_target', 'wrong borrowed target')
                name = capture['png']
                require(name == f'cycle-{ci}-window-{wi}-size-{si}.png', 'unsafe/foreign pixel artifact name')
                path = directory / name
                require(path.is_file() and not path.is_symlink(), 'missing/unsafe pixels')
                pw, ph, pixels = png_rgba(path)
                require((pw, ph) == (width, height) and pixels == pattern(width, height), 'swap-chain pixels differ from independent pattern')
                pngs.append({'file': name, 'width': width, 'height': height, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
            require(len(extents) == CAPTURES, 'three different target extents were not captured')
    return dict(schema=1, stage='0.49', status='passed', validation_run=directory.name,
                adapter_selection=selection, renderer_class='software' if selection == 'warp' else 'hardware-reported',
                adapters=[list(a) for a in sorted(adapters)], native_presenter_cases=NATIVE_CASES,
                contexts=len(generations), cycles=CYCLES, windows=CYCLES * WINDOWS,
                stress_frames=CYCLES * WINDOWS * STRESS_FRAMES, captures=len(pngs), pngs=pngs,
                window_created=True, presentation_submission_verified=True, back_buffer_pixels_verified=True,
                blocking_fence_waits=total_waits, visible_pixels_verified=False,
                hardware_acceleration_verified=False, performance_measured=False)


def execute(root: Path, racket: str, directory: Path, run, *, selection='warp', index=0) -> dict:
    select(selection, index)
    require(directory.is_dir() and not any(directory.iterdir()), 'DXGI evidence directory must be fresh/empty')
    try:
        identity = json.loads(run([racket, root / 'tools/ci-identity.rkt']))
        require(isinstance(identity, dict) and identity.get('os') == 'windows' and identity.get('architecture') == 'x86_64'
                and type(identity.get('pointer_bytes')) is int and identity['pointer_bytes'] == 8, 'DXGI requires Windows x64 Racket')
        build = directory / 'abi'
        run(['cmake', '-S', root / 'tools/dxgi-abi', '-B', build, '-G', 'Visual Studio 17 2022', '-A', 'x64'])
        run(['cmake', '--build', build, '--config', 'Release'])
        run(['ctest', '--test-dir', build, '-C', 'Release', '--output-on-failure'])
        sdk = json.loads(run([build / 'Release/check-dxgi.exe']))
        layouts = json.loads(run([racket, root / 'tools/check-dxgi-layouts.rkt']))
        for r, kind in ((sdk, 'windows-sdk'), (layouts, 'racket-ffi-layouts')):
            require(isinstance(r, dict) and r.get('kind') == kind and r.get('status') == 'passed', 'ABI evidence missing or from host mirrors only')
            sizes = r.get('sizes')
            require(isinstance(sizes, dict) and set(sizes) == set(SIZES)
                    and all(type(sizes[k]) is int and sizes[k] == n for k, n in SIZES.items()), 'ABI size disagreement')
        require(type(sdk.get('slots_verified')) is int and sdk['slots_verified'] == 22
                and type(sdk.get('guids_verified')) is int and sdk['guids_verified'] == 5, 'SDK slot/GUID coverage missing')
        run([racket, '-l', 'raco', '--', 'make', root / 'tools/gpu-dxgi-doctor.rkt'])
        run([racket, root / 'tools/gpu-dxgi-doctor.rkt', '--directory', directory,
             '--adapter', selection, '--adapter-index', str(index)])
        result = inspect(directory, selection, index)
        result.update(racket_identity=identity, windows_sdk_abi_verified=True, racket_layouts_verified=True)
        review = ('<!doctype html><meta charset="utf-8"><title>DXGI back-buffer review</title>'
                  '<h1>DXGI / ' + html.escape(selection) + '</h1>'
                  '<p>Actual swap-chain readbacks, encoded after context teardown. '
                  'These images do not certify physical screen pixels or hardware acceleration.</p>' +
                  ''.join('<figure><img src="' + p['file'] + '" alt="' + p['file'] + '"><figcaption>' +
                          p['file'] + '</figcaption></figure>' for p in result['pngs']))
        (directory / 'dxgi.review.html').write_text(review, encoding='utf-8')
        temporary = directory / 'dxgi.inspection.json.tmp'
        temporary.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
        os.replace(temporary, directory / 'dxgi.inspection.json')
        return result
    except Exception as e:
        # Fresh directories prevent success reuse; retain a clear failure record.
        for name in ('dxgi.inspection.json', 'dxgi.inspection.json.tmp', 'dxgi.review.html'):
            (directory / name).unlink(missing_ok=True)
        (directory / 'dxgi.validation.failed.json').write_text(
            json.dumps(dict(stage='0.49', status='failed', error=str(e)), indent=2) + '\n', encoding='utf-8')
        raise

"""Inspect executed Metal handoffs. Synthetic unit fixtures are not GPU evidence."""
from __future__ import annotations
import hashlib
import html
import json
import math
from pathlib import Path
import sys
from dxgi_validation import read_json, png_rgba, require

NATIVE_CASES = 33
CYCLES, CONTEXTS, HANDOFFS = 3, 2, 24
WIDTH, HEIGHT = 37, 29
SYMBOLS = {'gr_backendtexture_new_metal', 'gr_backendtexture_delete',
           'gr_backendtexture_is_valid', 'gr_backendtexture_get_backend',
           'sk_image_new_from_texture', 'sk_surface_new_backend_texture'}
SOURCES = ('gpu-interop.rkt', 'unsafe/gpu-metal.rkt', 'private/gpu-external.rkt',
           'private/gpu-interop-cleanup.rkt', 'private/gpu-interop-guard.rkt',
           'private/gpu-metal-interop.rkt', 'private/gpu-metal-interop-system.rkt',
           'private/gpu-metal-interop-session.rkt', 'private/gpu-metal-interop-policy.rkt',
           'private/gpu-metal-interop-native.rkt', 'private/gpu-metal-handles.rkt',
           'private/gpu-metal-util.rkt', 'private/gpu-native-scope.rkt',
           'tests/metal-interop-fixture.rkt', 'tests/gpu-metal-interop-native-test.rkt',
           'tools/gpu-metal-interop-doctor.rkt', 'tools/metal_interop_validation.py',
           'tools/metal-interop-fixture/fixture.mm', 'tools/metal-interop-fixture/sdk-check.mm',
           'tools/metal-interop-fixture/CMakeLists.txt')


def exact(v, n):
    return type(v) is int and v == n


def positive(v):
    return type(v) is int and v > 0


def finite(v):
    return type(v) in (int, float) and math.isfinite(v) and v >= 0


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    tmp = path.with_name(path.name + '.tmp')
    tmp.write_text(json.dumps(value, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    tmp.replace(path)


def expected_pixels(painted=False, premultiplied=False):
    # Independent oracle, not read back from either renderer or shared C data.
    out = bytearray()
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if painted and 3 <= x < 9 and 4 <= y < 9:
                out.extend((128 if premultiplied else 255, 0, 128 if premultiplied else 255, 128))
            elif x == WIDTH // 2:
                out.extend((0, 0, 0, 0))
            else:
                alpha = 128 if x % 7 == 0 else 255
                c = alpha if premultiplied else 255
                right, bottom = x > WIDTH // 2, y >= HEIGHT // 2
                out.extend((c if right == bottom else 0, c if right else 0,
                            c if bottom and not right else 0, alpha))
    return bytes(out)


def metadata(raw, directory):
    require(isinstance(raw, dict) and exact(raw.get('schema'), 1) and raw.get('stage') == '0.52', 'wrong schema/stage')
    require(raw.get('validation_run') == directory.name, 'foreign run identity')
    require(raw.get('os') == 'macosx' and raw.get('architecture') in ('aarch64', 'x86_64'), 'not 64-bit macOS')
    require(raw.get('vm') == 'chez-scheme' and isinstance(raw.get('racket_version'), str) and raw['racket_version'], 'Racket identity')
    require(raw.get('backend') == 'metal', 'not Metal')
    for key in ('hardware_acceleration_verified', 'presentation_verified', 'performance_measured',
                'zero_copy_claimed', 'producer_coverage_verified'):
        require(raw.get(key) is False, 'unsupported claim: ' + key)


def context(c, *, closed=False, quarantined=False):
    require(isinstance(c, dict) and c.get('backend') == 'metal' and exact(c.get('native_backend'), 2), 'native Metal context')
    require(c.get('state') == ('closed' if closed else 'ready') and positive(c.get('generation')), 'context lifetime')
    require(c.get('binding_package') == '3.119.1' and c.get('native_version') == '119.0', 'native pin')
    require(c.get('owns_command_queue') is True and c.get('requires_gl_context') is False and c.get('requires_window') is False, 'owned headless queue')
    require(isinstance(c.get('device'), str) and c['device'], 'device identity missing')
    require(isinstance(c.get('renderer'), str) and c['renderer'], 'renderer identity missing')
    require(c.get('shutdown_requested') is quarantined, 'shutdown request mismatch')
    if quarantined:
        require(positive(c.get('live_children')), 'quarantined context lost its pin')
    else:
        for k in ('live_children', 'pending_releases', 'failed_releases'):
            require(exact(c.get(k), 0), 'context resource leak: ' + k)
    return c['generation']


def session(n, *, timeout=False):
    require(isinstance(n, dict), 'missing native session')
    require(n.get('quarantined') is timeout and n.get('state') == ('quarantined' if timeout else 'closed'), 'session lifetime')
    require(positive(n.get('timeout_ms')) and n['timeout_ms'] <= 60000, 'unbounded timeout')
    require(n.get('retained_texture') is timeout and n.get('retained_producer') is timeout, 'native retain/release accounting')
    require(n.get('retained_completion_buffer') is False, 'completion buffer not retired')
    waits = n.get('waits')
    require(isinstance(waits, list), 'missing waits')
    if timeout:
        require(n.get('error_reason') == 'timeout' and isinstance(n.get('error'), str) and n['error'], 'wrong negative error')
        require(waits == [], 'timeout fabricated producer/tail completion')
    else:
        require(n.get('error') is False and n.get('error_reason') is False, 'hidden native error')
        require([w.get('phase') for w in waits] == ['producer', 'ganesh-queue-tail'], 'wrong completion boundaries')
        for row in waits:
            require(exact(row.get('status'), 4) and positive(row.get('polls')) and finite(row.get('elapsed_ms')), 'command not completed')


def texture(t, generation):
    require(t.get('backend') == 'metal' and exact(t.get('context_generation'), generation), 'foreign handoff')
    require(t.get('handoff_state') == 'consumed' and t.get('raw_handles_exposed') is False, 'invalid handoff lifetime/pointers')
    require(t.get('completion') == 'bounded-synchronous' and t.get('ownership') == 'retained-single-handoff', 'handoff contract')
    require(t.get('producer_coverage_verified') is False and t.get('premultiplied') is True, 'producer/alpha claim')
    require(t.get('same_device') is True and t.get('producer_retained_references') is True, 'device/producer validation')
    for k, v in dict(width=37, height=29, depth=1, levels=1, array_length=1, samples=1,
                     format=70, texture_type=2, usage=5, storage_mode=2, hazard_tracking_mode=2).items():
        require(exact(t.get(k), v), 'unsupported texture: ' + k)
    require(t.get('swizzle') == [2, 3, 4, 5] and all(type(v) is int for v in t['swizzle']), 'nonidentity swizzle')
    require(t.get('format_name') == 'RGBA8888' and t.get('origin') == 'top-left', 'format/origin')
    for k in ('framebuffer_only', 'has_parent', 'has_buffer', 'has_heap', 'has_iosurface', 'shareable', 'has_remote_storage'):
        require(t.get(k) is False, 'unsupported storage: ' + k)
    session(t.get('native'))


def io_events(events, mode):
    require(isinstance(events, list) and all(isinstance(e, dict) for e in events), 'IO ledger')
    expected = ['flush', 'submit', 'external-metal-producer-complete']
    expected += ['gpu-snapshot', 'external-image-copy'] if mode == 'copy' else ['external-surface-borrow']
    expected += ['flush', 'submit', 'external-metal-completion', 'external-resource-return']
    require([e.get('kind') for e in events] == expected, 'hidden/missing transfer or command')
    for e in events:
        k = e['kind']
        if k == 'submit':
            require(e.get('wait_requested') is False, 'unbounded native submission wait')
        elif k == 'external-metal-producer-complete':
            require(exact(e.get('producer_status'), 4) and e.get('wait_requested') is True and e.get('cpu_pixel_readback') is False, 'producer completion')
        elif k == 'external-metal-completion':
            require(exact(e.get('completion_status'), 4) and e.get('wait_requested') is True and e.get('same_ganesh_queue') is True
                    and e.get('cpu_pixel_readback') is False, 'Ganesh completion')
        elif k == 'external-image-copy':
            require(e.get('backend') == 'metal' and e.get('aliases_source') is False and e.get('cpu_readback') is False
                    and exact(e.get('skia_copy_draws'), 1), 'copy not independent GPU storage')
        elif k == 'external-surface-borrow':
            require(e.get('backend') == 'metal' and e.get('contents_preserved') is True, 'borrow discards original pixels')
        elif k == 'external-resource-return':
            require(e.get('backend') == 'metal' and e.get('completion_verified') is True and e.get('cpu_readback') is False, 'return without completion')
        elif k == 'gpu-snapshot':
            require(exact(e.get('width'), WIDTH) and exact(e.get('height'), HEIGHT), 'snapshot extent')


def inspect(directory):
    raw = read_json(directory / 'metal-interop.diagnostic.json')
    metadata(raw, directory)
    require(raw.get('status') == 'passed' and raw.get('error') is False, 'native diagnostic did not pass')
    require(exact(raw.get('native_cases'), NATIVE_CASES) and exact(raw.get('native_failures'), 0), 'native suite coverage')
    require(raw.get('sdk_texture_getters_verified') is True and raw.get('typed_swizzle_return_verified') is True, 'native getters/call ABI unchecked')
    require(raw.get('producer') == 'independent-metal-sdk-fixture' and raw.get('consumer') == 'independent-metal-command-queue', 'producer/consumer identity')
    syms = raw.get('interop_symbols')
    require(isinstance(syms, list) and len(syms) == len(SYMBOLS) and {s.get('name') for s in syms} == SYMBOLS
            and all(s.get('available') is True for s in syms), 'missing/duplicate native symbols')
    suite = raw.get('suite_contexts')
    require(isinstance(suite, list) and len(suite) == 2, 'suite contexts')
    generations = set()
    for c in suite:
        gen = context(c, closed=True)
        require(gen not in generations, 'suite context reused'); generations.add(gen)
    cycles = raw.get('cycles')
    require(isinstance(cycles, list) and len(cycles) == CYCLES, 'cycle count')
    lookup, count = {}, 0
    for ci, cycle in enumerate(cycles):
        require(exact(cycle.get('cycle'), ci), 'cycle ordering')
        cs = cycle.get('contexts')
        require(isinstance(cs, list) and len(cs) == CONTEXTS, 'context count')
        for slot, c in enumerate(cs):
            require(exact(c.get('context'), slot), 'context ordering')
            gen = context(c.get('initial'))
            require(gen not in generations, 'context generation reused'); generations.add(gen)
            require(context(c.get('final'), closed=True) == gen, 'wrong context teardown')
            require(c['initial']['device'] == c['final']['device'], 'device changed')
            rows = c.get('handoffs')
            require(isinstance(rows, list) and len(rows) == HANDOFFS, 'handoff count')
            for ordinal, row in enumerate(rows):
                mode = 'copy' if ordinal % 2 == 0 else 'surface'
                require(exact(row.get('ordinal'), ordinal) and row.get('mode') == mode, 'handoff ordering')
                texture(row.get('handoff', {}), gen)
                require(row.get('pixels_verified') is True, 'missing pixel check')
                require(row.get('producer_closed_before_skia_readback') is (mode == 'copy'), 'external retirement not exercised')
                require(row.get('independent_consumer_readback') is (mode == 'surface'), 'independent consumer not used')
                im = row.get('image')
                if mode == 'copy':
                    require(isinstance(im, dict) and im.get('backend') == 'metal' and exact(im.get('context_generation'), gen)
                            and im.get('storage') == 'gpu' and im.get('texture_backed') is True and im.get('context_matches') is True
                            and exact(im.get('width'), WIDTH) and exact(im.get('height'), HEIGHT), 'imported image invalid/foreign')
                else:
                    require(im is False, 'borrowed surface exposed an image')
                io_events(row.get('io_events'), mode)
                lookup[(ci, slot, ordinal)] = mode; count += 1
    captures = raw.get('captures')
    require(isinstance(captures, list) and len(captures) == 12, 'capture count')
    seen, filenames, results = set(), set(), []
    for c in captures:
        key = tuple(c.get(k) for k in ('cycle', 'context', 'ordinal'))
        require(all(type(k) is int for k in key) and key in lookup and key[-1] in (0, 1) and key not in seen, 'capture identity')
        seen.add(key)
        require(c.get('mode') == lookup[key] and c.get('encoded_after_context_teardown') is True, 'capture lifetime/mode')
        require(exact(c.get('width'), WIDTH) and exact(c.get('height'), HEIGHT), 'capture dimensions')
        name = c.get('png')
        require(isinstance(name, str) and name.endswith('.png') and name not in filenames and not any(x in name for x in '/\\:'), 'unsafe/duplicate filename')
        filenames.add(name); path = directory / name
        require(path.is_file() and not path.is_symlink(), 'missing/symbolic image')
        w, h, pixels = png_rgba(path)
        require((w, h) == (WIDTH, HEIGHT) and pixels == expected_pixels(c['mode'] == 'surface'), 'independent PNG oracle mismatch')
        results.append(dict(file=name, width=w, height=h, sha256=digest(path)))
    negative = read_json(directory / 'metal-interop.timeout.json')
    metadata(negative, directory)
    require(negative['racket_version'] == raw['racket_version'] and negative['architecture'] == raw['architecture'], 'negative interpreter differs')
    require(negative.get('status') == 'expected-timeout-quarantined' and negative.get('normal_process_exit') is True, 'negative child did not verify timeout')
    for k in ('dependency_unblocked_after_timeout', 'intentional_retention_until_process_exit'):
        require(negative.get(k) is True, 'negative cleanup: ' + k)
    require(negative.get('graphics_handoff_submitted') is False, 'timeout submitted handoff graphics')
    session(negative.get('native'), timeout=True)
    context(negative.get('context'), quarantined=True)
    return dict(schema=1, stage='0.52', status='passed', backend='metal', validation_run=directory.name,
                native_cases=NATIVE_CASES, stress_contexts=6, suite_contexts=2, handoffs=count,
                copied_images=count//2, borrowed_targets=count//2, captures=results,
                independent_pixel_oracle_verified=True, expected_timeout_quarantine_verified=True,
                typed_swizzle_return_verified=True, metal_execution_verified=True,
                hardware_acceleration_verified=False, presentation_verified=False, performance_measured=False,
                zero_copy_claimed=False, producer_coverage_verified=False)


def build_sdk(root, directory, run, architecture, *, build_directory=None):
    require(architecture in ('aarch64', 'x86_64'), 'unsupported SDK architecture')
    abi = Path(build_directory) if build_directory is not None else directory / 'abi'
    run(['cmake', '-S', root / 'tools/metal-interop-fixture', '-B', abi, '-DCMAKE_BUILD_TYPE=Release',
         '-DCMAKE_OSX_ARCHITECTURES=' + ('arm64' if architecture == 'aarch64' else 'x86_64')])
    run(['cmake', '--build', abi, '--config', 'Release'])
    run(['ctest', '--test-dir', abi, '-C', 'Release', '--output-on-failure'])
    data = json.loads(run([abi / 'metal-interop-sdk-check']))
    require(data.get('kind') == 'apple-metal-sdk' and data.get('status') == 'passed' and exact(data.get('schema'), 1), 'not Apple SDK evidence')
    for k, v in dict(pointer_bytes=8, nsuinteger_bytes=8, bool_bytes=1, swizzle_bytes=4).items():
        require(exact(data.get(k), v), 'SDK mismatch: ' + k)
    require(data.get('gpu_execution_verified') is False, 'SDK-only test cannot establish GPU execution')
    write(directory / 'metal-sdk.json', data)
    return abi / 'libmetal-interop-fixture.dylib', data


def execute(root, racket, directory, run):
    require(directory.is_dir() and not any(directory.iterdir()), 'evidence directory must be fresh and empty')
    before = {p: digest(root / p) for p in (*SOURCES, 'SOURCE-SHA256SUMS.txt')}
    run([sys.executable, root / 'tools/update-source-sums.py', '--check'])
    identity = json.loads(run([racket, root / 'tools/ci-identity.rkt']))
    require(identity.get('os') == 'macosx' and identity.get('architecture') in ('aarch64', 'x86_64')
            and identity.get('vm') == 'chez-scheme' and exact(identity.get('pointer_bytes'), 8), 'requires 64-bit macOS Racket CS')
    fixture, sdk = build_sdk(root, directory, run, identity['architecture'])
    doctor = root / 'tools/gpu-metal-interop-doctor.rkt'
    run([racket, '-l', 'raco', '--', 'make', doctor])
    args = [racket, doctor, '--directory', directory, '--fixture', fixture]
    run(args)
    run([*args, '--timeout-case'])
    result = inspect(directory)
    raw = read_json(directory / 'metal-interop.diagnostic.json')
    require(raw['racket_version'] == identity['version'] and raw['architecture'] == identity['architecture'], 'doctor interpreter differs')
    run([sys.executable, root / 'tools/update-source-sums.py', '--check'])
    require(before == {p: digest(root / p) for p in before}, 'source changed while validating')
    result.update(identity=identity, sdk=sdk, source_sha256=before)
    page = '<!doctype html><meta charset="utf-8"><title>Metal interop validation</title><h1>Metal interop</h1>'
    page += '<p>Independent producer/consumer pixels. Not screen, speed, or zero-copy certification.</p>'
    for row in result['captures']:
        name = html.escape(row['file'], quote=True)
        page += f'<figure><img style="image-rendering:pixelated;width:296px" src="{name}"><figcaption>{name}</figcaption></figure>'
    page += '<pre>' + html.escape(json.dumps(result, indent=2)) + '</pre>'
    (directory / 'metal-interop.review.html').write_text(page, encoding='utf-8')
    write(directory / 'metal-interop.inspection.json', result)  # success marker LAST
    return result

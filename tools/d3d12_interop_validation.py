"""0.51 native handoff validation; synthetic fixtures are never native evidence."""
from __future__ import annotations
import hashlib
import html
import json
from pathlib import Path
import sys
from dxgi_validation import read_json, png_rgba, require, integer, select

NATIVE_CASES = 29
CYCLES = 3
CONTEXTS = 2
HANDOFFS = 24
SOURCES = ('gpu-interop.rkt', 'unsafe/gpu-d3d12.rkt',
           'tools/d3d12_interop_validation.py', 'tools/d3d12-interop-fixture/CMakeLists.txt',
           'private/gpu-external.rkt', 'private/gpu-d3d12-interop-policy.rkt',
           'private/gpu-d3d12-interop-system.rkt', 'private/gpu-d3d12-interop.rkt',
           'private/gpu-d3d12-interop-native.rkt', 'private/gpu-d3d12-handles.rkt',
           'private/gpu-driver-d3d12.rkt', 'private/gpu-interop-guard.rkt',
           'tests/gpu-interop-native-test.rkt', 'tests/d3d12-interop-fixture.rkt',
           'tools/gpu-d3d12-interop-doctor.rkt', 'tools/d3d12-interop-fixture/fixture.cpp',
           'tools/d3d12-interop-fixture/sdk-check.c')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, data):
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_text(json.dumps(data, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    temporary.replace(path)


def exact(x, n):
    return type(x) is int and x == n


def pattern(w, h, painted=False):
    data = bytearray()
    for y in range(h):
        for x in range(w):
            if painted and 1 <= x < 6 and 2 <= y < 6:
                data.extend((255, 0, 0, 255))
            elif x % 7 == 0:
                data.extend((0, 0, 0, 0))
            else:
                data.extend(((17*x+3*y) % 256, ((x^y)*13) % 256, (5*x+11*y) % 256, 255))
    return bytes(data)


def metadata(data, directory, selection, index):
    require(isinstance(data, dict) and exact(data.get('schema'), 1) and data.get('stage') == '0.51', 'report schema')
    require(data.get('validation_run') == directory.name, 'foreign/stale run identity')
    require(data.get('os') == 'windows' and data.get('architecture') == 'x86_64', 'not Windows x64')
    require(data.get('vm') == 'chez-scheme' and isinstance(data.get('racket_version'), str), 'Racket identity')
    require(data.get('backend') == 'direct3d' and data.get('adapter_selection') == selection, 'backend/adapter selection')
    require(data.get('adapter_index') is False if selection == 'warp' else exact(data.get('adapter_index'), index), 'adapter index')
    for key in ('hardware_acceleration_verified', 'presentation_verified', 'performance_measured',
                'resource_state_declarations_verified', 'zero_copy_claimed'):
        require(data.get(key) is False, 'unsupported claim: ' + key)


def context(c, selection, index, *, closed=False, retained=False):
    require(isinstance(c, dict) and c.get('backend') == 'direct3d' and exact(c.get('native_backend'), 3), 'native context backend')
    require(c.get('api') == 'D3D12' and c.get('command_queue_owned') is True and
            c.get('command_queue_type') == 'direct', 'context queue identity')
    require(c.get('adapter_selection') == selection, 'context adapter changed')
    require(c.get('adapter_index') is False if selection == 'warp' else exact(c.get('adapter_index'), index), 'context index')
    require(integer(c.get('adapter_flags')), 'adapter flags')
    require(c.get('d3d12_warp') is (selection == 'warp'), 'WARP identity')
    require(bool(c['adapter_flags'] & 2) is (selection == 'warp'), 'software adapter flag')
    require(c.get('renderer_class') == ('software' if selection == 'warp' else 'hardware-reported'), 'renderer classification')
    require(isinstance(c.get('adapter_name'), str) and c['adapter_name'], 'adapter name')
    for k in ('adapter_vendor_id', 'adapter_device_id', 'adapter_luid_low'):
        require(integer(c.get(k), 0, 0xffffffff), 'numeric adapter identity: ' + k)
    require(type(c.get('adapter_luid_high')) is int and -2**31 <= c['adapter_luid_high'] < 2**31, 'LUID high')
    require(c.get('binding_package') == '3.119.1' and c.get('native_version') == '119.0', 'native pin changed')
    require(c.get('hardware_acceleration_verified') is False, 'unverified hardware claim')
    require(integer(c.get('generation'), 1), 'context generation')
    require(c.get('state') == ('closed' if closed else 'ready'), 'context lifecycle')
    if retained:
        require(c.get('shutdown_requested') is True and integer(c.get('live_children'), 1), 'quarantine context not pinned/shutdown')
    else:
        require(c.get('shutdown_requested') is False, 'shutdown requested')
        for k in ('live_children', 'pending_releases', 'failed_releases'):
            require(exact(c.get(k), 0), 'resource leak: ' + k)
    return c['generation']


def session(n, *, mode=None, timeout=False):
    require(isinstance(n, dict) and n.get('same_device_verified') is True, 'same-device check absent')
    require(n.get('state_declaration_verified_by_runtime') is False, 'invented resource-state query')
    require(exact(n.get('cpu_pixel_readbacks'), 0) and integer(n.get('fence_waits')), 'handoff transfer/wait accounting')
    require(n.get('incoming_state') == 'pixel-shader-resource' and n.get('outgoing_state') == 'copy-source', 'declared state changed')
    if timeout:
        require(n.get('state') == 'quarantined' and n.get('quarantined') is True, 'not quarantined')
        require(n.get('producer_completion_verified') is False and n.get('external_state_returned') is False, 'timeout fabricated completion')
        require(exact(n.get('queue_submissions'), 0) and exact(n.get('native_gpu_copies'), 0), 'timeout submitted resource work')
        require(isinstance(n.get('error'), str) and 'fence timeout' in n['error'], 'wrong quarantine cause')
    else:
        require(n.get('state') == 'closed' and n.get('quarantined') is False and n.get('error') is False, 'native session not cleanly closed')
        require(n.get('producer_completion_verified') is True and n.get('external_state_returned') is True, 'handoff completion/state return missing')
        require(exact(n.get('queue_submissions'), 1 if mode == 'copy' else 2), 'native command submission count')
        require(exact(n.get('native_gpu_copies'), 1 if mode == 'copy' else 0), 'native bridge-copy count')


def io_events(events, mode):
    require(isinstance(events, list) and all(isinstance(e, dict) for e in events), 'IO ledger')
    kinds = [e.get('kind') for e in events]
    expected = (['flush', 'submit', 'flush', 'submit', 'external-d3d12-completion',
                 'external-image-copy', 'flush', 'submit', 'external-d3d12-completion', 'external-resource-return']
                if mode == 'copy' else
                ['flush', 'submit', 'external-surface-borrow', 'external-target-normalization',
                 'flush', 'submit', 'external-d3d12-completion', 'external-resource-return'])
    # A surface snapshot is reported by the existing common GPU-image layer.
    # It occurs before the corresponding copy or normalization event.
    expected.insert(2 if mode == 'copy' else 3, 'gpu-snapshot')
    require(kinds == expected, 'unexpected/missing IO event or hidden transfer')
    for e in events:
        if e['kind'] == 'submit':
            require(e.get('wait_requested') is False, 'unbounded Skia submit wait used')
        if e['kind'] == 'external-d3d12-completion':
            require(e.get('wait_requested') is True and e.get('cpu_pixel_readback') is False, 'completion not explicit')
        if e['kind'] == 'gpu-snapshot':
            require(integer(e.get('width'), 1) and integer(e.get('height'), 1), 'snapshot dimensions')
        if e['kind'] == 'external-image-copy':
            require(e.get('backend') == 'direct3d' and e.get('aliases_source') is False and e.get('cpu_readback') is False,
                    'copy is aliased or CPU staged')
            require(exact(e.get('native_bridge_copies'), 1) and exact(e.get('skia_copy_draws'), 1), 'copy work accounting')
        if e['kind'] == 'external-target-normalization':
            require(exact(e.get('gpu_snapshot_copies'), 1) and exact(e.get('gpu_copy_draws'), 1)
                    and e.get('cpu_readback') is False and e.get('backend') == 'direct3d', 'normalization evidence')
        if e['kind'] == 'external-resource-return':
            require(e.get('completion_verified') is True and e.get('cpu_readback') is False
                    and e.get('outgoing_state') == 'copy-source', 'incomplete resource return')


def inspect(directory: Path, selection='warp', index=0):
    select(selection, index)
    raw = read_json(directory / 'interop.diagnostic.json')
    metadata(raw, directory, selection, index)
    require(raw.get('status') == 'passed' and raw.get('error') is False, 'native interop diagnostic failed')
    require(exact(raw.get('native_cases'), NATIVE_CASES) and exact(raw.get('native_failures'), 0), 'native suite coverage/failure')
    require(raw.get('sdk_getdesc_call_verified') is True, 'COM aggregate-return call not verified')
    require(raw.get('producer') == 'independent-d3d12-sdk-fixture' and raw.get('consumer') == 'independent-direct-command-queue', 'producer/consumer provenance')
    seen = set(); count = 0
    suite = raw.get('suite_contexts')
    require(isinstance(suite, list) and len(suite) == 2, 'native suite context cleanup missing')
    for c in suite:
        gen = context(c, selection, index, closed=True)
        require(gen not in seen, 'suite context reused'); seen.add(gen)
    cycles = raw.get('cycles')
    require(isinstance(cycles, list) and len(cycles) == CYCLES, 'lifecycle cycles')
    lookup = {}
    for ci, cycle in enumerate(cycles):
        require(exact(cycle.get('cycle'), ci), 'cycle order')
        cs = cycle.get('contexts')
        require(isinstance(cs, list) and len(cs) == CONTEXTS, 'independent contexts missing')
        for slot, c in enumerate(cs):
            require(exact(c.get('context'), slot), 'context order')
            initial, final = c['initial'], c['final']
            gen = context(initial, selection, index)
            require(gen not in seen, 'context generation reused'); seen.add(gen)
            require(context(final, selection, index, closed=True) == gen, 'wrong context retired')
            for k in ('adapter_name', 'adapter_vendor_id', 'adapter_device_id', 'adapter_luid_low', 'adapter_luid_high'):
                require(initial[k] == final[k], 'device identity changed')
            rows = c.get('handoffs')
            require(isinstance(rows, list) and len(rows) == HANDOFFS, 'shortened handoff workload')
            for ordinal, row in enumerate(rows):
                mode = 'copy' if ordinal % 2 == 0 else 'surface'
                w, h = (37, 29) if slot == 0 else (67, 41)
                require(exact(row.get('ordinal'), ordinal) and row.get('mode') == mode, 'handoff order/mode')
                require(exact(row.get('width'), w) and exact(row.get('height'), h), 'handoff dimensions')
                t = row['handoff']; n = t['native']; session(n, mode=mode)
                require(t.get('backend') == 'direct3d' and exact(t.get('context_generation'), gen), 'foreign handoff')
                require(t.get('handoff_state') == 'consumed' and t.get('raw_handles_exposed') is False, 'handoff lifetime/pointers')
                require(t.get('ownership') == 'retained-single-handoff' and t.get('completion') == 'bounded-synchronous', 'ownership/completion contract')
                require(t.get('state_query_available') is False and t.get('format_name') == 'RGBA8888', 'format/state metadata')
                require(exact(t.get('width'), w) and exact(t.get('height'), h), 'native descriptor dimensions')
                for k, v in {'dimension':3, 'depth':1, 'levels':1, 'format':28, 'samples':1, 'quality':0, 'layout':0, 'heap_type':1, 'flags':1}.items():
                    require(exact(t.get(k), v), 'native descriptor field ' + k)
                require(integer(t.get('heap_flags')) and not (t['heap_flags'] & ~0xc4), 'unsupported heap flags')
                require(row.get('pixels_verified') is True, 'handoff pixels unchecked')
                require(row.get('producer_closed_before_skia_readback') is (mode == 'copy'), 'producer retention/copy independence')
                require(row.get('independent_consumer_readback') is (mode == 'surface'), 'independent consumer not exercised')
                if mode == 'copy':
                    im = row['image']
                    require(im.get('texture_backed') is True and im.get('storage') == 'gpu' and im.get('context_matches') is True, 'import not GPU-backed')
                    require(im.get('backend') == 'direct3d' and exact(im.get('context_generation'), gen), 'foreign returned image')
                    require(exact(im.get('width'), w) and exact(im.get('height'), h), 'returned image dimensions')
                else:
                    require(row.get('image') is False, 'borrowed surface exported an image')
                io_events(row['io_events'], mode)
                lookup[(ci, slot, ordinal)] = row
                count += 1
    captures = raw.get('captures')
    require(isinstance(captures, list) and len(captures) == 12, 'capture coverage')
    names, keys, pixels = set(), set(), []
    for item in captures:
        key = tuple(item.get(k) for k in ('cycle', 'context', 'ordinal'))
        require(all(type(k) is int for k in key) and key in lookup and key[-1] in (0, 1) and key not in keys, 'capture identity')
        keys.add(key); row = lookup[key]
        require(item.get('mode') == row['mode'] and item.get('encoded_after_context_teardown') is True, 'capture lifetime/mode')
        require(exact(item.get('width'), row['width']) and exact(item.get('height'), row['height']), 'capture size')
        name = item.get('png')
        require(isinstance(name, str) and name.endswith('.png') and name not in names and
                not any(c in name for c in '/\\:') and name not in ('.', '..'), 'unsafe/duplicate PNG')
        path = directory / name
        require(path.is_file() and not path.is_symlink(), 'missing/symbolic PNG'); names.add(name)
        w, h, data = png_rgba(path)
        require((w, h) == (row['width'], row['height']) and data == pattern(w, h, row['mode'] == 'surface'), 'independent PNG oracle mismatch')
        pixels.append(dict(file=name, width=w, height=h, sha256=digest(path)))
    timeout = read_json(directory / 'interop.timeout.json')
    metadata(timeout, directory, selection, index)
    require(timeout.get('racket_version') == raw['racket_version'], 'timeout interpreter differs')
    require(timeout.get('status') == 'expected-timeout-quarantined' and timeout.get('normal_process_exit') is True, 'timeout child did not verify expected failure')
    require(timeout.get('intentional_retention_until_process_exit') is True and timeout.get('graphics_handoff_submitted') is False, 'quarantine claim')
    require(isinstance(timeout.get('error'), str) and 'fence timeout' in timeout['error'], 'wrong negative result')
    session(timeout.get('native'), timeout=True)
    context(timeout['context'], selection, index, retained=True)
    return dict(schema=1, stage='0.51', status='passed', validation_run=directory.name,
                backend='direct3d', adapter_selection=selection, native_cases=NATIVE_CASES,
                stress_contexts=6, suite_contexts=2, cycles=3, handoffs=count,
                copied_images=count//2, borrowed_targets=count//2, captures=pixels,
                independent_pixel_oracle_verified=True, explicit_state_return_exercised=True,
                runtime_state_query_claimed=False, expected_timeout_quarantine_verified=True,
                hardware_acceleration_verified=False, presentation_verified=False,
                performance_measured=False, zero_copy_claimed=False)


def execute(root: Path, racket: str, directory: Path, run, *, selection='warp', index=0):
    select(selection, index)
    require(directory.is_dir() and not any(directory.iterdir()), 'fresh empty evidence directory required')
    out = directory / 'interop.inspection.json'
    try:
        sources = {p: digest(root / p) for p in SOURCES}
        identity = json.loads(run([racket, root / 'tools/ci-identity.rkt']))
        require(identity.get('os') == 'windows' and identity.get('architecture') == 'x86_64'
                and exact(identity.get('pointer_bytes'), 8), 'requires Windows x64 Racket')
        build = directory / 'abi'
        run(['cmake', '-S', root / 'tools/d3d12-interop-fixture', '-B', build, '-G', 'Visual Studio 17 2022', '-A', 'x64'])
        run(['cmake', '--build', build, '--config', 'Release'])
        run(['ctest', '--test-dir', build, '-C', 'Release', '--output-on-failure'])
        sdk = json.loads(run([build / 'Release/interop-sdk-check.exe']))
        require(sdk.get('kind') == 'windows-sdk' and sdk.get('status') == 'passed'
                and exact(sdk.get('slots'), 6) and exact(sdk.get('resource_desc_bytes'), 56), 'SDK ABI evidence failed')
        write(directory / 'interop.sdk.json', sdk)
        doctor = root / 'tools/gpu-d3d12-interop-doctor.rkt'
        run([racket, '-l', 'raco', '--', 'make', doctor])
        args = [racket, doctor, '--directory', directory, '--fixture', build / 'Release/d3d12-interop-fixture.dll',
                '--adapter', selection, '--adapter-index', str(index)]
        run(args)
        run([*args, '--timeout-case'])
        result = inspect(directory, selection, index)
        require(sources == {p: digest(root / p) for p in SOURCES}, 'workload source changed during execution')
        raw = read_json(directory / 'interop.diagnostic.json')
        require(raw.get('racket_version') == identity.get('version') and raw.get('vm') == identity.get('vm'), 'selected interpreter changed')
        result.update(windows_sdk_verified=True, com_aggregate_return_verified=True,
                      workload_sha256=sources, identity=identity,
                      raw_sha256={n: digest(directory / n) for n in ('interop.diagnostic.json', 'interop.timeout.json', 'interop.sdk.json')})
        page = '<!doctype html><meta charset="utf-8"><title>Direct3D interop</title><h1>0.51 — Direct3D interop</h1>'
        page += '<p>Native producer, explicit handoff, independent consumer. Software WARP is not hardware attestation. Borrowed targets include a normalization copy. No physical-display test.</p>'
        page += ''.join('<figure><img src="'+html.escape(p['file'], quote=True)+'"><figcaption>'+html.escape(p['file'])+'</figcaption></figure>' for p in result['captures'])
        page += '<pre>'+html.escape(json.dumps(result, indent=2))+'</pre>'
        (directory / 'interop.review.html').write_text(page, encoding='utf-8')
        write(out, result)  # Success marker LAST.
        return result
    except BaseException as e:
        out.unlink(missing_ok=True)
        (directory / 'interop.review.html').unlink(missing_ok=True)
        write(directory / 'interop.validation.failed.json', dict(stage='0.51', status='failed', error=str(e)))
        raise

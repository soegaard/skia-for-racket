"""Shared wrapper declarations and *observed* backend identity checks.

The JSON registry is declarative and performs no native probing. These checks
validate native diagnostic evidence separately; they do not attest hardware.
"""
from __future__ import annotations
import copy
import json
from pathlib import Path
from types import MappingProxyType

ROOT = Path(__file__).resolve().parents[1]
FEATURES = frozenset(('offscreen', 'images', 'explicit_transfers', 'cache_controls',
                      'presentation', 'document_executor', 'external_resource_interop'))


def require(condition, message):
    if not condition:
        raise ValueError(message)


def integer(v, lo=0, hi=0xffffffff):
    return type(v) is int and lo <= v <= hi


def _pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate JSON key: ' + key)
        result[key] = value
    return result


def _nonfinite(value):
    raise ValueError('non-finite JSON number: ' + value)


def read_json(path, maximum=32 * 1024 * 1024):
    path = Path(path)
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= maximum,
            'missing, symbolic or oversized JSON: ' + str(path))
    return json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=_pairs,
                      parse_constant=_nonfinite)


def validate_catalog(value):
    require(isinstance(value, dict) and type(value.get('schema')) is int and value['schema'] == 1,
            'invalid backend catalog schema')
    rows = value.get('backends')
    require(isinstance(rows, list) and all(isinstance(r, dict) for r in rows), 'invalid backend rows')
    require([r.get('backend') for r in rows] == ['opengl', 'metal', 'direct3d'],
            'catalog disagrees with implemented backends')
    ids = []
    for r in rows:
        require(integer(r.get('native_backend')), 'invalid native backend ID')
        ids.append(r['native_backend'])
        require(r.get('engine') == 'ganesh' and type(r.get('owned_context')) is bool,
                'invalid engine/context declaration')
        require(isinstance(r.get('platforms'), list) and r['platforms'] and
                all(isinstance(p, str) and p for p in r['platforms']), 'invalid platform declaration')
        require(isinstance(r.get('software_selection'), str) and r['software_selection'],
                'invalid software selection declaration')
        f = r.get('features')
        require(isinstance(f, dict) and set(f) == FEATURES and all(type(x) is bool for x in f.values()),
                'invalid wrapper feature declarations')
    require(len(ids) == len(set(ids)), 'duplicate native backend ID')
    return copy.deepcopy(value)


_CATALOG = validate_catalog(read_json(ROOT / 'private/gpu-backends.json'))
BACKEND_IDS = MappingProxyType({r['backend']: r['native_backend'] for r in _CATALOG['backends']})


def declared_capabilities(backend):
    require(isinstance(backend, str) and backend in BACKEND_IDS, 'unknown GPU backend')
    row = copy.deepcopy(next(r for r in _CATALOG['backends'] if r['backend'] == backend))
    row.update(schema=1, scope='wrapper-declarations', native_probe_performed=False,
               runtime_availability='not-probed', hardware_acceleration_verified=False,
               visible_pixels_verified=False, performance_measured=False)
    return row


def selection(backend, host, adapter=None, adapter_index=None):
    require(isinstance(backend, str) and backend in BACKEND_IDS, 'unknown GPU backend')
    require(host in ('gui', 'egl', 'owned'), 'invalid GPU host')
    require(host != 'egl' or backend == 'opengl', 'EGL requires OpenGL')
    require(host != 'owned' or backend != 'opengl', 'OpenGL needs a GUI or EGL host')
    if backend != 'direct3d':
        require(adapter is None and adapter_index is None, 'adapter selection requires Direct3D')
        return None, None
    adapter = 'hardware' if adapter is None else adapter
    adapter_index = 0 if adapter_index is None else adapter_index
    require(adapter in ('warp', 'hardware') and integer(adapter_index, 0, 0xfffffffe),
            'invalid Direct3D adapter selection')
    require(adapter != 'warp' or adapter_index == 0, 'WARP does not accept an adapter index')
    return adapter, adapter_index


def check_backend_context(c, backend, *, adapter=None, adapter_index=None):
    require(isinstance(c, dict) and backend in BACKEND_IDS and c.get('backend') == backend,
            'wrong backend context')
    require(type(c.get('native_backend')) is int and c['native_backend'] == BACKEND_IDS[backend],
            'wrong native backend ID')
    if backend != 'direct3d':
        return
    require(c.get('api') == 'D3D12' and c.get('command_queue_owned') is True and
            c.get('command_queue_type') == 'direct', 'Direct3D context has no owned direct queue')
    actual = c.get('adapter_selection')
    require(actual in ('warp', 'hardware'), 'missing actual adapter selection')
    require(type(c.get('d3d12_warp')) is bool and c['d3d12_warp'] == (actual == 'warp'),
            'contradictory WARP identity')
    flags = c.get('adapter_flags')
    require(integer(flags) and bool(flags & 2) == (actual == 'warp'), 'wrong DXGI adapter class')
    require(c.get('renderer_class') == ('software' if actual == 'warp' else 'hardware-reported'),
            'wrong Direct3D renderer class')
    require(c.get('hardware_acceleration_verified') is False, 'unsupported hardware attestation')
    for field in ('adapter_name', 'renderer'):
        require(isinstance(c.get(field), str) and c[field], 'missing adapter identity: ' + field)
    for field, lo, hi in (('adapter_vendor_id', 0, 0xffffffff), ('adapter_device_id', 0, 0xffffffff),
                           ('adapter_luid_low', 0, 0xffffffff), ('adapter_luid_high', -0x80000000, 0x7fffffff)):
        require(integer(c.get(field), lo, hi), 'invalid DXGI identity: ' + field)
    require(integer(c.get('minimum_feature_level'), 1), 'missing D3D feature-level request')
    if actual == 'warp':
        require(c.get('adapter_index') is False, 'WARP has no hardware adapter index')
    else:
        require(integer(c.get('adapter_index'), 0, 0xfffffffe), 'invalid hardware adapter index')
    if adapter is not None:
        require(actual == adapter, 'actual Direct3D adapter differs from explicit request')
        if adapter == 'hardware':
            require(type(adapter_index) is int and c['adapter_index'] == adapter_index,
                    'actual hardware adapter index differs from explicit request')


def check_backend_host(report, backend, *, presentation=False):
    # Historical GL/Metal reports keep their own existing host requirements.
    if backend != 'direct3d':
        return
    require(report.get('os') == 'windows' and report.get('architecture') == 'x86_64',
            'Direct3D report is not from Windows x64')
    if not presentation:
        host = report.get('host')
        require(isinstance(host, dict) and host.get('headless') is True and
                host.get('window_created') is False and host.get('requires_gui') is False and
                host.get('requires_gl_context') is False, 'Direct3D offscreen used an implicit GUI/GL host')


def context_signature(c, backend):
    check_backend_context(c, backend)
    if backend == 'direct3d':
        keys = ('adapter_name', 'adapter_vendor_id', 'adapter_device_id',
                'adapter_luid_low', 'adapter_luid_high', 'adapter_selection', 'adapter_index',
                'api', 'minimum_feature_level', 'native_version', 'binding_package')
    else:
        keys = ('renderer', 'vendor', 'api_version', 'native_version', 'binding_package')
    return tuple(c[k] for k in keys)


def context_api_label(c, backend):
    # Do not manufacture GL-style driver strings for DXGI's numeric identity.
    if backend == 'direct3d':
        return 'D3D12 (driver version not queried)'
    return c['api_version']


def check_dxgi_present_event(e):
    require(isinstance(e, dict) and e.get('kind') == 'present-request' and
            e.get('backend') == 'direct3d' and e.get('method') == 'dxgi-same-queue',
            'wrong Direct3D present event')
    require(e.get('result') == 'submitted' and type(e.get('hresult')) is int and e['hresult'] == 0,
            'occluded/failed Present is not a measured successful frame')
    require(e.get('wait_requested') is False, 'unexpected explicit completion wait in Present')
    require(integer(e.get('buffer_index'), 0, 1) and integer(e.get('swap_chain_generation'), 1) and
            integer(e.get('fence_value'), 1, 0xfffffffffffffffe), 'missing Direct3D target/fence identity')


def check_redraw_fence_accounting(window):
    """Verify successful/retried sample waits separately from queue/cleanup waits."""
    rows = [window['warmup'], *window['frames']]
    measured = 0
    for row in rows:
        for key in ('backend_fence_waits', 'retry_backend_fence_waits'):
            require(integer(row.get(key)), 'missing backend fence count: ' + key)
            measured += row[key]
        require(row.get('backend_fence_waits_included_in_elapsed') is True,
                'backend waits omitted from presenter latency')
        check_dxgi_present_event(row['io_events'][-1])
    require(integer(window.get('measured_backend_fence_waits')) and
            window['measured_backend_fence_waits'] == measured, 'measured backend fence total mismatch')
    outside = window.get('backend_fence_waits_outside_samples')
    require(integer(outside), 'missing queued/cleanup backend fence count')
    adapter = window['closed_presenter']['adapter']
    require(integer(adapter.get('blocking_fence_waits')) and
            adapter['blocking_fence_waits'] == measured + outside, 'unaccounted backend fence waits')
    # These target fields represent actual DXGI reporting, not generic labels.
    require(adapter.get('queue_ownership') == 'context-driver' and
            adapter.get('buffer_count') == 2 and type(adapter['buffer_count']) is int and
            adapter.get('swap_effect') == 'flip-discard', 'wrong DXGI presentation host')
    for cp in window['checkpoints']:
        host = cp['presenter']['adapter']
        require(host.get('presentation_context_children') == 1 and
                type(host['presentation_context_children']) is int,
                'live DXGI presenter lost its context pin')
        require(host.get('quarantined') is False and host.get('quarantined_frames') == 0 and
                type(host['quarantined_frames']) is int, 'quarantined DXGI checkpoint')

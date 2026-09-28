#!/usr/bin/env python3
"""Validate one 0.41 run from raw diagnostics and pixels, not success markers.

Standard-library-only. --self-test uses synthetic fixtures, never a real GPU.
Metal presentation and performance are deliberately outside this acceptance gate.
"""
from __future__ import annotations
import argparse
import html
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

_spec = importlib.util.spec_from_file_location('gpu_image_inspection', Path(__file__).with_name('inspect-gpu-images.py'))
images = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(images)
shared = images.shared
require = shared.require
exact_int = images.exact_int
METAL_NATIVE_CASES = 8
CROSS_NATIVE_CASES = 9
PREFIXES = ('offscreen-opengl', 'offscreen-metal', 'images-opengl', 'images-metal',
            'metal-lifecycle', 'cross-backend')


def read_report(directory, name):
    path = directory / (name + '.diagnostic.json')
    require(path.resolve().parent == directory.resolve(), 'diagnostic path escapes run directory')
    require(path.stat().st_size <= 4*1024*1024, 'oversized diagnostic')
    data = json.loads(path.read_text(encoding='utf-8'))
    require(isinstance(data, dict) and exact_int(data.get('schema_version'), 1) and
            data.get('stage') == '0.41' and data.get('status') == 'passed',
            name + ': not a successful 0.41 raw diagnostic')
    require(data.get('performance_measured') is False, name + ': performance was not measured')
    return data


def lifecycle(data, directory):
    require(data.get('kind') == 'metal-lifecycle' and data.get('backend') == 'metal', 'wrong Metal lifecycle report')
    require(exact_int(data.get('native_test_cases'), METAL_NATIVE_CASES) and
            exact_int(data.get('native_test_failures'), 0), 'Metal-specific suite did not fully pass')
    require(data.get('headless') is True and data.get('presentation_tested') is False,
            'offscreen lifecycle cannot claim window presentation')
    cycles = data.get('cycles')
    require(isinstance(cycles, list) and len(cycles) == 3, 'three Metal rendering/teardown cycles are required')
    generations, paths, devices = set(), set(), set()
    for index, cycle in enumerate(cycles):
        require(isinstance(cycle, dict) and exact_int(cycle.get('index'), index), 'invalid cycle index')
        before, after = cycle.get('initial_context'), cycle.get('closed_context')
        shared.context(before, backend='metal')
        shared.context(after, backend='metal', closed=True)
        generation = before['generation']
        require(generation == after['generation'] and generation not in generations, 'reused or wrong Metal generation')
        generations.add(generation); devices.add(before['device'])
        if data.get('require_hardware'):
            require(before['renderer_class'] == 'hardware-reported', 'required Metal hardware identity missing')
        t = cycle.get('target', {})
        require(exact_int(t.get('native_backend'), 2) and t.get('context_matches') is True and
                t.get('exact_pixels') is True and t.get('origin') == 'top-left' and
                t.get('render_path') == 'sk_surface_new_render_target', 'Metal cycle did not render the required target')
        require(exact_int(t.get('width'), 8) and exact_int(t.get('height'), 8) and exact_int(t.get('row_bytes'), 32),
                'incorrect Metal smoke layout')
        require(t.get('actual_sample_count') is False and exact_int(t.get('requested_sample_count'), 0),
                'unsupported actual-sample claim')
        require(t.get('transfer_format') == 'RGBA8888-unpremultiplied' and
                cycle.get('encoded_after_teardown') is True, 'missing post-teardown CPU output')
        path = cycle.get('image')
        require(isinstance(path, str) and path not in paths, 'reused Metal smoke artifact')
        paths.add(path)
        require(images.load(directory, path, (8, 8)) == images.pattern(), 'wrong actual Metal smoke pixels')
    require(len(devices) == 1, 'Metal default device changed during lifecycle probe')
    return {'cycles_checked': 3, 'native_test_cases': METAL_NATIVE_CASES, 'device': devices.pop(),
            'rendering_verified': True, 'encoded_after_teardown': True, 'headless': True}


def cross_backend(data):
    require(data.get('kind') == 'cross-backend' and exact_int(data.get('native_test_cases'), CROSS_NATIVE_CASES) and
            exact_int(data.get('native_test_failures'), 0), 'cross-backend native suite did not fully pass')
    for backend in ('opengl', 'metal'):
        before, after = data.get(backend + '_context'), data.get('closed_' + backend + '_context')
        shared.context(before, backend=backend); shared.context(after, backend=backend, closed=True)
        require(before['generation'] == after['generation'], 'wrong cross-backend teardown generation')
        if data.get('require_hardware'):
            require(before['renderer_class'] == 'hardware-reported', 'cross-backend hardware identity missing')
    require(data['opengl_context']['generation'] != data['metal_context']['generation'], 'cross-backend domains are not distinct')
    require(data.get('transfer_directions') == ['opengl-to-metal', 'metal-to-opengl'], 'missing bidirectional transfers')
    return {'native_test_cases': CROSS_NATIVE_CASES, 'transfer_directions': data['transfer_directions'],
            'foreign_use_rejected': True, 'explicit_cpu_transfer_verified': True}


def parity(directory):
    raw = {name: read_report(directory, name) for name in PREFIXES}
    run_ids = {d.get('validation_run') for d in raw.values()}
    require(len(run_ids) == 1 and all(isinstance(x, str) and x for x in run_ids),
            'reports must identify the same validation run (SKIA_GPU_VALIDATION_RUN)')
    identities = {(d.get('os'), d.get('architecture'), d.get('racket_version')) for d in raw.values()}
    require(len(identities) == 1 and next(iter(identities))[0] == 'macosx' and
            next(iter(identities))[1] in ('aarch64', 'x86_64') and
            isinstance(next(iter(identities))[2], str) and next(iter(identities))[2],
            'parity reports must be from the same 64-bit macOS/Racket environment')
    metal_result = lifecycle(raw['metal-lifecycle'], directory)
    cross_result = cross_backend(raw['cross-backend'])
    # Re-run individual inspectors on RAW reports and PNGs. A copied or stale
    # .inspection.json cannot certify missing/incorrect native work.
    for backend in ('opengl', 'metal'):
        for kind in ('offscreen', 'images'):
            data = raw[kind + '-' + backend]
            require(data.get('backend') == backend, 'mislabeled backend report')
            (shared.offscreen if kind == 'offscreen' else images.images)(data, directory)
    metal_devices = {raw[p]['initial_context']['device'] for p in ('offscreen-metal', 'images-metal')}
    metal_devices.update((metal_result['device'], raw['cross-backend']['metal_context']['device']))
    require(len(metal_devices) == 1, 'Metal reports refer to different devices')
    results = []
    all_paths = set()
    for kind in ('offscreen', 'images'):
        gl_scenes, metal_scenes = raw[kind + '-opengl']['scenes'], raw[kind + '-metal']['scenes']
        require([s['name'] for s in gl_scenes] == [s['name'] for s in metal_scenes], 'different scene registries')
        for gl, metal in zip(gl_scenes, metal_scenes):
            names = [gl['cpu_image'], gl['gpu_image'], metal['cpu_image'], metal['gpu_image']]
            require(len(set(names)) == 4 and not all_paths.intersection(names), 'reused cross-backend image filenames')
            all_paths.update(names)
            cpu_gl, gpu_gl, cpu_metal, gpu_metal = [images.load(directory, n, shared.SIZE) for n in names]
            require(cpu_gl == cpu_metal, 'CPU references differ across backend runs; do not compare unlike scenes')
            if kind == 'images':
                images.samples(gpu_gl); images.samples(gpu_metal)
            stats = shared.comparison(gpu_gl, gpu_metal, gl['name'] if kind == 'offscreen' else 'images')
            results.append({'kind': kind, 'name': gl['name'], 'cpu_image': names[0],
                            'opengl_image': names[1], 'metal_image': names[3], **stats})
    return {'schema_version': 1, 'stage': '0.41', 'status': 'passed', 'kind': 'parity',
            'validation_run': next(iter(run_ids)), 'comparisons': results, 'comparisons_checked': len(results),
            'metal_lifecycle': metal_result, 'cross_backend': cross_result,
            'shared_native_cases_per_backend': {'surface': 33, 'image': 42},
            'opengl_renderer': raw['offscreen-opengl']['initial_context']['renderer'],
            'metal_device': metal_result['device'], 'metal_rendering_verified': True,
            'metal_presentation_verified': False, 'resident_replay_readbacks': 0,
            'performance_measured': False, 'universal_pixel_identity_claimed': False}


def inspect(directory):
    directory = Path(directory)
    output, review = directory / 'parity.inspection.json', directory / 'parity.review.html'
    try:
        result = parity(directory)
        panels = []
        for row in result['comparisons']:
            panels.append('<article><h2>' + html.escape(row['kind'] + ' / ' + row['name']) + '</h2><div class="pair">')
            for key, title in (('cpu_image', 'CPU reference'), ('opengl_image', 'OpenGL'), ('metal_image', 'Metal')):
                panels.append('<figure><img width="420" height="260" src="' + html.escape(row[key], quote=True) +
                              '"><figcaption>' + title + '</figcaption></figure>')
            panels.append('</div><pre>' + html.escape(json.dumps(row, indent=2)) + '</pre></article>')
        page = ('<!doctype html><meta charset="utf-8"><title>Skia 0.41 Metal parity</title>'
                '<style>body{font:16px system-ui;max-width:1400px;margin:2em auto;padding:0 1em}'
                '.pair{display:flex;gap:1em;flex-wrap:wrap}figure{margin:0}img{max-width:100%;'
                'background:repeating-conic-gradient(#ddd 0% 25%,white 0% 50%) 0/16px 16px}'
                'pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:13px}article{margin-top:2em}</style>'
                '<h1>Offscreen OpenGL / Metal parity</h1><p>The same drawing and retained-image workflows run '
                'on both backends. Actual native IDs, owned contexts, teardown, raw pixels, explicit transfers '
                'and the live cross-backend suite are checked. Review edges, glyphs, filters and alpha below. '
                'This is not Metal window presentation, a performance benchmark, or universal pixel identity.</p>' +
                ''.join(panels) + '<h2>Inspection</h2><pre>' + html.escape(json.dumps(result, indent=2)) + '</pre>')
        shared.atomic_text(review, page)
        shared.atomic_text(output, json.dumps(result, indent=2) + '\n')
        return result
    except (ValueError, OSError, KeyError, TypeError, AttributeError):
        output.unlink(missing_ok=True); review.unlink(missing_ok=True)
        raise


def inspect_single(prefix):
    prefix = Path(prefix)
    output, review = Path(str(prefix)+'.inspection.json'), Path(str(prefix)+'.review.html')
    try:
        data = read_report(prefix.parent, prefix.name)
        if data.get('kind') == 'metal-lifecycle':
            details = lifecycle(data, prefix.parent)
        elif data.get('kind') == 'cross-backend':
            details = cross_backend(data)
        else:
            raise ValueError('not a Metal lifecycle or cross-backend diagnostic')
        result = {'schema_version':1, 'stage':'0.41', 'status':'passed', 'kind':data['kind'],
                  **details, 'performance_measured':False, 'metal_presentation_verified':False}
        page = '<!doctype html><meta charset="utf-8"><title>Skia Metal validation</title>'
        page += '<h1>'+html.escape(data['kind'])+'</h1><p>Executed offscreen checks, not window presentation or performance.</p>'
        for cycle in data.get('cycles', []):
            page += '<figure><img width="128" height="128" style="image-rendering:pixelated" src="'+html.escape(cycle['image'], quote=True)+'"><figcaption>Metal smoke after teardown</figcaption></figure>'
        page += '<pre>'+html.escape(json.dumps(result, indent=2))+'</pre>'
        shared.atomic_text(review, page)
        shared.atomic_text(output, json.dumps(result, indent=2)+'\n')
        return result
    except (ValueError, OSError, KeyError, TypeError, AttributeError):
        output.unlink(missing_ok=True); review.unlink(missing_ok=True)
        raise


# Fixtures below are synthetic and are never used by any live doctor.
def fixture(directory):
    raw = {}
    for kind in ('offscreen', 'images'):
        module = shared if kind == 'offscreen' else images
        for backend in ('opengl', 'metal'):
            name = kind + '-' + backend
            d = (module.fixture if backend == 'opengl' else module.fixture_metal)(directory)
            d.update(stage='0.41', os='macosx', architecture='aarch64', racket_version='SYNTHETIC', validation_run='SYNTHETIC-RUN')
            if kind == 'offscreen': d['native_test_cases'] = 33
            entries = [(d, 'detached_image')]
            entries += [(s, k) for s in d['scenes'] for k in ('cpu_image', 'gpu_image')]
            for parent, key in entries:
                old = parent[key]; new = name + '.' + old
                (directory / new).write_bytes((directory / old).read_bytes()); parent[key] = new
            raw[name] = d
    data = dict(schema_version=1, stage='0.41', kind='metal-lifecycle', backend='metal', status='passed',
                performance_measured=False, headless=True, presentation_tested=False,
                native_test_cases=METAL_NATIVE_CASES, native_test_failures=0, cycles=[])
    for index in range(3):
        name = f'metal-lifecycle.cycle-{index+1}.png'
        (directory/name).write_bytes(shared.png_bytes(images.pattern(), (8, 8)))
        data['cycles'].append(dict(index=index, initial_context=shared.fixture_metal_context(generation=index+1),
            closed_context=shared.fixture_metal_context(True, index+1), image=name, encoded_after_teardown=True,
            target=dict(native_backend=2, context_matches=True, exact_pixels=True, width=8, height=8, row_bytes=32,
                        origin='top-left', render_path='sk_surface_new_render_target', actual_sample_count=False,
                        requested_sample_count=0, transfer_format='RGBA8888-unpremultiplied')))
    raw['metal-lifecycle'] = data
    raw['cross-backend'] = dict(schema_version=1, stage='0.41', kind='cross-backend', status='passed',
        performance_measured=False, native_test_cases=CROSS_NATIVE_CASES, native_test_failures=0,
        transfer_directions=['opengl-to-metal', 'metal-to-opengl'], opengl_context=shared.fixture_context(),
        closed_opengl_context=shared.fixture_context(True), metal_context=shared.fixture_metal_context(generation=2),
        closed_metal_context=shared.fixture_metal_context(True, 2))
    for name, d in raw.items():
        d.update(os='macosx', architecture='aarch64', racket_version='SYNTHETIC', validation_run='SYNTHETIC-RUN')
        (directory / (name + '.diagnostic.json')).write_text(json.dumps(d))
    return raw


class Checks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='skia-metal-parity-synthetic-')
        self.addCleanup(self.temp.cleanup); self.root = Path(self.temp.name); self.raw = fixture(self.root)
    def edit(self, name, proc):
        proc(self.raw[name]); (self.root/(name+'.diagnostic.json')).write_text(json.dumps(self.raw[name]))
    def reject(self):
        with self.assertRaises((ValueError, OSError)): parity(self.root)
    def test_individual_lifecycle(self): self.assertEqual(inspect_single(self.root/'metal-lifecycle')['cycles_checked'], 3)
    def test_individual_cross_backend(self): self.assertEqual(inspect_single(self.root/'cross-backend')['native_test_cases'], CROSS_NATIVE_CASES)
    def test_valid(self): self.assertEqual(parity(self.root)['comparisons_checked'], 10)
    def test_mislabeled_backend(self): self.edit('offscreen-metal', lambda d:d.update(backend='opengl')); self.reject()
    def test_false_backend_id(self): self.edit('offscreen-metal', lambda d:d['initial_context'].update(native_backend=False)); self.reject()
    def test_legacy_report(self): self.edit('images-metal', lambda d:d.update(stage='0.40')); self.reject()
    def test_failed_native(self): self.edit('images-metal', lambda d:d.update(native_test_failures=1)); self.reject()
    def test_wrong_native_coverage(self): self.edit('offscreen-metal', lambda d:d.update(native_test_cases=0)); self.reject()
    def test_false_cross_count(self): self.edit('cross-backend', lambda d:d.update(native_test_failures=False)); self.reject()
    def test_wrong_cross_coverage(self): self.edit('cross-backend', lambda d:d.update(native_test_cases=8)); self.reject()
    def test_missing_transfer_direction(self): self.edit('cross-backend', lambda d:d['transfer_directions'].pop()); self.reject()
    def test_missing_cycle(self): self.edit('metal-lifecycle', lambda d:d['cycles'].pop()); self.reject()
    def test_reused_generation(self): self.edit('metal-lifecycle', lambda d:d['cycles'][1]['initial_context'].update(generation=1)); self.reject()
    def test_cycle_not_encoded_after_close(self): self.edit('metal-lifecycle', lambda d:d['cycles'][0].update(encoded_after_teardown=False)); self.reject()
    def test_bad_smoke_pixels(self): (self.root/'metal-lifecycle.cycle-1.png').write_bytes(shared.png_bytes(bytes(256),(8,8))); self.reject()
    def test_metal_is_not_presentation(self): self.edit('metal-lifecycle', lambda d:d.update(presentation_tested=True)); self.reject()
    def test_cycle_failure_count(self): self.edit('metal-lifecycle', lambda d:d.update(native_test_failures=1)); self.reject()
    def test_resident_readback(self): self.edit('images-metal', lambda d:d['scenes'][0]['reuse_events'].append({'kind':'readback'})); self.reject()
    def test_resident_cpu_wait(self): self.edit('images-metal', lambda d:d['scenes'][0]['reuse_events'][-1].update(wait_requested=True)); self.reject()
    def test_wrong_device(self): self.edit('cross-backend', lambda d:d['metal_context'].update(device='OTHER')); self.reject()
    def test_mixed_run(self): self.edit('offscreen-metal', lambda d:d.update(validation_run='OLD-RUN')); self.reject()
    def test_missing_run(self): self.edit('cross-backend', lambda d:d.pop('validation_run')); self.reject()
    def test_mixed_architecture(self): self.edit('images-metal', lambda d:d.update(architecture='x86_64')); self.reject()
    def test_no_metal_queue(self): self.edit('images-metal', lambda d:d['initial_context'].update(owns_command_queue=False)); self.reject()
    def test_failed_teardown(self): self.edit('images-metal', lambda d:d['closed_context'].update(pending_releases=1)); self.reject()
    def test_cpu_references_differ(self):
        row=self.raw['offscreen-metal']['scenes'][0]; p=self.root/row['cpu_image']
        pixels=bytearray(shared.png(p.read_bytes(), shared.SIZE)); pixels[4*(100*420+100)]+=1
        p.write_bytes(shared.png_bytes(pixels)); self.reject()
    def test_no_success_from_forged_inspection(self):
        (self.root/'images-metal.inspection.json').write_text('{"status":"passed"}')
        self.edit('images-metal', lambda d:d.update(status='unavailable')); self.reject()
    def test_atomic_failure_clears_stale_results(self):
        for name in ('parity.inspection.json', 'parity.review.html'): (self.root/name).write_text('STALE')
        self.edit('cross-backend', lambda d:d.update(status='error'))
        with self.assertRaises(ValueError): inspect(self.root)
        self.assertFalse((self.root/'parity.inspection.json').exists())
        self.assertFalse((self.root/'parity.review.html').exists())
    def test_review_publication(self):
        self.assertEqual(inspect(self.root)['status'], 'passed')
        self.assertIn('Offscreen OpenGL / Metal parity', (self.root/'parity.review.html').read_text())


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path)
    parser.add_argument('--probe-prefix', type=Path)
    parser.add_argument('--self-test', action='store_true')
    args=parser.parse_args()
    if args.self_test:
        raise SystemExit(0 if unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Checks)).wasSuccessful() else 1)
    if bool(args.directory) == bool(args.probe_prefix): parser.error('specify one of --directory or --probe-prefix')
    try: print(json.dumps(inspect(args.directory) if args.directory else inspect_single(args.probe_prefix), indent=2))
    except (ValueError, OSError, KeyError, TypeError, AttributeError) as error:
        parser.exit(1, f'GPU parity inspection failed: {error}\n')

#!/usr/bin/env python3
"""0.69 standard-library checks. Synthetic images/receipts are not native evidence."""
from __future__ import annotations
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import text_blob_validation as tv

ROOT=Path(__file__).resolve().parents[1]
RACKET_FILES=('text-blobs.rkt','private/text-run-data.rkt','private/text-run-util.rkt',
              'tests/text-blob-fixtures.rkt','tests/text-blob-scenes.rkt','tests/text-blob-pure-test.rkt',
              'tests/text-blob-native-test.rkt','tests/text-blob-gpu-test.rkt',
              'tools/text-blob-doctor.rkt','examples/text-blobs-advanced.rkt')
SIGNATURES={
 'sk_textblob_builder_alloc_run':'_pointer _pointer _int _float _float _pointer _pointer -> _void',
 'sk_textblob_builder_alloc_run_pos_h':'_pointer _pointer _int _float _pointer _pointer -> _void',
 'sk_textblob_builder_alloc_run_rsxform':'_pointer _pointer _int _pointer _pointer -> _void',
 'sk_textblob_builder_alloc_run_text':'_pointer _pointer _int _float _float _int _pointer _pointer -> _void',
 'sk_textblob_builder_alloc_run_text_pos_h':'_pointer _pointer _int _float _int _pointer _pointer -> _void',
 'sk_textblob_builder_alloc_run_text_pos':'_pointer _pointer _int _int _pointer _pointer -> _void',
 'sk_textblob_builder_alloc_run_text_rsxform':'_pointer _pointer _int _int _pointer _pointer -> _void',
 'sk_textblob_get_intercepts':'_pointer _pointer _pointer _pointer -> _int',
 'sk_text_utils_get_pos_path':'_pointer _size _int _pointer _pointer _pointer -> _void',
}

def synthetic_pixels(scene):
    # Explicitly synthetic analytical fixture, not a screenshot of Skia output.
    out=bytearray(tv.WHITE*(tv.WIDTH*tv.HEIGHT));ps=tv.polygons(scene)
    for y in range(tv.HEIGHT):
        for x in range(tv.WIDTH):
            color=tv.GREEN if 2<=x<6 and 2<=y<6 else (tv.BLUE if any(tv.inside((x+.5,y+.5),p) for p in ps) else tv.WHITE)
            at=4*(tv.WIDTH*y+x);out[at:at+4]=bytes(color)
    return bytes(out)

class Sources(unittest.TestCase):
    def text(self,name):return (ROOT/name).read_text(encoding='utf-8')
    def test_three_capabilities_have_public_anchors_without_execution_claims(self):
        import api_inventory as inv
        c=inv.load_catalog(ROOT);summary=inv.validate_catalog(c);rows={r['id']:r for r in c['features']['capabilities']}
        self.assertNotIn('0.69',summary['next_stages'])
        for name in ('text.blob-runs','text.intercepts','fonts.path-position'):
            self.assertEqual(rows[name]['status'],'supported-with-limits')
            self.assertIsNone(rows[name]['planned_stage']);self.assertTrue(rows[name]['public_equivalents'])
            self.assertEqual(rows[name]['execution_evidence'],inv.EVIDENCE_SCOPE)
    def test_new_sources_parse_and_all_test_cases_stay_inside_suites(self):
        import api_inventory as inv
        for name in RACKET_FILES:self.assertTrue(inv.forms(self.text(name)),name)
        for name,suite in (('tests/text-blob-pure-test.rkt','text-blob-pure-tests'),('tests/text-blob-native-test.rkt','text-blob-native-tests')):
            forms=inv.forms(self.text(name))
            self.assertFalse(any(isinstance(f,list) and f and f[0]=='test-case' for f in forms))
            body=next(f[2] for f in forms if isinstance(f,list) and f[:2]==['define',suite])
            self.assertEqual(body[0],'test-suite')
            self.assertGreaterEqual(sum(isinstance(f,list) and f and f[0]=='test-case' for f in body),20)
    def test_native_declarations_match_reviewed_C_signatures(self):
        import api_inventory as inv
        declarations=[f for f in inv.forms(self.text('private/native.rkt')) if isinstance(f,list) and f and f[0]=='define-native']
        for name,sig in SIGNATURES.items():
            matches=[f for f in declarations if f[1]==name];self.assertEqual(len(matches),1,name)
            self.assertEqual(matches[0][2],['_fun',*sig.split()],name)
    def test_direct_native_calls_have_the_reviewed_arity(self):
        import api_inventory as inv
        arities={n:s.split().index('->') for n,s in SIGNATURES.items()}
        def walk(f):
            if not isinstance(f,list) or not f or f[0]=='quote':return
            if isinstance(f[0],str) and f[0] in arities:self.assertEqual(len(f)-1,arities[f[0]],f[0])
            for x in f:walk(x)
        walk(inv.forms(self.text('text-blobs.rkt')))
    def test_builder_type_is_defined_after_its_text_blob_parent(self):
        core=self.text('private/core.rkt')
        self.assertLess(core.index('(struct text-blob ('),core.index('(struct multi-text-blob text-blob'))
        self.assertIn('(text-blob-builder-resource? v)',core)
        self.assertIn('(text-blob-builder-resource-handle v)',core)
        self.assertIn('(set-box! (text-blob-builder-resource-runs v) \'())',core)
    def test_native_buffer_fill_precedes_ownership_commit(self):
        source=self.text('text-blobs.rkt');start=source.index('(define (append-run!');stop=source.index('(define (text-blob-builder-add-run!')
        body=source[start:stop]
        self.assertLess(body.index('(set! touched? #t)'),body.index('(allocate-run! bp fp'))
        self.assertLess(body.index('(fill-run! who native-run'),body.index('(set-box! rb (cons run'))
        self.assertIn('(when touched? (skia-close! b))',body)
    def test_finish_transfers_fonts_before_closing_single_use_builder(self):
        source=self.text('text-blobs.rkt');body=source[source.index('(define (text-blob-builder-finish!'):source.index('(define (retained-runs')]
        self.assertLess(body.index('(set! blob (make-multi-text-blob-record'),body.index('(set-box! rb \'())'))
        self.assertLess(body.index('(set-box! rb \'())'),body.rindex('(skia-close! b)'))
        self.assertIn('[(null? runs) (skia-close! b) #f]',body)
    def test_transformed_intercepts_reject_before_native_query(self):
        source=self.text('text-blobs.rkt');body=source[source.index('(define (text-blob-intercepts'):source.index('(define (positioned-glyphs->path')]
        self.assertLess(body.index('ignores RSXform'),body.index('(sk_textblob_get_intercepts'))
        self.assertIn('(even? count)',body);self.assertIn('(<= count (* 2 glyph-count))',body)
    def test_path_text_uses_shaped_positions_not_characters_and_does_not_clamp(self):
        source=self.text('text-blobs.rkt');body=source[source.index('(define (shaped-run->text-blob/on-path'):]
        for needed in ('shaped-run-positions','shaped-run-glyphs','path-measure-matrix','(<= 0 d contour-length)'):
            self.assertIn(needed,body)
        for forbidden in ('font-text->glyphs','font-glyph-positions','typeface-kerning','string-ref'):
            self.assertNotIn(forbidden,body)
    def test_outline_dispatch_and_missing_outline_policy_are_explicit(self):
        source=self.text('private/core.rkt')
        self.assertIn('(if (multi-text-blob? blob) (multi-text-blob->path blob) (legacy-text-blob->path blob))',source)
        self.assertIn('(sk_path_transform pp m)',source)
        self.assertIn('no monochrome outline; explicit raster output is required',source)
    def test_snapshots_and_builder_remain_CPU_independent(self):
        source=self.text('private/lifetime.rkt')
        self.assertIn('text-blob text-blob-builder shaper shaper-font',source)
    def test_UTF8_clusters_are_strict_and_copied(self):
        source=self.text('private/text-run-util.rkt')
        for needed in ('(bytes->string/utf-8 bs #f)','bytes->immutable-bytes','(bytes-copy text)', '(< c size)', '#xc0', '#x80'):
            self.assertIn(needed,source)
    def test_registered_native_pure_GPU_and_source_tests(self):
        runner=self.text('run-tests.rkt')
        self.assertIn('(run-tests text-blob-pure-tests)',runner)
        self.assertIn("dynamic-require text-blob-native-tests-file 'text-blob-native-tests",runner)
        self.assertIn('tests/text-blob-gpu-test.rkt',self.text('info.rkt'))
        self.assertIn("'test-text-blobs.py'",self.text('tools/ci.py'))
    def test_source_contains_no_public_native_pointer_ingress(self):
        source=self.text('text-blobs.rkt')
        for forbidden in ('get-ffi-obj','ffi-lib','all-defined-out'):self.assertNotIn(forbidden,source)
    def test_procedural_fixture_really_contains_Unicode_and_ligature_tables(self):
        source=self.text('tests/text-blob-fixtures.rkt')
        for needed in ('GSUB','DFLT','liga','1488','1489','119070','#xb1b0afba'):self.assertIn(needed,source)
        for forbidden in ('base64','file->bytes','ffi/unsafe'):self.assertNotIn(forbidden,source)
    def test_native_pins_and_minimums_are_unchanged(self):
        info=self.text('info.rkt')
        for clause in ('(define version "0.77")','("base" #:version "8.18")','("draw-lib" #:version "1.22")'):self.assertIn(clause,info)
        self.assertEqual(self.text('private/native-default-version.txt').strip(),'3.119.1')
    def test_workflow_requires_GPU_and_independent_Linux_viewers(self):
        source=self.text('.github/workflows/text-blobs.yml')
        for needed in ('--require-gpu','--require-renderers','--backend egl','--backend direct3d','--adapter warp'):self.assertIn(needed,source)
        for forbidden in ('continue-on-error','pull_request_target'):self.assertNotIn(forbidden,source)

class Geometry(unittest.TestCase):
    def test_independent_positive_scenes(self):
        for scene in tv.SCENES:tv.pixel_checks(synthetic_pixels(scene),scene)
    def test_blank_images_reject(self):
        for scene in tv.SCENES:
            with self.assertRaises(ValueError):tv.pixel_checks(bytes(tv.WHITE)*(tv.WIDTH*tv.HEIGHT),scene)
    def test_marker_alone_does_not_count_as_text(self):
        data=bytearray(tv.WHITE*(tv.WIDTH*tv.HEIGHT));at=4*(tv.WIDTH*4+4);data[at:at+4]=bytes(tv.GREEN)
        with self.assertRaises(ValueError):tv.pixel_checks(bytes(data),'multi')
    def test_missing_any_one_glyph_is_detected(self):
        for scene in tv.SCENES:
            ink,_=tv.safe_probes(scene)
            for sites in ink:
                data=bytearray(synthetic_pixels(scene))
                for at in sites:data[at:at+4]=bytes(tv.WHITE)
                with self.assertRaises(ValueError):tv.pixel_checks(bytes(data),scene)
    def test_wrong_scene_rejects(self):
        with self.assertRaises(ValueError):tv.pixel_checks(synthetic_pixels('multi'),'transformed')
    def test_nonopaque_background_rejects(self):
        data=bytearray(synthetic_pixels('curve'));data[3]=0
        with self.assertRaises(ValueError):tv.pixel_checks(bytes(data),'curve')
    def test_bad_dimensions_reject(self):
        with self.assertRaises(ValueError):tv.pixel_checks(b'','multi')
    def test_nontrivial_cubic_tangents_are_independent(self):
        a=tv.curve_frame(10);b=tv.curve_frame(58)
        self.assertLess(a[1],b[1]);self.assertGreater(b[2],a[2]);self.assertAlmostEqual(a[0]**2+a[1]**2,1)
    def test_quarter_turn_maps_glyph_dimensions(self):
        p=tv.transformed(tv.RECT,(0,1,30,40))
        self.assertEqual((min(x for x,y in p),min(y for x,y in p),max(x for x,y in p),max(y for x,y in p)),(30,40,58,56))


def good_row(spec=('multi','pdf','native')):
    scene,fmt,mode=spec;stem='-'.join(spec)
    features=['geometry','annotation']+(['native-text'] if mode=='native' else [])
    return dict(scene=scene,format=fmt,text_mode=mode,file=stem+'.'+fmt,rgba=stem+'.rgba',callback_count=1,
                run_count=3 if scene=='multi' else 1,audit=dict(mode='export',backend=fmt,blocking=False,vector_only=True,
                events=[dict(feature=f,status='vector') for f in features]))

class Receipts(unittest.TestCase):
    def test_valid_receipts(self):
        for spec in tv.SPECS:tv.receipt(good_row(spec),spec)
    def reject(self,change):
        row=good_row();change(row)
        with self.assertRaises(ValueError):tv.receipt(row,tv.SPECS[0])
    def test_boolean_authoring_count(self):self.reject(lambda r:r.update(callback_count=True))
    def test_duplicate_authoring(self):self.reject(lambda r:r.update(callback_count=2))
    def test_wrong_retained_run_count(self):self.reject(lambda r:r.update(run_count=1))
    def test_foreign_filename(self):self.reject(lambda r:r.update(file='../other.pdf'))
    def test_dry_preflight_not_export(self):self.reject(lambda r:r['audit'].update(mode='preflight'))
    def test_raster_fallback(self):self.reject(lambda r:r['audit']['events'][0].update(status='rasterized'))
    def test_no_native_text_event(self):self.reject(lambda r:r['audit'].update(events=r['audit']['events'][:2]))
    def test_blocking_export(self):self.reject(lambda r:r['audit'].update(blocking=True))
    def test_wrong_backend(self):self.reject(lambda r:r['audit'].update(backend='svg'))
    def test_unverified_vector_policy(self):self.reject(lambda r:r['audit'].update(vector_only=False))

class Files(unittest.TestCase):
    def test_duplicate_JSON_key_rejects(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'a.json';p.write_text('{"schema":1,"schema":1}')
            with self.assertRaises(ValueError):tv.read_json(p)
    def test_nonfinite_JSON_rejects(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'a.json';p.write_text('{"value":NaN}')
            with self.assertRaises(ValueError):tv.read_json(p)
    def test_escaping_paths_reject(self):
        with tempfile.TemporaryDirectory() as d:
            for name in ('../a.rgba','a/b.rgba','/a.rgba','a\\b.rgba','a.txt'):
                with self.assertRaises(ValueError):tv.evidence_file(Path(d),name)
    def test_stale_document_tokens_reject_before_file_reads(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);(p/'documents.json').write_text(json.dumps(dict(schema=1,stage='0.69',status='passed',run_token='old')))
            with self.assertRaises(ValueError):tv.inspect_documents(p,'new')


def good_gpu():
    return dict(schema=1,stage='0.69',status='passed',run_token='token',backend='egl',adapter='hardware',failures=0,
                frames=[dict(scene=s,text_mode=m,file=s+'-'+m+'.rgba') for s,m in tv.GPU_SPECS],
                drawing_readbacks=0,inspection_readbacks=6,contexts_closed=True,gui_executed=False,physical_display_verified=False)

class GPUReceipts(unittest.TestCase):
    def evaluate(self,row,*,pixels=False):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'gpu.json').write_text(json.dumps(row))
            if pixels:
                data={s:synthetic_pixels(s) for s in tv.SCENES}
                for s,m in tv.GPU_SPECS:(root/(s+'-'+m+'.rgba')).write_bytes(data[s])
            return tv.inspect_gpu(root,'token','egl','hardware')
    def test_synthetic_complete_GPU_evidence(self):self.assertEqual(self.evaluate(good_gpu(),pixels=True)['frames'],6)
    def test_counts_cannot_be_boolean_or_incorrect(self):
        for key in ('failures','drawing_readbacks','inspection_readbacks'):
            for value in (True,-1,99):
                row=good_gpu();row[key]=value
                with self.assertRaises(ValueError):self.evaluate(row)
    def test_missing_frame_rejects(self):
        row=good_gpu();row['frames'].pop()
        with self.assertRaises(ValueError):self.evaluate(row)
    def test_duplicate_frame_rejects(self):
        row=good_gpu();row['frames'][-1]=row['frames'][0]
        with self.assertRaises(ValueError):self.evaluate(row)
    def test_open_context_rejects(self):
        row=good_gpu();row['contexts_closed']=False
        with self.assertRaises(ValueError):self.evaluate(row)
    def test_foreign_backend_and_stale_token(self):
        for key,value in (('backend','metal'),('adapter','warp'),('run_token','old'),('schema',True)):
            row=good_gpu();row[key]=value
            with self.assertRaises(ValueError):self.evaluate(row)
    def test_invented_physical_display_claim_rejects(self):
        row=good_gpu();row['physical_display_verified']=True
        with self.assertRaises(ValueError):self.evaluate(row)

class Orchestration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec=importlib.util.spec_from_file_location('text_blob_gate',ROOT/'tools/validate-text-blobs.py')
        cls.gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(cls.gate)
    def test_compile_includes_dynamic_native_suites(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'run-tests.rkt').write_text('(define-runtime-path a "tests/a.rkt")\n(define-runtime-path b "tests/a.rkt")')
            targets=self.gate.compile_targets(root)
            self.assertEqual(targets.count(root/'tests/a.rkt'),1)
            self.assertIn(root/'run-tests.rkt',targets);self.assertIn(root/'tests/text-blob-gpu-test.rkt',targets)
    def test_empty_compile_graph_rejects(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'run-tests.rkt').write_text('#lang racket/base')
            with self.assertRaises(ValueError):self.gate.compile_targets(root)
    def test_unsafe_compile_graph_rejects(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'run-tests.rkt').write_text('(define-runtime-path a "tests/../a.rkt")')
            with self.assertRaises(ValueError):self.gate.compile_targets(root)
    def test_timeout_must_be_positive_and_finite(self):
        for value in ('0','-1','nan','inf'):
            with contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):self.gate.main(['--timeout',value])
    def test_WARP_is_not_an_EGL_adapter(self):
        with patch.object(self.gate.shutil,'which',return_value='/selected/racket'),contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):
            self.gate.main(['--backend','egl','--adapter','warp'])

if __name__=='__main__':unittest.main(verbosity=2)

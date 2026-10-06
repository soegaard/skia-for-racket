#!/usr/bin/env python3
"""0.68a standard-library tests. Synthetic evidence is not native execution."""
from __future__ import annotations
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import api_inventory as inv
import typeface_validation as tv

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('typeface_validator', ROOT/'tools/validate-typefaces.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
ADDITIONS = {
 'sk_typeface_create_from_data','sk_fontmgr_create_from_data','sk_fontmgr_create_styleset','sk_fontmgr_match_family',
 'sk_fontstyleset_create_empty','sk_fontstyleset_unref','sk_fontstyleset_get_count','sk_fontstyleset_get_style',
 'sk_fontstyleset_create_typeface','sk_fontstyleset_match_style','sk_fontstyle_get_weight','sk_fontstyle_get_width',
 'sk_fontstyle_get_slant','sk_typeface_is_fixed_pitch','sk_typeface_count_glyphs','sk_typeface_count_tables',
 'sk_typeface_get_table_tags','sk_typeface_get_table_size','sk_typeface_get_table_data','sk_typeface_copy_table_data',
 'sk_typeface_get_post_script_name','sk_typeface_get_kerning_pair_adjustments'}
NAMES = ('typefaces.rkt','private/typeface-util.rkt','tests/typeface-fixtures.rkt',
         'tests/typeface-pure-test.rkt','tests/typeface-native-test.rkt','tools/typeface-doctor.rkt','examples/typefaces.rkt')


class Sources(unittest.TestCase):
    def text(self, name): return (ROOT/name).read_text(encoding='utf-8')
    def test_source_ci_registers_the_standard_library_suite(self):
        self.assertIn("'test-typefaces.py'", self.text('tools/ci.py'))
    def test_direct_native_calls_match_declared_arities(self):
        declarations = {f[1]: f[2].index('->') - 1
                        for f in inv.forms(self.text('private/native.rkt'))
                        if isinstance(f,list) and f and f[0] == 'define-native' and f[1] in ADDITIONS}
        def walk(value):
            if not isinstance(value,list) or not value: return
            if isinstance(value[0],str) and value[0] in declarations:
                self.assertEqual(len(value)-1,declarations[value[0]],value[0])
            for child in value: walk(child)
        walk(inv.forms(self.text('typefaces.rkt')))
    def test_numeric_package_version_and_distinct_stage(self):
        self.assertIn('(define version "0.72")', self.text('info.rkt'))
        self.assertEqual(inv.STAGE, '0.72')
        self.assertIn('("base" #:version "8.18")', self.text('info.rkt'))
        self.assertIn('("draw-lib" #:version "1.22")', self.text('info.rkt'))
        self.assertEqual(inv.load_catalog(ROOT)['upstream']['package_version'], '3.119.1')
    def test_typeface_capabilities_keep_public_source_anchors(self):
        c = inv.load_catalog(ROOT); inv.validate_catalog(c)
        rows = {row['id']:row for row in c['features']['capabilities']}
        for name in ('fonts.bytes', 'fonts.styles', 'fonts.tables-metadata', 'fonts.units-and-stream'):
            self.assertEqual(rows[name]['status'], 'supported-with-limits')
            self.assertIsNone(rows[name]['planned_stage'])
            self.assertTrue(rows[name]['public_equivalents'])
            self.assertEqual(rows[name]['execution_evidence'], inv.EVIDENCE_SCOPE)
    def test_native_additions_are_declared_in_existing_registry(self):
        declarations = [f for f in inv.forms(self.text('private/native.rkt'))
                        if isinstance(f, list) and f and f[0] == 'define-native']
        self.assertTrue(ADDITIONS <= {f[1] for f in declarations})
        for name in ADDITIONS:
            self.assertEqual(sum(f[1] == name for f in declarations), 1)
    def test_size_t_and_kerning_abi(self):
        s = self.text('private/native.rkt')
        self.assertIn('(_fun _pointer _uint32 _size _size _bytes -> _size)', s)
        self.assertIn('(_fun _pointer _pointer _int _pointer -> _stdbool)', s)
    def test_all_new_racket_files_parse_as_datums(self):
        for n in NAMES:
            with self.subTest(file=n): self.assertTrue(inv.forms(self.text(n)))
    def test_racket_suites_are_nested_not_top_level_cases(self):
        for file, suite in (('tests/typeface-pure-test.rkt', 'typeface-pure-tests'),
                            ('tests/typeface-native-test.rkt', 'typeface-native-tests')):
            forms = inv.forms(self.text(file))
            self.assertFalse(any(isinstance(f,list) and f and f[0] == 'test-case' for f in forms))
            value = next(f[2] for f in forms if isinstance(f,list) and f[:2] == ['define',suite])
            self.assertEqual(value[0], 'test-suite')
            self.assertGreaterEqual(sum(isinstance(f,list) and f and f[0] == 'test-case' for f in value), 18)
    def test_style_set_uses_generic_ownership(self):
        core = self.text('private/core.rkt')
        self.assertIn('(font-style-set-resource? v)', core)
        self.assertIn('(font-style-set-resource-handle v)', core)
        self.assertIn('font-manager font-style-set typeface', self.text('private/lifetime.rkt'))
        self.assertIn("(new-owned who 'font-style-set create sk_fontstyleset_unref)", self.text('typefaces.rkt'))
    def test_copied_font_data_and_table_outputs_are_owned(self):
        s = self.text('typefaces.rkt')
        self.assertIn('sk_data_new_with_copy submitted', s)
        self.assertIn("who 'font-data", s)
        self.assertIn('sk_typeface_copy_table_data tp t', s)
        self.assertIn('bytes->immutable-bytes', s)
        self.assertIn('void/reference-sink copied submitted', s)
    def test_macos_ttc_fallback_extracts_exact_standalone_member(self):
        source = self.text('typefaces.rkt')
        util = self.text('private/typeface-util.rkt')
        self.assertIn("(eq? (system-type 'os) 'macosx)", source)
        self.assertIn('(values (ttc-member->sfnt who copied i) 0)', source)
        self.assertIn('(define (ttc-member->sfnt who data index)', util)
        self.assertIn('#xb1b0afba', util)
        self.assertIn('(bytes-copy! copy 8 #"\\0\\0\\0\\0")', util)
    def test_empty_queries_still_enter_owned_scope(self):
        s = self.text('typefaces.rkt')
        self.assertIn('(call-with-owned who (list (typeface-h who face))', s)
        self.assertIn('[(< n 2) #()]', s)
        self.assertIn('[(zero? n) #""]', s)
    def test_undefined_kerning_buffer_not_read_on_false(self):
        s = self.text('typefaces.rkt')
        self.assertIn('(and (sk_typeface_get_kerning_pair_adjustments tp input n output)', s)
        self.assertIn('(ptr-ref output _int32 i)', s)
        self.assertIn('(* (max 0 (sub1 n)) 4)', self.text('private/typeface-util.rkt'))
    def test_missing_table_is_not_assumed_empty(self):
        self.assertIn('(table-tags who tp)', self.text('typefaces.rkt'))
        self.assertIn('(and size', self.text('typefaces.rkt'))
    def test_source_contains_no_font_mutation_or_batch_callbacks(self):
        s = self.text('typefaces.rkt')
        for forbidden in ('sk_font_set_typeface','sk_font_get_paths','get-ffi-obj','ffi-lib', 'dynamic-require'):
            self.assertNotIn(forbidden, s)
    def test_font_fixtures_are_generated_from_geometry(self):
        s = self.text('tests/typeface-fixtures.rkt')
        for expected in ('(define (build-font', '(define (glyph', '#xb1b0afba', 'fixture-collection-bytes'):
            self.assertIn(expected, s)
        for forbidden in ('base64','file->bytes','ffi/unsafe','system*'):
            self.assertNotIn(forbidden, s)
    def test_regression_graph_contains_both_suites(self):
        s = self.text('run-tests.rkt')
        self.assertIn('(run-tests typeface-pure-tests)', s)
        self.assertIn("dynamic-require typeface-native-tests-file 'typeface-native-tests", s)
    def test_native_tests_check_snapshot_and_scope_failures(self):
        s = self.text('tests/typeface-native-test.rkt')
        for text in ('bytes-fill!', 'wrong-thread', 'let/ec', 'font-style-set-match', 'typeface->font-bytes',
                     '(shape-text shaper fixture-text)', 'fixture-collection-bytes'):
            self.assertIn(text, s)
    def test_document_matrix_uses_embed_capable_pdf_and_outlined_svg(self):
        self.assertEqual(len(tv.SPECS), 6)
        self.assertNotIn(('regular','svg','native'), tv.SPECS)
        self.assertIn('#:policy \'vector-only', self.text('tools/typeface-doctor.rkt'))
        self.assertNotIn('draw-rasterized', self.text('tools/typeface-doctor.rkt'))
    def test_selected_ci_executes_native_and_independent_documents(self):
        s = self.text('.github/workflows/typefaces.yml')
        for text in ('8.18','9.3','--require-renderers','validate-typefaces.py','install-native-windows.ps1'):
            self.assertIn(text, s)
        self.assertNotIn('continue-on-error', s)
    def test_no_obsolete_package_assertions(self):
        for p in (ROOT/'tools').glob('*.py'):
            self.assertNotIn('(define version "' + '0.67' + '")', p.read_text(encoding='utf-8'), p.name)


def good_metadata():
    return [dict(face=f, postscript_name='SkiaRacketFixture-'+f.title(), glyph_count=4, units_per_em=1000,
                 fixed_pitch=True, table_tags=[0x6e616d65,0x6d617870,0x636d6170], font_data_bytes=1600,
                 font_data_index=0, kerning_available=True, kerning=[-80]) for f in ('regular','bold')]


def good_receipt(spec=('regular','pdf','native')):
    f, fmt, mode = spec
    fs = ['geometry','annotation'] + (['native-text'] if mode == 'native' else [])
    return dict(face=f, format=fmt, text_mode=mode, callback_count=1, audit_policy='vector-only',
                audit=dict(mode='export',backend=fmt,blocking=False,vector_only=True,
                           events=[dict(feature=x,status='vector') for x in fs]))


class Receipts(unittest.TestCase):
    def test_each_valid_spec(self):
        for spec in tv.SPECS: tv.receipt(good_receipt(spec),spec)
    def test_bad_authoring_count(self):
        for v in (True,0,2,None):
            r=good_receipt();r['callback_count']=v
            with self.assertRaises(ValueError):tv.receipt(r,tv.SPECS[0])
    def test_mode_policy_and_blocking_are_distinct(self):
        for key,value in (('mode','preflight'),('backend','svg'),('blocking',True),('vector_only',False)):
            r=good_receipt();r['audit'][key]=value
            with self.assertRaises(ValueError):tv.receipt(r,tv.SPECS[0])
    def test_missing_native_text_event(self):
        r=good_receipt();r['audit']['events'].pop()
        with self.assertRaises(ValueError):tv.receipt(r,tv.SPECS[0])
    def test_raster_fallback_event(self):
        r=good_receipt();r['audit']['events'].append(dict(feature='raster-group',status='embedded-raster'))
        with self.assertRaises(ValueError):tv.receipt(r,tv.SPECS[0])
    def test_outline_must_not_claim_native_text(self):
        spec=('regular','pdf','outline');r=good_receipt(spec)
        r['audit']['events'].append(dict(feature='native-text',status='vector'))
        with self.assertRaises(ValueError):tv.receipt(r,spec)
    def test_foreign_face(self):
        with self.assertRaises(ValueError):tv.receipt(good_receipt(),('bold','pdf','native'))
    def test_valid_metadata_and_unsupported_kerning(self):
        rows=good_metadata();tv.metadata(rows)
        rows[0].update(kerning_available=False,kerning=False);tv.metadata(rows)
    def test_kerning_unavailability_must_not_invent_zeros(self):
        rows=good_metadata();rows[0].update(kerning_available=False,kerning=[0])
        with self.assertRaises(ValueError):tv.metadata(rows)
    def test_metadata_identity_and_table_errors(self):
        for key,value in (('postscript_name','other'),('units_per_em',True),('table_tags',[]),
                          ('glyph_count',3),('fixed_pitch',False),('font_data_index',-1),('font_data_bytes',0)):
            rows=good_metadata();rows[0][key]=value
            with self.assertRaises(ValueError):tv.metadata(rows)
    def test_duplicate_metadata(self):
        rows=good_metadata();rows[1]=rows[0]
        with self.assertRaises(ValueError):tv.metadata(rows)
    def test_missing_document_matrix(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t);(p/'documents.json').write_text(json.dumps(dict(schema=1,stage='0.68a',run_token='x',
                 status='passed',rendering_executed=True,gpu_executed=False,gui_executed=False,
                 documents=[],typefaces=good_metadata())))
            with self.assertRaises(ValueError):tv.inspect_documents(p,'x')


class Runner(unittest.TestCase):
    def test_static_and_dynamic_regressions_compiled(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);(root/'run-tests.rkt').write_text('(define-runtime-path x "tests/native.rkt")\n')
            names=[p.relative_to(root).as_posix() for p in validator.compile_targets(root)]
            for name in ('run-tests.rkt','tests/native.rkt','typefaces.rkt','tools/typeface-doctor.rkt'):
                self.assertIn(name,names)
    def test_missing_dynamic_graph_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);(root/'run-tests.rkt').write_text('')
            with self.assertRaises(ValueError):validator.compile_targets(root)
    def test_unsafe_dynamic_target_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);(root/'run-tests.rkt').write_text('(define-runtime-path x "tests/../evil.rkt")')
            with self.assertRaises(ValueError):validator.compile_targets(root)
    def test_invalid_timeout(self):
        for value in ('nan','inf','0','-1'):
            with contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):
                validator.main(['--timeout',value])
    def test_failed_subprocess_has_log_and_no_success_claim(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);out=root/'out'
            with patch.object(validator,'ROOT',root),patch.object(validator.shutil,'which',return_value='/selected/racket'),\
                 patch.object(validator.subprocess,'run',side_effect=subprocess.CalledProcessError(1,['fixture'])),\
                 contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
                code=validator.main(['--directory',str(out)])
            r=json.loads((out/'validation.json').read_text())
            self.assertEqual(code,1);self.assertEqual(r['status'],'failed')
            self.assertTrue(Path(r['failed_log']).is_file())
            self.assertFalse(r['regressions_passed']);self.assertFalse(r['rendering_executed'])
    def test_existing_directory_not_reused(self):
        with tempfile.TemporaryDirectory() as t:
            with patch.object(validator.shutil,'which',return_value='/selected/racket'),\
                 contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):
                validator.main(['--directory',t])


if __name__=='__main__':unittest.main(verbosity=2)

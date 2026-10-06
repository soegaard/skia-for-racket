#!/usr/bin/env python3
"""Inventory tests. Synthetic cases test the inspector, not Skia rendering.

RepositoryIntegration deliberately requires the complete checkout. The other
classes exercise fail-closed behavior using explicitly synthetic source trees.
"""
from __future__ import annotations
import contextlib
import copy
import importlib.util
import io
import json
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import api_inventory as inv
import api_inventory_native as native

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
CATALOG = inv.load_catalog(ROOT)
spec = importlib.util.spec_from_file_location("api_inventory_validator", HERE / "validate-api-inventory.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def synthetic_tree(root: Path):
    """Construct a synthetic complete *scope*, not a copy of the real project."""
    for file in inv.CATALOG_FILES:
        dest = root / file; dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text((ROOT / file).read_text(), encoding="utf-8")
    caps = CATALOG["features"]["capabilities"]
    required = set(CATALOG["features"]["public_modules"])
    for cap in caps:
        required.update(cap["implementation_files"] + cap["test_sources"])
    for name in required:
        file = root / name; file.parent.mkdir(parents=True, exist_ok=True)
        refs = sorted({r["name"] for cap in caps for r in cap["public_equivalents"] if r["module"] == name})
        file.write_text("#lang racket/base\n; SYNTHETIC test source, not an implementation.\n(provide " + " ".join(refs) + ")\n", encoding="utf-8")
    expected = set(CATALOG["bindings"]["symbols"])
    cpu = set(CATALOG["bindings"]["cpu_symbols"])
    gpu = sorted(expected - cpu)
    for i, (file, macro, index, _group) in enumerate(inv.REGISTRIES):
        selected = sorted(cpu) if i == 0 else gpu[i-1::8]
        path = root / file; path.parent.mkdir(parents=True, exist_ok=True)
        lines = ["#lang racket/base", "; SYNTHETIC registry"]
        for symbol in selected:
            params = " ".join(["placeholder"] * (index-1))
            lines.append(f"({macro} {params} {symbol} (_fun -> _void))")
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    (root / "private/native-default-version.txt").write_text("3.119.1\n")
    (root / "info.rkt").write_text('#lang info\n(define version "0.73")\n(define deps \'(("base" #:version "8.18") ("draw-lib" #:version "1.22")))\n')
    inv.check_report(root, CATALOG, write=True)
    (root / "tools").mkdir(exist_ok=True)
    # The real manifest validator is independently tested in existing source CI.
    (root / "tools/update-source-sums.py").write_text(
        'def check(root, *, manifest_only):\n'
        '    assert manifest_only is False\n'
        '    return 123\n')
    (root / "SOURCE-SHA256SUMS.txt").write_text("synthetic manifest\n")


def mutate_cap(c, ident, field, value):
    next(f for f in c["features"]["capabilities"] if f["id"] == ident)[field] = value


class Catalog(unittest.TestCase):
    def test_actual_reviewed_catalog(self):
        result = inv.validate_catalog(CATALOG)
        self.assertEqual(result["c_function_declarations"], 849)
        self.assertEqual(result["managed_source_files"], 86)
        self.assertEqual(result["distinct_bound_symbols"], 589)
        self.assertEqual(result["cpu_bound_symbols"], 534)
    def test_every_symbol_has_exactly_one_primary_disposition(self):
        assigned = [s for f in CATALOG["features"]["capabilities"] for s in f["native_symbols"]]
        self.assertEqual(len(assigned), len(set(assigned)))
        self.assertEqual(set(assigned), set().union(*map(set, CATALOG["upstream"]["headers"].values())))
    def test_nine_registries_include_late_interop(self):
        rows = {x[0]: x for x in inv.REGISTRIES}
        self.assertEqual(len(rows), 9)
        self.assertEqual(rows['private/gpu-metal-interop-native.rkt'][2], 1)
        self.assertEqual(rows['private/gpu-gl-interop-native.rkt'][2], 2)
        self.assertEqual(rows['private/gpu-d3d12-interop-native.rkt'][1], 'bind')
    def test_known_false_gaps_reconciled(self):
        caps = {f['id']: f for f in CATALOG['features']['capabilities']}
        self.assertEqual(caps['canvas.rounded-clip']['status'], 'racket-equivalent')
        self.assertEqual(caps['paths.iteration']['status'], 'supported-with-limits')
        self.assertEqual(caps['images.gpu-transfers']['status'], 'supported-with-limits')
        self.assertEqual(caps['future.variable-fonts']['native_symbols'], [])
    def test_no_managed_shader_mask_factory_claim(self):
        f = next(x for x in CATALOG['features']['capabilities'] if x['id'] == 'filters.shader-mask')
        self.assertEqual(f['origin'], 'c-shim-only')
        self.assertEqual(f['managed_sources'], [])
    def test_no_feature_execution_is_inferred(self):
        self.assertTrue(all(f['execution_evidence'] == inv.EVIDENCE_SCOPE for f in CATALOG['features']['capabilities']))
    def test_no_speculative_runtime_exports(self):
        refs = [r['name'] for f in CATALOG['features']['capabilities'] for r in f['public_equivalents']]
        self.assertIn('make-image-info', refs)
        self.assertNotIn('color4f', refs)


def rejection_test(change):
    def test(self):
        c = copy.deepcopy(CATALOG)
        change(c)
        with self.assertRaises((ValueError, KeyError, TypeError)):
            inv.validate_catalog(c)
    return test


changes = {
 'boolean_schema': lambda c: c['features'].update(schema=True),
 'wrong_stage': lambda c: c['features'].update(stage='0.64'),
 'foreign_baseline': lambda c: c['features'].update(baseline_commit='0'*40),
 'foreign_bindings': lambda c: c['bindings'].update(source_commit='0'*40),
 'changed_native_pin': lambda c: c['upstream'].update(package_version='4.153.1'),
 'changed_upstream_commit': lambda c: c['upstream'].update(skia_revision='0'*40),
 'boolean_abi_increment': lambda c: c['features']['comparison'].update(increment=False),
 'boolean_abi_milestone': lambda c: c['features']['comparison'].update(milestone=True),
 'changed_minimum': lambda c: c['features']['comparison'].update(minimum_racket='9.3'),
 'unclassified_symbol': lambda c: c['upstream']['headers']['include/c/sk_shader.h'].append('sk_shader_zz_new'),
 'duplicate_header_symbol': lambda c: c['upstream']['headers']['include/c/sk_shader.h'].append(c['upstream']['headers']['include/c/sk_shader.h'][0]),
 'invalid_symbol_name': lambda c: c['upstream']['headers']['include/c/sk_shader.h'].__setitem__(0,'malformed'),
 'missing_capability': lambda c: c['features']['capabilities'].pop(0),
 'duplicate_capability': lambda c: c['features']['capabilities'].append(copy.deepcopy(c['features']['capabilities'][0])),
 'extra_capability_field': lambda c: c['features']['capabilities'][0].update(pretend=True),
 'invalid_status': lambda c: c['features']['capabilities'][0].update(status='probably-supported'),
 'invalid_plan_stage': lambda c: c['features']['capabilities'][0].update(planned_stage='0.99'),
 'invented_pass': lambda c: c['features']['capabilities'][0].update(execution_evidence='passed'),
 'missing_limit': lambda c: c['features']['capabilities'][0].update(limitations=''),
 'bad_binding_claim': lambda c: c['features']['capabilities'][0].update(bindings_expected=[]),
 'bad_unbound_claim': lambda c: mutate_cap(c,'colors.xyz-ops','unbound_declarations',[]),
 'unplanned_missing': lambda c: mutate_cap(c,'colors.xyz-ops','planned_stage',None),
 'future_as_m119': lambda c: mutate_cap(c,'future.variable-fonts','origin','m119'),
 'binding_only_public': lambda c: mutate_cap(c,'streams.internal','public_equivalents',[{'module':'main.rkt','name':'make-font'}]),
 'supported_without_anchor': lambda c: mutate_cap(c,'paths.iteration','public_equivalents',[]),
 'unsupported_managed_path': lambda c: c['features']['capabilities'][0]['managed_sources'].append('binding/SkiaSharp/Invented.cs'),
 'missing_managed_disposition': lambda c: c['features']['managed_source_crosswalk'].pop(next(iter(c['features']['managed_source_crosswalk']))),
 'wrong_cpu_inventory': lambda c: c['bindings']['cpu_symbols'].append('sk_invented_call'),
 'wrong_combined_inventory': lambda c: c['bindings']['symbols'].append('sk_invented_call'),
 'native_evidence_fabricated': lambda c: c['evidence'].update(per_symbol_export_list_retained=True),
 'native_evidence_foreign': lambda c: c['evidence'].update(source_commit='0'*40),
 'native_evidence_wrong_abi': lambda c: c['evidence'].update(native_version='153.0'),
 'native_evidence_rendering': lambda c: c['evidence'].update(rendering_claim_for_inventory_features=True),
 'bad_artifact_hash': lambda c: c['evidence'].update(artifact_sha256='wrong'),
 'path_iteration_false_gap': lambda c: mutate_cap(c,'paths.iteration','status','intentionally-excluded'),
 'gpu_transfer_false_gap': lambda c: mutate_cap(c,'images.gpu-transfers','status','intentionally-excluded'),
}
for name, change in changes.items():
    setattr(Catalog, 'test_reject_' + name, rejection_test(change))


class FilesAndJson(unittest.TestCase):
    def test_duplicate_json(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'x.json'; p.write_text('{"x":1,"x":2}')
            with self.assertRaises(ValueError): inv.read_json(p)
    def test_nonfinite_json(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'x.json'
            for v in ('NaN','Infinity','-Infinity'):
                p.write_text('{"x":'+v+'}')
                with self.assertRaises(ValueError): inv.read_json(p)
    def test_nonobject_json(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'x.json'
            for v in ('[]','true','null','1'):
                p.write_text(v)
                with self.assertRaises(ValueError): inv.read_json(p)
    def test_missing_json(self):
        with tempfile.TemporaryDirectory() as t, self.assertRaises(ValueError): inv.read_json(Path(t)/'missing')
    def test_oversized_json(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'x.json';p.write_text('{}')
            with patch.object(inv,'MAX_JSON',1), self.assertRaises(ValueError): inv.read_json(p)
    def test_unsafe_paths(self):
        with tempfile.TemporaryDirectory() as t:
            for p in ('../x','/x','a/../x','a\\x','a:x','a//x','./x','a\nx',''):
                with self.subTest(p=p), self.assertRaises(ValueError): inv.safe_file(Path(t),p,must_exist=False)
    def test_missing_source(self):
        with tempfile.TemporaryDirectory() as t, self.assertRaises(ValueError): inv.safe_file(Path(t),'missing')
    def test_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            r=Path(t);(r/'target').write_text('{}');(r/'alias').symlink_to(r/'target')
            with self.assertRaises(ValueError): inv.safe_file(r,'alias')
            with self.assertRaises(ValueError): inv.read_json(r/'alias')
    def test_directory_not_file(self):
        with tempfile.TemporaryDirectory() as t:
            (Path(t)/'dir').mkdir()
            with self.assertRaises(ValueError): inv.safe_file(Path(t),'dir')
    def test_normal_path(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'x';p.write_text('x');self.assertEqual(inv.safe_file(Path(t),'x'),p)


class Reader(unittest.TestCase):
    def test_top_level(self):
        self.assertEqual(inv.forms('#lang racket/base\n(define-native sk_x (_fun -> _void))')[0][1], 'sk_x')
    def test_line_comments(self):
        self.assertEqual(inv.forms(';(define-native sk_fake _)\n(define x 1)'), [['define','x','1']])
    def test_nested_comments(self):
        self.assertEqual(inv.forms('#| ( #| more |# ) |# (x)'), [['x']])
    def test_datum_comment(self):
        self.assertEqual(inv.forms('#;(define-native sk_fake _) (x)'), [['x']])
    def test_nested_datum_comments(self):
        self.assertEqual(inv.forms('#; #; (fake1) (fake2) (real)'), [['real']])
    def test_strings_not_identifiers(self):
        f=inv.forms('(x "sk_fake" #rx"sk_other" #"sk_bytes")')[0]
        self.assertTrue(all(isinstance(x, inv.String) for x in f[1:]))
    def test_string_escaped_quote(self):
        self.assertEqual(inv.forms('(x "a\\\"b")')[0][1].value,'a"b')
    def test_character_delimiters(self):
        f=inv.forms('(list #\\( #\\) #\\space #\\nul)')[0]
        self.assertEqual(len(f),5)
    def test_quotes_are_not_calls(self):
        self.assertEqual(inv.forms("'(define-native sk_fake _) ")[0][0], 'quote')
    def test_all_brackets(self): self.assertEqual(inv.forms('(x [y {z}])'), [['x',['y',['z']]]])
    def test_bad_brackets(self):
        for text in ('(x]', '(x', ')', '#| open', '(x "open', '#\\', "'"):
            with self.subTest(text=text), self.assertRaises(ValueError): inv.forms(text)
    def test_c_declarations_only(self):
        text='''// SK_C_API void sk_fake();\n/* SK_C_API int sk_fake2(void); */
#define sk_macro(x) (x)
typedef void (*gr_callback)(int);
SK_C_API const sk_image_t* sk_image_x(const sk_image_t* image);
SK_C_API void sk_image_y(\n int x, const float y[2]);'''
        self.assertEqual(inv.c_functions(text), ['sk_image_x','sk_image_y'])
    def test_duplicate_c_declaration(self):
        with self.assertRaises(ValueError): inv.c_functions('SK_C_API void sk_x(); SK_C_API void sk_x();')


class Sources(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);synthetic_tree(self.root)
    def tearDown(self): self.temp.cleanup()
    def test_synthetic_complete_scope(self):
        r=inv.validate_sources(self.root,CATALOG)
        self.assertEqual(len(r['binding_locations']),589);self.assertEqual(r['registry_count'],9)
        self.assertFalse(r['rendering_executed'])
    def test_missing_registry_fails(self):
        (self.root/'private/gpu-metal-interop-native.rkt').unlink()
        with self.assertRaises(ValueError): inv.validate_sources(self.root,CATALOG)
    def test_duplicate_declaration_fails(self):
        p=self.root/'private/native.rkt';s=p.read_text();p.write_text(s+s[s.index('(define-native'):s.index('\n',s.index('(define-native'))+1])
        with self.assertRaises(ValueError): inv.scan_bindings(self.root)
    def test_added_binding_fails(self):
        p=self.root/'private/native.rkt';p.write_text(p.read_text()+'(define-native sk_unreviewed_new (_fun -> _void))\n')
        with self.assertRaisesRegex(ValueError,'binding drift'): inv.validate_sources(self.root,CATALOG)
    def test_removed_binding_fails(self):
        p=self.root/'private/native.rkt';s=p.read_text().splitlines();p.write_text('\n'.join(s[:2]+s[3:])+'\n')
        with self.assertRaisesRegex(ValueError,'binding drift'): inv.validate_sources(self.root,CATALOG)
    def test_new_registry_fails(self):
        (self.root/'private/surprise.rkt').write_text('(define-my-binding sk_new (_fun -> _void))')
        with self.assertRaisesRegex(ValueError,'unregistered'): inv.scan_bindings(self.root)
    def test_raw_native_library_binder_fails(self):
        (self.root/'private/surprise.rkt').write_text('(require (only-in "native.rkt" skia-native-library-handle))\n(define x (get-ffi-obj \'sk_x (skia-native-library-handle) _pointer))')
        with self.assertRaisesRegex(ValueError,'unregistered'): inv.scan_bindings(self.root)
    def test_macro_template_not_counted(self):
        p=self.root/'private/native.rkt';p.write_text(p.read_text()+'\n(define-syntax-rule (not-a-call name) (define-native sk_fake name))\n')
        self.assertNotIn('sk_fake', inv.scan_bindings(self.root)['symbols'])
    def test_comment_string_and_quote_not_counted(self):
        p=self.root/'private/native.rkt';p.write_text(p.read_text()+'\n; (define-native sk_fake _)\n#;(define-native sk_fake _)\n(define s "(define-native sk_fake _)")\n\'(define-native sk_fake _)\n')
        self.assertNotIn('sk_fake', inv.scan_bindings(self.root)['symbols'])
    def test_bad_registry_position_fails(self):
        p=self.root/'private/gpu-image-native.rkt';p.write_text('(define-image-native safe "sk_x" _)\n')
        with self.assertRaisesRegex(ValueError,'unrecognized'): inv.scan_bindings(self.root)
    def test_missing_public_export(self):
        p=self.root/'annotations.rkt';p.write_text('#lang racket/base\n; canvas-annotate-url!\n')
        with self.assertRaisesRegex(ValueError,'public declaration not found'): inv.validate_sources(self.root,CATALOG)
    def test_new_public_module(self):
        (self.root/'unreviewed.rkt').write_text('#lang racket/base\n')
        with self.assertRaisesRegex(ValueError,'public module inventory'): inv.validate_sources(self.root,CATALOG)
    def test_missing_test_source(self):
        (self.root/'tests/native-test.rkt').unlink()
        with self.assertRaisesRegex(ValueError,'missing file'): inv.validate_sources(self.root,CATALOG)
    def test_plans_are_not_scanned_or_changed(self):
        p=self.root/'plans/local.rkt';p.parent.mkdir();p.write_text('private local plan, not parseable as Racket ((((')
        old=p.read_bytes();inv.validate_sources(self.root,CATALOG);self.assertEqual(p.read_bytes(),old)
    def test_changed_package_minimum(self):
        p=self.root/'info.rkt';p.write_text(p.read_text().replace('8.18','9.3'))
        with self.assertRaisesRegex(ValueError,'minimum'): inv.validate_sources(self.root,CATALOG)
    def test_changed_native_pin(self):
        (self.root/'private/native-default-version.txt').write_text('4.153.1\n')
        with self.assertRaisesRegex(ValueError,'native pin'): inv.validate_sources(self.root,CATALOG)
    def test_reexport_through_private_file(self):
        (self.root/'private/exports.rkt').write_text('(provide marker (rename-out [old renamed]))')
        (self.root/'facade.rkt').write_text('(provide (all-from-out "private/exports.rkt"))')
        self.assertEqual(inv.source_exports(self.root,'facade.rkt'),{'marker','renamed'})
    def test_nested_submodule_not_public(self):
        (self.root/'facade.rkt').write_text('(module* internal #f (provide hidden)) (provide real)')
        self.assertEqual(inv.source_exports(self.root,'facade.rkt'),{'real'})
    def test_reexport_cycle_fails(self):
        (self.root/'a.rkt').write_text('(provide (all-from-out "b.rkt"))')
        (self.root/'b.rkt').write_text('(provide (all-from-out "a.rkt"))')
        with self.assertRaises(ValueError): inv.source_exports(self.root,'a.rkt')
    def test_report_drift_fails(self):
        p=self.root/inv.REPORT;p.write_text(p.read_text()+'wrong\n')
        with self.assertRaisesRegex(ValueError,'report drift'): inv.check_report(self.root,CATALOG)
    def test_write_is_deterministic(self):
        before=(self.root/inv.REPORT).read_bytes();inv.check_report(self.root,CATALOG,write=True)
        self.assertEqual((self.root/inv.REPORT).read_bytes(),before)
    def test_source_mutation_changes_fingerprint(self):
        first=inv.validate_sources(self.root,CATALOG)
        p=self.root/'private/core.rkt';p.write_text(p.read_text()+'; change\n')
        second=inv.validate_sources(self.root,CATALOG)
        self.assertNotEqual(first['source_hashes'],second['source_hashes'])


class Upstream(unittest.TestCase):
    def test_full_synthetic_upstream_scope(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);skia=root/'skia';sharp=root/'sharp';u=CATALOG['upstream']
            hpaths=sorted(set(u['headers'])|set(u['non_function_headers'])|set(u['excluded_headers']))
            for path in hpaths:
                file=skia/path;file.parent.mkdir(parents=True,exist_ok=True)
                file.write_text('\n'.join('SK_C_API void '+name+'(void);' for name in u['headers'].get(path,[])))
            for path in u['managed_files']:
                file=sharp/path;file.parent.mkdir(parents=True,exist_ok=True);file.write_text('// synthetic family source\n')
            responses=[(hpaths,{'synthetic':True}),(u['managed_files'],{'synthetic':True})]
            with patch.object(inv,'upstream_check',side_effect=responses):
                result=inv.verify_upstream(CATALOG,skia,sharp)
            self.assertFalse(result['rendering_executed'])
            file=skia/'include/c/sk_shader.h';file.write_text(file.read_text()+'\nSK_C_API void sk_unclassified(void);')
            with patch.object(inv,'upstream_check',side_effect=responses), self.assertRaisesRegex(ValueError,'declaration drift'):
                inv.verify_upstream(CATALOG,skia,sharp)
    def test_managed_tree_drift(self):
        u=CATALOG['upstream'];hpaths=sorted(set(u['headers'])|set(u['non_function_headers'])|set(u['excluded_headers']))
        with patch.object(inv,'upstream_check',side_effect=[(hpaths,{}),(u['managed_files'][:-1],{})]), self.assertRaisesRegex(ValueError,'managed source tree'):
            inv.verify_upstream(CATALOG,Path('/unused'),Path('/unused'))
    def test_header_tree_drift(self):
        with patch.object(inv,'upstream_check',side_effect=[([],{}),(CATALOG['upstream']['managed_files'],{})]), self.assertRaisesRegex(ValueError,'header tree'):
            inv.verify_upstream(CATALOG,Path('/unused'),Path('/unused'))
    def test_pinned_sources_command_shape(self):
        self.assertEqual(len(inv.SKIA_COMMIT),40);self.assertEqual(len(inv.SHARP_COMMIT),40)
    def test_real_git_blob_verification(self):
        with tempfile.TemporaryDirectory() as t:
            r=Path(t);(r/'include/c').mkdir(parents=True);p=r/'include/c/sk_fixture.h';p.write_text('SK_C_API void sk_fixture(void);\n')
            def git(*args): return subprocess.check_output(['git','-C',str(r),*args],stderr=subprocess.DEVNULL).decode().strip()
            git('init');git('add','.');git('-c','user.name=Test','-c','user.email=test@example.invalid','commit','-m','synthetic')
            commit=git('rev-parse','HEAD')
            paths, hashes=inv.upstream_check(r,commit,'include/c','.h')
            self.assertEqual(paths,['include/c/sk_fixture.h']);self.assertEqual(len(hashes[paths[0]]['git_blob']),40)
            p.write_text('changed')
            with self.assertRaisesRegex(ValueError,'dirty/truncated'): inv.upstream_check(r,commit,'include/c','.h')
    def test_wrong_git_commit(self):
        with tempfile.TemporaryDirectory() as t:
            with patch.object(inv.subprocess,'run',return_value=subprocess.CompletedProcess([],0,stdout=b'wrong\n')):
                with self.assertRaisesRegex(ValueError,'wrong upstream commit'):inv.upstream_check(Path(t),inv.SKIA_COMMIT,'include/c','.h')


class NativeEvidence(unittest.TestCase):
    def result(self):
        return {'schema':1,'stage':'0.73','status':'observed','token':'a'*32,'library':str(Path('/selected/lib')),
                'library_sha256':'b'*64,'abi':'119.0','pointer_bytes':8,
                'symbols':{'sk_present':True,'sk_missing':False},
                'native_calls':['sk_version_get_milestone','sk_version_get_increment'],
                'backend_created':False,'rendering_executed':False,'hardware_verified':False,
                'package_version_verified':False,'signature_compatibility_verified':False}
    def validate(self,r):
        return native.validate_observation(r,token='a'*32,library=Path('/selected/lib'),sha256='b'*64,
                                           symbols=['sk_present','sk_missing'],required=['sk_present'])
    def test_valid_partial_availability(self): self.assertIs(self.validate(self.result())['symbols']['sk_missing'],False)
    def test_no_parent_native_import(self):
        text=(HERE/'api_inventory_native.py').read_text()
        self.assertIn('    import ctypes\n',text)
        self.assertIn('"-I"',text)
    def test_missing_library(self):
        with tempfile.TemporaryDirectory() as t, self.assertRaises(ValueError):
            native.observe(Path(t)/'missing',['sk_x'],directory=Path(t)/'out')
    def test_native_failures_remain_failures(self):
        with tempfile.TemporaryDirectory() as t:
            r=Path(t);p=r/'fake.so';p.write_bytes(b'not a native library')
            with self.assertRaisesRegex(ValueError,'observer exited'):
                native.observe(p,['sk_x'],directory=r/'out')
            self.assertTrue((r/'out/stderr.log').is_file())
    def test_timeout_propagates(self):
        with tempfile.TemporaryDirectory() as t:
            r=Path(t);p=r/'fake.so';p.write_bytes(b'fake')
            with patch.object(native.subprocess,'run',side_effect=subprocess.TimeoutExpired('fake',1)), self.assertRaises(subprocess.TimeoutExpired):
                native.observe(p,['sk_x'],directory=r/'out')


def native_reject(field,value):
    def test(self):
        r=self.result();r[field]=value
        with self.assertRaises(ValueError):self.validate(r)
    return test
for field,value in {'schema':True,'stage':'0.64','status':'passed','token':'c'*32,'library':'other',
                    'library_sha256':'c'*64,'abi':'153.0','pointer_bytes':4,'symbols':{'sk_present':True},
                    'native_calls':['sk_draw_something'],'backend_created':True,'rendering_executed':True,
                    'hardware_verified':True,'package_version_verified':True,'signature_compatibility_verified':True}.items():
    setattr(NativeEvidence,'test_reject_'+field,native_reject(field,value))
setattr(NativeEvidence,'test_reject_integer_availability',native_reject('symbols',{'sk_present':1,'sk_missing':0}))
setattr(NativeEvidence,'test_reject_unresolved_cpu',native_reject('symbols',{'sk_present':False,'sk_missing':False}))


class Runner(unittest.TestCase):
    def simulate(self,args=(), change=None, upstream_error=False, native_error=False):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);synthetic_tree(root)
            if change:change(root)
            with patch.object(inv,'verify_upstream',side_effect=ValueError('upstream failed') if upstream_error else None,return_value={'synthetic':True}) as up, \
                 patch.object(validator,'observe',side_effect=ValueError('native failed') if native_error else None,
                              return_value={'symbols':{'sk_a':True,'sk_b':False},'library_sha256':'c'*64}) as obs, \
                 contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
                code=validator.main(['--directory',str(root/'output/test'),*args],root=root)
            report=inv.read_json(root/'output/test/validation.json')
            return code, report, up.call_count, obs.call_count
    def test_offline_gate(self):
        code,r,u,n=self.simulate();self.assertEqual(code,0);self.assertFalse(r['rendering_executed']);self.assertEqual((u,n),(0,0))
    def test_full_selected_gate(self):
        code,r,u,n=self.simulate(['--skia-source','sk','--skiasharp-source','sharp','--native-library','lib'])
        self.assertEqual(code,0);self.assertTrue(r['upstream_passed']);self.assertTrue(r['native_observed']);self.assertEqual((u,n),(1,1))
    def test_upstream_failure_stops_native(self):
        code,r,u,n=self.simulate(['--skia-source','sk','--skiasharp-source','sharp','--native-library','lib'],upstream_error=True)
        self.assertEqual(code,1);self.assertFalse(r['native_observed']);self.assertEqual(n,0)
    def test_native_failure_stays_failed(self):
        code,r,_,_=self.simulate(['--native-library','lib'],native_error=True)
        self.assertEqual(code,1);self.assertEqual(r['status'],'failed')
    def test_source_failure_stops_optional_gates(self):
        code,r,u,n=self.simulate(['--native-library','lib'],change=lambda root:(root/'private/native.rkt').unlink())
        self.assertEqual(code,1);self.assertFalse(r['source_passed']);self.assertEqual(n,0)
    def test_report_drift_fails(self):
        code,r,_,_=self.simulate(change=lambda root:(root/inv.REPORT).write_text('stale'))
        self.assertEqual(code,1);self.assertIn('drift',r['error'])
    def test_existing_directory_refused(self):
        with tempfile.TemporaryDirectory() as t,self.assertRaises(FileExistsError):validator.main(['--directory',t])
    def test_bad_cli(self):
        for args in (['--skia-source','one'],['--timeout','nan'],['--timeout','0']):
            with contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):validator.main(args)


class CommandLine(unittest.TestCase):
    def test_cli_write_checks_full_sources_first(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);synthetic_tree(root);old=(root/inv.REPORT).read_bytes()
            p=root/'private/native.rkt';p.write_text(p.read_text()+'(define-native sk_unclassified (_fun -> _void))\n')
            with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
                code=inv.main(['--write'],root=root)
            self.assertEqual(code,1);self.assertEqual((root/inv.REPORT).read_bytes(),old)
    def test_cli_check_and_write(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);synthetic_tree(root)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(inv.main(['--check'],root=root),0)
                self.assertEqual(inv.main(['--write'],root=root),0)
    def test_cli_partial_upstream_rejected(self):
        with contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):inv.main(['--skia-source','only'])


class RepositoryIntegration(unittest.TestCase):
    """These are NOT optional: the complete checkout must pass in source CI."""
    def test_complete_project_source_and_anchors(self): inv.validate_sources(ROOT,CATALOG)
    def test_generated_report_current(self): inv.check_report(ROOT,CATALOG)
    def test_ci_checks_pinned_upstream_and_native(self):
        text=(ROOT/'.github/workflows/api-inventory.yml').read_text()
        for token in (inv.SKIA_COMMIT, inv.SHARP_COMMIT,'--native-library','--skia-source','--skiasharp-source',"racket: ['8.18', '9.3']"):
            self.assertIn(token,text)
        self.assertNotIn('continue-on-error:',text)
        self.assertIn("'test-api-inventory.py'",(ROOT/'tools/ci.py').read_text())
    def test_design_decisions_cover_lifetimes_and_precision(self):
        text=re.sub(r'\s+', ' ', (ROOT/'docs/API-DESIGN-DECISIONS.md').read_text())
        for token in ('D1.', 'D2.', 'D3.', 'D4.', 'D5.', 'D6.', 'D7.', 'D8.', 'D9.', 'D10.',
                      '1/255','placement offset','lease','not sample','SkiaSharp 3.119.1'):
            self.assertIn(token,text)


if __name__=='__main__':
    unittest.main(verbosity=2)

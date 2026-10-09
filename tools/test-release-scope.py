#!/usr/bin/env python3
"""0.78a review regressions. Synthetic fixtures are not native execution evidence.

RepositoryIntegration is mandatory in the real source CI. The delivery verifier
runs the other classes only and reports that complete-checkout limitation.
"""
from __future__ import annotations
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import release_scope as r
ROOT = Path(__file__).resolve().parents[1]
POLICY = r.read_json(ROOT / r.POLICY)
# These are hypothetical pending scenarios, not the current repository status.
# Keeping them exercises rejection/closure gates after real 0.78b closure.
POLICY = copy.deepcopy(POLICY)
for _fixture_id in ('colors.xyz-ops', 'surfaces.null'):
    POLICY['decisions'][_fixture_id] = dict(
        resolution='pending', target='0.78b',
        reason='Synthetic pending-family scenario; not current source support.',
        acceptance='Synthetic closure gate; not native execution evidence.')


def synthetic_catalog():
    rows = []
    for i, (ident, decision) in enumerate(POLICY['decisions'].items()):
        res = decision['resolution']
        status = {'equivalent':'racket-equivalent','limited':'supported-with-limits',
                  'pending':'missing-available-abi','deferred':'missing-available-abi',
                  'excluded':'intentionally-excluded'}[res]
        if ident.startswith('future.'):
            status = 'unavailable-pinned-abi'
        symbols = [] if ident.startswith('future.') else [f'sk_synthetic_{i}']
        if ident == 'colors.float':
            symbols = ['sk_color4f_from_color','sk_color4f_to_color']
        existing = res in ('equivalent','limited')
        rows.append(dict(id=ident,title='SYNTHETIC '+ident,status=status,
            planned_stage=decision['target'],native_symbols=symbols,
            bindings_expected=symbols if res=='limited' else [],
            unbound_declarations=[] if res=='limited' else symbols,
            public_equivalents=[dict(module='main.rkt',name='fixture')] if existing else [],
            implementation_files=['private/core.rkt'] if existing else [],
            test_sources=['tests/fixture.rkt'] if existing else [],
            limitations='Synthetic restricted contract; not Skia implementation.',
            backend_scope='No native execution',document_behavior='No native output',
            managed_sources=['binding/SkiaSharp/Test.cs'],origin='future-extension' if ident.startswith('future.') else 'm119',
            execution_evidence=r.EVIDENCE))
    for ident,status in [('existing.limited','supported-with-limits'),('existing.equivalent','racket-equivalent'),('existing.supported','supported')]:
        rows.append(dict(id=ident,title='SYNTHETIC '+ident,status=status,planned_stage=None,
                         native_symbols=[],bindings_expected=[],unbound_declarations=[],
                         public_equivalents=[dict(module='main.rkt',name='fixture')],
                         implementation_files=['private/core.rkt'],test_sources=['tests/fixture.rkt'],
                         limitations='Synthetic limits',backend_scope='none',document_behavior='none',
                         managed_sources=['binding/SkiaSharp/Test.cs'],origin='m119',execution_evidence=r.EVIDENCE))
    declared=sorted(s for x in rows for s in x['native_symbols'])
    bound=sorted(s for x in rows for s in x['bindings_expected'])
    return dict(upstream=dict(package_version='3.119.1',skia_revision=r.COMPARISON['skia_revision'],
                 skiasharp_revision=r.COMPARISON['skiasharp_revision'],headers={'include/c/sk_fixture.h':declared},
                 managed_files=['binding/SkiaSharp/Test.cs']),
        bindings=dict(symbols=bound,cpu_symbols=bound,source_commit=r.BASELINE),
        features=dict(stage=r.STAGE,baseline_commit=r.BASELINE,
                      comparison=dict(package='3.119.1',milestone=119,increment=0,minimum_racket='8.18',minimum_draw_lib='1.22'),
                      public_modules=['main.rkt'],capabilities=rows))


def fixture():
    catalog=synthetic_catalog()
    hashes={'private/core.rkt':'b'*64,'tests/fixture.rkt':'c'*64}
    policy=copy.deepcopy(POLICY)
    review=r.make_initial_review(catalog,hashes,policy)
    return catalog,hashes,review,policy


class Review(unittest.TestCase):
    def setUp(self):self.c,self.h,self.v,self.p=fixture()
    def check(self):return r.validate_review(self.c,self.h,self.v,self.p)
    def test_valid(self):
        s=self.check();self.assertFalse(s['release_ready']);self.assertFalse(s['rendering_executed'])
        self.assertEqual(len(s['open_in_scope']),2)
    def test_every_family_is_covered(self):self.assertEqual(self.check()['capability_families'],len(self.c['features']['capabilities']))
    def test_equivalence_does_not_bind_native_symbols(self):
        c=next(c for c in self.c['features']['capabilities'] if c['id']=='colors.float')
        self.assertEqual(c['bindings_expected'],[]);self.assertEqual(len(c['unbound_declarations']),2)
        self.assertEqual(next(x for x in self.v['capabilities'] if x['id']=='colors.float')['resolution'],'equivalent')
    def test_accepted_gpu_families_are_not_open_gaps(self):
        rows={x['id']:x for x in self.v['capabilities']}
        for ident in ('gpu.trace','gpu.interface-variants'):
            self.assertEqual(rows[ident]['status'],'supported-with-limits')
            self.assertEqual(rows[ident]['resolution'],'limited')
            self.assertIsNone(rows[ident]['target'])
        self.assertEqual({x['id'] for x in self.check()['open_in_scope']},
                         {'surfaces.null','colors.xyz-ops'})
    def test_stale_pending_gpu_policy_is_rejected(self):
        self.p['decisions']['gpu.trace'].update(resolution='pending',target='0.77c')
        with self.assertRaisesRegex(ValueError,'supported family disposition'):
            r.make_initial_review(self.c,self.h,self.p)
    def test_gpu_limit_changes_require_explicit_review(self):
        cap=next(x for x in self.c['features']['capabilities'] if x['id']=='gpu.interface-variants')
        cap['limitations']='All GLES and WebGL hosts are guaranteed.'
        with self.assertRaisesRegex(ValueError,'capability review drift'):self.check()
    def test_source_hashes_are_frozen(self):
        self.h['private/core.rkt']='a'*64
        with self.assertRaisesRegex(ValueError,'input drift'):self.check()
    def test_added_source_detected(self):
        self.h['new.rkt']='a'*64
        with self.assertRaises(ValueError):self.check()
    def test_removed_source_detected(self):
        self.h.pop('tests/fixture.rkt')
        with self.assertRaises(ValueError):self.check()
    def test_declared_limits_cannot_change(self):
        self.c['features']['capabilities'][0]['limitations']='broader unsupported promise'
        with self.assertRaisesRegex(ValueError,'capability review drift'):self.check()
    def test_no_metadata_execution_claim(self):
        self.c['features']['capabilities'][0]['execution_evidence']='all-green'
        with self.assertRaisesRegex(ValueError,'runtime evidence'):self.check()
    def test_new_unclassified_declaration(self):
        self.c['upstream']['headers']['include/c/sk_fixture.h'].append('sk_new')
        with self.assertRaisesRegex(ValueError,'unclassified'):self.check()
    def test_duplicate_declaration(self):
        self.c['upstream']['headers']['include/c/sk_fixture.h']*=2
        with self.assertRaisesRegex(ValueError,'duplicate'):self.check()
    def test_duplicate_assignment(self):
        self.c['features']['capabilities'][1]['native_symbols']+=self.c['features']['capabilities'][0]['native_symbols']
        with self.assertRaises(ValueError):self.check()
    def test_duplicate_binding(self):
        self.c['bindings']['symbols']*=2
        with self.assertRaises(ValueError):self.check()
    def test_unknown_cpu_binding(self):
        self.c['bindings']['cpu_symbols'].append('sk_not_bound')
        with self.assertRaises(ValueError):self.check()
    def test_binding_classification_mismatch(self):
        self.c['features']['capabilities'][0]['bindings_expected']=['sk_invented']
        with self.assertRaises(ValueError):self.check()
    def test_all_missing_require_explicit_policy(self):
        self.p['decisions'].pop('surfaces.null')
        with self.assertRaisesRegex(ValueError,'explicit residual'):self.check()
    def test_completed_revision_cannot_be_inferred(self):
        row=next(x for x in self.v['capabilities'] if x['id']=='surfaces.null');row['resolution']='supported'
        with self.assertRaisesRegex(ValueError,'missing feature'):self.check()
    def test_past_stage_is_not_a_closure_target(self):
        cap=next(x for x in self.c['features']['capabilities'] if x['id']=='colors.xyz-ops')
        cap['planned_stage']='0.71';self.p['decisions']['colors.xyz-ops']['target']='0.71'
        with self.assertRaisesRegex(ValueError,'closure stage'):self.check()
    def test_unnamed_deferral(self):
        self.p['decisions']['documents.xps']['target']='someday'
        with self.assertRaises(ValueError):self.check()
    def test_exclusion_needs_explanation(self):
        self.p['decisions']['images.raw-storage']['reason']=''
        with self.assertRaisesRegex(ValueError,'missing decision'):self.check()
    def test_unknown_policy_id(self):
        self.p['decisions']['fake']=copy.deepcopy(self.p['decisions']['gpu.trace'])
        with self.assertRaisesRegex(ValueError,'unknown policy'):self.check()
    def test_changed_policy_fingerprint(self):
        self.p['decisions']['gpu.trace']['reason']='review this deliberately'
        with self.assertRaisesRegex(ValueError,'policy changed'):self.check()
    def test_duplicate_review_row(self):
        self.v['capabilities'].append(self.v['capabilities'][0])
        with self.assertRaisesRegex(ValueError,'duplicate'):self.check()
    def test_missing_review_row(self):
        self.v['capabilities'].pop()
        with self.assertRaisesRegex(ValueError,'unreviewed'):self.check()
    def test_unsorted_review_rows(self):
        self.v['capabilities'].reverse()
        with self.assertRaisesRegex(ValueError,'sorted'):self.check()
    def test_missing_public_anchor_not_completed(self):
        next(x for x in self.c['features']['capabilities'] if x['id']=='fonts.streams')['public_equivalents']=[]
        with self.assertRaisesRegex(ValueError,'anchors'):self.check()
    def test_summary_does_not_sum_deferred_into_closed(self):
        s=self.check();self.assertEqual(s['release_dispositions']['deferred'],6)
        self.assertFalse(s['in_scope_gaps_closed']);self.assertFalse(s['release_ready'])
    def test_source_evidence_is_not_feature_evidence(self):
        s=self.check();self.assertFalse(s['per_capability_runtime_verified']);self.assertFalse(s['native_symbols_probed'])
    def test_review_deterministic(self):self.assertEqual(self.v,r.make_initial_review(self.c,self.h,self.p))
    def test_report_deterministic_and_explicit(self):
        a=r.generated_report(self.c,self.v,self.check())
        self.assertEqual(a,r.generated_report(self.c,self.v,self.check()))
        for text in ('not a 1.0 release approval','not implemented','0.77c','0.78b','Color4f','overload'):
            # Color4f is the catalogue correction; ID is the stable table label.
            if text=='Color4f':text='colors.float'
            self.assertIn(text,a)
    def test_generation_does_not_mutate_review(self):
        old=copy.deepcopy((self.c,self.v,self.p));r.generated_report(self.c,self.v,self.check())
        self.assertEqual(old,(self.c,self.v,self.p))


def reject_review(change):
    def test(self):
        c,h,v,p=fixture();change(c,h,v,p)
        with self.assertRaises((ValueError,KeyError,TypeError)):r.validate_review(c,h,v,p)
    return test
for name,change in {
 'boolean_schema':lambda c,h,v,p:v.update(schema=True),
 'foreign_commit':lambda c,h,v,p:v.update(reviewed_commit='a'*40),
 'false_stage':lambda c,h,v,p:v.update(stage='0.78d'),
 'extra_release_claim':lambda c,h,v,p:v.update(release_ready=True),
 'overload_claim':lambda c,h,v,p:v.update(basis='all overloads verified'),
 'empty_hashes':lambda c,h,v,p:v.update(source_hashes={}),
 'malformed_hash':lambda c,h,v,p:v['source_hashes'].update({'private/core.rkt':'x'}),
 'unsafe_hash_path':lambda c,h,v,p:v['source_hashes'].update({'../secret':'a'*64}),
 'changed_native_pin':lambda c,h,v,p:c['upstream'].update(package_version='4.0.0'),
 'changed_skia_commit':lambda c,h,v,p:c['upstream'].update(skia_revision='a'*40),
 'changed_minimum':lambda c,h,v,p:c['features']['comparison'].update(minimum_racket='9.3'),
 'boolean_increment':lambda c,h,v,p:c['features']['comparison'].update(increment=False),
 'unknown_catalog_status':lambda c,h,v,p:c['features']['capabilities'][0].update(status='probably'),
 'extra_policy_claim':lambda c,h,v,p:p.update(rendering=True),
 'empty_review':lambda c,h,v,p:v.update(capabilities=[]),
 'unknown_review_id':lambda c,h,v,p:v['capabilities'][0].update(id='unknown'),
}.items():
    setattr(Review,'test_reject_'+name,reject_review(change))


class Files(unittest.TestCase):
    def test_duplicate_json_keys(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'x';p.write_text('{"a":1,"a":2}')
            with self.assertRaisesRegex(ValueError,'duplicate'):r.read_json(p)
    def test_nonfinite_json(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'x';p.write_text('{"a":NaN}')
            with self.assertRaisesRegex(ValueError,'nonfinite'):r.read_json(p)
    def test_nonobject_json(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'x';p.write_text('[]')
            with self.assertRaises(ValueError):r.read_json(p)
    def test_size_limit(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'x';p.write_text('{}')
            with patch.object(r,'MAX_JSON',1),self.assertRaises(ValueError):r.read_json(p)
    def test_path_traversal(self):
        with tempfile.TemporaryDirectory() as t:
            for name in ('../x','/x','a/../x','a//x','a\\x','C:/x','','a\nx'):
                with self.subTest(name=name),self.assertRaises(ValueError):r.path_at(Path(t),name,exists=False)
    def test_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);(root/'real').write_text('x')
            try:(root/'alias').symlink_to(root/'real')
            except (OSError,NotImplementedError):self.skipTest('host does not allow symlink creation')
            with self.assertRaises(ValueError):r.path_at(root,'alias')
            with self.assertRaises(ValueError):r.atomic_text(root/'alias','y')
    def test_report_check_does_not_rewrite(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);(root/'docs').mkdir();p=root/r.REPORT;p.write_text('old')
            with self.assertRaisesRegex(ValueError,'report drift'):r.check_report(root,'new',write=False)
            self.assertEqual(p.read_text(),'old')
    def test_atomic_report_write(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);r.check_report(root,'new\n',write=True);r.check_report(root,'new\n',write=False)
            self.assertEqual((root/r.REPORT).read_bytes(),b'new\n')


class Completion(unittest.TestCase):
    def output(self):return f'{r.PURE_CASES} success(es) 0 failure(s) 0 error(s) {r.PURE_CASES} test(s) run\nrelease-scope-pure: {r.PURE_CASES} cases, 0 failures\n'
    def test_full(self):r.check_pure_output(self.output())
    def test_crlf(self):r.check_pure_output(self.output().replace('\n','\r\n'))
    def test_partial(self):
        with self.assertRaises(ValueError):r.check_pure_output(self.output().split('\n')[0])
    def test_duplicate(self):
        with self.assertRaises(ValueError):r.check_pure_output(self.output()*2)
    def test_wrong_count(self):
        with self.assertRaises(ValueError):r.check_pure_output(self.output().replace('16','15'))
    def test_errors(self):
        with self.assertRaises(ValueError):r.check_pure_output(self.output().replace('0 error','1 error'))


class Orchestration(unittest.TestCase):
    def invoke(self,*,racket=False,strict=False,failed=None,partial=False,drift=False,write=False):
        c,h,v,p=fixture();summary=r.validate_review(c,h,v,p)
        calls=[];audits=[]
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);out=root/'evidence'
            def audit(root,**kw):
                audits.append(kw)
                if failed=='audit' or drift and len(audits)>1:raise ValueError('synthetic source drift')
                return summary
            def execute(command,**kw):
                commands=list(map(str,command));calls.append(commands)
                kind='compile' if 'make' in commands else 'pure'
                if failed==kind:raise subprocess.CalledProcessError(1,commands)
                kw['stdout'].write('partial\n' if partial else Completion().output())
                return subprocess.CompletedProcess(commands,0)
            args=['--directory',str(out)]
            if racket:args+=['--racket',sys.executable]
            if strict:args+=['--require-no-open-gaps']
            if write:args+=['--write']
            with patch.object(r,'audit',side_effect=audit),patch.object(r.subprocess,'run',side_effect=execute),contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
                code=r.main(args,root=root)
            result=r.read_json(out/'validation.json')
        return code,result,calls,audits
    def test_source_only_not_execution(self):
        code,result,calls,_=self.invoke();self.assertEqual(code,0);self.assertEqual(calls,[])
        self.assertTrue(result['source_audit_passed']);self.assertFalse(result['pure_executed']);self.assertFalse(result['release_ready'])
    def test_requested_pure_execution(self):
        code,result,calls,audits=self.invoke(racket=True);self.assertEqual(code,0)
        self.assertTrue(result['pure_passed']);self.assertEqual(len(calls),2);self.assertEqual(len(audits),2)
    def test_strict_scope_is_not_default(self):
        code,result,_,_=self.invoke(strict=True);self.assertEqual(code,1)
        self.assertTrue(result['source_audit_passed']);self.assertIn('open in-scope',result['error'])
    def test_audit_failure_stops_execution(self):
        code,result,calls,_=self.invoke(racket=True,failed='audit');self.assertEqual(code,1);self.assertEqual(calls,[])
        self.assertFalse(result['source_audit_passed'])
    def test_compile_failure_stops_suite(self):
        code,result,calls,_=self.invoke(racket=True,failed='compile');self.assertEqual(code,1);self.assertEqual(len(calls),1)
        self.assertFalse(result['pure_executed']);self.assertFalse(result['pure_passed'])
    def test_pure_failure_is_not_a_pass(self):
        code,result,_,_=self.invoke(racket=True,failed='pure');self.assertEqual(code,1)
        self.assertTrue(result['pure_executed']);self.assertFalse(result['pure_passed'])
    def test_partial_pure_receipt(self):self.assertEqual(self.invoke(racket=True,partial=True)[0],1)
    def test_input_change_after_racket(self):self.assertEqual(self.invoke(racket=True,drift=True)[0],1)
    def test_write_forwarded_only_to_report_audit(self):
        code,_,_,audits=self.invoke(write=True);self.assertEqual(code,0);self.assertEqual(audits,[{'write':True}])
    def test_bad_timeouts(self):
        for value in ('nan','inf','0','-1'):
            with self.subTest(value=value),contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):r.main(['--timeout',value])
    def test_existing_evidence_directory_refused(self):
        with tempfile.TemporaryDirectory() as t,self.assertRaises(FileExistsError):r.main(['--directory',t],root=Path(t))
    def test_no_silent_refresh_cli(self):
        with contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):r.main(['--refresh'])


class RepositoryIntegration(unittest.TestCase):
    """Mandatory in source CI; never mocked or auto-skipped in a checkout."""
    def test_current_review_and_full_source_graph(self):r.audit(ROOT)
    def test_pure_source_count_and_registration(self):
        source=(ROOT/'tests/release-scope-pure-test.rkt').read_text(encoding='utf-8')
        self.assertEqual(source.count('(test-case '),r.PURE_CASES)
        run=(ROOT/'run-tests.rkt').read_text(encoding='utf-8')
        self.assertIn('(run-tests release-scope-pure-tests)',run)
        self.assertIn('"tests/release-scope-pure-test.rkt"',run)
    def test_required_ci_and_no_new_automatic_workflow(self):
        ci=(ROOT/'tools/ci.py').read_text(encoding='utf-8');self.assertIn("'test-release-scope.py'",ci)
        workflow=(ROOT/'.github/workflows/api-inventory.yml').read_text(encoding='utf-8')
        self.assertIn('python tools/validate-release-scope.py --require-no-open-gaps --racket',workflow)
        self.assertIn('output/release-scope-ci/',workflow)
        self.assertNotIn('continue-on-error:',workflow)
        auto={p.name for p in (ROOT/'.github/workflows').glob('*.yml') if '\n  push:' in p.read_text() or '\n  pull_request:' in p.read_text()}
        self.assertEqual(auto,{'ci.yml','api-inventory.yml','acceptance.yml'})

if __name__=='__main__':unittest.main(verbosity=2)

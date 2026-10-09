#!/usr/bin/env python3
"""API snapshot regressions. Synthetic data is never native or repository proof.

The default invocation includes RepositoryIntegration and must run in the full
checkout. A delivery environment may select other classes explicitly and must
report that restriction rather than claiming repository validation.
"""
from __future__ import annotations
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

import public_api as api
ROOT = Path(__file__).resolve().parents[1]


def policy():
    return dict(schema=1, stage=api.STAGE, baseline_commit=api.BASELINE, package_version='0.78',
                minimum_racket='8.18', comparison='exact-export-and-call-boundary',
                contract_document=api.CONTRACT,
                modules=[dict(path='canvas.rkt', stability='experimental', load_group='gui', reason='Fixture'),
                         dict(path='main.rkt', stability='stable', load_group='headless', reason='Fixture')])


def export(name='f', **changes):
    value = dict(name=name, phase='0', export_kind='value', kind='procedure', arity_mask='2',
                 required_keywords=[], allowed_keywords=[])
    value.update(changes)
    return value


def snapshot(group='headless'):
    return dict(schema=1, stage=api.STAGE, baseline_commit=api.BASELINE, group=group,
                modules=[dict(path='main.rkt' if group=='headless' else 'canvas.rkt', exports=[export()])])


def observation(group='headless', token='test-token'):
    return dict(schema=1, stage=api.STAGE, status='passed', run_token=token, group=group,
                modules=snapshot(group)['modules'], gui_instantiated=group=='gui',
                native_overrides='nonexistent', exported_procedures_called=False,
                rendering_executed=False, release_ready=False,
                runtime=dict(racket='9.3', os='unix', vm='chez-scheme'))


def completion():
    n=api.PURE_CASES
    return f'{n} success(es) 0 failure(s) 0 error(s) {n} test(s) run\npublic-api-pure: {n} cases, 0 failures\n'


class Policy(unittest.TestCase):
    def test_valid(self): self.assertEqual(len(api.checked_policy(policy())), 2)
    def test_private_path(self):
        p=policy();p['modules'][0]['path']='private/canvas.rkt'
        with self.assertRaises(ValueError):api.checked_policy(p)
    def test_duplicate(self):
        p=policy();p['modules'].append(p['modules'][0])
        with self.assertRaises(ValueError):api.checked_policy(p)
    def test_main_required(self):
        p=policy();p['modules'].pop()
        with self.assertRaises(ValueError):api.checked_policy(p)
    def test_both_groups_required(self):
        p=policy();p['modules'][0]['load_group']='headless'
        with self.assertRaises(ValueError):api.checked_policy(p)
    def test_unsafe_cannot_be_stable(self):
        p=policy();p['modules'].append(dict(path='unsafe/gpu-metal.rkt',stability='stable',load_group='headless',reason='x'))
        with self.assertRaises(ValueError):api.checked_policy(p)
    def test_unknown_stability(self):
        p=policy();p['modules'][0]['stability']='implicitly-safe'
        with self.assertRaises(ValueError):api.checked_policy(p)
    def test_bool_schema(self):
        p=policy();p['schema']=True
        with self.assertRaises(ValueError):api.checked_policy(p)
    def test_wrong_commit(self):
        p=policy();p['baseline_commit']='0'*40
        with self.assertRaises(ValueError):api.checked_policy(p)
    def test_no_extra_approval_field(self):
        p=policy();p['release_ready']=True
        with self.assertRaises(ValueError):api.checked_policy(p)


class Snapshots(unittest.TestCase):
    def test_valid(self):api.checked_snapshot(snapshot(),policy(),'headless')
    def test_identity(self):self.assertEqual(api.differences(snapshot(),snapshot()),[])
    def test_added_export(self):
        after=snapshot();after['modules'][0]['exports'].append(export('g'))
        self.assertEqual(api.differences(snapshot(),after)[0]['change'],'added')
    def test_removed_export(self):
        after=snapshot();after['modules'][0]['exports']=[]
        self.assertEqual(api.differences(snapshot(),after)[0]['change'],'removed')
    def test_positional_change(self):
        after=snapshot();after['modules'][0]['exports'][0]['arity_mask']='6'
        self.assertEqual(api.differences(snapshot(),after)[0]['change'],'changed')
    def test_required_keyword_change(self):
        after=snapshot();after['modules'][0]['exports'][0].update(required_keywords=['x'],allowed_keywords=['x'])
        self.assertTrue(api.differences(snapshot(),after))
    def test_optional_keyword_change(self):
        after=snapshot();after['modules'][0]['exports'][0]['allowed_keywords']=['x']
        self.assertTrue(api.differences(snapshot(),after))
    def test_any_keywords_differs_from_none(self):
        after=snapshot();after['modules'][0]['exports'][0]['allowed_keywords']=None
        self.assertTrue(api.differences(snapshot(),after))
    def test_parameter_not_plain_procedure(self):
        after=snapshot();after['modules'][0]['exports'][0]['kind']='parameter'
        self.assertTrue(api.differences(snapshot(),after))
    def test_export_binding_kind_is_part_of_key(self):
        after=snapshot();after['modules'][0]['exports'][0]['export_kind']='syntax'
        self.assertEqual(len(api.differences(snapshot(),after)),2)
    def test_empty_module_coverage(self):
        after=snapshot('gui');after['modules'][0]['exports']=[]
        before=copy.deepcopy(after);before['modules']=[]
        self.assertEqual(api.differences(before,after)[0]['change'],'module-coverage')
    def test_no_paths_in_descriptor(self):
        s=snapshot();s['modules'][0]['exports'][0]['source_path']='/tmp/foo.rkt'
        with self.assertRaises(ValueError):api.checked_snapshot(s,policy(),'headless')
    def test_duplicate_export(self):
        s=snapshot();s['modules'][0]['exports']*=2
        with self.assertRaises(ValueError):api.checked_snapshot(s,policy(),'headless')
    def test_required_must_be_allowed(self):
        s=snapshot();s['modules'][0]['exports'][0]['required_keywords']=['x']
        with self.assertRaises(ValueError):api.checked_snapshot(s,policy(),'headless')
    def test_empty_main_is_not_coverage(self):
        s=snapshot();s['modules'][0]['exports']=[]
        with self.assertRaises(ValueError):api.checked_snapshot(s,policy(),'headless')
    def test_missing_module_is_not_success(self):
        s=snapshot();s['modules']=[]
        with self.assertRaises(ValueError):api.checked_snapshot(s,policy(),'headless')
    def test_invalid_arity_masks(self):
        for m in (True,2,'02','-0','1.0','nan','',None):
            s=snapshot();s['modules'][0]['exports'][0]['arity_mask']=m
            with self.subTest(mask=m),self.assertRaises(ValueError):api.checked_snapshot(s,policy(),'headless')
    def test_unbounded_arity_is_exact(self):
        s=snapshot();s['modules'][0]['exports'][0]['arity_mask']='-11'
        api.checked_snapshot(s,policy(),'headless')
        self.assertEqual(api.arity_description('-11'),'0, 2, 4+')
    def test_large_arity_mask(self):
        s=snapshot();s['modules'][0]['exports'][0]['arity_mask']=str(1<<80)
        api.checked_snapshot(s,policy(),'headless')
        self.assertEqual(api.arity_description(str(1<<80)),'80')
    def test_phase_only_cannot_claim_runtime_signature(self):
        s=snapshot();s['modules'][0]['exports'][0]['phase']='1'
        with self.assertRaises(ValueError):api.checked_snapshot(s,policy(),'headless')
    def test_macro_descriptor(self):
        s=snapshot();s['modules'][0]['exports']=[dict(name='m',phase='0',export_kind='syntax',kind='syntax')]
        api.checked_snapshot(s,policy(),'headless')
    def test_no_macro_arity_guess(self):
        s=snapshot();s['modules'][0]['exports'][0]['kind']='syntax'
        with self.assertRaises(ValueError):api.checked_snapshot(s,policy(),'headless')
    def test_nonzero_phase_preserved(self):
        s=snapshot();s['modules'][0]['exports']=[dict(name='compile',phase='1',export_kind='value',kind='phase-only')]
        api.checked_snapshot(s,policy(),'headless')
    def test_class_needs_no_instance(self):
        s=snapshot();s['modules'][0]['exports']=[dict(name='c%',phase='0',export_kind='value',kind='class')]
        api.checked_snapshot(s,policy(),'headless')
    def test_class_methods_not_invented(self):
        s=snapshot();s['modules'][0]['exports']=[dict(name='c%',phase='0',export_kind='value',kind='class',method_arities={})]
        with self.assertRaises(ValueError):api.checked_snapshot(s,policy(),'headless')
    def test_generator_repeatable(self):
        snapshots={g:snapshot(g) for g in api.GROUPS}
        before=copy.deepcopy(snapshots)
        self.assertEqual(api.generated_report(policy(),snapshots),api.generated_report(policy(),snapshots))
        self.assertEqual(snapshots,before)
    def test_experimental_reexports_not_upgraded(self):
        report=api.generated_report(policy(),{g:snapshot(g) for g in api.GROUPS})
        self.assertEqual(report.count('| f | experimental |'),2)
    def test_generated_report_explains_limits(self):
        report=api.generated_report(policy(),{g:snapshot(g) for g in api.GROUPS})
        for text in ('not a 1.0 release approval','Macro grammars','class constructor','0.78c'):
            self.assertIn(text,report)


class Receipts(unittest.TestCase):
    def test_valid(self):api.checked_observation(observation(),policy(),'headless','test-token')
    def test_token(self):
        with self.assertRaises(ValueError):api.checked_observation(observation(),policy(),'headless','other')
    def test_group(self):
        with self.assertRaises(ValueError):api.checked_observation(observation('gui'),policy(),'headless','test-token')
    def test_failed_status(self):
        v=observation();v['status']='failed'
        with self.assertRaises(ValueError):api.checked_observation(v,policy(),'headless','test-token')
    def test_gui_in_headless_is_failure(self):
        v=observation();v['gui_instantiated']=True
        with self.assertRaises(ValueError):api.checked_observation(v,policy(),'headless','test-token')
    def test_old_racket_is_failure(self):
        v=observation();v['runtime']['racket']='8.17'
        with self.assertRaises(ValueError):api.checked_observation(v,policy(),'headless','test-token')
    def test_no_rendering_claims(self):
        for field in ('rendering_executed','release_ready','exported_procedures_called'):
            v=observation();v[field]=True
            with self.subTest(field=field),self.assertRaises(ValueError):api.checked_observation(v,policy(),'headless','test-token')
    def test_missing_native_override_rejected(self):
        v=observation();v['native_overrides']='system defaults'
        with self.assertRaises(ValueError):api.checked_observation(v,policy(),'headless','test-token')
    def test_runtime_not_embedded_in_snapshot(self):
        v=api.snapshot_from_observation(observation(),policy(),'headless','test-token')
        self.assertNotIn('runtime',v);self.assertEqual(v,snapshot())
    def test_source_data_cannot_claim_extra_runtime(self):
        v=observation();v['unknown']=True
        with self.assertRaises(ValueError):api.checked_observation(v,policy(),'headless','test-token')
    def test_valid_completion(self):api.checked_pure_output(completion())
    def test_crlf_completion(self):api.checked_pure_output(completion().replace('\n','\r\n'))
    def test_duplicate_completion(self):
        with self.assertRaises(ValueError):api.checked_pure_output(completion()*2)
    def test_failed_summary(self):
        with self.assertRaises(ValueError):api.checked_pure_output(completion().replace('0 failure(s)','1 failure(s)'))
    def test_no_summary(self):
        with self.assertRaises(ValueError):api.checked_pure_output('public-api-pure: 22 cases, 0 failures\n')
    def test_unreported_error(self):
        with self.assertRaises(ValueError):api.checked_pure_output(completion()+'ERROR\n')


class JsonAndPaths(unittest.TestCase):
    def test_duplicate_json(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'a.json';p.write_text('{"a":1,"a":2}')
            with self.assertRaises(ValueError):api.read_json(p)
    def test_nonfinite_json(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'a.json';p.write_text('{"a":NaN}')
            with self.assertRaises(ValueError):api.read_json(p)
    def test_not_object(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'a.json';p.write_text('[]')
            with self.assertRaises(ValueError):api.read_json(p)
    def test_unsafe_paths(self):
        with tempfile.TemporaryDirectory() as t:
            for name in ('../a','/a','a//b','./a','a\\b','a:b','a\nb',''):
                with self.subTest(name=name),self.assertRaises(ValueError):api.path_at(Path(t),name,exists=False)
    def test_missing_file(self):
        with tempfile.TemporaryDirectory() as t,self.assertRaises(ValueError):api.path_at(Path(t),'no.rkt')
    def test_native_and_display_environment(self):
        with tempfile.TemporaryDirectory() as t,patch.dict('os.environ',{'DISPLAY':':99','WAYLAND_DISPLAY':'x','RACKET_SKIA_LIBRARY':'installed'}):
            env=api.isolated_environment(Path(t),'headless')
            self.assertNotIn('DISPLAY',env);self.assertNotIn('WAYLAND_DISPLAY',env)
            self.assertIn('skia-must-not-load',env['RACKET_SKIA_LIBRARY'])
            self.assertEqual(api.isolated_environment(Path(t),'gui')['DISPLAY'],':99')
    def test_existing_override_file_is_not_used(self):
        with tempfile.TemporaryDirectory() as t:
            (Path(t)/'skia-must-not-load').touch()
            with self.assertRaises(ValueError):api.isolated_environment(Path(t),'headless')


class Orchestration(unittest.TestCase):
    def invoke(self, *, source=False, headless=False, fail=None, drift=False, mutation=False):
        spec=importlib.util.spec_from_file_location('api_validator_fixture',ROOT/'tools/validate-public-api.py')
        validator=importlib.util.module_from_spec(spec);spec.loader.exec_module(validator)
        calls=[]
        with tempfile.TemporaryDirectory(prefix='api fixture ') as t:
            root=Path(t)
            for p in [api.POLICY,api.REPORT,api.CONTRACT,*api.SNAPSHOTS.values()]:
                target=root/p;target.parent.mkdir(parents=True,exist_ok=True);target.write_text('fixture\n')
            (root/api.POLICY).write_text(api.json_text(policy()))
            for group,path in api.SNAPSHOTS.items():(root/path).write_text(api.json_text(snapshot(group)))
            before={p:(root/p).read_bytes() for p in [api.POLICY,*api.SNAPSHOTS.values()]}
            scope=types.ModuleType('release_scope')
            scope.audit=lambda _:dict(in_scope_gaps_closed=True,release_ready=False)
            def command(args,**kwargs):
                label=kwargs['log'].stem;calls.append(label)
                if label==fail:raise RuntimeError('synthetic command failure')
                if label=='reflection-fixtures':return completion()
                if label=='aggregate-pure':return '22 success(es) 0 failure(s) 0 error(s) 22 test(s) run\nNative rendering tests NOT RUN (--pure).\n'
                if label=='public-value-example':return 'public-value-example: passed\n'
                return ''
            def reflect(root_,policy_,group,racket,directory,token):
                calls.append(group)
                if group==fail:raise RuntimeError('synthetic probe failure')
                value=observation(group,token)
                if drift:value['modules'][0]['exports'][0]['arity_mask']='4'
                if mutation:(root/api.REPORT).write_text('mutated\n')
                return value
            args=['--directory',str(root/'evidence')]+(['--source-only'] if source else ['--racket','racket'])
            if headless:args.append('--headless-only')
            def check(_):
                if fail=='source':raise ValueError('synthetic source failure')
                return dict(status='source-verified')
            with patch.dict(sys.modules,{'release_scope':scope}),patch.object(api,'source_contracts',side_effect=check),\
                 patch.object(api,'run_logged',side_effect=command),patch.object(api,'reflect_group',side_effect=reflect),\
                 patch.object(validator.shutil,'which',return_value='/synthetic/racket'),\
                 contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
                code=validator.main(args,root=root)
            result=api.read_json(root/'evidence/result.json')
            self.assertEqual(before,{p:(root/p).read_bytes() for p in before})
            return code,result,calls
    def test_all_required(self):
        code,r,c=self.invoke();self.assertEqual(code,0);self.assertEqual(r['status'],'passed')
        self.assertTrue(r['api_signatures_verified']);self.assertFalse(r['rendering_executed']);self.assertFalse(r['release_ready'])
        self.assertIn('compile-runner-and-probe',c);self.assertIn('aggregate-pure',c);self.assertEqual(c[-2:],['headless','gui'])
    def test_source_only_is_not_runtime_pass(self):
        code,r,c=self.invoke(source=True);self.assertEqual(code,0);self.assertEqual(r['status'],'source-only')
        self.assertFalse(r['api_signatures_verified']);self.assertFalse(r['racket_executed']);self.assertEqual(c,[])
    def test_headless_only_is_partial(self):
        code,r,c=self.invoke(headless=True);self.assertEqual(code,0);self.assertEqual(r['status'],'headless-only')
        self.assertFalse(r['api_signatures_verified']);self.assertNotIn('gui',c)
    def test_source_failure_stops_calls(self):
        code,r,c=self.invoke(fail='source');self.assertEqual(code,1);self.assertEqual(c,[])
    def test_compilation_failure(self):
        code,r,c=self.invoke(fail='compile-runner-and-probe');self.assertEqual(code,1);self.assertEqual(len(c),1)
    def test_fixture_failure(self):self.assertEqual(self.invoke(fail='reflection-fixtures')[0],1)
    def test_aggregate_failure(self):self.assertEqual(self.invoke(fail='aggregate-pure')[0],1)
    def test_example_failure(self):self.assertEqual(self.invoke(fail='public-value-example')[0],1)
    def test_headless_probe_failure(self):self.assertEqual(self.invoke(fail='headless')[0],1)
    def test_gui_failure_is_not_skipped(self):
        code,r,c=self.invoke(fail='gui');self.assertEqual(code,1);self.assertFalse(r['api_signatures_verified'])
    def test_signature_drift(self):self.assertEqual(self.invoke(drift=True)[0],1)
    def test_mutating_baseline_is_failure(self):self.assertEqual(self.invoke(mutation=True)[0],1)


class ExampleImports(unittest.TestCase):
    """Synthetic syntax trees exercise the boundary walker, not Racket expansion."""
    def audit(self, nodes, *, tutorial=False):
        class String:
            def __init__(self, value): self.value=value
        def strings(value):
            if isinstance(value, tuple): return String(value[0])
            return [strings(x) for x in value] if isinstance(value,list) else value
        inv=types.ModuleType('api_inventory');inv.String=String
        inv.load_catalog=lambda root:dict(features=dict(public_modules=['main.rkt','gpu.rkt']))
        inv.forms=lambda source:strings(nodes if source=='candidate' else [['require',('../../main.rkt',)]])
        with tempfile.TemporaryDirectory() as t:
            root=Path(t)
            candidate=root/('examples/public/candidate.rkt' if tutorial else 'examples/candidate.rkt')
            candidate.parent.mkdir(parents=True,exist_ok=True);candidate.write_text('candidate')
            public=root/'examples/public/value.rkt';public.parent.mkdir(parents=True,exist_ok=True);public.write_text('public')
            with patch.dict(sys.modules,{'api_inventory':inv}):
                return api.example_import_audit(root)
    def test_public_relative_api(self):self.audit([['require',('../../main.rkt',)]],tutorial=True)
    def test_public_collection_symbol(self):self.audit([['require','skia','skia/gpu']],tutorial=True)
    def test_renamed_public_api(self):self.audit([['require',['prefix-in','sk:',('../../main.rkt',)]]],tutorial=True)
    def test_direct_private_path(self):
        with self.assertRaisesRegex(ValueError,'private'):self.audit([['require',('../private/core.rkt',)]])
    def test_private_collection_symbol(self):
        with self.assertRaisesRegex(ValueError,'implementation'):self.audit([['require','skia/private/core']])
    def test_private_lib_form(self):
        with self.assertRaisesRegex(ValueError,'implementation'):
            self.audit([['require',['lib',('private/core.rkt',),('skia',)]]])
    def test_private_lib_component_form(self):
        with self.assertRaisesRegex(ValueError,'implementation'):
            self.audit([['require',['lib',('core.rkt',),('skia',),('private',)]]])
    def test_internals_submodule(self):
        with self.assertRaisesRegex(ValueError,'submodule'):
            self.audit([['require',['submod',('../main.rkt',),'color-internals']]])
    def test_literal_dynamic_private_import(self):
        with self.assertRaisesRegex(ValueError,'private'):
            self.audit([['dynamic-require',('../private/core.rkt',),False]])
    def test_historical_fixture_is_explicit_development_dependency(self):
        result=self.audit([['require',('../tests/scene-fixture.rkt',)]])
        self.assertEqual(result['examples/candidate.rkt']['development_helpers'],['tests/scene-fixture.rkt'])
    def test_tutorial_fixture_is_not_public_api(self):
        with self.assertRaisesRegex(ValueError,'non-public'):
            self.audit([['require',('../../tests/scene-fixture.rkt',)]],tutorial=True)
    def test_tutorial_cannot_hide_behind_example_helper(self):
        with self.assertRaisesRegex(ValueError,'non-public'):
            self.audit([['require',('../helper.rkt',)]],tutorial=True)
    def test_historical_computed_import_is_reported(self):
        result=self.audit([['dynamic-require','runtime-path',False]])
        self.assertEqual(result['examples/candidate.rkt']['computed_imports'],['dynamic-require'])
    def test_tutorial_computed_import_is_rejected(self):
        with self.assertRaisesRegex(ValueError,'computed'):
            self.audit([['dynamic-require','runtime-path',False]],tutorial=True)
    def test_unknown_public_module_is_rejected(self):
        with self.assertRaisesRegex(ValueError,'unlisted'):
            self.audit([['require','skia/not-a-public-api']],tutorial=True)
    def test_outside_relative_path_is_rejected(self):
        with self.assertRaisesRegex(ValueError,'escapes'):
            self.audit([['require',('../../../outside.rkt',)]],tutorial=True)
    def test_quotes_are_data_not_imports(self):
        result=self.audit([['quote',['require',('../private/not-imported.rkt',)]]])
        self.assertEqual(result['examples/candidate.rkt']['development_helpers'],[])


class RepositoryIntegration(unittest.TestCase):
    def test_complete_source_contracts(self):
        result=api.source_contracts(ROOT)
        self.assertEqual(result['public_modules'],len(api.checked_policy(api.read_json(ROOT/api.POLICY))))
        self.assertFalse(result['api_signatures_verified'])
    def test_existing_release_ledger_includes_api_inputs(self):
        import release_scope
        catalog=__import__('api_inventory').load_catalog(ROOT)
        sources=__import__('api_inventory').validate_sources(ROOT,catalog)
        hashes=release_scope.review_inputs(ROOT,catalog,sources['source_hashes'])
        for name in (api.POLICY,api.CONTRACT,api.REPORT,*api.SNAPSHOTS.values(),
                     'tools/public_api.py','tools/public-api-reflect.rkt','tests/public-api-fixture.rkt'):
            self.assertIn(name,hashes)
        release_scope.audit(ROOT)
    def test_required_native_public_example(self):
        workflow=(ROOT/'.github/workflows/api-inventory.yml').read_text(encoding='utf-8')
        self.assertIn('racket examples/public/raster-lifetime.rkt',workflow)


if __name__=='__main__':unittest.main(verbosity=2)

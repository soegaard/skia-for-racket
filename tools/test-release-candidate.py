#!/usr/bin/env python3
"""Release gate regressions. Synthetic evidence is not native execution.

The default invocation includes mandatory complete-repository integration.
Delivery environments may run explicitly named synthetic classes only.
"""
from __future__ import annotations
import copy
import datetime as dt
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import tempfile
import types
import unittest
from unittest.mock import patch
import urllib.error
import zipfile

import release_graph as graph
import release_candidate as rc
ROOT = Path(__file__).resolve().parents[1]
PIN = 'a' * 40
SHA = 'b' * 40
REPO = 'owner/repository'
START = '2026-10-09T10:00:00Z'
END = '2026-10-09T10:02:00Z'


def write(root, name, value):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding='utf-8')


def fixture_tree(root):
    # A complete SYNTHETIC workflow graph, not a reconstruction of the repo.
    source = ROOT / graph.WORKFLOW
    write(root, graph.WORKFLOW, source.read_text())
    write(root, 'tools/ci-matrix.json', json.dumps({'cpu': [dict(id='linux', runner='ubuntu-24.04', racket='8.18'),
                                                          dict(id='mac', runner='macos-15', racket='9.3')],
                                                 'egl': [dict(surface='surfaceless', runner='ubuntu-24.04')]}))
    for name in ('validation_regressions.py', 'ci_matrix.py'):
        write(root, 'tools/' + name, '# synthetic source\n')
    for key in ('ci', 'api-inventory'):
        body = (f'name: {key}\non:\n  workflow_call:\njobs:\n  test:\n'
                f'    name: {key} / ${{{{ matrix.racket }}}}\n    runs-on: ubuntu-24.04\n'
                "    strategy:\n      matrix:\n        racket: ['8.18', '9.3']\n"
                '    steps:\n      - name: Check\n        run: echo synthetic\n'
                f'      - name: Evidence\n        if: always()\n        uses: actions/upload-artifact@{PIN}\n'
                f'        with:\n          name: {key}-${{{{ matrix.racket }}}}-${{{{ github.run_attempt }}}}\n')
        write(root, '.github/workflows/' + key + '.yml', body)
    write(root, '.github/workflows/acceptance.yml',
          'name: Acceptance\non:\n  workflow_call:\njobs:\n  feature:\n    name: Feature\n'
          '    uses: ./.github/workflows/feature.yml\n    with:\n      regressions: full\n')
    write(root, '.github/workflows/feature.yml',
          'name: Feature\non:\n  workflow_call:\njobs:\n  native:\n    name: Native\n    runs-on: windows-2022\n'
          "    steps:\n      - name: Linux setup\n        if: runner.os == 'Linux'\n        run: echo linux\n"
          "      - name: Full regressions\n        if: inputs.regressions != 'none'\n        run: echo full\n"
          f'      - uses: actions/upload-artifact@{PIN}\n        with:\n          name: native-${{{{ github.run_attempt }}}}\n')
    return graph.build_policy(root)


def policy():
    return {'needs': ['ci', 'acceptance', 'inventory'],
            'jobs': [dict(name='CI / Native', workflow='.github/workflows/ci.yml', runner='ubuntu-24.04',
                         artifacts=['native-{attempt}'],
                         steps=[dict(number=2, name='Test', expected='success'),
                                dict(number=3, name='Windows only', expected='skipped')])],
            'artifact_names': ['native-{attempt}']}


def run():
    return dict(id=100, run_attempt=2, head_sha=SHA, name='Release candidate', path=graph.WORKFLOW,
                repository=dict(full_name=REPO), head_repository=dict(full_name=REPO),
                event='workflow_dispatch', status='in_progress', conclusion=None, run_started_at=START)


def jobs():
    base = dict(id=10, name='CI / Native', run_id=100, head_sha=SHA, run_attempt=2,
                status='completed', conclusion='success', started_at=START, completed_at=END,
                steps=[dict(number=1, name='Set up job', status='completed', conclusion='success'),
                       dict(number=2, name='Test', status='completed', conclusion='success'),
                       dict(number=3, name='Windows only', status='completed', conclusion='skipped')])
    own = dict(id=11, name=graph.GATE, run_id=100, head_sha=SHA, run_attempt=2,
               status='in_progress', conclusion=None, started_at=END)
    return [base, own]


def artifacts():
    return [dict(id=40, name='native-2', size_in_bytes=100, expired=False,
                 digest='sha256:' + 'a' * 64, created_at=END,
                 workflow_run=dict(id=100, head_sha=SHA))]


def identity():
    return dict(repository=REPO, sha=SHA, run_id=100, attempt=2)


def needs():
    return {key: {'result': 'success', 'outputs': {}} for key in policy()['needs']}


class Expressions(unittest.TestCase):
    def test_on_is_not_boolean(self):
        self.assertIn('on', graph.workflow_data('on:\n  push:\njobs: {}'))
    def test_duplicate_keys(self):
        with self.assertRaises(ValueError): graph.workflow_data('jobs: {}\njobs: {}')
    def test_alias_rejected(self):
        with self.assertRaises(ValueError): graph.workflow_data('a: &a {}\njobs: *a')
    def test_tag_rejected(self):
        with self.assertRaises(ValueError): graph.workflow_data('jobs: !!map {}')
    def test_interpolation(self):
        self.assertEqual(graph.render('Job ${{ matrix.racket }}', {'matrix.racket': '8.18'}), 'Job 8.18')
    def test_unknown_expression(self):
        with self.assertRaises(ValueError): graph.render('${{ env.SECRET }}', {})
    def test_computed_expression(self):
        with self.assertRaises(ValueError): graph.render('${{ format("x") }}', {})
    def test_condition(self):
        self.assertTrue(graph.condition("inputs.regressions != 'none'", {'inputs.regressions': 'full'}))
    def test_negative_condition(self):
        self.assertFalse(graph.condition("runner.os == 'Windows'", {'runner.os': 'Linux'}))
    def test_always(self): self.assertTrue(graph.condition('${{ always() }}', {}))
    def test_failure(self): self.assertFalse(graph.condition('failure()', {}))
    def test_unknown_condition_rejected(self):
        with self.assertRaises(ValueError): graph.condition('someFunction()', {})
    def test_runner_must_be_hosted(self):
        with self.assertRaises(ValueError): graph.runner_os('self-hosted')
    def test_runner_must_be_pinned(self):
        with self.assertRaises(ValueError): graph.runner_os('ubuntu-latest')
    def test_write_permissions(self):
        with self.assertRaises(ValueError): graph.permission_check({'contents': 'write'})
    def test_duplicate_json(self):
        with self.assertRaises(ValueError): graph.json_data('{"a":1,"a":2}')
    def test_nonfinite_json(self):
        with self.assertRaises(ValueError): graph.json_data('{"a":NaN}')


class Matrices(unittest.TestCase):
    def test_no_matrix(self): self.assertEqual(graph.matrix_rows(None, {}), [{}])
    def test_cartesian(self): self.assertEqual(len(graph.matrix_rows({'a': ['1','2'], 'b': ['x','y']}, {})), 4)
    def test_include_only(self): self.assertEqual(graph.matrix_rows({'include': [{'a':'1'}, {'a':'2'}]}, {}), [{'a':'1'}, {'a':'2'}])
    def test_include_merges_without_axis_overwrite(self):
        rows=graph.matrix_rows({'a':['1','2'], 'include':[{'b':'x'}, {'a':'3','b':'y'}]}, {})
        self.assertEqual(rows, [{'a':'1','b':'x'},{'a':'2','b':'x'},{'a':'3','b':'y'}])
    def test_exclude(self): self.assertEqual(graph.matrix_rows({'a':['1','2'],'exclude':[{'a':'1'}]}, {}), [{'a':'2'}])
    def test_empty_axis(self):
        with self.assertRaises(ValueError): graph.matrix_rows({'a':[]}, {})
    def test_empty_result(self):
        with self.assertRaises(ValueError): graph.matrix_rows({'a':['1'],'exclude':[{'a':'1'}]}, {})
    def test_duplicate_row(self):
        with self.assertRaises(ValueError): graph.matrix_rows({'a':['1','1']}, {})
    def test_dynamic_ci(self):
        self.assertEqual(graph.matrix_rows('${{ fromJSON(needs.source.outputs.cpu) }}', {'cpu':[{'a':1}]}), [{'a':1}])
    def test_unknown_dynamic_matrix(self):
        with self.assertRaises(ValueError): graph.matrix_rows('${{ fromJSON(env.DATA) }}', {})
    def test_limit(self):
        with self.assertRaises(ValueError): graph.matrix_rows({'a':list(range(100)), 'b':list(range(100))}, {})


class Graph(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.p=fixture_tree(self.root)
    def edit(self, name, before, after):
        p=self.root/name;p.write_text(p.read_text().replace(before,after))
    def test_every_matrix_job(self):self.assertEqual(len(self.p['jobs']),5)
    def test_artifacts_unique(self):self.assertEqual(len(self.p['artifact_names']),5)
    def test_nested_names(self):self.assertIn('Acceptance / Feature / Native',[j['name'] for j in self.p['jobs']])
    def test_repeatable(self):self.assertEqual(self.p,graph.build_policy(self.root))
    def test_conditional_steps_recorded(self):
        j=next(x for x in self.p['jobs'] if x['name'].startswith('Acceptance'))
        self.assertEqual([x['expected'] for x in j['steps']],['skipped','success','success'])
    def test_changed_command_changes_fingerprint(self):
        self.edit('.github/workflows/ci.yml','echo synthetic','echo changed')
        self.assertNotEqual(self.p,graph.build_policy(self.root))
    def test_new_omitted_workflow_fails(self):
        write(self.root,'.github/workflows/omitted.yml','jobs: {}')
        with self.assertRaisesRegex(ValueError,'omitted'):graph.build_policy(self.root)
    def test_callee_cycle(self):
        self.edit('.github/workflows/acceptance.yml','workflows/feature.yml','workflows/acceptance.yml')
        with self.assertRaisesRegex(ValueError,'cyclic'):graph.build_policy(self.root)
    def test_conditional_job_forbidden(self):
        self.edit('.github/workflows/ci.yml','  test:\n','  test:\n    if: false\n')
        with self.assertRaisesRegex(ValueError,'conditional'):graph.build_policy(self.root)
    def test_allowed_failure_forbidden(self):
        self.edit('.github/workflows/ci.yml','  test:\n','  test:\n    continue-on-error: true\n')
        with self.assertRaises(ValueError):graph.build_policy(self.root)
    def test_allowed_step_failure_forbidden(self):
        self.edit('.github/workflows/ci.yml','      - name: Check\n','      - name: Check\n        continue-on-error: true\n')
        with self.assertRaises(ValueError):graph.build_policy(self.root)
    def test_unpinned_action_forbidden(self):
        self.edit('.github/workflows/ci.yml',PIN,'v4')
        with self.assertRaisesRegex(ValueError,'pinned'):graph.build_policy(self.root)
    def test_foreign_reusable_workflow(self):
        self.edit('.github/workflows/acceptance.yml','./.github/workflows/feature.yml','other/repo/.github/workflows/f.yml@main')
        with self.assertRaises(ValueError):graph.build_policy(self.root)
    def test_partial_regressions_forbidden(self):
        self.edit('.github/workflows/acceptance.yml','regressions: full','regressions: none')
        with self.assertRaises(ValueError):graph.build_policy(self.root)
    def test_secret_inheritance_forbidden(self):
        self.edit('.github/workflows/acceptance.yml','    name: Feature\n','    name: Feature\n    secrets: inherit\n')
        with self.assertRaises(ValueError):graph.build_policy(self.root)
    def test_root_cannot_drop_inventory(self):
        self.edit(graph.WORKFLOW,'needs: [ci, acceptance, inventory]','needs: [ci, acceptance]')
        with self.assertRaisesRegex(ValueError,'omits'):graph.build_policy(self.root)
    def test_no_automatic_expensive_workflow(self):
        self.edit(graph.WORKFLOW,'  workflow_dispatch:\n','  workflow_dispatch:\n  push:\n')
        with self.assertRaisesRegex(ValueError,'manual'):graph.build_policy(self.root)
    def test_duplicate_artifact_fails(self):
        self.edit('.github/workflows/ci.yml','ci-${{ matrix.racket }}','api-inventory-${{ matrix.racket }}')
        with self.assertRaisesRegex(ValueError,'collision'):graph.build_policy(self.root)
    def test_report_is_not_receipt(self):self.assertIn('Not a run receipt',graph.generated_report(self.p))
    def test_concurrency_collision(self):
        for name in ('ci','acceptance'):
            p=self.root/f'.github/workflows/{name}.yml'
            p.write_text('concurrency:\n  group: same-${{ github.workflow }}\n'+p.read_text())
        with self.assertRaisesRegex(ValueError,'collision'):graph.build_policy(self.root)
    def test_standalone_concurrency_collision(self):
        p=self.root/'.github/workflows/acceptance.yml'
        p.write_text('concurrency:\n  group: acceptance-${{ github.ref }}\n'+p.read_text())
        with self.assertRaisesRegex(ValueError,'collision'):graph.build_policy(self.root)


class RunEvidence(unittest.TestCase):
    def check(self,r):rc.verify_run(r,**identity())
    def test_valid(self):self.check(run())
    def test_needs(self):rc.verify_needs(needs(),policy())
    def test_needs_skipped(self):
        n=needs();n['ci']['result']='skipped'
        with self.assertRaises(ValueError):rc.verify_needs(n,policy())
    def test_needs_missing(self):
        n=needs();n.pop('inventory')
        with self.assertRaises(ValueError):rc.verify_needs(n,policy())
    def test_needs_added(self):
        n=needs();n['other']={'result':'success'}
        with self.assertRaises(ValueError):rc.verify_needs(n,policy())


def bad_run(field,value):
    def test(self):
        r=run();r[field]=value
        with self.assertRaises(ValueError):self.check(r)
    return test
for name,field,value in [('sha','head_sha','0'*40),('run','id',101),('boolean_run','id',True),
                        ('attempt','run_attempt',1),('boolean_attempt','run_attempt',True),
                        ('name','name','CI'),('path','path','.github/workflows/ci.yml'),
                        ('event','event','pull_request'),('completed','status','completed'),
                        ('failed','conclusion','failure'),('time','run_started_at',None),
                        ('fork','head_repository',{'full_name':'fork/repo'}),('repository','repository',{})]:
    setattr(RunEvidence,'test_reject_'+name,bad_run(field,value))


class JobEvidence(unittest.TestCase):
    def check(self,value):return rc.verify_jobs(value,policy(),run=run(),sha=SHA,run_id=100,attempt=2)
    def test_complete(self):self.assertEqual(self.check(jobs()),1)
    def test_optional_run_attempt_field(self):
        j=jobs();j[0].pop('run_attempt');self.check(j)
    def test_missing_job(self):
        with self.assertRaisesRegex(ValueError,'coverage'):self.check(jobs()[1:])
    def test_extra_job(self):
        j=jobs();j.append(dict(j[0],id=15,name='unexpected'))
        with self.assertRaises(ValueError):self.check(j)
    def test_duplicate_id(self):
        j=jobs();j[1]['id']=j[0]['id']
        with self.assertRaises(ValueError):self.check(j)
    def test_duplicate_name(self):
        j=jobs();j[1]['name']=j[0]['name']
        with self.assertRaises(ValueError):self.check(j)
    def test_missing_step(self):
        j=jobs();j[0]['steps'].pop(1)
        with self.assertRaises(ValueError):self.check(j)
    def test_step_wrong_position(self):
        j=jobs();j[0]['steps'][1]['number']=20
        with self.assertRaises(ValueError):self.check(j)
    def test_step_renamed(self):
        j=jobs();j[0]['steps'][1]['name']='Wrong command'
        with self.assertRaises(ValueError):self.check(j)
    def test_skipped_run_step(self):
        j=jobs();j[0]['steps'][1]['conclusion']='skipped'
        with self.assertRaises(ValueError):self.check(j)
    def test_error_swallowed_by_job(self):
        j=jobs();j[0]['steps'][1]['conclusion']='failure'
        with self.assertRaises(ValueError):self.check(j)
    def test_failed_post_step(self):
        j=jobs();j[0]['steps'].append(dict(number=10,status='completed',conclusion='failure'))
        with self.assertRaises(ValueError):self.check(j)
    def test_duplicate_step(self):
        j=jobs();j[0]['steps'].append(j[0]['steps'][0])
        with self.assertRaises(ValueError):self.check(j)
    def test_self_must_be_in_progress(self):
        j=jobs();j[1]['status']='completed';j[1]['conclusion']='success'
        with self.assertRaises(ValueError):self.check(j)


def bad_job(field,value):
    def test(self):
        j=jobs();j[0][field]=value
        with self.assertRaises(ValueError):self.check(j)
    return test
for field,value in [('head_sha','0'*40),('run_id',101),('run_attempt',1),('status','queued'),
                    ('started_at','2026-10-08T10:00:00Z'),('completed_at',None),('steps',[])]:
    setattr(JobEvidence,'test_bad_'+field,bad_job(field,value))
for value in ('failure','skipped','cancelled','neutral','timed_out',None):
    setattr(JobEvidence,'test_bad_conclusion_'+str(value),bad_job('conclusion',value))


class ArtifactEvidence(unittest.TestCase):
    def check(self,value):return rc.select_artifacts(value,policy(),run=run(),sha=SHA,run_id=100,attempt=2)
    def test_complete(self):self.assertEqual(list(self.check(artifacts())),['native-2'])
    def test_old_attempt_ignored(self):
        a=artifacts();a.append(dict(a[0],id=50,name='native-1'));self.check(a)
    def test_old_attempt_not_substitute(self):
        a=artifacts();a[0]['name']='native-1'
        with self.assertRaises(ValueError):self.check(a)
    def test_duplicate(self):
        a=artifacts();a.append(dict(a[0],id=41))
        with self.assertRaises(ValueError):self.check(a)
    def test_no_artifacts(self):
        with self.assertRaises(ValueError):self.check([])


def bad_artifact(field,value):
    def test(self):
        a=artifacts();a[0][field]=value
        with self.assertRaises(ValueError):self.check(a)
    return test
for field,value in [('expired',True),('size_in_bytes',0),('digest',None),('created_at',START.replace('09T','08T')),
                    ('workflow_run',{'id':101,'head_sha':SHA}),('id',False)]:
    setattr(ArtifactEvidence,'test_bad_'+field,bad_artifact(field,value))


class Archives(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
    def archive(self, names=('result.json',)):
        p=self.root/'evidence.zip'
        with zipfile.ZipFile(p,'w') as z:
            for name in names:z.writestr(name,'{"status":"synthetic"}')
        return p
    def check(self,p):return rc.inspect_zip(p,rc.digest(p))
    def test_valid(self):self.assertEqual(self.check(self.archive())['members'],1)
    def test_wrong_hash(self):
        with self.assertRaises(ValueError):rc.inspect_zip(self.archive(),'0'*64)
    def test_empty(self):
        with self.assertRaises(ValueError):self.check(self.archive(()))
    def test_path_traversal(self):
        with self.assertRaises(ValueError):self.check(self.archive(('../result.json',)))
    def test_absolute(self):
        with self.assertRaises(ValueError):self.check(self.archive(('/result.json',)))
    def test_backslash(self):
        with self.assertRaises(ValueError):self.check(self.archive(('a\\result.json',)))
    def test_duplicate(self):
        import warnings
        with warnings.catch_warnings():
            warnings.simplefilter('ignore');p=self.archive(('same','same'))
        with self.assertRaises(ValueError):self.check(p)
    def test_symlink(self):
        p=self.root/'link.zip'
        with zipfile.ZipFile(p,'w') as z:
            i=zipfile.ZipInfo('link');i.create_system=3;i.external_attr=(stat.S_IFLNK|0o777)<<16;z.writestr(i,'target')
        with self.assertRaises(ValueError):self.check(p)
    def test_expansion_limit(self):
        p=self.archive()
        with patch.object(rc,'MAX_UNCOMPRESSED',5),self.assertRaises(ValueError):self.check(p)


class Retrieval(unittest.TestCase):
    def reader(self):return rc.GitHubReader(REPO,'not-a-real-token')
    def test_two_pages(self):
        r=self.reader()
        with patch.object(r,'get',side_effect=[{'total_count':101,'jobs':list(range(100))},{'total_count':101,'jobs':[100]}]) as get:
            self.assertEqual(r.paged('/actions/runs/100/attempts/2/jobs','jobs'),list(range(101)))
            self.assertIn('page=2',get.call_args.args[0])
    def test_truncated_page(self):
        r=self.reader()
        with patch.object(r,'get',return_value={'total_count':101,'jobs':[]}),self.assertRaises(ValueError):r.paged('/actions/x','jobs')
    def test_total_changes(self):
        r=self.reader()
        with patch.object(r,'get',side_effect=[{'total_count':101,'jobs':[{}]*100},{'total_count':102,'jobs':[{}]*2}]),self.assertRaises(ValueError):r.paged('/actions/x','jobs')
    def test_boolean_total(self):
        r=self.reader()
        with patch.object(r,'get',return_value={'total_count':True,'jobs':[{}]}),self.assertRaises(ValueError):r.paged('/actions/x','jobs')
    def test_foreign_auth_host(self):
        with self.assertRaises(ValueError):self.reader().request('https://example.com/file',authorized=True)
    def test_plain_http(self):
        with self.assertRaises(ValueError):self.reader().request('http://api.github.com/repos/'+REPO+'/x',authorized=True)
    def test_artifact_redirect_host(self):
        with self.assertRaises(ValueError):self.reader().request('https://evil.example/download',authorized=False)
    def test_token_only_to_api(self):
        r=self.reader();seen=[]
        r.opener=types.SimpleNamespace(open=lambda req,timeout:seen.append(dict(req.header_items())))
        r.request(r.base+'/actions/runs/100',authorized=True)
        r.request('https://test.blob.core.windows.net/zip?signed=example',authorized=False)
        self.assertIn('Authorization',seen[0]);self.assertNotIn('Authorization',seen[1])
    def test_redirect_never_reuses_token(self):
        r=self.reader()
        first=types.SimpleNamespace(code=302,headers={'Location':'https://test.blob.core.windows.net/x'})
        from contextlib import nullcontext
        with tempfile.TemporaryDirectory() as t:
            response=io.BytesIO(b'zip bytes');response.code=200
            with patch.object(r,'request',side_effect=[nullcontext(first),response]) as call:
                r.download(40,Path(t)/'x.zip')
            self.assertEqual([c.kwargs['authorized'] for c in call.call_args_list],[True,False])


class Orchestration(unittest.TestCase):
    def env(self):
        return dict(GITHUB_ACTIONS='true',GITHUB_EVENT_NAME='workflow_dispatch',GITHUB_WORKFLOW='Release candidate',
                    GITHUB_REPOSITORY=REPO,GITHUB_SHA=SHA,GITHUB_RUN_ID='100',GITHUB_RUN_ATTEMPT='2',
                    GITHUB_WORKFLOW_REF=REPO+'/'+graph.WORKFLOW+'@refs/heads/main',GH_TOKEN='synthetic',
                    RELEASE_NEEDS_JSON=json.dumps(needs()))
    def test_identity(self):self.assertEqual(rc.github_identity(self.env(),{'commit':SHA}),identity())
    def test_foreign_checkout(self):
        with self.assertRaises(ValueError):rc.github_identity(self.env(),{'commit':'0'*40})
    def test_no_context(self):
        with self.assertRaises(ValueError):rc.github_identity({}, {'commit':SHA})
    def test_source_only_receipt(self):
        spec=importlib.util.spec_from_file_location('release_cli_test',ROOT/'tools/validate-release-candidate.py')
        cli=importlib.util.module_from_spec(spec);spec.loader.exec_module(cli)
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);write(root,graph.POLICY,'{}')
            with patch.object(rc,'source_contracts',return_value=policy()),patch.object(rc,'collect') as collect:
                self.assertEqual(cli.main(['--source-only','--directory',str(root/'out')],root=root),0)
            r=rc.read_json(root/'out/result.json')
            self.assertEqual(r['status'],'source-only');self.assertFalse(r['release_candidate_validated'])
            self.assertFalse(r['release_ready']);collect.assert_not_called()
    def test_failure_writes_no_success(self):
        spec=importlib.util.spec_from_file_location('release_cli_test2',ROOT/'tools/validate-release-candidate.py')
        cli=importlib.util.module_from_spec(spec);spec.loader.exec_module(cli)
        with tempfile.TemporaryDirectory() as t:
            root=Path(t)
            with patch.object(rc,'source_contracts',side_effect=ValueError('synthetic drift')):
                self.assertEqual(cli.main(['--source-only','--directory',str(root/'out')],root=root),1)
            self.assertFalse(rc.read_json(root/'out/result.json')['release_candidate_validated'])
    def test_existing_evidence_is_refused(self):
        spec=importlib.util.spec_from_file_location('release_cli_test3',ROOT/'tools/validate-release-candidate.py')
        cli=importlib.util.module_from_spec(spec);spec.loader.exec_module(cli)
        with tempfile.TemporaryDirectory() as t:
            self.assertEqual(cli.main(['--source-only','--directory',t],root=Path(t)),1)



class Collection(unittest.TestCase):
    def exercise(self, *, fault=None):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);directory=root/'evidence';directory.mkdir()
            archive=root/'fixture.zip'
            with zipfile.ZipFile(archive,'w') as z:z.writestr('result.json','{"synthetic":true}')
            raw=archive.read_bytes();metadata=artifacts();metadata[0].update(size_in_bytes=len(raw),digest='sha256:'+hashlib.sha256(raw).hexdigest())
            calls=[]
            class Reader:
                def __init__(self,*_):self.reads=0
                def get(self,path):
                    calls.append(path);self.reads+=1
                    value=run()
                    if fault=='cancelled' and self.reads>1:value['status']='completed';value['conclusion']='cancelled'
                    return value
                def paged(self,path,key):
                    calls.append(path)
                    if key=='jobs':
                        value=jobs()
                        if fault=='missing-job':value.pop(0)
                        return value
                    return [] if fault=='missing-artifact' else metadata
                def download(self,ident,path):
                    calls.append('download')
                    if fault=='download':raise RuntimeError('synthetic connection failure')
                    path.write_bytes(b'corrupted' if fault=='digest' else raw)
            env=Orchestration().env()
            if fault=='dependency':env['RELEASE_NEEDS_JSON']=json.dumps(dict(needs(),ci={'result':'failure'}))
            try:
                result=rc.collect(root,directory,policy(),{'commit':SHA},env=env,reader_factory=Reader)
            except (ValueError,RuntimeError):
                result=None
            return result,calls,sorted(p.name for p in directory.iterdir())
    def test_complete_synthetic_run(self):
        result,calls,files=self.exercise()
        self.assertEqual(result['jobs_verified'],1);self.assertEqual(result['artifacts_verified'],1)
        self.assertIn('/actions/runs/100/attempts/2/jobs',calls)
        self.assertIn('artifact-index.json',files)
    def test_dependency_failure_stops_before_network(self):
        result,calls,_=self.exercise(fault='dependency');self.assertIsNone(result);self.assertEqual(calls,[])
    def test_missing_job_stops_before_download(self):
        result,calls,_=self.exercise(fault='missing-job');self.assertIsNone(result);self.assertNotIn('download',calls)
    def test_missing_artifact_not_summary_fallback(self):self.assertIsNone(self.exercise(fault='missing-artifact')[0])
    def test_download_failure_not_summary_fallback(self):self.assertIsNone(self.exercise(fault='download')[0])
    def test_wrong_archive_hash_blocks_pass(self):self.assertIsNone(self.exercise(fault='digest')[0])
    def test_cancellation_during_collection_blocks_pass(self):self.assertIsNone(self.exercise(fault='cancelled')[0])
    def test_partial_metadata_retained(self):
        result,_,files=self.exercise(fault='digest')
        self.assertIsNone(result);self.assertIn('jobs.json',files);self.assertIn('artifact-metadata.json',files)


class SourcePackaging(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);write(self.root,'main.rkt','#lang racket/base\n')
        write(self.root,'SOURCE-SHA256SUMS.txt','synthetic manifest bytes\n')
        self.rows={'main.rkt':rc.digest(self.root/'main.rkt')}
        self.manifest=types.SimpleNamespace(NAME='SOURCE-SHA256SUMS.txt',read_manifest=lambda _:self.rows)
    def build(self,name):
        with patch.object(rc,'manifest_module',return_value=self.manifest):return rc.source_archive(self.root,self.root/name)
    def test_reproducible_zip(self):
        self.assertEqual(self.build('a.zip')['sha256'],self.build('b.zip')['sha256'])
    def test_roundtrip_source_bytes(self):
        self.build('a.zip')
        with zipfile.ZipFile(self.root/'a.zip') as z:
            self.assertEqual(z.read('main.rkt'),(self.root/'main.rkt').read_bytes())
            self.assertEqual(z.namelist(),['SOURCE-SHA256SUMS.txt','main.rkt'])
            self.assertTrue(all(i.date_time==(1980,1,1,0,0,0) for i in z.infolist()))
    def test_source_mutation_rejected(self):
        write(self.root,'main.rkt','mutated')
        with self.assertRaises(ValueError):self.build('a.zip')
    def test_existing_zip_refused(self):
        self.build('a.zip')
        with self.assertRaises(ValueError):self.build('a.zip')
    def test_native_file_excluded(self):
        write(self.root,'native.dll','synthetic');self.rows['native.dll']=rc.digest(self.root/'native.dll')
        with self.assertRaises(ValueError):self.build('a.zip')
    def test_generated_member_excluded(self):
        write(self.root,'output/data.txt','synthetic');self.rows['output/data.txt']=rc.digest(self.root/'output/data.txt')
        with self.assertRaises(ValueError):self.build('a.zip')


class RepositoryIntegration(unittest.TestCase):
    def test_complete_current_contracts(self):
        p=rc.source_contracts(ROOT)
        self.assertGreater(len(p['jobs']),0)
        self.assertEqual(set(p['needs']),{'ci','acceptance','inventory'})
    def test_minimum_and_platform_install_lanes(self):
        p=graph.build_policy(ROOT)
        rows=[j for j in p['jobs'] if j['workflow']=='.github/workflows/ci.yml' and j['job_id']=='cpu']
        self.assertEqual({j['matrix']['id'] for j in rows},
                         {'minimum-racket','linux-x64','macos-arm64','macos-x64','windows-x64'})
        self.assertEqual(next(j for j in rows if j['matrix']['id']=='minimum-racket')['matrix']['racket'],'8.18')
    def test_source_ci_and_api_ci_require_the_new_tests(self):
        self.assertIn("'test-release-candidate.py'",(ROOT/'tools/ci.py').read_text())
        self.assertIn('python tools/test-release-candidate.py',(ROOT/'.github/workflows/api-inventory.yml').read_text())
    def test_required_feature_families_not_omitted(self):
        p=graph.build_policy(ROOT)
        paths={j['workflow'] for j in p['jobs']}
        for name in ('dc-output','gpu-dc','render-canvas','float-pixels','gpu-context-controls','streams'):
            self.assertIn('.github/workflows/'+name+'.yml',paths)
    def test_snapshot_bytes_and_runtime_claims_remain_separate(self):
        public=rc.read_json(ROOT/'api/public-api-policy.json')
        self.assertEqual(public['stage'],'0.78c')
        self.assertEqual(public['package_version'],'0.78')
        self.assertFalse(rc.read_json(ROOT/graph.POLICY)['release_ready'])


if __name__=='__main__':unittest.main(verbosity=2)

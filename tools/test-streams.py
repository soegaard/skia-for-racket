#!/usr/bin/env python3
"""0.75a source, byte-inspector and mocked orchestration tests; not native evidence."""
from __future__ import annotations
import ast
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import stream_validation as v

ROOT = Path(__file__).resolve().parents[1]
TOKEN = 'synthetic-only'


def compiled_test_present(command, test_name):
    # The validator builds native Path objects. Their string representation
    # uses backslashes on Windows and forward slashes on Unix.
    suffix = '/tests/' + test_name
    return any(str(arg).replace('\\', '/').endswith(suffix) for arg in command)


def receipt():
    return dict(schema=1, stage='0.75a', run_token=TOKEN, status='passed', native_version='119.0',
                length=4096, source_position=7, file_roundtrip=True, family='Skia Racket Fixture',
                streams_closed=True, live_port_callbacks=False, gpu_executed=False)


def fixtures(root, token=TOKEN):
    root.mkdir(parents=True, exist_ok=True)
    report = receipt(); report['run_token'] = token
    (root/'streams.json').write_text(json.dumps(report), encoding='utf-8')
    data = bytes(range(256))*16
    for name, content in (('stream.bin', data), ('tail.bin', data[7:]), ('decoded.rgba', v.PIXELS)):
        (root/name).write_bytes(content)


class CompilePathPortability(unittest.TestCase):
    def test_unix_and_windows_compile_paths(self):
        for value in ('/tmp/skia/tests/stream-native-test.rkt',
                      'D:\\a\\skia\\tests\\stream-native-test.rkt'):
            command = ['racket', '-l', 'raco', '--', 'make', value]
            self.assertTrue(compiled_test_present(command, 'stream-native-test.rkt'))
            self.assertFalse(compiled_test_present(command, 'unrelated-native-test.rkt'))


class Completion(unittest.TestCase):
    def valid(self):
        return '34 success(es) 0 failure(s) 0 error(s) 34 test(s) run\nstream-pure: 34 cases, 0 failures\n'
    def test_complete(self): v.suite_output(self.valid(), 'stream-pure', 34)
    def test_crlf(self): v.suite_output(self.valid().replace('\n', '\r\n'), 'stream-pure', 34)
    def test_missing(self):
        with self.assertRaises(ValueError): v.suite_output('', 'stream-pure', 34)
    def test_duplicate(self):
        with self.assertRaises(ValueError): v.suite_output(self.valid()*2, 'stream-pure', 34)
    def test_wrong_suite(self):
        with self.assertRaises(ValueError): v.suite_output(self.valid(), 'stream-native', 34)
    def test_wrong_count(self):
        with self.assertRaises(ValueError): v.suite_output(self.valid(), 'stream-pure', 33)
    def test_printed_error(self):
        with self.assertRaises(ValueError): v.suite_output('ERROR\n'+self.valid(), 'stream-pure', 34)
    def test_failure(self):
        with self.assertRaises(ValueError): v.suite_output(self.valid().replace('0 failure(s)', '1 failure(s)'), 'stream-pure', 34)
    def test_marker_alone(self):
        with self.assertRaises(ValueError): v.suite_output(self.valid().split('\n')[1], 'stream-pure', 34)


class Evidence(unittest.TestCase):
    def inspect(self, change=None, file=None, content=None):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); fixtures(root)
            if change:
                data = receipt(); data.update(change)
                (root/'streams.json').write_text(json.dumps(data), encoding='utf-8')
            if file:
                if content is None: (root/file).unlink()
                else: (root/file).write_bytes(content)
            return v.inspect(root, TOKEN)
    def test_synthetic_valid(self): self.assertEqual(self.inspect()['status'], 'passed')
    def test_not_live_streaming_claim(self): self.assertFalse(self.inspect()['live_port_streaming_verified'])
    def test_bad_metadata(self):
        for change in ({'schema': True}, {'stage': '0.75b'}, {'run_token': 'stale'}, {'status': 'failed'},
                       {'native_version': '153.0'}, {'length': True}, {'length': 0}, {'source_position': 0},
                       {'source_position': False}, {'file_roundtrip': False}, {'streams_closed': False},
                       {'live_port_callbacks': True}, {'gpu_executed': True}, {'family': 'wrong'}):
            with self.subTest(change=change), self.assertRaises(ValueError): self.inspect(change)
    def test_missing_byte_file(self):
        with self.assertRaises(ValueError): self.inspect(file='stream.bin')
    def test_truncated_bytes(self):
        with self.assertRaises(ValueError): self.inspect(file='stream.bin', content=b'abc')
    def test_large_bytes(self):
        with self.assertRaises(ValueError): self.inspect(file='stream.bin', content=bytes(4097))
    def test_wrong_tail(self):
        with self.assertRaises(ValueError): self.inspect(file='tail.bin', content=bytes(range(256))*15)
    def test_wrong_pixels(self):
        with self.assertRaises(ValueError): self.inspect(file='decoded.rgba', content=bytes(16))
    def test_duplicate_json(self):
        with self.assertRaises(ValueError): self.inspect(file='streams.json', content=b'{"schema":1,"schema":1}')
    def test_nonfinite_json(self):
        with self.assertRaises(ValueError): self.inspect(file='streams.json', content=b'{"value":NaN}')
    def test_linked_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);fixtures(root)
            (root/'copy.bin').write_bytes((root/'stream.bin').read_bytes())
            (root/'stream.bin').unlink();(root/'stream.bin').symlink_to(root/'copy.bin')
            with self.assertRaises(ValueError):v.inspect(root,TOKEN)


class Orchestration(unittest.TestCase):
    def invoke(self, mode=None, failure=None, partial=False, mutate=False):
        spec=importlib.util.spec_from_file_location('stream_driver_test', ROOT/'tools/validate-streams.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        commands=[]
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            (root/'SOURCE-SHA256SUMS.txt').write_text('synthetic manifest\n')
            (root/'run-tests.rkt').write_text('(define-runtime-path some-test "tests/unrelated-native-test.rkt")\n')
            def execute(command, **kwargs):
                command=list(map(str,command));commands.append(command)
                name=Path(command[1]).name if len(command)>1 else ''
                out=kwargs['stdout']
                if name==failure:
                    out.write('synthetic selected command failure\n');out.flush()
                    raise subprocess.CalledProcessError(1,command)
                for suite,count in (('stream-pure',v.PURE_CASES),('stream-native',v.NATIVE_CASES)):
                    if name==suite+'-test.rkt':
                        out.write('incomplete\n' if partial else f'{count} success(es) 0 failure(s) 0 error(s) {count} test(s) run\n{suite}: {count} cases, 0 failures\n')
                if name=='stream-doctor.rkt':
                    fixtures(Path(command[command.index('--directory')+1]),command[command.index('--token')+1])
                    if mutate:(root/'SOURCE-SHA256SUMS.txt').write_text('changed')
                out.flush()
                return subprocess.CompletedProcess(command,0)
            args=['--racket',sys.executable,'--directory',str(root/'out')]
            if mode is not None:args+=['--regressions',mode]
            with patch.object(module.shutil,'which',return_value=sys.executable), \
                 patch.object(module.subprocess,'run',side_effect=execute), \
                 contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
                result=module.main(args,root=root)
            return result,json.loads((root/'out/validation.json').read_text()),commands
    def test_default_full(self):
        rc,report,commands=self.invoke()
        self.assertEqual(rc,0);self.assertTrue(report['regressions_passed'])
        self.assertEqual(sum(Path(c[1]).name=='run-tests.rkt' for c in commands),1)
    def test_explicit_full(self):self.assertEqual(self.invoke('full')[0],0)
    def test_none_is_not_reported_as_passed_regressions(self):
        rc,report,commands=self.invoke('none')
        self.assertEqual(rc,0);self.assertFalse(report['regressions_passed'])
        self.assertFalse(report['regressions_attempted']);self.assertEqual(report['regressions_status'],'not-run')
        self.assertFalse(any(Path(c[1]).name=='run-tests.rkt' for c in commands))
    def test_none_compile_graph_has_only_feature_roots(self):
        _,_,commands=self.invoke('none');compile=next(c for c in commands if 'make' in c)
        self.assertFalse(any('unrelated' in n or n.endswith('run-tests.rkt') for n in compile))
        self.assertTrue(compiled_test_present(compile, 'stream-native-test.rkt'))
    def test_full_compile_includes_dynamic_graph(self):
        _,_,commands=self.invoke();compile=next(c for c in commands if 'make' in c)
        self.assertTrue(compiled_test_present(compile, 'unrelated-native-test.rkt'))
    def test_feature_commands_survive_split(self):
        _,_,full=self.invoke('full');_,_,focused=self.invoke('none')
        def select(commands):return [Path(c[1]).name for c in commands if c[1]!='-l' and not c[1].endswith('run-tests.rkt')]
        self.assertEqual(select(full),select(focused))
    def test_regression_failure_stops_features(self):
        rc,report,commands=self.invoke(failure='run-tests.rkt')
        self.assertEqual(rc,1);self.assertFalse(report['native_passed'])
        self.assertEqual(report['regressions_status'],'failed')
        self.assertFalse(any(c[1].endswith('stream-native-test.rkt') for c in commands))
    def test_native_failure_stops_evidence(self):
        rc,report,commands=self.invoke('none',failure='stream-native-test.rkt')
        self.assertEqual(rc,1);self.assertFalse(report['byte_oracles_passed'])
        self.assertFalse(any(c[1].endswith('stream-doctor.rkt') for c in commands))
    def test_example_failure_stops_evidence(self):self.assertEqual(self.invoke('none',failure='streams.rkt')[0],1)
    def test_partial_output_fails(self):self.assertEqual(self.invoke('none',partial=True)[0],1)
    def test_mutated_source_fails(self):self.assertEqual(self.invoke('none',mutate=True)[0],1)
    def test_source_failure_fails(self):self.assertEqual(self.invoke('none',failure='api-inventory.py')[0],1)
    def test_no_gpu_or_live_port_claim(self):
        _,report,_=self.invoke('none');self.assertFalse(report['gpu_executed']);self.assertFalse(report['live_port_callbacks'])


class Sources(unittest.TestCase):
    def text(self,name):return (ROOT/name).read_text(encoding='utf-8')
    def test_actual_case_counts(self):
        for kind,count in (('pure',v.PURE_CASES),('native',v.NATIVE_CASES)):
            text=self.text(f'tests/stream-{kind}-test.rkt')
            self.assertEqual(text.count('(test-case '),count)
            self.assertIn(f'(define stream-{kind}-test-count {count})',text)
    def test_resource_integration(self):
        source=self.text('private/core.rkt')
        self.assertIn('(native-stream? v)',source);self.assertIn('(native-stream-handle v)',source)
        self.assertIn('stream-input stream-output',self.text('private/lifetime.rkt'))
    def test_no_managed_callback_installation(self):
        for name in ('streams.rkt','stream-inputs.rkt','private/stream-buffer.rkt'):
            source=self.text(name)
            for forbidden in ('sk_managedstream_set_procs','sk_managedwstream_set_procs','get-ffi-obj'):
                self.assertNotIn(forbidden,source)
    def test_output_quota_precedes_native_write(self):
        source=self.text('streams.rkt')
        start=source.index('(define (output-stream-write-bytes!')
        body=source[start:source.index('(define (output-stream-bytes-written',start)]
        self.assertLess(body.index('(stream-count who (+ prior n)'),body.index('(sk_wstream_write'))
    def test_memory_input_always_copies(self):self.assertIn('(sk_memorystream_new_with_data snapshot (bytes-length snapshot) #t)',self.text('streams.rkt'))
    def test_consumer_input_is_duplicated(self):
        source=self.text('stream-inputs.rkt')
        self.assertIn('(define duplicate (sk_stream_duplicate ptr))',source)
        self.assertIn('(lambda () (unless transferred? (sk_stream_destroy duplicate)))',source)
        self.assertIn('(sk_codec_new_from_stream ptr result)',source)
        self.assertIn('(sk_typeface_create_from_stream ptr index)',source)
    def test_macos_ttc_stream_reuses_reviewed_sfnt_conversion(self):
        source=self.text('stream-inputs.rkt')
        self.assertIn('"typefaces.rkt"',source)
        self.assertIn("(eq? (system-type 'os) 'macosx)",source)
        self.assertIn('(input-stream-duplicate stream)',source)
        self.assertIn('(input-stream-read-bytes probe 4)',source)
        self.assertIn('(input-stream-rewind! probe)',source)
        self.assertIn('(typeface-from-bytes (input-stream->bytes probe) #:index index)',source)
        self.assertIn('(sk_typeface_create_from_stream ptr index)',source)
    def test_picture_import_keeps_unknown_provenance(self):
        self.assertIn('picture-from-bytes picture-from-file picture-from-stream',self.text('private/audit-trace.rkt'))
    def test_suite_and_python_registration(self):
        source=self.text('run-tests.rkt')
        self.assertIn('(run-tests stream-pure-tests)',source)
        self.assertIn("dynamic-require stream-native-tests-file 'stream-native-tests",source)
        self.assertIn("'test-streams.py'",self.text('tools/ci.py'))
    def test_workflow_receives_regression_scope(self):
        source=self.text('.github/workflows/streams.yml')
        self.assertIn('workflow_call:',source);self.assertNotIn('\n  push:',source)
        self.assertIn('--regressions "$SKIA_REGRESSIONS_MODE"',source)
        self.assertIn('--regressions "$env:SKIA_REGRESSIONS_MODE"',source)
        self.assertIn('test "$STREAMS_RESULT" = success',self.text('.github/workflows/acceptance.yml'))
    def test_public_names_documented(self):
        import api_inventory as inv
        documentation=self.text('docs/STREAMS.md')
        for module in ('streams.rkt','stream-inputs.rkt'):
            for name in inv.source_exports(ROOT,module):self.assertIn(name,documentation)
    def test_canonical_numeric_package_version(self):self.assertIn('(define version "0.78")',self.text('info.rkt'))
    def test_split_remains_visible(self):
        source=self.text('plans/skia-for-racket-gap-reduction-roadmap.md')
        self.assertIn('## 0.75a',source);self.assertIn('## 0.75b',source)


if __name__=='__main__':unittest.main(verbosity=2)

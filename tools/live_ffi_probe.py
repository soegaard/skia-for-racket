#!/usr/bin/env python3
"""Run the compiler-free real-Skia gate without modifying the repository.

No mocked native workers, fallback buffering, C compiler, CMake, or extra shared
library. Compilation here means Racket's ordinary `raco make` only.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
import xml.etree.ElementTree as ET
import importlib.util
_FIXTURES = Path(__file__).resolve().parents[1] / 'tests/live-ffi-probe/fixtures.py'
_spec = importlib.util.spec_from_file_location('live_ffi_probe_fixtures', _FIXTURES)
fixtures = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fixtures)

HERE = Path(__file__).resolve().parent
EXPECTED_CASES = 25
OPERATIONS = {'copy', 'bounded-pipe', 'gc', 'decode', 'png', 'jpeg', 'webp', 'pdf', 'svg'}


def need(ok, message):
    if not ok:
        raise ValueError(message)


def source_hashes():
    return {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(HERE.iterdir()) if p.suffix in ('.py', '.rkt')}


def read_native_report(path: Path, token: str):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            need(key not in result, 'duplicate JSON key: '+key)
            result[key] = value
        return result
    d = json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique)
    need(d.get('status') == 'passed' and d.get('stage') == '0.75b-pure-ffi-probe', 'native gate did not pass')
    need(d.get('run_token') == token, 'stale or foreign native report')
    need(type(d.get('test_cases')) is int and d['test_cases'] == EXPECTED_CASES, 'wrong native test count')
    need(type(d.get('failures')) is int and d['failures'] == 0, 'native cases failed')
    need(type(d.get('active_operations')) is int and d['active_operations'] == 0, 'active native work remains')
    need(d.get('native_version') == '119.0' and d.get('vm') == 'chez-scheme', 'unexpected native ABI or VM')
    need(d.get('compiler_required') is False, 'unexpected compiler requirement')
    need(set(d.get('operations', {})) == OPERATIONS, 'missing native operation receipts')
    for name, row in d['operations'].items():
        notes = row.get('notes', {})
        need(type(notes.get('callbacks')) is int and notes['callbacks'] > 0, 'no real callbacks: ' + name)
        expected_input = name in {'copy', 'bounded-pipe', 'gc', 'decode'}
        expected_output = name != 'decode'
        need(type(notes.get('input-destroyed', 0)) is int and notes.get('input-destroyed', 0) == int(expected_input), 'input cleanup missing: ' + name)
        need(type(notes.get('output-destroyed', 0)) is int and notes.get('output-destroyed', 0) == int(expected_output), 'output cleanup missing: ' + name)
        need(type(row.get('read')) is int and row['read'] >= 0, 'bad read count')
        need(type(row.get('written')) is int and row['written'] >= 0, 'bad write count')
        if expected_output:
            need(0 < notes.get('max-copy', 0) <= 65536, 'unbounded or absent output copies')
    need(d['operations']['decode']['notes'].get('codec-created') == 1, 'no retained native codec observed')
    need(d['operations']['svg']['notes'].get('bytes-before-close', 0) > 0,
         'SVG did not write before finalization')
    return d


def inspect(native: Path, report: dict, run, require_renderers: bool):
    from PIL import Image
    from pypdf import PdfReader
    need((native/'copied.bin').read_bytes() == fixtures.payload(), 'native stream copy differs')
    for name in ('copy', 'bounded-pipe', 'gc'):
        need(report['operations'][name]['read'] == len(fixtures.payload()) and
             report['operations'][name]['written'] == len(fixtures.payload()),
             'native copy receipt byte count differs: '+name)
    need((native/'decoded.rgba').read_bytes() == fixtures.rgba(), 'real codec pixels differ from reference')
    inspected = {}
    for fmt in ('png', 'jpeg', 'webp'):
        p = native / ('encoded.'+fmt)
        with Image.open(p) as im:
            need(im.size == (fixtures.WIDTH, fixtures.HEIGHT), 'wrong encoded image dimensions')
            data = im.convert('RGBA').tobytes()
        if fmt != 'jpeg':
            need(data == fixtures.rgba(), 'lossless image pixels differ: ' + fmt)
        else:
            for y in (4, 19):
                for x in (4, 27):
                    off = (y*fixtures.WIDTH+x)*4
                    need(max(abs(a-b) for a,b in zip(data[off:off+3], fixtures.rgba()[off:off+3])) <= 8,
                         'JPEG interior colors differ')
        need(p.stat().st_size == report['operations'][fmt]['written'], 'encoder write count differs')
        inspected[fmt] = {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
    pdf = native/'document.pdf'
    reader = PdfReader(str(pdf), strict=True)
    need(len(reader.pages) == 1, 'wrong PDF page count')
    box = list(map(float, reader.pages[0].mediabox))
    need(box == [0, 0, 64, 48], 'wrong PDF bounds')
    svg = native/'document.svg'
    root = ET.fromstring(svg.read_bytes())
    need(root.tag.split('}')[-1] == 'svg', 'not an SVG root')
    def dimension(value):
        m = re.fullmatch(r'([0-9.]+)(?:px)?', value or '')
        need(m is not None, 'unexpected native SVG units')
        return float(m[1])
    need(dimension(root.get('width')) == 64 and dimension(root.get('height')) == 48,
         'wrong native SVG dimensions')
    rendered = {}
    for fmt, executable in [('pdf', 'pdftoppm'), ('svg', 'rsvg-convert')]:
        doc = pdf if fmt == 'pdf' else svg
        need(doc.stat().st_size == report['operations'][fmt]['written'], 'document write count differs')
        if not shutil.which(executable):
            need(not require_renderers, 'required renderer not found: '+executable)
            rendered[fmt] = 'not-run: renderer unavailable'
            continue
        image = native/('rendered-'+fmt+'.png')
        if fmt == 'pdf':
            command = [executable, '-singlefile', '-r', '72', '-png', str(doc), str(image.with_suffix(''))]
        else:
            command = [executable, '--width', '64', '--height', '48', '--output', str(image), str(doc)]
        run(command)
        with Image.open(image) as im:
            need(im.size == (64,48), 'wrong rendered document size')
            im = im.convert('RGB')
            for y in (6,24,41):
                for x in (7,32,56):
                    need(max(abs(a-b) for a,b in zip(im.getpixel((x,y)), (51,102,153))) <= 2,
                         'independent document pixels differ: '+fmt)
        rendered[fmt] = 'passed'
    return {'copy': 'exact', 'decode': 'exact', 'images': inspected, 'documents_rendered': rendered}



def run_probe(root, output, racket, run, require_renderers=False):
    """Execute the retained 25-case native gate in a separate Racket process."""
    output=Path(output);output.mkdir(parents=True,exist_ok=False)
    token=uuid.uuid4().hex
    identity=json.loads(run([racket,root/'tools/live-stream-identity.rkt']))
    need(identity.get('vm')=='chez-scheme' and identity.get('os_threads') is True,
         'requires Racket CS with OS-thread support')
    fixtures.write(output/'fixtures')
    completion=run([racket,root/'tests/live-ffi-probe/probe.rkt', '--library',identity['path'],
                    '--directory',output/'native','--fixtures',output/'fixtures','--token',token])
    need(len(re.findall(r'^pure-ffi-native: 25 cases, 0 failures\s*$',completion,re.M))==1,
         'missing or duplicate native probe completion')
    report=read_native_report(output/'native/native-report.json',token)
    need(report['racket_version']==identity['racket_version'],'native probe interpreter mismatch')
    inspection=inspect(output/'native',report,run,require_renderers)
    summary=dict(status='passed',native_cases=25,compiler_required=False,identity=identity,
                 native_report=report,inspection=inspection)
    (output/'validation.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
    return summary

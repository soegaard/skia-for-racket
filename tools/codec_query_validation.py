"""0.76a native negotiation evidence; synthetic fixtures are not native execution."""
from __future__ import annotations
import hashlib
import io
import json
from pathlib import Path
import re

PURE_CASES = 31
NATIVE_CASES = 26
SCALES = (1, .5, .25, .125, 2)
SIZE = (16, 12)


def need(ok, message):
    if not ok:
        raise ValueError(message)


def unique(pairs):
    data = {}
    for key, value in pairs:
        need(key not in data, 'duplicate JSON key: ' + key)
        data[key] = value
    return data


def suite_output(text, name, cases):
    text = text.replace('\r\n', '\n')
    summary = re.findall(r'^(\d+) success\(es\) (\d+) failure\(s\) (\d+) error\(s\) (\d+) test\(s\) run$', text, re.M)
    marker = re.findall(rf'^{re.escape(name)}: (\d+) cases, (\d+) failures$', text, re.M)
    need(summary == [(str(cases), '0', '0', str(cases))] and marker == [(str(cases), '0')],
         'incomplete or failed ' + name + ' suite')
    need(not re.search(r'^(?:FAILURE|ERROR|FAILED)\b', text, re.M), 'printed suite failure')


def read_file(directory, name, limit):
    need(directory.is_dir() and not directory.is_symlink(), 'missing or linked evidence directory')
    path = directory / name
    need(path.is_file() and not path.is_symlink(), 'missing or linked evidence: ' + name)
    with path.open('rb') as stream:
        data = stream.read(limit + 1)
    need(len(data) <= limit, 'oversized evidence: ' + name)
    return data


def fixture_pixels():
    return bytes(v for y in range(12) for x in range(16)
                 for v in (x*13 % 256, y*19 % 256, (x*7+y*11) % 256, 255))


def exact_list(value, expected, label):
    need(type(value) is list and len(value) == len(expected)
         and all(type(v) is int for v in value) and value == list(expected), 'wrong ' + label)


def inspect(directory: Path, token: str):
    from PIL import Image
    def invalid(value):
        raise ValueError('nonfinite JSON: ' + value)
    report = json.loads(read_file(directory, 'queries.json', 65536), object_pairs_hook=unique,
                        parse_constant=invalid)
    need(type(report) is dict and type(report.get('schema')) is int and report['schema'] == 1,
         'invalid receipt schema')
    need(report.get('stage') == '0.76a' and report.get('status') == 'passed'
         and report.get('run_token') == token, 'foreign or failed receipt')
    need(report.get('native_version') == '119.0', 'wrong native ABI')
    need(report.get('query_coordinates') == 'encoded-pixels', 'wrong query coordinate space')
    for field in ('scaled_decode_executed', 'subset_decode_executed', 'gpu_executed'):
        need(report.get(field) is False, 'unexpected/missing execution claim: ' + field)
    exact_list(report.get('oriented_jpeg_half'), (8, 6), 'EXIF-independent scaled dimensions')
    rows = report.get('formats')
    need(type(rows) is list and len(rows) == 3 and all(type(r) is dict for r in rows), 'wrong format matrix')
    need([r.get('format') for r in rows] == ['png', 'jpeg', 'webp'], 'duplicate or missing format')
    hashes = {}
    for row in rows:
        name = row['format']
        exact_list(row.get('source_size'), SIZE, 'source size')
        need(row.get('decode_unchanged') is True, 'decode stability not established')
        sizes = row.get('scaled')
        need(type(sizes) is list and len(sizes) == len(SCALES), 'incomplete scale matrix')
        for i, (scale, size) in enumerate(zip(SCALES, sizes)):
            need(type(size) is list and len(size) == 3 and type(size[0]) in (int, float)
                 and size[0] == scale and all(type(v) is int for v in size[1:]), 'invalid scale result')
            width, height = size[1:]
            need(1 <= width <= 16 and 1 <= height <= 12, 'invalid suggested extent')
            expected = None
            if name == 'png' or scale >= 1:
                expected = SIZE
            elif name == 'jpeg':
                expected = {1: (8, 6), 2: (4, 3), 3: (2, 2)}[i]
            if expected is not None:
                exact_list(size[1:], expected, name + ' native scale suggestion')
        if name == 'webp':
            exact_list(row.get('odd_subset'), (0, 2, 7, 6), 'WebP adjusted subset')
            exact_list(row.get('even_subset'), (2, 4, 6, 4), 'WebP exact subset')
        else:
            need(row.get('odd_subset') is False and row.get('even_subset') is False,
                 name + ' unsupported subset must be false')
        encoded = read_file(directory, name + '.encoded', 1024*1024)
        with Image.open(io.BytesIO(encoded)) as image:
            need(image.format == name.upper() and image.size == SIZE, 'wrong independent encoded dimensions/format')
            image.load()
            if name != 'jpeg':
                need(image.convert('RGBA').tobytes() == fixture_pixels(), 'independent lossless fixture pixels differ')
        before = read_file(directory, name + '-before.rgba', 16*12*4)
        after = read_file(directory, name + '-after.rgba', 16*12*4)
        need(len(before) == 16*12*4 and before == after, 'query changed full decoded pixels')
        if name != 'jpeg':
            need(before == fixture_pixels(), 'native lossless pixels differ')
        for suffix, data in (('.encoded', encoded), ('-before.rgba', before), ('-after.rgba', after)):
            hashes[name + suffix] = hashlib.sha256(data).hexdigest()
    return dict(status='passed', native_receipt=report, files=hashes,
                scaled_decode_verified=False, subset_decode_verified=False, gpu_executed=False)

"""0.75a byte/evidence inspector. Python fixtures are not native execution."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re

PURE_CASES = 35
NATIVE_CASES = 39
PIXELS = bytes((255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255))


def need(ok, message):
    if not ok:
        raise ValueError(message)


def unique(pairs):
    result = {}
    for key, value in pairs:
        need(key not in result, 'duplicate JSON key: ' + key)
        result[key] = value
    return result


def suite_output(text, name, cases):
    text = text.replace('\r\n', '\n')
    summary = re.findall(r'^(\d+) success\(es\) (\d+) failure\(s\) (\d+) error\(s\) (\d+) test\(s\) run$', text, re.M)
    marker = re.findall(rf'^{re.escape(name)}: (\d+) cases, (\d+) failures$', text, re.M)
    need(summary == [(str(cases), '0', '0', str(cases))] and marker == [(str(cases), '0')],
         'incomplete or failed ' + name + ' suite')
    need(not re.search(r'^(?:FAILURE|ERROR|FAILED)\b', text, re.M), 'printed suite failure')


def read_file(directory, name, limit):
    path = directory / name
    need(path.is_file() and not path.is_symlink(), 'missing or linked evidence: ' + name)
    with path.open('rb') as source:
        data = source.read(limit + 1)
    need(len(data) <= limit, 'oversized evidence: ' + name)
    return data


def inspect(directory: Path, token: str):
    def invalid(value):
        raise ValueError('nonfinite JSON: ' + value)
    report = json.loads(read_file(directory, 'streams.json', 16384),
                        object_pairs_hook=unique, parse_constant=invalid)
    need(type(report) is dict and type(report.get('schema')) is int and report['schema'] == 1,
         'invalid receipt schema')
    need(report.get('stage') == '0.75a' and report.get('run_token') == token
         and report.get('status') == 'passed', 'foreign or failed receipt')
    need(report.get('native_version') == '119.0', 'wrong native ABI')
    for name, value in (('length', 4096), ('source_position', 7)):
        need(type(report.get(name)) is int and report[name] == value, 'wrong ' + name)
    for name, value in (('file_roundtrip', True), ('streams_closed', True),
                        ('live_port_callbacks', False), ('gpu_executed', False)):
        need(report.get(name) is value, 'missing/incorrect claim: ' + name)
    need(report.get('family') == 'Skia Racket Fixture', 'font input not retained')
    payload = bytes(range(256)) * 16
    expected = {'stream.bin': payload, 'tail.bin': payload[7:], 'decoded.rgba': PIXELS}
    hashes = {}
    for name, wanted in expected.items():
        data = read_file(directory, name, len(wanted))
        need(data == wanted, 'byte oracle mismatch: ' + name)
        hashes[name] = hashlib.sha256(data).hexdigest()
    return dict(status='passed', files=hashes, native_receipt=report,
                live_port_streaming_verified=False, gpu_executed=False)

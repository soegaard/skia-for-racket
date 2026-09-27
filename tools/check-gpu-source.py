#!/usr/bin/env python3
"""Conservative source-structure checks; NOT Racket expansion or execution."""
from __future__ import annotations
import argparse
import json
import pathlib
import re

class String(str):
    pass

def read_forms(text: str):
    tokens = []
    i = 0
    while i < len(text):
        c = text[i]
        if c.isspace():
            i += 1; continue
        if text.startswith('#lang ', i):
            n = text.find('\n', i); i = len(text) if n < 0 else n + 1; continue
        if c == ';':
            n = text.find('\n', i); i = len(text) if n < 0 else n + 1; continue
        if text.startswith('#|', i):
            depth = 1; i += 2
            while depth and i < len(text):
                if text.startswith('#|', i): depth += 1; i += 2
                elif text.startswith('|#', i): depth -= 1; i += 2
                else: i += 1
            if depth: raise ValueError('unterminated block comment')
            continue
        if text.startswith('#;', i): tokens.append('#;'); i += 2; continue
        if text.startswith('#\\', i):
            start = i; i += 2
            if i == len(text): raise ValueError('unfinished character literal')
            i += 1
            while i < len(text) and not text[i].isspace() and text[i] not in '()[]{}': i += 1
            tokens.append(text[start:i]); continue
        prefix = re.match(r'(?:#(?:px|rx)?#?)?"', text[i:])
        if prefix:
            start = i; i += len(prefix.group())
            while i < len(text):
                if text[i] == '\\': i += 2
                elif text[i] == '"': i += 1; break
                else: i += 1
            else: raise ValueError('unterminated string')
            tokens.append(String(text[start:i])); continue
        if c in '()[]{}': tokens.append(c); i += 1; continue
        if c in "'`": tokens.append(c); i += 1; continue
        if c == ',':
            token = ',@' if text.startswith(',@', i) else ','
            tokens.append(token); i += len(token); continue
        start = i
        while i < len(text) and not text[i].isspace() and text[i] not in '()[]{};"': i += 1
        if start == i: raise ValueError(f'unrecognized reader input at {i}')
        tokens.append(text[start:i])
    index = 0
    def form():
        nonlocal index
        if index >= len(tokens): raise ValueError('unexpected EOF')
        token = tokens[index]; index += 1
        if isinstance(token, String): return token
        if token == '#;':
            form()
            return form() if index < len(tokens) else None
        if token in ("'", '`', ',', ',@'):
            return [{"'": 'quote', '`': 'quasiquote', ',': 'unquote', ',@': 'unquote-splicing'}[token], form()]
        if token in ('(', '[', '{'):
            end = {'(': ')', '[': ']', '{': '}'}[token]
            result = []
            while index < len(tokens) and tokens[index] != end:
                result.append(form())
            if index == len(tokens): raise ValueError(f'unclosed {token}')
            index += 1
            return result
        if token in (')', ']', '}'): raise ValueError(f'unexpected closing delimiter {token} near token {index}')
        return token
    forms = []
    while index < len(tokens): forms.append(form())
    return forms

def check(root: pathlib.Path):
    files = sorted([*root.glob('gpu*.rkt'), *root.glob('private/gpu*.rkt'),
                    *root.glob('private/native-platform.rkt'), *root.glob('tests/gpu*.rkt'),
                    *root.glob('tools/gpu*.rkt')])
    results = {}
    for file in files:
        try:
            forms = read_forms(file.read_text())
        except ValueError as exc:
            raise ValueError(f'{file.relative_to(root)}: {exc}') from exc
        def arities(form):
            if not isinstance(form, list) or not form:
                return
            if form[0] in ('quote', 'quasiquote'):
                return
            if form[0] in ('if', 'set!') and len(form) != {'if':4, 'set!':3}[form[0]]:
                raise ValueError(f'{file}: malformed {form[0]} form')
            if form[0] == 'define' and len(form) > 1 and isinstance(form[1], str) and len(form) != 3:
                raise ValueError(f'{file}: malformed value definition {form[1]}')
            for child in form:
                arities(child)
        for form in forms:
            arities(form)
        results[str(file.relative_to(root))] = len(forms)
    forms = read_forms((root/'tests/gpu-pure-test.rkt').read_text())
    definition = [f for f in forms if isinstance(f, list) and len(f) >= 3 and f[:2] == ['define', 'gpu-pure-tests']]
    if len(definition) != 1: raise ValueError('missing or duplicate GPU suite definition')
    definition = definition[0]
    if len(definition) != 3: raise ValueError('extra expressions escaped GPU test-suite into its define')
    suite = definition[2]
    if not isinstance(suite, list) or suite[0] != 'test-suite': raise ValueError('expected test-suite form')
    cases = suite[2:]
    if not all(isinstance(case, list) and case and case[0] == 'test-case' for case in cases):
        raise ValueError('unexpected non-test-case expression at suite level')
    source_count = len(re.findall(r'\(test-case\b', (root/'tests/gpu-pure-test.rkt').read_text()))
    if source_count != len(cases): raise ValueError('test cases escaped the executable suite')
    # There must not be a module-level GUI require or driver load in the safe API.
    public = (root/'gpu.rkt').read_text()
    if re.search(r'\(require[^)]*racket/gui', public, re.S): raise ValueError('GUI dependency leaked into GPU foundation')
    if 'sk_surface_new_render_target' not in (root/'private/gpu-smoke.rkt').read_text():
        raise ValueError('probe lost its explicit GPU target constructor')
    return {'racket_source_structure': results, 'gpu_source_cases': len(cases),
            'racket_expansion_executed': False, 'rackunit_executed': False,
            'native_gpu_executed': False}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    print(json.dumps(check(args.root), indent=2))

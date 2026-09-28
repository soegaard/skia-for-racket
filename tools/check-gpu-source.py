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

def check(root: pathlib.Path, *, require_integration=False):
    files = sorted([*root.glob('gpu*.rkt'), *root.glob('private/gpu*.rkt'),
                    *root.glob('private/native-platform.rkt'), *root.glob('tests/gpu*.rkt'),
                    *root.glob('tools/gpu*.rkt'), *root.glob('examples/gpu*.rkt')])
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
    def suite_cases(path, name, *, factory=False):
        source = (root/path).read_text()
        forms = read_forms(source)
        definitions = [f for f in forms if isinstance(f,list) and len(f)>=3 and f[0]=='define'
                       and ((isinstance(f[1],list) and f[1] and f[1][0]==name) if factory else f[1]==name)]
        if len(definitions)!=1: raise ValueError(f'{path}: missing or duplicate suite definition')
        definition = definitions[0]
        suites = [f for f in definition[2:] if isinstance(f,list) and f and f[0]=='test-suite']
        if len(suites)!=1 or definition[-1] is not suites[0]:
            raise ValueError(f'{path}: suite must be the final returned value')
        if not factory and len(definition)!=3: raise ValueError(f'{path}: extra suite expressions')
        cases = suites[0][2:]
        if not all(isinstance(c,list) and c and c[0]=='test-case' for c in cases):
            raise ValueError(f'{path}: non-test-case at suite level')
        if len(re.findall(r'\(test-case\b',source))!=len(cases):
            raise ValueError(f'{path}: test case escaped its executable suite')
        return len(cases)
    counts = {
        'foundation_pure':suite_cases('tests/gpu-pure-test.rkt','gpu-pure-tests'),
        'surface_pure':suite_cases('tests/gpu-surface-pure-test.rkt','gpu-surface-pure-tests'),
        'surface_live':suite_cases('tests/gpu-surface-native-test.rkt','make-gpu-surface-native-tests',factory=True)}
    public = (root/'gpu.rkt').read_text()
    if re.search(r'\(require[^)]*racket/gui',public,re.S):
        raise ValueError('GUI dependency leaked into optional GPU module')
    if 'sk_surface_new_render_target' not in (root/'private/gpu-smoke.rkt').read_text():
        raise ValueError('foundation probe lost its real GPU constructor')
    for module in ('private/gpu-surfaces.rkt',):
        forms = read_forms((root/module).read_text())
        names = [n for f in forms if isinstance(f,list) and f and f[0]=='provide' for n in f[1:] if isinstance(n,str)]
        doc = (root/'docs/GPU-OFFSCREEN.md').read_text()
        if any(n not in doc for n in names): raise ValueError(f'{module}: undocumented public binding')
    integration = {}
    for path, required in {
        'private/core.rkt':['struct gpu-surface surface','struct gpu-canvas canvas',
                            'domain-check-lease!','require-cpu-surface',
                            'surface-backend','canvas-execution-backend',
                            "[(gpu-surface? owner) 'gpu]"],
        'private/lifetime.rkt':['domain-resource?','resource-pointer','domain-resource-close!'],
        'raster-buffers.rkt':['module* gpu-transfer-internals','call-with-raster-buffer-gpu-transfer'],
        'run-tests.rkt':['tests/gpu-surface-pure-test.rkt','(run-tests gpu-surface-pure-tests)'],
        'docs/API.md':['surface-backend','canvas-execution-backend'],
    }.items():
        file = root/path
        if not file.exists():
            if require_integration: raise ValueError(f'missing full-repository integration file: {path}')
            integration[path] = 'not present in source-only bundle'
            continue
        text = file.read_text()
        if any(term not in text for term in required): raise ValueError(f'{path}: missing integration guard/export')
        integration[path] = 'source markers present (not Racket expansion)'
    return {'racket_source_structure':results, 'gpu_source_cases':counts,
            'integration_source_checks':integration,
            'racket_expansion_executed':False, 'rackunit_executed':False,
            'native_gpu_executed':False}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[1])
    parser.add_argument('--require-integration',action='store_true')
    args = parser.parse_args()
    print(json.dumps(check(args.root,require_integration=args.require_integration),indent=2))

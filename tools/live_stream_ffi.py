"""Validate the explicitly reviewed pure-FFI worker import registry.

The main include/c inventory and the Xamarin callback-table extension are kept
separate. No native execution is inferred from this declaration check.
"""
from __future__ import annotations
import json
from pathlib import Path

def checked_imports(root: Path, forms, String):
    source=root/'private/live-port-native.rkt'
    manifest=json.loads((root/'api/live-stream-ffi.json').read_text(encoding='utf-8'))
    if manifest.get('schema') != 1 or manifest.get('native_version') != '119.0':
        raise ValueError('wrong live-FFI manifest version')
    expected=manifest['standard'] | manifest['xamarin']
    actual={}
    for form in forms(source.read_text(encoding='utf-8')):
        if isinstance(form,list) and form and form[0]=='define-raw':
            if len(form)!=3 or not isinstance(form[1],str) or form[1] in actual:
                raise ValueError('malformed/duplicate live-FFI declaration')
            actual[form[1]]=form[2]
    for name,signature in expected.items():
        parsed=forms(signature)
        if len(parsed)!=1 or actual.get(name)!=parsed[0]:
            raise ValueError('live-FFI signature drift: '+name)
    if set(actual)!=set(expected):
        raise ValueError('unclassified live-FFI imports: '+repr(sorted(set(actual)^set(expected))))
    upstream=root/'api/upstream-m119.json'
    if upstream.is_file():
        symbols=set().union(*(set(v) for v in json.loads(upstream.read_text())['headers'].values()))
        if not set(manifest['standard']) <= symbols:
            raise ValueError('live worker import not in pinned include/c baseline')
        if set(manifest['xamarin']) & symbols:
            raise ValueError('Xamarin imports incorrectly classified as include/c')
    if set(manifest['xamarin']) != {
        'sk_managedstream_set_procs','sk_managedwstream_set_procs',
        'sk_managedstream_new','sk_managedstream_destroy',
        'sk_managedwstream_new','sk_managedwstream_destroy'}:
        raise ValueError('unreviewed Xamarin extension set')
    return sorted(manifest['standard']), sorted(manifest['xamarin'])

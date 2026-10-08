"""Strict source inventory for the pinned Xamarin trace adapter (not include/c)."""
from pathlib import Path
import json

EXPECTED = {
    'sk_managedtracememorydump_new': '(_fun _stdbool _stdbool _pointer -> _pointer)',
    'sk_managedtracememorydump_delete': '(_fun _pointer -> _void)',
    'sk_managedtracememorydump_set_procs': '(_fun _trace-procs -> _void)',
}
CALLBACKS = {
    'numeric': '(_fun #:atomic? #t _pointer _pointer _pointer _pointer _pointer _uint64 -> _void)',
    'string': '(_fun #:atomic? #t _pointer _pointer _pointer _pointer _pointer -> _void)',
}
MODULE='private/graphics-trace-native.rkt'
SIDECAR='api/global-cache-ffi.json'

def need(ok,message):
    if not ok: raise ValueError(message)

def canonical(node):
    if isinstance(node,list): return '('+' '.join(map(canonical,node))+')'
    need(type(node) is str,'unsupported FFI type syntax')
    return node

def unique(pairs):
    out={}
    for k,v in pairs:
        need(k not in out,'duplicate FFI manifest key');out[k]=v
    return out

def checked_imports(root, forms, String=None):
    root=Path(root)
    p=root/SIDECAR
    need(p.is_file() and not p.is_symlink(),'missing/symlink trace FFI sidecar')
    data=json.loads(p.read_text(encoding='utf-8'),object_pairs_hook=unique)
    need(type(data.get('schema')) is int and data['schema']==1,'wrong trace FFI schema')
    need(data.get('stage')=='0.77a' and data.get('skia_revision')=='40f75dc0051d141913c07c20d4c19590c7da0cb7','wrong trace ABI pin')
    need(data.get('header')=='include/xamarin/sk_managedtracememorydump.h'
         and data.get('header_git_blob')=='cabc6297dbb3cb6a3e9936139bc2b56ee0c91e9b','wrong trace header')
    need(data.get('execution_evidence')=='not asserted by declarations','unreviewed trace execution claim')
    need(data.get('scope')=='Xamarin trace adapter only; not additional include/c feature coverage','trace coverage scope drift')
    need(data.get('module')==MODULE and data.get('macro')=='define-trace','wrong trace registry')
    need(data.get('signatures')==EXPECTED and data.get('callbacks')==CALLBACKS,'trace signature manifest drift')
    need(data.get('table_fields')==['numeric','string'],'trace layout manifest drift')
    src=root/MODULE
    need(src.is_file() and not src.is_symlink(),'missing/symlink trace module')
    nodes=forms(src.read_text(encoding='utf-8'))
    declarations=[n for n in nodes if isinstance(n,list) and n and n[0]=='define-trace']
    need(all(len(n)==3 for n in declarations),'malformed trace declaration')
    observed={n[1]:canonical(n[2]) for n in declarations}
    need(len(declarations)==len(EXPECTED) and observed==EXPECTED,'trace callout signature drift')
    defs={n[1]:n[2] for n in nodes if isinstance(n,list) and len(n)==3 and n[0]=='define' and type(n[1]) is str}
    for key,wanted in CALLBACKS.items():
        need(canonical(defs.get('_'+key+'-callback',[]))==wanted,'trace callback signature drift: '+key)
    tables=[n for n in nodes if isinstance(n,list) and len(n)>2 and n[:2]==['define-cstruct','_trace-procs']]
    need(len(tables)==1 and tables[0][2]==[['numeric','_fpointer'],['string','_fpointer']],'trace callback field drift')
    return sorted(EXPECTED)

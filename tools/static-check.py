# Optional Python 3 source/installer checks; not a Racket compiler.
from pathlib import Path
import re, subprocess, tempfile, shutil, zipfile, json, platform
import syntax_scan as mod
R=Path(__file__).resolve().parents[1]
errors=[mod.scan(p) for p in R.rglob('*.rkt')]; assert not any(errors), errors
# Small structural reader: sufficient for counting test-suite contents and
# recognizing top-level definitions, NOT a Racket reader or expander.
def sexps(text):
    toks=re.findall(r';[^\n]*|"(?:\\.|[^"\\])*"|[()\[\]{}]|[^\s()\[\]{}";]+', text)
    root=[]; stack=[root]
    for t in toks:
        if t.startswith(';'):continue
        if t in '([{': a=[];stack[-1].append(a);stack.append(a)
        elif t in ')]}':stack.pop()
        else:stack[-1].append(t)
    assert len(stack)==1
    return root
counts={}
for f,var in [('pure-test.rkt','pure-tests'),('lifetime-test.rkt','lifetime-tests'),('native-test.rkt','native-tests'),
              ('codec-pure-test.rkt','codec-pure-tests'),('codec-native-test.rkt','codec-native-tests'),
              ('pdf-pure-test.rkt','pdf-pure-tests'),('pdf-native-test.rkt','pdf-native-tests'),
              ('svg-pure-test.rkt','svg-pure-tests'),('svg-native-test.rkt','svg-native-tests'),
              ('output-pure-test.rkt','output-pure-tests'),('output-native-test.rkt','output-native-tests'),
              ('path-matrix-pure-test.rkt','path-matrix-pure-tests'),
              ('path-matrix-native-test.rkt','path-matrix-native-tests'),
              ('filter-graph-pure-test.rkt','filter-graph-pure-tests'),
              ('filter-graph-native-test.rkt','filter-graph-native-tests')]:
    ast=sexps((R/'tests'/f).read_text())
    defs=[x for x in ast if isinstance(x,list) and len(x)>2 and x[:2]==['define',var]]
    assert len(defs)==1
    body=defs[0][2];assert body[0]=='test-suite'
    cases=body[2:]
    assert all(isinstance(t,list) and t and t[0]=='test-case' for t in cases),(f,cases[-1:])
    count=len(cases);counts[f]=count
    assert count==len(re.findall(r'\(test-case\s', (R/'tests'/f).read_text()))
# Check that every explicitly exported core name has a definition or a
# struct-generated binding, or is the imported byte-limit parameter.
ast=sexps((R/'private/core.rkt').read_text()); defined={'current-skia-byte-limit'}; exports=[]
for f in ast:
    if not isinstance(f,list) or not f:continue
    if f[0]=='provide':exports+=f[1:]
    elif f[0] in ('define','define-syntax','define-syntax-rule'):
        defined.add(f[1][0] if isinstance(f[1],list) else f[1])
    elif f[0]=='struct':
        n=f[1];defined|={n,n+'?'}
        for field in f[2]:
            k=field[0] if isinstance(field,list) else field
            defined.add(n+'-'+k)
        if '#:constructor-name' in f:defined.add(f[f.index('#:constructor-name')+1])
assert not set(exports)-defined, sorted(set(exports)-defined)
api=(R/'docs/API.md').read_text();assert not [s for s in exports if s not in api]
# The common page layer is a separate public module with local definitions.
output_defined=set();output_exports=[]
for f in sexps((R/'output.rkt').read_text()):
    if not isinstance(f,list) or not f:continue
    if f[0]=='provide':output_exports+=f[1:]
    elif f[0] in ('define','define-syntax','define-syntax-rule'):
        output_defined.add(f[1][0] if isinstance(f[1],list) else f[1])
    elif f[0]=='struct':
        n=f[1];output_defined|={n,n+'?'}
        for field in f[2]:
            k=field[0] if isinstance(field,list) else field
            output_defined.add(n+'-'+k)
        if '#:constructor-name' in f:output_defined.add(f[f.index('#:constructor-name')+1])
assert not set(output_exports)-output_defined, sorted(set(output_exports)-output_defined)
assert not [s for s in output_exports if s not in api]
# Pure matrix values and the private implementation's SAFE public exports.
# No binding from core's path-matrix-internals submodule is exported by main.
for module in ['matrix.rkt', 'private/path-matrix.rkt', 'private/filter-graph.rkt']:
    local=set(); public=[]
    for form in sexps((R/module).read_text()):
        if not isinstance(form,list) or not form: continue
        if form[0]=='provide': public+=form[1:]
        elif form[0] in ('define','define-syntax','define-syntax-rule'):
            local.add(form[1][0] if isinstance(form[1],list) else form[1])
        elif form[0]=='struct':
            name=form[1]; local|={name,name+'?'}
            for field in form[2]:
                local.add(name+'-'+(field[0] if isinstance(field,list) else field))
            if '#:constructor-name' in form: local.add(form[form.index('#:constructor-name')+1])
    assert not set(public)-local, (module, sorted(set(public)-local))
    assert not [s for s in public if s not in api], (module, public)
subprocess.run(['bash','-n',str(R/'tools/validate-path-matrix.sh')],check=True)
subprocess.run(['bash','-n',str(R/'tools/validate-filter-graphs.sh')],check=True)
# Check internal local require paths exist (literal relative .rkt strings).
for f in R.rglob('*.rkt'):
    for ref in re.findall(r'"((?:\.\.?/)?[^"\n]+\.rkt)"',f.read_text()):
        if ' ' not in ref:
            assert (f.parent/ref).exists(),(f,ref)
for shell in ['install-native.sh','install-harfbuzz.sh','audit-symbols.sh','audit-harfbuzz-symbols.sh']:
    subprocess.run(['bash','-n',str(R/'tools'/shell)],check=True)
# Exercise installer in a separate temporary project with synthetic data.
# No fake shared library is created in the deliverable.
with tempfile.TemporaryDirectory(prefix='skia-installer-check-') as temp:
    t=Path(temp); project=t/'project with spaces'; (project/'tools').mkdir(parents=True)
    target=project/'tools/install-native.sh';shutil.copy2(R/'tools/install-native.sh',target)
    if platform.system() == 'Darwin':
        pkg='SkiaSharp.NativeAssets.macOS'; rid='osx'; lib='libSkiaSharp.dylib'
    elif platform.system() == 'Linux' and platform.machine() in ('x86_64','aarch64','arm64'):
        pkg='SkiaSharp.NativeAssets.Linux.NoDependencies'
        rid='linux-x64' if platform.machine() == 'x86_64' else 'linux-arm64'
        lib='libSkiaSharp.so'
    else:
        raise SystemExit('Installer smoke checks need macOS or supported Linux.')
    def archive(name,version='3.119.1',member=True,package=pkg):
        f=t/name
        with zipfile.ZipFile(f,'w') as z:
            z.writestr('native.nuspec',f'<package><metadata><id>{package}</id><version>{version}</version></metadata></package>')
            if member:z.writestr(f'runtimes/{rid}/native/{lib}',b'SYNTHETIC-INSTALLER-TEST-NOT-A-LIBRARY')
        return f
    def run(f):return subprocess.run(['bash',str(target),'--archive',str(f)],capture_output=True,text=True)
    good=run(archive('good package.nupkg'));assert good.returncode==0,good.stderr
    dest=project/'native'/rid/lib;original=dest.read_bytes()
    installed={'valid offline archive':good.returncode}
    for key,kwargs in [('wrong-version',{'version':'4.0.0'}),('wrong-package',{'package':'Different.Package'}),('missing-member',{'member':False})]:
        r=run(archive(key+'.nupkg',**kwargs));assert r.returncode!=0;assert dest.read_bytes()==original
        installed[key]='rejected; previous library preserved'
    assert not list((project/'native').glob('.install.*'))
    help=subprocess.run(['bash',str(target),'--help'],capture_output=True,text=True);assert help.returncode==0
    installed['help']='success'
# Exercise the HarfBuzz installer with the same create-only synthetic archive strategy.
with tempfile.TemporaryDirectory(prefix='harfbuzz-installer-check-') as temp:
    t=Path(temp); project=t/'project with spaces'; (project/'tools').mkdir(parents=True)
    target=project/'tools/install-harfbuzz.sh';shutil.copy2(R/'tools/install-harfbuzz.sh',target)
    if platform.system() == 'Darwin':
        hpkg='HarfBuzzSharp.NativeAssets.macOS'; hrid='osx'; hlib='libHarfBuzzSharp.dylib'
    elif platform.system() == 'Linux' and platform.machine() in ('x86_64','aarch64','arm64'):
        hpkg='HarfBuzzSharp.NativeAssets.Linux'
        hrid='linux-x64' if platform.machine() == 'x86_64' else 'linux-arm64'
        hlib='libHarfBuzzSharp.so'
    else:
        raise SystemExit('HarfBuzz installer smoke checks need macOS or supported Linux.')
    def harchive(name,version='8.3.1.2',member=True,package=hpkg):
        f=t/name
        with zipfile.ZipFile(f,'w') as z:
            z.writestr('native.nuspec',f'<package><metadata><id>{package}</id><version>{version}</version></metadata></package>')
            if member:z.writestr(f'runtimes/{hrid}/native/{hlib}',b'SYNTHETIC-HARFBUZZ-INSTALLER-TEST-NOT-A-LIBRARY')
        return f
    def hrun(f):return subprocess.run(['bash',str(target),'--archive',str(f)],capture_output=True,text=True)
    good=hrun(harchive('good package.nupkg'));assert good.returncode==0,good.stderr
    dest=project/'native'/hrid/hlib;original=dest.read_bytes()
    hinstalled={'valid offline archive':good.returncode}
    for key,kwargs in [('wrong-version',{'version':'9.0.0'}),('wrong-package',{'package':'Different.Package'}),('missing-member',{'member':False})]:
        r=hrun(harchive(key+'.nupkg',**kwargs));assert r.returncode!=0;assert dest.read_bytes()==original
        hinstalled[key]='rejected; previous library preserved'
    assert not list((project/'native').glob('.install-hb.*'))
    help=subprocess.run(['bash',str(target),'--help'],capture_output=True,text=True);assert help.returncode==0
    hinstalled['help']='success'

result={'racket_files_scanned':len(list(R.rglob('*.rkt'))),'source_test_case_counts':counts,'core_exports_accounted_for':len(exports),'output_exports_accounted_for':len(output_exports),'local_module_paths':'exist','shell_syntax':'passed','installer_synthetic_tests':installed,'harfbuzz_installer_synthetic_tests':hinstalled,'racket_execution':'NOT RUN','live_skia_execution':'NOT RUN'}
print(json.dumps(result,indent=2))

from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def scan(path):
    text=path.read_text(); stack=[]; i=0; line=1
    while i<len(text):
        c=text[i]
        if c=='\n': line+=1; i+=1; continue
        if c==';':
            n=text.find('\n',i); i=len(text) if n<0 else n; continue
        if text.startswith('#|',i):
            depth=1;i+=2
            while i<len(text) and depth:
                if text.startswith('#|',i):depth+=1;i+=2
                elif text.startswith('|#',i):depth-=1;i+=2
                else: line+=text[i]=='\n';i+=1
            if depth: return f'{path.name}: unclosed block comment'
            continue
        if text.startswith('#\\',i):
            i+=2
            if i<len(text): i+=1
            while i<len(text) and text[i] not in '()[]{} \n\t\r': i+=1
            continue
        if c=='"':
            i+=1
            while i<len(text):
                if text[i]=='\\':i+=2
                elif text[i]=='"':i+=1;break
                else: line+=text[i]=='\n';i+=1
            else:return f'{path.name}:{line}: unterminated string'
            continue
        if c in '([{':stack.append((c,line))
        elif c in ')]}':
            if not stack:return f'{path.name}:{line}: unmatched {c}'
            a,l=stack.pop()
            if '([{'.index(a)!=')]}'.index(c):return f'{path.name}:{line}: {c} mismatches {a} from {l}'
        i+=1
    if stack:return f'{path.name}: unclosed {stack[-8:]}'
    return None
if __name__=='__main__':
    errors=[]
    for path in ROOT.rglob('*.rkt'):
        e=scan(path)
        if e:errors.append(e)
    print('\n'.join(errors) if errors else f'Delimiter/string scan passed for {len(list(ROOT.rglob("*.rkt")))} Racket files. This is not compilation.')
    raise SystemExit(bool(errors))

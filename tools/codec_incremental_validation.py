"""Independent native incremental progress/pixel inspector; never decodes via Skia."""
from __future__ import annotations
import hashlib
import io
import json
from pathlib import Path
import re
import struct
import zlib

PURE_CASES = 36
NATIVE_CASES = 38

def need(ok, message):
    if not ok: raise ValueError(message)
def integer(value, expected, message):
    need(type(value) is int and value == expected, message)
def flag(value, expected, message):
    need(type(value) is bool and value is expected, message)
def pairs_unique(pairs):
    out={}
    for k,v in pairs:
        need(k not in out,'duplicate JSON key: '+k);out[k]=v
    return out

def suite_output(text, name, count):
    normalized=text.replace('\r\n','\n')
    expected=f'{count} success(es) 0 failure(s) 0 error(s) {count} test(s) run'
    summaries=re.findall(r'^\d+ success\(es\) \d+ failure\(s\) \d+ error\(s\) \d+ test\(s\) run$',normalized,re.M)
    need(summaries==[expected],'missing/conflicting RackUnit completion')
    completions=re.findall(r'^codec-incremental-(?:pure|native): \d+ cases, \d+ failures$',normalized,re.M)
    need(completions==[f'{name}: {count} cases, 0 failures'],'missing/conflicting focused completion')
    need(not re.search(r'\b(?:ERROR|FAILURE)\b',normalized),'RackUnit error in successful output')

def reference(width=8,height=6):
    return bytes(v for y in range(height) for x in range(width)
                 for v in ((37*x+17*y)%256,(13*x+53*y)%256,(71*x+7*y)%256,255))

def png_parts(data):
    need(data[:8]==b'\x89PNG\r\n\x1a\n','wrong PNG signature')
    at=8;out=[]
    while at<len(data):
        need(at+12<=len(data),'truncated PNG chunk')
        n=struct.unpack_from('>I',data,at)[0]
        end=at+12+n
        need(end<=len(data),'truncated PNG chunk payload')
        tag=data[at+4:at+8];payload=data[at+8:end-4]
        need(zlib.crc32(tag+payload)==struct.unpack_from('>I',data,end-4)[0],'PNG CRC differs')
        out.append((tag,payload,end));at=end
    return out

def file_bytes(root,name):
    need(type(name) is str and re.fullmatch(r'[A-Za-z0-9-]+\.(?:pixels|png|bin)',name),'unsafe evidence filename')
    p=root/name
    need(p.is_file() and not p.is_symlink(),'missing/symlink evidence: '+name)
    return p.read_bytes()

def capture(data,width,height,stride,rows=None):
    integer(stride,44,'wrong independent stride')
    need(len(data)==stride*height,'wrong capture allocation size')
    packed=b''.join(data[y*stride:y*stride+4*width] for y in range(height))
    for y in range(height):need(data[y*stride+4*width:(y+1)*stride]==b'\0'*(stride-4*width),'row padding changed')
    if rows is not None:
        expected=reference(width,height)[:rows*width*4]+b'\0'*((height-rows)*width*4)
        need(packed==expected,'decoded rows or initialized remainder differ')
    return packed

def statistics(stats,*,decode_calls,retained,pixel_bytes=None):
    need(type(stats) is dict,'missing native session statistics')
    integer(stats.get('start-calls'),1,'incremental start was repeated or missing')
    integer(stats.get('pixel-allocations'),1,'retained destination was replaced or absent')
    integer(stats.get('decode-calls'),decode_calls,'native advance count differs')
    integer(stats.get('header-attempts'),1,'fixture unexpectedly recreated its codec')
    integer(stats.get('stream-creations'),1,'fixture has unexpected input stream count')
    integer(stats.get('stream-destructions'),0 if retained else 1,'native stream lifetime differs')
    flag(stats.get('decoder-retained?'),retained,'wrong decoder lifetime claim')
    if pixel_bytes is not None:integer(stats.get('pixel-bytes'),pixel_bytes,'wrong retained pixel byte count')

def inspect(directory,token):
    from PIL import Image
    root=Path(directory)
    p=root/'incremental.json'
    need(p.is_file() and not p.is_symlink(),'missing/symlink receipt')
    obj=json.loads(p.read_text(encoding='utf-8'),object_pairs_hook=pairs_unique)
    integer(obj.get('schema'),1,'wrong schema')
    need(obj.get('stage')=='0.76c' and obj.get('status')=='passed','wrong stage/status')
    need(obj.get('run_token')==token,'foreign execution token')
    need(obj.get('native_version')=='119.0','wrong native ABI')
    for field,value in [('sessions_closed',True),('incremental_decode_executed',True),
                        ('one_shot_fallback',False),('compiler_required',False),('gpu_executed',False)]:
        flag(obj.get(field),value,'wrong/missing claim: '+field)
    integer(obj.get('registered_sources'),0,'native memory sources leaked')
    matrices=obj.get('matrices')
    need(type(matrices) is list and len(matrices)==2,'wrong matrix count')
    need([m.get('name') for m in matrices]==['normal','adam7'],'duplicate/missing matrix')
    for matrix,height,count in zip(matrices,(6,8),(6,7)):
        name=matrix['name'];integer(matrix.get('width'),8,'wrong width');integer(matrix.get('height'),height,'wrong height')
        integer(matrix.get('row_bytes'),44,'wrong stride')
        source=file_bytes(root,name+'.png');chunks=png_parts(source)
        need([tag for tag,_,_ in chunks]==[b'IHDR']+[b'IDAT']*count+[b'IEND'],'fixture chunk framing differs')
        need(chunks[0][1][-1]==(1 if name=='adam7' else 0),'wrong PNG interlace flag')
        with Image.open(io.BytesIO(source)) as im:
            need(im.size==(8,height),'independent encoded dimensions differ')
            need(im.convert('RGBA').tobytes()==reference(8,height),'independent encoded pixels differ')
        steps=matrix.get('steps');need(type(steps) is list and len(steps)==count,'wrong progress length')
        previous=None
        for i,step in enumerate(steps,1):
            final=i==count
            need(step.get('state')==('complete' if final else 'needs-input'),'premature/absent native completion')
            need(step.get('result')==('success' if final else 'incomplete-input'),'wrong native result')
            rows=step.get('initialized_rows')
            if name=='normal':integer(rows,i,'wrong normal PNG initialized rows')
            elif final:integer(rows,height,'wrong complete Adam7 rows')
            else:need(rows is False or type(rows) is int and 0<=rows<=height,'invalid Adam7 initialized rows')
            need(step.get('pixels')==f'{name}-{i}.pixels','wrong capture name')
            packed=capture(file_bytes(root,step['pixels']),8,height,44,i if name=='normal' else (height if final else None))
            if not final:
                need(packed!=reference(8,height),'partial fixture unexpectedly identical to completion')
                need(any(packed),'partial fixture has no native pixel output')
            stats=step.get('statistics')
            statistics(stats,decode_calls=i,retained=not final,pixel_bytes=44*height)
            expected_extent=len(source) if final else chunks[i][2]
            integer(stats.get('input-bytes'),expected_extent,'wrong fed prefix size')
            integer(stats.get('visible-input-bytes'),expected_extent,'wrong visible prefix size')
            flag(stats.get('input-final?'),final,'wrong final-input marker')
            previous=packed
    short=obj.get('truncated',{})
    need(short.get('state')=='incomplete' and short.get('result')=='incomplete-input','final truncation was not terminal incomplete')
    integer(short.get('initialized_rows'),2,'wrong truncated row count')
    need(short.get('pixels')=='truncated.pixels','missing truncated capture')
    capture(file_bytes(root,'truncated.pixels'),8,6,44,2)
    short_source=file_bytes(root,'truncated.png');chunk_rows=png_parts(short_source)
    need([t for t,_,_ in chunk_rows]==[b'IHDR',b'IDAT',b'IDAT'],'wrong truncated fixture')
    need(file_bytes(root,'normal.png').startswith(short_source),'truncated fixture is not the checked source prefix')
    statistics(short.get('statistics'),decode_calls=1,retained=False,pixel_bytes=264)
    flag(short['statistics'].get('input-final?'),True,'truncated input was not sealed')
    unsupported=obj.get('unsupported',{})
    need(unsupported.get('state')=='failed' and unsupported.get('result')=='unimplemented','unsupported mode hidden or bypassed')
    flag(unsupported.get('pixels'),False,'unsupported decode has a pixel capture')
    statistics(unsupported.get('statistics'),decode_calls=0,retained=False)
    cancelled=obj.get('cancelled',{})
    need(cancelled.get('state')=='cancelled' and cancelled.get('result')=='cancelled','cancellation missing')
    flag(cancelled.get('pixels'),False,'cancelled decode has a pixel capture')
    statistics(cancelled.get('statistics'),decode_calls=1,retained=False,pixel_bytes=0)
    need(file_bytes(root,'live-copy.bin')==bytes(range(256)),'live-port coexistence copy differs')
    return dict(status='passed',stage='0.76c',run_token=token,partial_captures=11,final_captures=2,
                framing='complete PNG chunks; native decoder retained after start',
                files={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.iterdir()) if p.is_file()})

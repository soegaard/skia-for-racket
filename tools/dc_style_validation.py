"""Independent semantic probes for 0.57 styles. Never equates Cairo/Skia edges."""
from __future__ import annotations
import math
from pathlib import Path
import dc_validation as d
PURE_CASES, NATIVE_CASES, MATH_CASES = 24, 40, 45
SIZE = (64, 64)
MODES = ('direct', 'procedure', 'datum', 'reference')
TOLERANCE = 3
REPLAY_TOLERANCE = 2

def filename(mode):
    return f'dc-style.{mode}.png'

def probes(mode='direct'):
    # These expectations are specified independently of the renderer and its
    # reported pixels. Linear gradients sample at pixel centers.
    result = []
    for x in (0, 4, 11, 15):
        t = (x + .5) / 16
        result.append((x, 8, (round(255*(1-t)), 0, round(255*t), 255)))
    result.extend(((20, 4, (255,0,0,255)), (21,4,(0,255,0,255)), (20,5,(0,0,255,255)),
                   (36,3,(255,0,0,255)), (36,4,(255,255,255,255)),
                   (52,4,(178,178,178,255)),
                   (34,18,(0,0,255,255)), (35,18,(255,255,255,255)),
                   (50,18,(0,0,255,255)), (51,18,(255,200,0,255)),
                   (36,36,(255,128,128,255)), (52,36,(255,0,0,255))))
    # The public bitmap contract says backing scale applies when a bitmap is
    # drawn into another context. Skia and both replay paths therefore require
    # the logical 2x2 stipple period. The pinned bitmap-dc%/Cairo reference
    # instead repeats the physical 4x4 surface on macOS; keep that backend
    # quirk as review evidence, not as the semantic oracle for skia-dc%.
    if mode != 'reference':
        result.append((53,36,(0,255,0,255)))
    t = math.sqrt(.5**2+.5**2)/8
    result.append((8,24,(round(255*(1-t)),0,round(255*t),255)))
    result.append((20,40,(round(255*(1-4.5/16)),0,round(255*4.5/16),255)))
    return result

def inspect_styles(directory, identity):
    directory = Path(directory)
    path = directory/'dc-styles.json'
    d.require(path.is_file() and not path.is_symlink(), 'missing/symlinked style report')
    raw = d.read_json(path)
    d.require(d.exact(raw.get('schema'),1) and raw.get('stage') == '0.57', 'wrong style schema/stage')
    d.require(raw.get('status') == 'passed' and raw.get('validation_run') == directory.name, 'failed/stale style run')
    for key, want in (('pure_cases',PURE_CASES),('native_cases',NATIVE_CASES),('math_cases',MATH_CASES),
                      ('pure_failures',0),('native_failures',0)):
        d.require(d.exact(raw.get(key),want), f'incomplete style test evidence: {key}')
    for k in ('gui_initialized','gpu_execution_verified','full_drop_in_compatibility',
              'cairo_drawing_fallback','reference_pixel_equivalence_claimed'):
        d.require(raw.get(k) is False, f'unsupported style claim: {k}')
    d.require(raw.get('region_query_scratch_context') is True, 'missing query-only Cairo disclosure')
    d.require(raw.get('snapshots_encoded_after_dc_close') is True, 'missing post-close style encoding')
    for k, source in (('os','os'),('architecture','architecture'),('racket_version','version')):
        d.require(raw.get(k) == identity[source], f'foreign style interpreter: {k}')
    names = [filename(mode) for mode in MODES]
    d.require(raw.get('captures') == names, 'missing/reordered style capture list')
    images, receipts = {}, []
    for mode, name in zip(MODES,names):
        path = directory/name
        d.require(path.is_file() and not path.is_symlink(), 'missing/symlinked style capture')
        pixels = d.png_rgba(path,SIZE)
        for x,y,want in probes(mode):
            i=4*(y*SIZE[0]+x)
            d.require(all(abs(a-b)<=TOLERANCE for a,b in zip(pixels[i:i+4],want)),
                      f'{name}: independent style probe failed at ({x},{y})')
        # A stippled pen must remain continuous for the selected solid style. The color differs periodically but there must be no white gaps.
        for x in range(2,30):
            i=4*(56*64+x)
            d.require(min(pixels[i:i+3]) < 40 and pixels[i+3] == 255, f'{name}: stippled pen has a gap')
        images[mode] = pixels
        receipts.append(dict(file=name,width=64,height=64,sha256=d.sha256(path)))
    for mode in ('procedure','datum'):
        d.require(all(abs(a-b)<=REPLAY_TOLERANCE for a,b in zip(images['direct'],images[mode])),
                  f'style {mode} replay mismatch')
    reference_error=max(abs(a-b) for a,b in zip(images['direct'],images['reference']))
    return dict(status='passed',pure_cases=PURE_CASES,native_cases=NATIVE_CASES,math_cases=MATH_CASES,
                independent_style_probes_verified=True,probe_channel_tolerance=TOLERANCE,
                replay_channel_tolerance=REPLAY_TOLERANCE,reference_max_channel_difference=reference_error,
                reference_pixel_equivalence_claimed=False,captures=receipts)

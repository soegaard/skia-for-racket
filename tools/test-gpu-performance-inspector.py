#!/usr/bin/env python3
"""Synthetic reports only; no Racket, GPU, or hardware performance is measured."""
from __future__ import annotations
import copy, importlib.util, json, struct, tempfile, unittest, zlib
from pathlib import Path
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('perf_inspector',HERE/'inspect-gpu-performance.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

def config():return dict(samples=3,warmup=1,frames=60,cycles=3,width=128,height=128,sample_count=0,checkpoint_interval=30,
 cache_limit_bytes=32*1024**2,cache_growth_allowance_bytes=16*1024**2,cache_growth_allowance_resources=64,cpu_pressure_bytes=4*1024**2)
def ctx(gen,backend='opengl',state='ready',live=0):
 return dict(backend=backend,generation=gen,state=state,live_children=live,pending_releases=0,failed_releases=0,shutdown_requested=False,
  native_backend=0 if backend=='opengl' else 2,binding_package='3.119.1',native_version='119.0',renderer='Synthetic fixture',renderer_class='software',
  api_version='Synthetic API',vendor='Synthetic',owns_command_queue=backend=='metal')
def cache(gen,backend='opengl'):
 return dict(backend=backend,context_generation=gen,limit_bytes=32*1024**2,budgeted_resources=2,budgeted_bytes=100,
             total_gpu_bytes=False,purgeable_bytes=False,limit_is_hard_allocation_cap=False)
def one():return dict(start_ms=10,end_ms=11,elapsed_ms=1,host_cpu_ms=1,gc_cpu_ms=0)
def completion(upload=False):
 r=dict(timepoints_ms=[10,11,12,13,14],draw_ms=1,flush_ms=1,submit_ms=1,completion_wait_ms=1,completed_ms=4,
        host_cpu_ms=1,gc_cpu_ms=0,completion='explicit CPU synchronization')
 r['io_events']=([dict(kind='upload')] if upload else [])+[dict(kind='flush'),dict(kind='submit',wait_requested=False),dict(kind='flush'),dict(kind='submit',wait_requested=True)]
 return r

def png(directory,name):
 def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
 pixels=bytearray(bytes([0,140,190,255])*128*128)
 for x in range(1,127):pixels[x*4:x*4+4]=b'\0'*4
 for x,y,col in [(0,0,(255,0,0,255)),(127,0,(0,255,0,255)),(0,127,(0,0,255,255)),(127,127,(255,255,0,255))]:
  off=(y*128+x)*4;pixels[off:off+4]=bytes(col)
 data=b''.join(b'\0'+pixels[y*512:(y+1)*512] for y in range(128))
 (directory/name).write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',128,128,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(data))+chunk(b'IEND',b''))

def base(kind,backend):
 return dict(schema_version=1,stage='0.45',kind=kind,status='passed',backend=backend,validation_run='synthetic-run',os='unix',architecture='x86_64',
  racket_version='synthetic',clock='current-inexact-monotonic-milliseconds',performance_measured=True,speedup_claimed=False,display_latency_measured=False,
  isolated_gpu_timestamps=False,total_gpu_memory_measured=False,config=config(),require_hardware=False,visible_pixels_verified=False,
  workload_sources=[dict(path=p,sha1='a'*40) for p in m.SOURCE_PATHS])
def performance(directory,backend='opengl'):
 r=base('performance',backend);r.update(native_test_cases=20,native_test_failures=0,cache_symbols=[dict(name=n,available=True) for n in m.CACHE_SYMBOLS],scenes=[],cycles=[])
 for gen,name in enumerate(m.SCENES,1):
  uploads=[]
  for i in range(3):
   u=completion(True);u.update(fresh_cpu_identity=True,pixels_verified=True,width=128,height=128,bytes=65536,
    image=dict(texture_backed=True,storage='gpu',context_matches=True,backend=backend,context_generation=gen));uploads.append(u)
  reads=[]
  for i in range(3):
   x=one();x.update(bytes=65536,source_precompleted=True,pixels_verified=True,io_events=[dict(kind='readback'),dict(kind='flush'),dict(kind='submit',wait_requested=True)]);reads.append(x)
  s=dict(name=name,scene_version='gpu-scenes-0.39/v1',logical_size=[420,260],initial_context=ctx(gen,backend),closed_context=ctx(gen,backend,'closed'),encoded_after_teardown=True,
   isolated_driver_compile_ms=False,warmup_completed=1,warmup_replay=[completion()],first_use=completion(),warm_replay=[completion() for _ in range(3)],upload=uploads,readback=reads,
   authoring_recording=[one() for _ in range(3)],cpu_raster=[one() for _ in range(3)],sksl_effect_construction=[one() for _ in range(3)] if name=='runtime' else [],
   cache_after=cache(gen,backend),cpu_image=name+'.cpu.png',gpu_image=name+'.gpu.png',target=dict(storage='gpu',context_matches=True,backend=backend,context_generation=gen,
   native_backend=0 if backend=='opengl' else 2,width=128,height=128,origin='top-left',render_path='sk_surface_new_render_target',requested_sample_count=0,actual_sample_count=False))
  png(directory,s['cpu_image']);png(directory,s['gpu_image']);r['scenes'].append(s)
 for i in range(3):
  gen=10+i;c=dict(index=i,frames=60,initial_context=ctx(gen,backend),closed_context=ctx(gen,backend,'closed'),baseline_cache=cache(gen,backend),
   content_verified=True,final_pixel_samples=[[255,0,0,255],[0,255,0,255],[0,0,255,255],[255,255,0,255]],intentional_gc_wrappers=6,max_observed_live_children=4,checkpoints=[])
  for j in range(2):
   ca=cache(gen,backend);ca['limit_bytes']=0 if j==0 else 32*1024**2
   c['checkpoints'].append(dict(frame=30*(j+1),context=ctx(gen,backend,live=1),cache=ca,heap_bytes=1000,weak_wrappers_retired=True,
     resident_io=[e for _ in range(30) for e in [dict(kind='flush'),dict(kind='submit',wait_requested=False)]]))
  r['cycles'].append(c)
 return r

def presentation_row(index,gen,backend,size):
 r=one();r.update(callback=one(),frame_expired=True,canvas_expired=True,io_events=[dict(kind='flush'),dict(kind='submit',wait_requested=False),dict(kind='present-request',wait_requested=False)])
 r['frame']=dict(backend=backend,frame_index=index,pixel_width=size,pixel_height=size,logical_width=size,logical_height=size,scale_x=1,scale_y=1,visible=True,drawable=True,
  target=dict(storage='gpu',backend=backend,context_generation=gen,native_backend=0 if backend=='opengl' else 2,context_matches=True,width=size,height=size,
              actual_sample_count=0 if backend=='opengl' else 1,render_path='sk_surface_new_backend_render_target',origin='bottom-left' if backend=='opengl' else 'top-left'))
 return r

def redraw(backend='opengl'):
 r=base('redraw',backend);r['windows']=[]
 for n in range(6):
  gen=n+1;windows=dict(cycle=n//2,window=n%2,initial_context=ctx(gen,backend),baseline_cache=cache(gen,backend),warmup=presentation_row(1,gen,backend,128),frames=[],checkpoints=[],render_callbacks=63,retry_skips=0)
  for i in range(60):windows['frames'].append(presentation_row(2+i+(i//30),gen,backend,128 if i<30 else 168))
  for j in range(2):
   windows['checkpoints'].append(dict(frame=30*(j+1),context=ctx(gen,backend),cache=cache(gen,backend),heap_bytes=1000,queued_requests=4,queued_callbacks=1,
    presenter=dict(last_error=False,frames_cancelled=0,adapter=dict(live_drawables=0,quarantined_frames=0,pending_presentation_buffers=1))))
  windows['closed_presenter']=dict(state='closed',presents_requested=63,adapter=dict(context=ctx(gen,backend,'closed'),live_drawables=0,owns_host_framebuffer=False,layer_closed=True,pending_presentation_buffers=0,quarantined_frames=0))
  r['windows'].append(windows)
 return r

class Checks(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.directory=Path(self.temp.name);self.r=performance(self.directory)
 def tearDown(self):self.temp.cleanup()
 def bad(self,fn,r=None):
  r=copy.deepcopy(self.r if r is None else r);fn(r)
  with self.assertRaises((ValueError,KeyError,TypeError)):m.validate(r,self.directory)
 def test_opengl(self):self.assertEqual(m.validate(self.r,self.directory)['status'],'passed')
 def test_metal(self):self.assertEqual(m.validate(performance(self.directory,'metal'),self.directory)['status'],'passed')
 def test_redraw(self):self.assertEqual(m.validate(redraw(),self.directory)['fresh_contexts_checked'],6)
 def test_metal_redraw(self):self.assertEqual(m.validate(redraw('metal'),self.directory)['status'],'passed')
 def test_unavailable(self):self.bad(lambda r:r.update(status='unavailable'))
 def test_native_failure(self):self.bad(lambda r:r.update(native_test_failures=1))
 def test_false_failures(self):self.bad(lambda r:r.update(native_test_failures=False))
 def test_coverage(self):self.bad(lambda r:r.update(native_test_cases=19))
 def test_symbol(self):self.bad(lambda r:r['cache_symbols'][0].update(available=False))
 def test_time_regression(self):self.bad(lambda r:r['scenes'][0]['first_use'].update(timepoints_ms=[10,9,12,13,14]))
 def test_false_timing(self):self.bad(lambda r:r['scenes'][0]['first_use'].update(completed_ms=False))
 def test_nan(self):self.bad(lambda r:r['scenes'][0]['first_use'].update(completed_ms=float('nan')))
 def test_inconsistent_sum(self):self.bad(lambda r:r['scenes'][0]['first_use'].update(completed_ms=3))
 def test_completion_not_submission(self):self.bad(lambda r:r['scenes'][0]['first_use']['io_events'][-1].update(wait_requested=False))
 def test_resident_readback(self):self.bad(lambda r:r['scenes'][0]['warm_replay'][0]['io_events'].insert(0,dict(kind='readback')))
 def test_fresh_upload(self):self.bad(lambda r:r['scenes'][0]['upload'][0].update(fresh_cpu_identity=False))
 def test_upload_foreign(self):self.bad(lambda r:r['scenes'][0]['upload'][0]['image'].update(context_generation=99))
 def test_readback_prewait(self):self.bad(lambda r:r['scenes'][0]['readback'][0].update(source_precompleted=False))
 def test_readback_pixels_required(self):self.bad(lambda r:r['scenes'][0]['readback'][0].update(pixels_verified=False))
 def test_false_warmup_count(self):self.bad(lambda r:r['scenes'][0].update(warmup_completed=True))
 def test_source_fingerprint(self):self.bad(lambda r:r['workload_sources'][0].update(sha1='not-a-hash'))
 def test_wrong_readback_size(self):self.bad(lambda r:r['scenes'][0]['readback'][0].update(bytes=4))
 def test_actual_samples_not_invented(self):self.bad(lambda r:r['scenes'][0]['target'].update(actual_sample_count=0))
 def test_warmup(self):self.bad(lambda r:r['scenes'][0].update(warmup_completed=0))
 def test_samples(self):self.bad(lambda r:r['scenes'][0]['warm_replay'].pop())
 def test_cpu_scene_missing(self):self.bad(lambda r:r['scenes'].pop())
 def test_compile_is_not_isolated(self):self.bad(lambda r:r['scenes'][2].update(isolated_driver_compile_ms=1))
 def test_unsafe_path(self):self.bad(lambda r:r['scenes'][0].update(cpu_image='../escape.png'))
 def test_corrupt_png(self):
  (self.directory/'paths.gpu.png').write_bytes(b'broken')
  with self.assertRaises(ValueError):m.validate(self.r,self.directory)
 def test_context_leak(self):self.bad(lambda r:r['cycles'][0]['closed_context'].update(live_children=1))
 def test_reused_context(self):self.bad(lambda r:r['cycles'][1].update(initial_context=r['cycles'][0]['initial_context']))
 def test_gc(self):self.bad(lambda r:r['cycles'][0]['checkpoints'][0].update(weak_wrappers_retired=False))
 def test_memory_envelope(self):self.bad(lambda r:r['cycles'][0]['checkpoints'][0]['cache'].update(budgeted_bytes=10**12))
 def test_pressure(self):self.bad(lambda r:r['cycles'][0]['checkpoints'][0]['cache'].update(limit_bytes=32*1024**2))
 def test_total_vram(self):self.bad(lambda r:r['scenes'][0]['cache_after'].update(total_gpu_bytes=1234))
 def test_render_pressure_content(self):self.bad(lambda r:r['cycles'][0].update(content_verified=False))
 def test_normal_stress_wait(self):self.bad(lambda r:r['cycles'][0]['checkpoints'][0]['resident_io'][1].update(wait_requested=True))
 def test_queued_count(self):self.bad(lambda r:r['windows'][0]['checkpoints'][0].update(queued_callbacks=4),redraw())
 def test_presenter_wait(self):self.bad(lambda r:r['windows'][0]['frames'][0]['io_events'][1].update(wait_requested=True),redraw())
 def test_expired_frame(self):self.bad(lambda r:r['windows'][0]['frames'][0].update(frame_expired=False),redraw())
 def test_pending_buffer(self):self.bad(lambda r:r['windows'][0]['closed_presenter']['adapter'].update(pending_presentation_buffers=1),redraw('metal'))
 def test_screen_claim(self):self.bad(lambda r:r.update(visible_pixels_verified=True),redraw())
 def test_hardware_not_assumed(self):self.bad(lambda r:r.update(require_hardware=True))
 def test_display_latency_not_assumed(self):self.bad(lambda r:r.update(display_latency_measured=True))
 def test_publication(self):
  prefix=self.directory/'benchmark';Path(str(prefix)+'.diagnostic.json').write_text(json.dumps(self.r));m.publish(prefix)
  self.assertIn('host latency',Path(str(prefix)+'.review.html').read_text());self.assertGreater(len(Path(str(prefix)+'.samples.csv').read_text().splitlines()),30)
 def test_failure_removes_stale_pass(self):
  prefix=self.directory/'benchmark';p=Path(str(prefix)+'.diagnostic.json');p.write_text(json.dumps(self.r));m.publish(prefix)
  self.r['native_test_failures']=1;p.write_text(json.dumps(self.r))
  with self.assertRaises(ValueError):m.publish(prefix)
  self.assertFalse(Path(str(prefix)+'.inspection.json').exists());self.assertFalse(Path(str(prefix)+'.review.html').exists())
 def test_statistics(self):
  s=m.statistics_row('x','y',list(range(1,21)));self.assertEqual(s['p95'],19);self.assertEqual(s['median'],10.5)
if __name__=='__main__':unittest.main(argv=['test-gpu-performance-inspector'],verbosity=2)

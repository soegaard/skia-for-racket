# GPU measurements and release stress — 0.45

This stage supplies measurements, not a claim that GPU rendering is always
faster. Run the supplied tools on the intended hardware. Synthetic inspector
and runner tests are not benchmark results. The baseline is 0.44 commit
`4304856a73dc8087d5962963428f37a84cbc8a21`; Linux EGL host acceptance remains
deferred to future GitHub Actions CI.

## Workloads and timing boundaries

`tools/gpu-performance-doctor.rkt` measures three deterministic existing scenes:
paths, text and runtime SkSL. They are authored at the shared 420x260 logical
size and recorded at the requested output extent (default 640x400). Each scene
gets a new Ganesh context. The native version, driver/API/vendor strings,
renderer class, context generation, target dimensions, color type and requested
sampling are recorded. The owned target's actual sample count remains unknown:
the pinned C API does not expose it. No universal CPU/GPU byte identity is assumed.

* **Authoring/recording:** callback resource creation and picture recording,
  measured separately from later picture replay. Disposal is outside this timer.
* **SkSL effect construction:** a deterministic native runtime-effect constructor,
  measured on the host. It is not isolated driver shader compilation.
* **First replay:** first completed picture replay in that fresh Ganesh context.
  Operating-system and driver caches are uncontrolled. This timing can include
  backend pipeline compilation, but does not isolate or label it as compile time.
* **Warm replay:** warmup iterations run to completion and are stored separately;
  measured iterations provide draw, flush, no-wait submit, final completion wait,
  and their continuous total. Warmup and first-use are excluded from steady-state
  summaries. All five timepoints are retained and checked.
* **CPU raster:** the same picture into a CPU surface, without encoding. It is a
  different execution workload, not a submission-time comparison or automatic
  GPU speedup ratio.
* **Upload:** a fresh 128x128 CPU image identity per sample prevents a repeated
  cached image from impersonating a fresh upload. Construction of the CPU source
  is outside the timer; GPU creation, submission and completion are inside.
  A separate untimed readback checks exact pixels before disposal.
* **Readback:** source work is completed before the timer; the public readback's
  own synchronization, allocation and CPU copying are inside. This is not pure
  DMA bandwidth. Every sample is compared against an untimed read of the same
  unchanged GPU source. Encoding occurs outside timing and after context teardown.

The clock is `current-inexact-monotonic-milliseconds`. Timings are **instrumented
host wall latency**, including wrapper/trace overhead and possible scheduling or
backpressure. There are no hardware GPU timestamps. CPU and GC counters are
process-wide counters, potentially including other Racket threads; they are
not subtracted from wall latency. Trace dictionaries and raw samples are retained
so a report can be inspected rather than trusting a median alone.

The reports also record source-byte fingerprints for the scene and measurement
modules, so changes in a workload need not be confused with driver regressions.
These SHA1 values are reproducibility labels, not security attestations.

Every sample is in JSON and CSV. The inspector recomputes count, min, median,
nearest-rank p95, max and mean from raw observations. No performance threshold
is used as a correctness gate; a slower machine should still pass correct work.
Run different resolutions/sampling configurations in separate directories and
compare equivalent workloads and completion boundaries only.

## Bounded release stress

Default offscreen stress recreates three contexts, each drawing 180 frames.
Each frame constructs an image/shader/paint/picture graph, closes the original
wrappers, and replays the retained picture. Every tenth frame intentionally
drops a snapshot wrapper to exercise finalization. Every 30 frames is an explicit
checkpoint: complete submitted work, allocate and drop 4 MiB of CPU pressure,
collect/drain, verify weak references have cleared, alternate the cache budget
between zero and 32 MiB, purge, and inspect the state.

Checkpoint invariants are one persistent target wrapper, no pending or failed
releases, no shutdown request, and budgeted cache usage within a recorded warmed
baseline plus 16 MiB / 64 resources. All temporary wrappers must retire within a
bounded 5-second GC/drain poll. Final sample colors are checked before complete
teardown. New context generations must be distinct.

These are bounds on live application wrappers and **budgeted** cache resources,
not proof of bounded total VRAM, process RSS or driver allocations. Racket managed
memory is logged diagnostically; the report's own retained timing rows consume
memory. Pressure is bounded application allocation and cache-budget pressure,
not forced operating-system OOM, GPU reset, or device-loss simulation.

## Sustained window redraw

`tools/gpu-redraw-doctor.rkt` uses the existing shared presenter callback on two
simultaneous windows per cycle, three recreated pairs by default. Each window
gets 180 directly measured frames, a warmup frame, six coalesced queued redraws,
and periodic resizes. Closing the first window leaves the second usable.
The callback constructs its drawing resources normally: this is application
redraw latency, not the cached-picture benchmark above.

The tool measures the complete host `gpu-presenter-render!` call and its drawing
callback separately. The former includes drawable acquisition, submission,
swap/present request and backpressure; it is **not display latency, vsync timing,
GPU completion time, or an FPS guarantee**. Raw direct-frame traces must contain
flush -> no-wait submit -> present request, with no CPU readback or completion
wait. Intentional sleeps for queued callbacks are not rendering samples.
Cache purge/wait and GC checkpoints, and final teardown, are outside normal-frame
timings. Expired frames/canvases, bounded pending Metal presentation buffers,
no quarantine, independent context generations and complete closure are checked.

The automated report does not certify physical display pixels. The accepted
0.42 manual check remains historical evidence; visible behavior on any newly
used platform still deserves inspection.

See [cache contracts](GPU-CACHE.md) and [validation commands](GPU-PERFORMANCE-TESTING.md).

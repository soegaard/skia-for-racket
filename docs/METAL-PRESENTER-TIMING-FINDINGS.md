# Metal presenter timing: windowed drawable waits

Investigation date: 2026-10-25.

Long windowed `nextDrawable` waits disappeared in a verified quiet-desktop run
without changing the game, window size, or rendering policy. The evidence is
consistent with desktop compositor workload delaying drawable availability
after the game's GPU work has finished. It does not establish that window
count alone is responsible, identify a particular application, or prove an
ownership defect in Skia or Racket.

The investigation stopped at that practical conclusion. The proposed
application-by-application experiment was not performed. No new frame pacing,
GPU completion wait, rendering thread, or presentation policy was introduced.
See [diagnostic usage](GPU-PRESENTATION.md#opt-in-metal-presenter-timing) and
[test coverage](GPU-PRESENTATION-TESTING.md) for the instrumentation committed
with this report.

## Workload and comparison method

The workload was the local International Karate + stage-12 example on an
Apple Silicon MacBook Pro, with macOS 26.5, Racket 9.3.0.2, and Instruments
26.0. Only one game instance was running. The game used its existing windowed
GPU/Metal renderer and restart control; its drawing and simulation code were
not edited. Its source SHA-256 remained
`4cc30e75ffe9c27071b93b88721a849ed3d74d9c928d6dd25f31d366b23a01eb`.

Both captures used:

- a 980 by 632 logical-unit window target, at scale 2, giving 1960 by 1264 pixels;
- `SKIA_METAL_PRESENTER_TIMING=1`, `SKIA_METAL_COCOA_TRACE=1`, and `SKIA_GC_TRACE=1`;
- both layer-update experiments explicitly disabled;
- buffered presenter, layer-state, Cocoa, GUI, and individual-GC records;
- Metal System Trace for GPU completion, Core Animation waits, and display events.

The comparison includes calls beginning in the five seconds after the restart
event, with each call's full duration. Startup and restart GC are excluded from
that sample. Neither capture dropped diagnostic records. Native timestamps
were aligned with the capture's start time. GPU completion, the presentation
request, the presentation notification, and actual display were examined
separately; none is interchangeable with another.

For the quiet capture, other applications' windows were hidden, not suspended.
Periodic window-metadata samples during gameplay showed only the game window.
The game remained visible and key, and native display records confirmed that
it was still **windowed and composited**, not using direct-to-display output.
An earlier, partially hidden desktop still had other visible windows and was
excluded as a fully quiet control.

## Matched five-second results

| Measurement | Previous desktop | Verified quiet desktop |
| --- | ---: | ---: |
| Acquired/rendered frames | 175 | 247 |
| `nextDrawable` calls longer than 20 ms | 19 | 0 |
| Acquisition duration, 95th percentile | 80.073 ms | 0.085 ms |
| Longest acquisition | 363.441 ms | 0.124 ms |
| Game drawing callback, 95th percentile | 1.127 ms | 1.267 ms |
| Present call to actual display, 95th percentile | 267.663 ms | 25.872 ms |
| Longest matched present-to-display delay | 594.017 ms | 85.546 ms |
| WindowServer recorded GPU-active interval coverage | 583.513 ms | 63.272 ms |
| WindowServer command execution span, 95th percentile | 16.660 ms | 0.261 ms |

The display-delay statistics matched 173 of the 175 baseline frames and all
247 quiet frames. WindowServer's GPU-active figure is the union of recorded
active intervals, avoiding double-counting overlapping engines. It is not a
measurement of complete hardware utilization. A command's execution span may
also include gaps between its recorded GPU work.

Across the entire quiet capture, all 517 acquisitions finished within 1 ms.
Three sampled frames still took approximately 52–86 ms from the present call
to actual display, but none blocked drawable acquisition. The result therefore
does not mean every quiet-desktop frame was presented without delay.

## What the stalled capture showed

In 16 of the 19 long acquisitions, all earlier game GPU work had completed
before the wait started. In the other three it completed within 0.287 ms of
the start. The drawing callback and layer updates were short; the long interval
was inside `nextDrawable` and matched Core Animation's native buffer wait.

For the buffer returned by the longest acquisition:

| Event for that buffer's previous frame | Relative to acquisition-wait start |
| --- | ---: |
| Application drawable reference released | about −58 ms |
| Presentation command completed on GPU | about −58 ms |
| WindowServer reads the buffer for composition | about +343 ms |
| Frame reaches the display | about +358 ms |
| `nextDrawable` returns | about +363 ms |

Eighteen of the 19 waits ended within 6 ms of the presentation notification
for the previous use of the same underlying image buffer. One wait concerned
a frame whose presentation notification had already occurred: notification
does not guarantee immediate buffer reuse.

WindowServer performed substantial composition work during the longest wait.
However, recorded activity across all GPU processes covered only about 105 ms
of that 363 ms interval. The trace does not justify attributing the entire
delay to a saturated GPU, nor does it identify the application responsible for
the compositor work. A separate WindowServer CPU/scheduling capture was not
collected after the quiet control, because the original drawable-acquisition
stalls no longer reproduced there.

## Other explanations checked

- **Layer changes:** model geometry remained stable. Separate opt-in runs that
  skipped unchanged setters, then also empty update transactions, still had
  drawable stalls. Neither experiment is an established fix.
- **Visibility:** the game was visible, key, and not minimized in the measured
  runs. `presentsWithTransaction` was false and display synchronization was on.
- **GC:** the baseline sample contained 26 minor collections totalling about
  12.37 ms, with none overlapping drawable acquisition. The major restart
  collection ended before the sample. GC did not explain these waits.
- **Racket flush suspension:** boundary observations reported no active flush
  suspension. The main Core Foundation run loop made no observed progress
  inside the blocking acquisitions, which does not establish that lack of
  event progress caused them.
- **Local ownership:** native calls already have autorelease pools. Each frame
  closes its Skia surface, deletes the target descriptor, and releases its
  explicit drawable reference. In the baseline sample, this local retirement
  finished within 2.19 ms of the present call. A zero local lease count does
  not enumerate every internal Skia or Apple reference.
- **Fullscreen:** an earlier clean fullscreen capture had no comparable long
  waits and used direct-to-display output. That comparison changed the display
  path; the quiet windowed control shows that fullscreen is not required to
  avoid the waits.

Isolated native Metal ownership probes also distinguished drawable objects
from their backing buffers. Holding 40 completed presentation command buffers
did not keep their drawable objects alive. Holding 40 already-presented
drawable objects reused two backing image buffers, with a maximum acquisition
time of 0.71 ms. Holding unpresented drawable objects instead allocated 40
backing buffers; it did not exhaust a hard three-object pool in that probe.
These probes did not use Skia and do not establish portable lifetime behavior.
They do not relax the presenter's prompt-release and ownership requirements.

## Scope and evidence

The practical finding is that desktop composition can delay buffer reuse even
when the application's drawing is fast. A single quiet capture cannot isolate
the responsible desktop content or establish that the number of windows alone
causes the problem. Background application work continued, and the captures
were made at different times. No application-specific conclusion is claimed.

Default rendering remains unchanged: timing and Cocoa tracing require their
own opt-ins and interested receivers; GC tracing is a developer collector,
not part of the rendering path. Both layer-update experiments remain off by
default. The code adds no normal-frame GPU wait, readback, retry, event pumping,
simulation change, or resource-limit change.

Raw traces, diagnostic launchers, and analysis outputs remain local in
`output/metal-presenter-timing/`; the game and those large artifacts are not
part of this commit. The principal local evidence files are:

- `ikplus-windowed-gc-state-system.trace` and `ikplus-windowed-gc-state.json`;
- `ikplus-windowed-quiet-verified-system.trace` and its matching JSON capture;
- `windowed-buffer-ownership-analysis.json` and `quiet-desktop-comparison.json`;
- `windowed-quiet-verified-desktop-observations.jsonl` for the periodic visibility checks.

The JSON capture SHA-256 values are
`862f05f4e81a4f5c6f596b2a02cbe869bc0747d7d893df316b3feb438e2084f4`
(baseline) and
`6d2500f403d5065b57b0ee793014ea0511de2689d2cb343b33804112d63dd7e0`
(verified quiet desktop). These measurements are observations from this host,
not performance guarantees, automated timing-test thresholds, or release
certification for other hosts or backends.

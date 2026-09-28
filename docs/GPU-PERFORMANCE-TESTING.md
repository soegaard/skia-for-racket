# GPU 0.45 validation and measurement

Run the ordinary selected-interpreter validator after applying this stage:

```bash
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACKET="$RACKET" bash tools/validate-gpu.sh
```

Every previous CPU/GPU/presentation/interop/document check remains selected.
After those, the desktop runner executes cache tests, benchmarks and offscreen
release stress on each selected backend, then sustained window redraw on that
backend. macOS selects OpenGL and Metal; other desktop platforms select OpenGL.
All dynamically loaded modules are included in the selected Racket's compilation.

Results use a fresh `output/gpu-0.45-*/` directory. New reviews are
`performance-opengl.review.html`, `performance-metal.review.html`,
`redraw-opengl.review.html`, and `redraw-metal.review.html`, each with diagnostic
JSON, independently checked inspection JSON and individual-sample CSV. Benchmark
reviews additionally contain CPU/GPU PNGs for paths, text and runtime effects.
The inspector requires actual resource/trace/PNG evidence, not merely a successful
exit code or summary. Output is published atomically per file, the success marker
last; failed inspection removes stale review/inspection/CSV results.

Source suites add **30 cache pure + 16 timing/configuration pure cases**, and
**20 cache-native cases per backend**. The sustained frame loops are workloads,
not extra RackUnit cases. The C mirror checks scalar/output-slot ABI assumptions,
not execution of the native library. Python runner/inspector tests are synthetic.

## Focused reruns and longer measurements

```bash
"$RACKET" tools/gpu-performance-doctor.rkt --backend metal \
  --prefix output/performance-metal-long --samples 40 --warmup 5 \
  --frames 1200 --cycles 5 --width 1280 --height 800
python3 tools/inspect-gpu-performance.py --probe-prefix output/performance-metal-long

"$RACKET" tools/gpu-redraw-doctor.rkt --backend metal \
  --prefix output/redraw-metal-long --frames 1200 --cycles 5
python3 tools/inspect-gpu-performance.py --probe-prefix output/redraw-metal-long
```

Substitute `opengl` for the other desktop backend. Longer redraw runs can take
minutes because swaps/drawable acquisition may apply backpressure. The validator
passes these environment settings unchanged to both doctors:
`GPU_BENCH_SAMPLES`, `GPU_BENCH_WARMUP`, `GPU_STRESS_FRAMES`, `GPU_STRESS_CYCLES`,
`GPU_BENCH_WIDTH`, `GPU_BENCH_HEIGHT`, and `GPU_BENCH_SAMPLE_COUNT`. Dimensions and
sampling control offscreen targets; window dimensions are requested logical GUI
sizes, and actual framebuffer dimensions/sampling are queried per frame.
To bound raw-report retention, frames times cycles cannot exceed 30000.
Frames must be a multiple of 30; the minimum smoke configuration still uses
three contexts, sixty frames per cycle and three timed samples. Budget/growth
allowances are explicit fixed values in the configuration, not learned from a
failing run. Unsupported sample requests fail; they do not select a hidden CPU
or alternate GPU backend.

`GPU_MODE=off` compiles the source and runs CPU/pure/self-tests but makes no live
performance claim. Optional mode permits only initial backend unavailability;
after initialization, native test, timing, lifetime, pixel or inspection failures
remain failures. `REQUIRE_HARDWARE=1` reaches both new doctors. Software
renderers can establish functional behavior but not hardware acceleration.
No comparison against a synthetic timing fixture counts as a hardware result.

## Future headless CI

The Linux runner is wired to the same performance/cache/offscreen release work
using `--host egl` and its explicit platform/device/surface parameters. It removes
all display variables and never compiles or invokes the redraw/window doctor.
Linux end-to-end acceptance remains **deferred to future GitHub Actions CI**, as
agreed for the 0.43 baseline. This stage adds no CI workflow and claims no Linux
Racket/Ganesh execution here.

Both validators update `SOURCE-SHA256SUMS.txt` only after **all selected checks**,
including the new inspectors, succeed. The authoring delivery records separately
which Python/C/source/patch checks ran and which Racket/GPU/hardware gates did not.
The recurring macOS CoreAnalytics/OpenGL context warning is not resolved by a
budgeted-cache check; retain its logs for a separate host-context investigation.

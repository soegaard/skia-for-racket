# Global caches and memory statistics — 0.77a

Package version: **0.77**. This module uses the existing pinned SkiaSharp 3.119.1
(m119.0) library. It requires **no new C/C++ compiler, CMake, or native helper**.
`graphics.rkt` is re-exported by `main.rkt` (`skia`). Requiring either module does
not initialize these APIs, purge caches, or change a cache limit.

## Scope: configuration, cached usage, and allocations are different

These controls apply to global caches in the loaded Skia runtime, shared by its
users in the process. They are not per-canvas, per-document or per-Racket-thread
settings. The separately exposed context-local GPU cache API is unchanged.

Cache limits request eviction behavior, not a hard bound on native memory.
Pinned/live objects may keep memory above a configured cache target. A purge
attempts to release cached objects; it cannot guarantee zero usage or lower
process RSS. `skia-purge-all-caches!` does **not** purge GPU-context caches.

Reported usage is not a measurement of all Skia allocations, Racket memory, RSS,
GPU driver allocations, or total GPU/system memory. Numeric diagnostic fields
can overlap or describe budgets/counts rather than allocations: do not sum them
into a supposed total. Backing-store and ownership graph hooks are not exposed
by the pinned managed trace adapter.

## Initialization and global font caches

```racket
(skia-initialize!)
(skia-font-cache-used)
(skia-font-cache-limit)
(skia-set-font-cache-limit! bytes)
(skia-font-cache-count-used)
(skia-font-cache-count-limit)
(skia-set-font-cache-count-limit! count)
(skia-purge-font-cache!)
```

`skia-initialize!` explicitly calls the native thread-safe, idempotent
initialization entry point. Ordinary use does not require an application to call
it separately. It returns `void` and is not a way to reset cache configuration.

Byte getters return exact nonnegative integers. Setter inputs must be exact
nonnegative integers representable as native `size_t`. Entry counts must fit a
nonnegative signed 32-bit integer. Inexact values, negatives and overflow are
rejected before invoking native code. These configuration values are not
restricted by `current-skia-byte-limit`: setting a cache target is not allocating
a buffer of that size.

**Each setter returns the previous native limit**, not the new value, amount
freed, or observed usage. A zero font byte/count limit is passed through as zero;
it does not prove that all active font resources have been released. A font cache
entry is a native strike associated with a typeface/size/matrix, not necessarily
one font family, face, or glyph.

## Global graphics-resource cache

```racket
(skia-resource-cache-used)
(skia-resource-cache-limit)
(skia-set-resource-cache-limit! bytes)
(skia-resource-cache-single-allocation-limit)
(skia-set-resource-cache-single-allocation-limit! bytes)
(skia-purge-resource-cache!)
(skia-purge-all-caches!)
```

The resource cache holds cached temporary bitmaps and other CPU resources.
The single-allocation setting controls admission of large individual cache
entries. **Zero here means no separate per-entry ceiling**, not a zero-byte
allocation policy. The total cache limit remains a separate setting.

Purges return `void`, leave limits unchanged, and can make subsequent rendering
more expensive as objects are recreated. They do not close the application's
images, typefaces, surfaces, or other live wrappers.

Applications must coordinate concurrent changes to these shared limits. There
is deliberately no helper pretending a temporary setting is thread-local or
isolated from another Skia user. When the application controls that concurrency,
a restoration pattern is:

```racket
(define saved (skia-font-cache-limit))
(dynamic-wind
  (lambda () (skia-set-font-cache-limit! (* 8 1024 1024)))
  (lambda ()
    ;; Perform the application's work under the chosen global policy.
    (void))
  (lambda () (skia-set-font-cache-limit! saved)))
```

Restoring settings does not restore evicted cache contents.

## Counter snapshots

```racket
(skia-cache-statistics)
```

Returns an immutable hash with these symbol keys:

| Key | Meaning |
| --- | --- |
| `scope` | `'process-global-skia-caches` |
| `atomic?` | `#f` |
| `font-bytes-used` / `font-byte-limit` | Reported font usage / configured byte limit |
| `font-count-used` / `font-count-limit` | Reported strike count / configured count limit |
| `resource-bytes-used` / `resource-byte-limit` | Reported global resource usage / configured limit |
| `resource-single-allocation-byte-limit` | Per-entry admission ceiling; zero means no separate ceiling |

The values come from individually synchronized native queries. **The group is
not an atomic joint snapshot**: other threads/places/native users may change
caches or limits between queries. In particular, do not infer a correctness
failure merely because sampled usage exceeds a sampled limit.

## Bounded native diagnostic snapshots

```racket
(skia-memory-statistics
 #:detailed? [detailed? #f]
 #:dump-wrapped? [dump-wrapped? #f]
 #:max-entries [max-entries 4096]
 #:string-limit [string-limit 4096]
 #:byte-limit [byte-limit 1048576])
```

This calls the real native global memory dump. `#:detailed?` selects light or
object-breakdown reporting. `#:dump-wrapped?` forwards the native wrapped-object
policy; it does not promise that any particular cache reports such objects.

The result is a detached `memory-statistics?` value:

```racket
(memory-statistics-entries report)       ; immutable vector of entries
(memory-statistics-detailed? report)
(memory-statistics-dump-wrapped? report)
(memory-statistics-truncated? report)
(memory-statistics-dropped-count report)
(memory-statistics-string-bytes report)
(memory-statistics-scope report)         ; 'process-global-skia-caches
(memory-statistics->jsexpr report)
```

An entry is a `memory-statistic?` with:

```racket
(memory-statistic-kind entry)            ; 'numeric or 'string
(memory-statistic-name entry)            ; native dump/object name
(memory-statistic-value-name entry)      ; field name
(memory-statistic-units entry)           ; string for numeric entries, #f otherwise
(memory-statistic-value entry)           ; exact uint64 or immutable string
```

Names/units are native diagnostic labels, not stable public object identifiers.
Detailed names can contain process-specific addresses as text; no native pointer
object is exported. Duplicate labels are preserved rather than combined. Entry
order is the native callback order and is not portable. All strings are strictly
decoded UTF-8 copies. JSON serialization preserves integer values textually, but
consumers using floating-point JSON numbers may lose precision above 2^53.

### Limits and incomplete reports

`#:max-entries` bounds retained records (0–65536). `#:string-limit` bounds each
native C-string scan/copy (0–65536 UTF-8 bytes, excluding the NUL). `#:byte-limit`
bounds total retained string payload. All are exact nonnegative integers.
A conservative accounting charge of `128 * max-entries + byte-limit` must fit
`current-skia-byte-limit`. This is a predictable collection bound, **not a promise
about actual process heap overhead or total native traversal time**.

An entry that would exceed a limit is omitted entirely: its name is not silently
shortened. The snapshot's `truncated?` flag and `dropped-count` disclose that
omission. A zero entry limit is useful for testing this behavior; it is not
reported as a complete empty dump. Once the entry limit is reached, callbacks
stop dereferencing/copying their string arguments. Limits do not interrupt
Skia's traversal. A fresh snapshot can succeed normally after a truncated one.

The dump is not an atomic global-memory transaction. Its backing/ownership
relationships are unavailable, and even an untruncated report is only what these
native cache reporters supply—not a complete heap inventory.

## Callback and threading rules

The managed trace table is separate from Skia's managed input/output stream
tables. This stage never installs or replaces stream callbacks, so the existing
live-port and incremental decoder providers remain intact.

Only private synchronous callbacks are installed. They copy bounded strings and
integer fields; they never invoke application procedures, use Racket ports, wait,
or call Skia. Exceptions are latched inside the callback and raised **after**
the native dump returns and its temporary object is deleted. Breaks are deferred
through that native/cleanup boundary. Snapshots are serialized by a Racket
semaphore, with the callback-sensitive section in atomic mode. There is no new
OS worker thread or C++ bridge.

Ordinary Racket threads can use the global controls. Calls from a live-port
service callback, and calls while any live-stream operation is active, are
rejected before re-entering Skia. A cache-lock wait must not block the Racket
thread needed to service the native worker. This restriction applies to getters,
setters, initialization, purges, and dump operations—not to detached result
inspection. Activity is rechecked inside the native-call atomic boundary.

The native trace callback table is process-global. Its callbacks and one small
provider marker are retained for the provider/process lifetime. A second module
instance or Racket place cannot replace the table and receives an explicit error
on its first dump. Scalar cache controls do not need that provider. Third-party
components that independently replace the same trace table are unsupported.
The process-global registry detects competing instances of this binding, not
noncooperating external code. Unloading/replacing the native library under live
bindings is unsupported.

## Validation

```bash
python tools/validate-global-caches.py --racket /path/to/racket
python tools/validate-global-caches.py --racket /path/to/racket --regressions none
```

Full regressions are the standalone default. Feature-only mode still compiles
and runs the focused **28 pure and 31 native cases**, the example, and the native
doctor. It retains commands/logs and independently inspects real measured
settings, named glyph-cache fields, native snapshots and raster bytes. The
inspector has no Pillow/document-renderer/GPU dependency.

Tests save and restore all changed limits. They cannot restore previously
purged cache contents and therefore should run in isolated test processes, not
inside an application's live rendering session. No default cache size or exact
font-memory allocation is hard-coded as a cross-platform expectation. Known
native root dump measurements are compared with corresponding scalar getters in
the doctor's quiescent process, not generalized to concurrent applications.

The reusable `global-caches.yml` child runs Linux 8.18/9.3 and Windows 9.3 under
Acceptance and contributes to `Acceptance required`. Central installed-package
CI runs the global regression suite on the supported platforms, including
macOS. Existing automatic workflow count and regression-scope semantics remain.

## Pinned implementation references

- `mono/skia`, commit `40f75dc0051d141913c07c20d4c19590c7da0cb7`:
  `include/c/sk_graphics.h`, `include/core/SkGraphics.h`,
  `src/core/SkGraphics.cpp`, and `src/core/SkStrikeCache.cpp`.
- At the same commit: `include/xamarin/sk_managedtracememorydump.h` (Git blob
  `cabc6297dbb3cb6a3e9936139bc2b56ee0c91e9b`) and
  `src/xamarin/sk_managedtracememorydump.cpp`.
- Racket foreign-interface manual, function types: callback atomicity,
  callback lifetime, and restrictions on exception escapes.

The 16 ordinary `sk_graphics_*` functions are reconciled in the standard native
inventory. The three Xamarin trace-adapter functions and their callback/table
signatures are checked separately by `api/global-cache-ffi.json` and
`tools/global_cache_ffi.py`; they do not inflate `include/c` coverage.
GPU options/targeted resource operations remain **0.77b**; GPU memory tracing and
interface helpers remain **0.77c**.

## Shared GPU collector (0.77c)

`gpu-memory-statistics` uses the same bounded collector and report accessors,
but `memory-statistics-scope` returns `gpu-context-skia-resources`. Global calls
retain `process-global-skia-caches`. Neither scope is process RSS or driver
allocation accounting; do not add overlapping records into a total. See
[GPU-DIAGNOSTICS.md](GPU-DIAGNOSTICS.md).

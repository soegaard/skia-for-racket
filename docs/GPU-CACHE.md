# GPU cache management — 0.45

Import `skia/gpu` in addition to `skia`. Cache operations require the matching
active `call-with-gpu-context` scope and its creator thread. They work with
OpenGL, Metal and the separately validated EGL provider. They cannot be called
inside `call-with-gpu-external-gl`, on a foreign context, or after abandonment.
The bindings are lazy and separate from the required CPU symbol inventory.

```racket
(call-with-gpu-context context
  (lambda ()
    (define before (gpu-cache-info context))
    (gpu-set-cache-limit! context (* 32 1024 1024))
    (gpu-purge-unlocked! context #:scratch-only? #f)
    (gpu-purge-bytes! context (* 4 1024 1024) #:prefer-scratch? #t)
    (gpu-perform-deferred-cleanup! context 1000)
    (gpu-free-resources! context)
    (define after (gpu-cache-info context))
    (values before after)))
```

`gpu-cache-info` returns an immutable, JSON-compatible snapshot with
`backend`, `context_generation`, `limit_bytes`, `budgeted_resources`, and
`budgeted_bytes`. The pinned m119 `GrDirectContext::getResourceCacheUsage`
implementation counts **budgeted** resources, despite broader wording in some
upstream documentation. It does not report total device memory, textures held
outside that cache, process RSS, or Racket managed memory. `total_gpu_bytes`
and `purgeable_bytes` are `#f`: the pinned C shim does not expose those queries.
`gpu-context-info` retains its historical creation-time cache fields; use the
new live query after changing a budget.

`gpu-set-cache-limit!` accepts an exact nonnegative size_t-sized integer,
including zero. This is a cache retention budget, not an allocation ceiling.
Live/in-use resources can exceed it. It does not destroy application-owned
images, surfaces, paints, or recorded graphs. Restore the old budget explicitly
when a temporary application policy ends; no process-global budget is changed.

`gpu-purge-unlocked!` asks for all unlocked resources, or scratch resources
first with `#:scratch-only? #t`. Skia can additionally purge persistent resources
to meet its budget even with that flag. `gpu-purge-bytes!` requests a byte count;
it neither guarantees that amount is available nor returns a fabricated number
of bytes freed. `#:prefer-scratch?` selects scratch-first versus LRU preference.

`gpu-perform-deferred-cleanup!` cleans eligible unlocked resources not used for
at least the supplied exact age in milliseconds. The binding bounds ages to
0..2147483647 to avoid native steady-clock conversion overflow. Zero means an
immediate eligibility check, not permission to discard live resources.

`gpu-free-resources!` invokes the more aggressive Skia cleanup operation.
**The pinned implementation internally flushes and submits.** Its submission
is not a CPU completion guarantee. Its private trace records
`native_may_submit = true` and `completion_guaranteed = false`. The other cache
requests also do not certify completion. A cache call can have driver-side
cost or stalls; do not interpret absence of an explicit wait as nonblocking.
Use `gpu-wait!` at an explicit completion boundary when needed.

Purging is not closure, context abandonment, or GC. Close wrappers using the
existing ownership protocol and drain deferred releases on their owner.
All mutation procedures return `void`. Invalid arguments are rejected before
native loading; native context loss and operation failure are not CPU fallbacks.

Pinned sources: `mono/skia@40f75dc0051d141913c07c20d4c19590c7da0cb7`,
`include/c/gr_context.h`, `src/c/gr_context.cpp`, and
`src/gpu/ganesh/GrDirectContext.cpp`. There is no new native record layout:
usage is returned through distinct `int*` and `size_t*` output slots.

# Graphite feasibility investigation — 0.47

## What changed upstream

The pinned 4.153.1 Skia submodule contains a public C header for Graphite:
[`include/c/sk_graphite.h` at 45afab4f](https://github.com/mono/skia/blob/45afab4f1f0921f3feb97f58cf89b136fffa85e6/include/c/sk_graphite.h).
It exposes opaque context, recorder, recording, texture and image-provider
handles, insertion/submission operations, surface factories and asynchronous
CPU readback. Therefore, a future investigation need not begin by assuming
that no Graphite C entry points exist. This is a feasibility finding, not a
claim that the current Racket wrapper supports Graphite.

The header's backend query reports whether Dawn, Metal or Vulkan was compiled
into a particular library. The isolated candidate tool calls only this reviewed
scalar query, in addition to the two version functions. It reports each build
flag separately. Missing query symbols produce unknown build flags; false
flags are not changed into runtime fallbacks. No backend context is created,
and a true build flag is not evidence of a usable device or successful pixels.

## Why this is not a Ganesh backend switch

The existing wrapper coordinates Ganesh contexts and retained resource affinity
with explicit owner-thread activation, submission, transfer and teardown.
Graphite adds an explicit recorder/recording boundary. A future implementation
must model context-to-recorder relationships, snapping a recording, insertion
status, recording order and submit completion. A `GrDirectContext*` and a
Graphite context/recorder are not interchangeable pointer values.

The header documents ownership transfer for recorder image providers and
separate destruction rules for recordings, texture wrappers and underlying GPU
textures. Some wrapping APIs accept release callbacks. Those callbacks require
a deliberate bridge to the existing Racket lifetime system; they must not be
silently treated like the callback-free Ganesh calls currently wrapped.

Most importantly, the header states that ordinary `sk_surface_read_pixels`
does not work for Graphite surfaces in production builds. The Graphite route
uses context-based asynchronous readback and a completion pump on the context's
owning thread. The callback result is borrowed for the callback duration and
must be copied before returning. Existing synchronous public CPU-transfer
semantics would therefore need an explicitly implemented synchronization bridge,
not reuse of the old native readback call.

## Suggested future feasibility stages

A first future stage would audit the exact candidate backend factory signatures,
build flags and queue/device ownership, then privately construct and tear down
one context on a supported host. Keep that stage outside public drawing APIs.

A second stage would record a minimal surface, snap, insert, submit and retrieve
known pixels through the actual asynchronous readback route. Exercise empty
recordings, insertion failure, lost-device handling, callback completion and
teardown. Establish which side owns each resource at every transition.

Only then should a backend-neutral public integration be designed. It must
cover retained images and graph affinity, cache semantics, explicit transfers,
window presentation, deferred cleanup and cancellation. Reuse mathematical
and drawing operations where their contracts genuinely agree; do not merge
incompatible context/recording lifetimes behind a shared pointer type.

These stages are a proposal, not work claimed completed in 0.47. Graphite is not
exported from `skia/gpu`, no automatic selection is changed, and no device,
rendering, hardware-acceleration or performance result is claimed here.

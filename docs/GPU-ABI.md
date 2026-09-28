# Pinned GPU ABI and source audit

Repository baseline: `a07aefeef0f91000c5a8683bb3b8835260a75064`.
SkiaSharp package: 3.119.1. All Skia source references below are pinned to
`40f75dc0051d141913c07c20d4c19590c7da0cb7` (m119).

The new private `gpu-native.rkt` owns a separate lazily resolved registry. It
opens the same version-checked Skia library selected by the existing loader.
The public `gpu.rkt` imports no driver until explicit construction. Exported
symbols may still be stubs: null constructors, native backend/context checks
and actual target/readback are separate validation steps.

## Calls and ownership

`gr_glinterface_create_native_interface` is tried first. A built-in provider can
assemble a desktop GL interface with its system function resolver if necessary.
The interface is validated, passed to `gr_direct_context_make_gl`, and the
caller's interface reference is dropped. The pinned C implementation passes a
retained `sk_ref_sp` into Ganesh, so retaining a second caller interface wrapper
is not necessary. No procedure resolver or raw function pointer is public.

The context is destroyed through `gr_recording_context_unref`. Limits, backend,
initial cache usage, reset, abandon, flush and submit use the pinned C functions.
Flush and submit are different operations; the smoke uses `submit(true)` for
CPU-visible completion before synchronous readback. No general fence or async
readback callback interface is claimed.

`sk_surface_new_render_target` allocates the smoke target. Its recording context
is borrowed and converted to the borrowed direct-context pointer for identity
comparison; neither borrowed pointer is unreferenced separately. Surface and
paint lifetimes are private domain children. No GPU pointer is handed to the
existing CPU `new-owned` machinery. The ordinary C canvas clear/rectangle calls
are sufficient for this focused rendering probe.

## Record layouts

| C record | Fields and offsets | Size on the 64-bit host mirror |
|---|---|---:|
| `gr_gl_framebufferinfo_t` | uint32 FBO 0; uint32 format 4; C bool protected 8 | 12 |
| `gr_gl_textureinfo_t` | uint32 target 0; uint32 ID 4; uint32 format 8; C bool protected 12 | 16 |
| `gr_mtl_textureinfo_t` | pointer texture 0 | 8 |
| Existing `sk_imageinfo_t` | pointer 0; width 8; height 12; color type 16; alpha type 20 | 24 |

The GL records are inventory for later external targets; this stage does not
import framebuffer/texture descriptors. Their `fProtected` fields must not be
omitted based on older SkiaSharp examples. The C mirror can compile against a
supplied upstream C header using `SKIA_C_TYPES_HEADER`; by default it checks an
independent local declaration, not upstream compilation. Racket pure FFI layout
checks are separate and still require executing the selected Racket.

Backend discriminants are OpenGL 0 and Metal 2; origins are top-left 0 and
bottom-left 1. C booleans use `_stdbool`, size/counts use `_size`, IDs use uint32,
and dimensions use the existing int32 image-info layout. No context-options
record is guessed or passed in this implementation.

## The Metal legacy-header mismatch

The legacy `MakeMetal(void*, void*)` declaration in `GrDirectContext.h` describes
transferable device and queue references. The actual implementation at this
commit calls `backendContext.fDevice.retain(device)` and
`backendContext.fQueue.retain(queue)` before using the modern context overload.
`sk_cfp::retain` in `SkCFObject.h` invokes `CFRetain`; its destructor releases the
reference. The C shim forwards to this overload or returns null when Metal is
disabled.

The probe therefore treats the arguments as borrowed from its own explicit
Create/new references, releases those references on both success and failure,
and lets Ganesh manage its own retained references. It does not add a donated
retain based solely on the stale comment. This decision is specific to the
pinned source and must be re-audited on any native upgrade. The repeated probe
helps detect crashes and ownership failures but is not a leak detector.

## Source locations

Pinned source root:
`https://github.com/mono/skia/tree/40f75dc0051d141913c07c20d4c19590c7da0cb7`

- `include/c/gr_context.h`: signatures and selected context operations.
- `src/c/gr_context.cpp`: GL retained interface, Metal forwarding, stubs,
  submit synchronization and borrowed direct-context conversion.
- `include/c/sk_surface.h`: GPU target constructor and readback signature.
- `include/c/sk_types.h`: protected flags, records and backend/origin enums.
- `include/gpu/GrDirectContext.h`: abandon, submission and legacy Metal comment.
- `src/gpu/ganesh/GrDirectContext.cpp`: actual Metal overload implementation.
- `include/gpu/mtl/GrMtlBackendContext.h`: device/queue `sk_cfp` fields.
- `include/ports/SkCFObject.h`: retain versus adopt semantics.

Racket contracts consulted:
`https://docs.racket-lang.org/draw/gl-context___.html`
`https://docs.racket-lang.org/draw/gl-config_.html`
`https://docs.racket-lang.org/foreign/Allocation_and_Finalization.html`
`https://docs.racket-lang.org/foreign/Custodian_Shutdown_Registration.html`

Pinned Windows package pages:
`https://www.nuget.org/packages/SkiaSharp.NativeAssets.Win32/3.119.1`
`https://www.nuget.org/packages/HarfBuzzSharp.NativeAssets.Win32/8.3.1.2`

Source review, package metadata, C mirrors and symbol inventories do not replace
executing the actual installed binary/provider/driver combination.

## Owned Metal rendering and autorelease scopes

Owned Metal contexts use the audited legacy constructor above. The binding
releases its Create/new references to the device and queue on success and
constructor failure; Ganesh retains what it needs. No native record layout or
new CPU-required symbol is added. The shared target validator checks native
backend 0 for OpenGL and 2 for Metal rather than accepting a non-null surface.

`objc_autoreleasePoolPush`/`objc_autoreleasePoolPop` wrap synchronous native
operations in local atomic sections. Pools are never held across application
drawing callbacks or `sleep`/GUI yielding. Queued native destructors capture
their pool scope for owner-side draining, including after abandonment. See
[Metal ownership](GPU-METAL.md) and [executed validation](GPU-METAL-TESTING.md).

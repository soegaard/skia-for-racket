# Borrowing external OpenGL storage

Import `skia/gpu-gl-interop` alongside `skia` and `skia/gpu`. This is an advanced
same-context boundary for host-owned OpenGL names, not an ownership-adoption,
texture-sharing, or raw-pointer export API. It needs a live desktop OpenGL 3.3+
context and a provider procedure resolver. The built-in Racket GL and EGL
providers supply one. Custom providers can supply
`#:get-proc-address (lambda (name) ...)` to `make-gpu-provider`; it accepts a
native function name string and returns that context's FFI pointer or `#f`.

All three operations below run **inside** `call-with-gpu-context` for the named
context. Wrong context, wrong Racket thread, futures, closed resources, lost
contexts, and nested external handoffs are rejected. OpenGL names are nonzero
uint32 integers interpreted in that current context. A number alone cannot
prove which context originally created an object when numeric names coincide;
do not pass IDs from other contexts. There is no sharing-group inference.
Metal contexts do not support these operations.

## Handing the command stream to external GL

```racket
(call-with-gpu-external-gl context thunk #:wait? [wait? #f])
```

Flushes and submits queued Skia work before calling `thunk` with zero arguments.
This is the place for the host's raw OpenGL operations. The callback may return
multiple values, which are preserved. It must keep the same native context
current and must not enter Skia GPU operations. Queue-only explicit resource
closure remains safe; native GPU release draining is rejected within the
external callback. Exceptions and escapes retire the scope; Skia's cached GL
state is invalidated on exit, including exceptional exit.

With `wait? #f`, ordering is through the same GL context/command stream, not a
CPU completion barrier. With `#t`, preceding Skia work is also completed before
the callback. **This function does not restore host GL state.** The host must
set its own program, VAO, blending, viewport, texture bindings, pixel transfer
state, and other state needed by its code. Invalidating Skia's cache means Skia
will re-establish its own state next time; it does not establish the host's.

## Drawing into a borrowed framebuffer

```racket
(call-with-gpu-gl-framebuffer context framebuffer-id width height draw
  #:origin [origin 'bottom-left]
  #:color-space [color-space #f]
  #:wait? [wait? #t])
```

`draw` receives one ordinary `canvas?`. The wrapper creates a private native
framebuffer description and Skia surface, verifies the Ganesh context, invokes
the callback, submits its work, then retires those wrappers. It never adopts or
deletes the host's framebuffer, texture, or stencil renderbuffer. Only the
canvas is exposed; there is no borrowed surface whose snapshot could escape.
The canvas expires at callback exit even if an outer GPU activation survives.
Multiple callback return values are preserved.

The initial supported format is deliberately narrow. The target must be a
**nonzero, complete, single-sampled FBO** whose sole enabled draw output is
`GL_COLOR_ATTACHMENT0`. That attachment must be level zero of a non-layered,
non-cube `GL_TEXTURE_2D` with sized internal format `GL_RGBA8`, identity component
swizzle, base level zero, and compare mode `GL_NONE`. The host must also provide
an eight-bit stencil **renderbuffer** with matching extent and no multisampling.
This avoids installing an untracked temporary stencil attachment on the host's
FBO. Dimensions, attachments, formats, samples, and draw-buffer selection are
queried rather than trusted from arguments. The host owns both attachments;
color and stencil contents are not preserved. Attachment identities are checked
again on return.

`origin` is exactly `bottom-left` or `top-left`, describing how the host's
storage should map to canvas coordinates. `width` and `height` are positive
signed-32-bit integers and must equal the queried attachment extent.
`color-space` is a live package color space or `#f` for untagged storage. It is
an interpretation of the host pixels, not a conversion of existing pixels.
The target uses premultiplied RGBA semantics.

Callbacks must leave the canvas save/layer stack balanced. An unbalanced stack
is an error; cleanup restores the stack before submission and retirement.
Callback errors still submit issued work according to the chosen return policy
before returning the external storage. Exceptions are not a drawing rollback.
No rendering or transfer operation is allowed on an escaped canvas.

By default, return includes a CPU completion wait so the host can safely reuse
its storage. Explicit `#:wait? #f` permits same-context ordered reuse without
that wait; it is **not** permission to mutate or delete storage concurrently on
another context/thread. The caller remains responsible for native lifetime and
synchronization when leaving the ordered GL stream.

## Copying an external texture into owned GPU storage

```racket
(gpu-copy-gl-texture context texture-id width height
  #:origin [origin 'bottom-left]
  #:premultiplied? [premultiplied? #t]
  #:color-space [color-space #f]
  #:wait? [wait? #t]) ; -> image?
```

Validates the same RGBA8, level-zero 2D texture restrictions, temporarily wraps
the host texture with Skia's **borrowed** texture constructor, and draws it 1:1
into a new Skia-owned GPU surface. Its snapshot is the returned ordinary GPU
`image?`. The temporary borrowed image and descriptor are retired before the
call returns. There is no CPU readback in the copy.

This is deliberately a **GPU-side copy, not zero-copy import**. Returning a
borrowed image would allow a shader, filter, or picture to retain the host's
storage beyond the apparent borrow scope. The owned copy instead uses the
already-established GPU image lifetime and transitive context affinity rules.
After the default synchronous return the host can alter or delete its original
texture without changing the copy. A retained shader can keep the copy's pixels
after both the external texture and original returned image wrapper close.

`premultiplied?` describes the input alpha representation; the owned destination
uses the normal premultiplied GPU surface representation. Nearest sampling and
source replacement avoid blending with destination pixels. Origins are explicit,
and color-space interpretation is retained. The same explicit `wait? #f`
same-context ordering contract as framebuffer return applies. Use the regular
`gpu-image->raster-image` for a subsequent, explicit CPU detachment.

## State restoration and errors

Borrowing/copying saves and restores only the current draw/read framebuffer
bindings, renderbuffer binding, active texture unit, and that unit's 2D texture
binding. Skia's cache is invalidated after restoration. It does **not** restore
all texture units, sampler objects, programs, vertex arrays, pixel-buffer
bindings, texture/sampler parameters, blending, or every other GL state
variable. Re-establish those explicitly before host drawing; use `call-with-gpu-external-gl` for the handoff.

A pending GL error at entry is reported instead of ignored. Reading the error
consumes that error; error flags are not preserved. Unsupported storage, dirty
or changed native context, mismatched dimensions, and failed Skia wrappers are
errors, not triggers for raster fallback. On a native-context violation cleanup
must not issue GL restoration into the wrong context. Recover the correct
native context or abandon the domain, retire references on the owner, and only
then dispose of host storage. Indeterminate native releases follow the existing
quarantine/no-retry policy.

No API here adopts external names, exports a Skia-owned texture name, borrows an
image that can escape into retained graphs, imports multisampled/default/MRT
framebuffers, synchronizes multiple contexts, or supplies EGL/GL fence sharing.
Those are separate capabilities requiring separate lifetime contracts.

The pinned C implementation maps `sk_image_new_from_texture` to
`SkImages::BorrowTextureFrom`; its adopted-texture constructor is different and
is not bound by this module. See the
[pinned image shim](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/c/sk_image.cpp)
and [headless/interop validation](GPU-HEADLESS-TESTING.md).

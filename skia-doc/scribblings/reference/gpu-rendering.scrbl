#lang scribble/manual

@(require (for-label racket/base skia/gpu skia/gpu-egl skia/gpu-racket-gl))

@title[#:tag "skia-reference-gpu-rendering" #:style 'toc]{GPU Contexts and Resources}

The GPU interfaces draw through OpenGL, Metal, or Direct3D. An offscreen GPU
surface lets you draw without displaying a window and keep the result on the
GPU for later drawing, filtering, or compositing. Choose the interface according
to how the result will be used:

@itemlist[
 @item{For one drawing that should produce a CPU image, use
       @racket[render-gpu->raster-image]. It creates a context, draws, reads back
       the pixels, and closes the temporary GPU resources.}
 @item{For repeated offscreen drawing, manage a @tech{GPU context} explicitly.
       Reuse its @tech{GPU surfaces} and @tech{GPU images}, entering
       @racket[call-with-gpu-context] whenever you perform GPU work.}
 @item{For a Racket GUI window, start with
       @seclink["skia-reference-presentation-gui"]{Presentation and GUI}.
       Its widgets can manage the context and frame lifecycle for you.}]

The package provides these context-creation routes. An owned route creates
the native host as well as the Skia context. A borrowed route uses an existing
host that the application must keep alive.

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Platform} @bold{Owned host} @bold{Existing host})
  (list "macOS" @elem{@racket[make-gpu-context] with @racket['metal]}
        @racket[make-racket-gl-provider])
  (list "Windows (x86-64)"
        @elem{@racket[make-gpu-context] with @racket['direct3d]}
        @racket[make-racket-gl-provider])
  (list "Linux" @elem{@racket[make-egl-gpu-context] (headless desktop OpenGL)}
        @elem{@racket[make-current-egl-gpu-provider] or @racket[make-racket-gl-provider]}))]

Direct3D uses a hardware adapter by default; @racket[#:adapter 'warp] explicitly
selects software rendering. These routes require the corresponding native
libraries and platform facilities. Backend names describe supported interfaces,
not a guarantee that they are available on the current machine or hardware
accelerated. There is no Vulkan backend, automatic backend selection, or
automatic CPU fallback.

Start with @secref["skia-gpu-contexts"] for context use and cleanup, then
@secref["skia-gpu-surfaces"] for drawing targets. Use
@secref["skia-gpu-transfers"] when the result must move to CPU memory.
Providers and context options customize construction; they are not required
configuration steps for every program. Integration with another library's
native GPU commands or textures is covered separately in
@secref["skia-reference-gpu-interop-output"].

@local-table-of-contents[]

@include-section["gpu-providers.scrbl"]
@include-section["gpu-context-options.scrbl"]
@include-section["gpu-contexts.scrbl"]
@include-section["gpu-opengl-hosts.scrbl"]
@include-section["gpu-surfaces.scrbl"]
@include-section["surface-properties.scrbl"]
@include-section["gpu-images.scrbl"]
@include-section["gpu-transfers.scrbl"]
@include-section["gpu-synchronization.scrbl"]
@include-section["gpu-diagnostics.scrbl"]

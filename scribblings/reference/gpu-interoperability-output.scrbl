#lang scribble/manual

@(require (for-label racket/base skia/gpu-gl-interop skia/gpu-interop))

@title[#:tag "skia-reference-gpu-interop-output" #:style 'toc]{Native GPU Interoperability}

This chapter covers advanced integration with an application that already uses
OpenGL, Metal, or Direct3D. It describes how Skia can work with that
application's native GPU commands or resources.

Most programs do not need this chapter. To draw only with Skia, start with
@seclink["skia-reference-gpu-rendering"]{GPU Contexts and Resources}. For a
Racket GUI window, continue with
@seclink["skia-reference-presentation-gui"]{Presentation and GUI}. Read this
chapter only when another library or engine already owns GPU commands, a
context, or a texture that you need to exchange with Skia.

Choose the operation by what you want Skia to do:

@itemlist[
 @item{To run external OpenGL commands between Skia operations, use
       @racket[call-with-gpu-external-gl]. It submits earlier Skia work and
       runs your callback in the same native OpenGL context.}
 @item{To draw into an application-owned OpenGL framebuffer, use
       @racket[call-with-gpu-gl-framebuffer]. To copy an application-owned
       OpenGL texture into a Skia image, use @racket[gpu-copy-gl-texture].
       See @secref["skia-gpu-gl-interop"] for the supported targets.}
 @item{For Metal or Direct3D textures, first create an
       @tech{external GPU texture handoff}. Use @racket[gpu-import-image]
       to copy the pixels into a Skia-owned image, or
       @racket[call-with-gpu-external-surface] to draw temporarily into the
       original texture. See @secref["skia-gpu-external-resources"] for the
       sequence and @secref["skia-gpu-native-handoffs"] for the unsafe
       native-pointer constructors.}]

Copying produces independent image storage. Temporary drawing access changes
the application's original storage and does not transfer ownership of it to
Skia. Neither operation permits simultaneous external and Skia access to the
same texture: follow the operation's synchronization rules before reusing
or releasing the native storage. These operations keep the pixel transfer on
the GPU; they are not CPU readback operations.

@local-table-of-contents[]

@include-section["gpu-gl-interop.scrbl"]
@include-section["gpu-external-resources.scrbl"]
@include-section["gpu-native-handoffs.scrbl"]

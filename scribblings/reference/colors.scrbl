#lang scribble/manual

@(require scribble/eval
          (for-label racket/base racket/contract skia skia/color))

@(define color-eval (make-base-eval))
@(color-eval '(require skia/color))

@title[#:tag "skia-colors"]{Color Specifications}

@defmodule[skia/color #:no-declare]
@(declare-exporting skia skia/color #:use-sources (skia/color))

A @deftech{color specification} is an @racket[rgba] value, a supported color-name
symbol, a hexadecimal string, or an unsigned ARGB integer. These are
@tech{detached value}s, not closeable native resources.

The supported names are @indexed-racket['transparent], @indexed-racket['black],
@indexed-racket['white], @indexed-racket['red], @indexed-racket['green],
@indexed-racket['blue], @indexed-racket['yellow], @indexed-racket['cyan],
@indexed-racket['magenta], @indexed-racket['gray], @indexed-racket['grey],
@indexed-racket['orange], and @indexed-racket['purple]. Names are case-sensitive.
Named green is @tt{#008000}, not
@tt{#00FF00}.

A string has the form @tt{#RRGGBB} or @tt{#RRGGBBAA}, with hexadecimal channel
bytes. The six-digit form has alpha 255. An integer instead uses
@tt{#xAARRGGBB}: alpha is its most significant byte. A supported name must be a
symbol, not a string containing the name. Alpha zero is transparent; alpha 255
is opaque.

@defproc[(color? [v any/c]) boolean?]{
Returns @racket[#t] when @racket[v] is a supported @tech{color specification}
and @racket[#f] otherwise. Recognizing a color does not allocate a native
resource or check whether Skia is installed.

@examples[#:eval color-eval
(color? 'blue)
(color? "blue")
(color? "#326DE6")
]
}

@section[#:tag "skia-rgba"]{RGBA Colors}

@defstruct*[rgba ([red byte?] [green byte?] [blue byte?] [alpha byte?]) #:transparent]{
Represents a color by red, green, blue, and alpha channels. Each channel is an
exact integer from 0 through 255. The constructor checks all four channels and
raises @racket[exn:fail:contract] for an invalid value. The RGB channels are not
multiplied by alpha.

The structure is transparent and its fields are immutable. The @racket[rgba?]
predicate returns @racket[#t] for an instance of this structure and @racket[#f]
otherwise. The @racket[rgba-red], @racket[rgba-green], @racket[rgba-blue], and
@racket[rgba-alpha] accessors return the corresponding channel as a byte.
The @racket[struct:rgba] binding is its structure-type descriptor.

@examples[#:eval color-eval
(rgba 50 109 230 128)
(rgba? (rgba 50 109 230 128))
(rgba-alpha (rgba 50 109 230 128))
]
}

@defproc[(rgb [red byte?] [green byte?] [blue byte?]) rgba?]{
Returns @racket[(rgba red green blue 255)]. The resulting color is opaque.

@examples[#:eval color-eval
(rgb 50 109 230)
(rgba-alpha (rgb 50 109 230))
]
}

@section[#:tag "skia-color-conversion"]{Color Representation Conversion}

@defproc[(color->rgba [color color?]) rgba?]{
Returns the RGBA representation of @racket[color]. An RGBA argument is returned
unchanged. Other accepted representations produce an RGBA value with the same
channel values. This operation changes the representation, not the color space.

@examples[#:eval color-eval
(color->rgba "#12345678")
(color->rgba #x78123456)
(equal? (color->rgba "#12345678") (color->rgba #x78123456))
(define color (rgb 50 109 230))
(eq? (color->rgba color) color)
]
}

@defproc[(color->argb [color color?]) (integer-in 0 #xffffffff)]{
Returns the packed unsigned integer for @racket[color], with bytes in alpha,
red, green, blue order from most to least significant. The RGB channels are
not multiplied by alpha. This operation does not convert between color spaces.

@examples[#:eval color-eval
(= (color->argb "#12345678") #x78123456)
(color->argb 'transparent)
]
}

@close-eval[color-eval]

@section[#:tag "skia-color-spaces"]{Color Spaces}

@(declare-exporting skia)

A @deftech{color space} describes how color samples are interpreted. A color-space
resource is different from a @tech{color specification}: it supplies the
interpretation, not the channel values. The @racket[color-space?] predicate is
provided by @racketmodname[skia], not @racketmodname[skia/color]. The constructors
and queries below are also provided by @racketmodname[skia].

An omitted or @racket[#f] color-space argument does not mean sRGB. Its meaning
depends on the operation; for @racket[make-surface] and @racket[rgba-bytes->image],
it creates an untagged result rather than selecting a default profile.

@defproc[(color-space? [v any/c]) boolean?]{
Returns @racket[#t] for a Skia color-space resource and @racket[#f] otherwise.
A closed color-space wrapper still satisfies this predicate but cannot be used
for native operations.
}

@defproc[(make-srgb-color-space) color-space?]{
Returns a new owned color-space reference describing sRGB, with its standard
RGB primaries and nonlinear transfer function. The result has an independent
wrapper lifetime even when Skia shares the underlying native color space.
Creating the reference does not convert any image or surface samples.
}

@defproc[(make-linear-srgb-color-space) color-space?]{
Returns a new owned color-space reference with the same RGB primaries as sRGB
and a linear transfer function. Samples in this space represent relative
linear-light channel values rather than sRGB-encoded values. The result follows
the same ownership rules as @racket[make-srgb-color-space].

The two spaces can be used with the image and surface constructors:

@racketblock[
(with-skia ([srgb (make-srgb-color-space)]
            [linear (make-linear-srgb-color-space)]
            [encoded (rgba-bytes->image 1 1 (bytes 128 128 128 255)
                                        #:color-space srgb)]
            [light (rgba-bytes->image 1 1 (bytes 128 128 128 255)
                                      #:color-space linear)]
            [surface (make-surface 2 1 #:color-space srgb)])
  (define canvas (surface-canvas surface))
  (draw-image canvas encoded 0 0)
  (draw-image canvas light 1 0)
  (bytes->list (surface->rgba-bytes surface #:color-space srgb)))
]

Both source images contain the same channel bytes, but those bytes describe
different colors. The sRGB source produces RGB values of 128; the linear source
produces approximately 188 in the sRGB destination. Alpha remains 255. The
@racket[#:color-space] arguments to @racket[rgba-bytes->image] declare the input
bytes' meaning; drawing into the tagged destination performs the conversion.
}

@defproc[(color-space=? [a color-space?] [b color-space?]) boolean?]{
Returns @racket[#t] when Skia considers @racket[a] and @racket[b] equivalent
color spaces, and @racket[#f] otherwise. This compares the color-space
descriptions, not Racket wrapper identity or image pixels. Both arguments must
be open resources used on their owning thread.
}

@defproc[(color-space-srgb? [space color-space?]) boolean?]{
Returns @racket[#t] when Skia recognizes @racket[space] as sRGB, and @racket[#f]
otherwise. The space must be open and used on its owning thread. Linear sRGB
does not satisfy this predicate merely because it has the same RGB primaries.
}

@defproc[(color-space-linear-gamma? [space color-space?]) boolean?]{
Returns @racket[#t] when @racket[space] has a linear transfer function, and
@racket[#f] otherwise. The space must be open and used on its owning thread.
The result does not identify the RGB primaries or verify the meaning of any
pixel samples.

@racketblock[
(with-skia ([srgb (make-srgb-color-space)]
            [another-srgb (make-srgb-color-space)]
            [linear (make-linear-srgb-color-space)])
  (list (color-space=? srgb another-srgb)
        (color-space=? srgb linear)
        (color-space-srgb? srgb)
        (color-space-srgb? linear)
        (color-space-linear-gamma? srgb)
        (color-space-linear-gamma? linear)))
]

The result is @racket['(#t #f #t #f #f #t)].
}

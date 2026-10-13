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

Color-space resources describe the meaning of samples rather than their channel
values. See @secref["skia-color-management"] for @racket[color-space?], the standard
sRGB constructors, custom RGB spaces, and conversion. Floating-point channel
values are described in @secref["skia-float-colors"].

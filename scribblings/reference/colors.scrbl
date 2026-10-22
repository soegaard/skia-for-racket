#lang scribble/manual

@(require "support/figures.rkt"
          scribble/eval
          (for-label racket/base racket/contract skia skia/color))

@(define color-eval (make-base-eval))
@(color-eval '(require skia/color))

@title[#:tag "skia-colors"]{Color Specifications}

@defmodule[skia/color #:no-declare]
@(declare-exporting skia skia/color #:use-sources (skia/color))

A @deftech{color specification} is an @racket[rgba] value, a supported color-name
symbol, a hexadecimal string, or an unsigned ARGB integer.

The supported names are case-sensitive symbols, not strings containing the
names. Their values are shown below in @tt{#RRGGBBAA} order:

@tabular[#:style 'boxed
 (list
  (list @bold{Name} @bold{RGBA value})
  (list @indexed-racket['transparent] @tt{#00000000})
  (list @indexed-racket['black]       @tt{#000000FF})
  (list @indexed-racket['white]       @tt{#FFFFFFFF})
  (list @indexed-racket['red]         @tt{#FF0000FF})
  (list @indexed-racket['green]       @tt{#008000FF})
  (list @indexed-racket['blue]        @tt{#0000FFFF})
  (list @indexed-racket['yellow]      @tt{#FFFF00FF})
  (list @indexed-racket['cyan]        @tt{#00FFFFFF})
  (list @indexed-racket['magenta]     @tt{#FF00FFFF})
  (list @indexed-racket['gray]        @tt{#808080FF})
  (list @indexed-racket['grey]        @tt{#808080FF})
  (list @indexed-racket['orange]      @tt{#FFA500FF})
  (list @indexed-racket['purple]      @tt{#800080FF}))]

A string has the form @tt{#RRGGBB} or @tt{#RRGGBBAA}, with case-insensitive
hexadecimal digits. The six-digit form has alpha 255. Short forms such as
@racket["#F00"] and color-name strings such as @racket["red"] are not accepted.

The alpha position differs between strings and integers: a string puts alpha
last, as @tt{#RRGGBBAA}; an integer puts it first, as @tt{#xAARRGGBB}.
Alpha zero is transparent; alpha 255 is opaque. These two specifications
therefore describe the same color:

@examples[#:eval color-eval
(color->rgba "#12345678")
(color->rgba #x78123456)
(equal? (color->rgba "#12345678") (color->rgba #x78123456))
]

These representations specify channel values, not a color-space resource.
See @secref["skia-color-management"] for color interpretation and conversion,
and @secref["skia-float-colors"] for floating-point channel values.

@racketblock[
(with-skia ([surface (make-surface 210 70 #:background 'white)]
            [red-paint (make-paint #:color 'red)]
            [orange-paint (make-paint #:color 'orange)]
            [green-paint (make-paint #:color 'green)]
            [blue-paint (make-paint #:color "#326DE6")]
            [purple-paint (make-paint #:color 'purple)])
  (draw-rect (surface-canvas surface) 10 10 34 50 red-paint)
  (draw-rect (surface-canvas surface) 49 10 34 50 orange-paint)
  (draw-rect (surface-canvas surface) 88 10 34 50 green-paint)
  (draw-rect (surface-canvas surface) 127 10 34 50 blue-paint)
  (draw-rect (surface-canvas surface) 166 10 34 50 purple-paint))
]

@reference-figure["color-swatches.png"
                  "Five solid color swatches: red, orange, named green, a hexadecimal blue, and purple."]

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

The fields are immutable.

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

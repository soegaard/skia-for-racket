#lang scribble/manual

@(require (for-label racket/base racket/contract skia))

@title[#:tag "skia-notation"]{Notation and Conventions}

@section{Contracts and Restrictions}

Argument contracts are supplemented by restrictions in the entry's description,
such as a rectangle fitting inside an image or a resource being open.

@section[#:tag "skia-scalars"]{Coordinates and Numeric Limits}

@deftech{binary32} is the IEEE 754 single-precision floating-point format,
using 32 bits per number. Skia uses this format for drawing coordinates;
exact inputs do not guarantee exact geometry.

A @deftech{drawing scalar} is a real number in the inclusive range
@racket[-3.402823e38] through @racket[3.402823e38]. The range excludes infinities
and NaNs.

Unless an entry states otherwise, this range applies to real-valued drawing
parameters, including coordinates, dimensions, angles, scale factors, and
coefficients. It also applies to components supplied in lists or vectors,
such as points, rectangles, and matrices. Individual entries state additional
restrictions or exceptions rather than repeating this general rule.
For example, @seclink["skia-projective-matrices"]{projective matrices} accept a
slightly wider range.
A nonnegative dimension may be zero. A pixel dimension instead uses an exact
integer and follows the bounds stated by the constructor.

The initial origin of a CPU surface is its upper-left corner. The x coordinate
increases to the right and the y coordinate increases downward. One drawing
unit initially corresponds to one pixel. @tech{Canvas transforms} change the mapping
for subsequent drawing; they do not move pixels already drawn.

The transform-order coordinate diagram in @secref["skia-canvas-transforms"]
shows the initial rightward-x/downward-y axes and the distinction between call
order and point-application order.

The arguments @racket[_x], @racket[_y], @racket[_width], and @racket[_height]
describe a rectangle by position and size, not by opposite corners. Its computed
right and bottom coordinates must also fit the drawing-scalar range. Operations
that enlarge bounds with padding, such as @racket[draw-rasterized] and
@racket[draw-output-group], require the enlarged bounds to fit this range too.

@section[#:tag "skia-antialiasing"]{Pixel Coverage and Antialiasing}

@deftech{Antialiasing} smooths shape edges by allowing fractional pixel coverage.
A boundary pixel can be partially covered instead of being either fully covered
or excluded. This applies to both drawn shapes and clipping boundaries.

Antialiasing is distinct from image sampling, which determines how source pixels
are selected or interpolated when drawing an image. See @secref["skia-image-drawing"].

@section{Errors and Stability}

Invalid argument types, option symbols, or argument relationships raise an
exception. An entry names a more specific exception class only when that class
is part of its contract. Resource validity is described in @secref["skia-resources"].

The compatibility policy distinguishes stable call boundaries from experimental
GPU, GUI, and interoperability interfaces. Stability does not imply identical
pixels across platforms. The complete policy is described in the
@hyperlink["https://github.com/soegaard/skia-for-racket/blob/main/docs/API-CONTRACTS.md"]{
public API contracts}.

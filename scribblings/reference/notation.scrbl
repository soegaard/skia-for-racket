#lang scribble/manual

@(require (for-label racket/base racket/contract skia))

@title[#:tag "skia-notation"]{Notation and Conventions}

@section{Signatures and Results}

An entry gives the arguments, their contracts, and the result contract. An
optional argument has a default value. Keyword names are literal parts of a
call. The notation follows
@secref["notation" #:doc '(lib "scribblings/reference/reference.scrbl")].

The displayed contracts describe the interface; they do not install runtime
contract wrappers. Additional relationships, such as a rectangle fitting inside
an image or a resource being open, are stated in the entry's description.
The result contract @racket[any] permits any number of values. A result written
with @racket[values] lists separate returned values, not elements of a list.
An ellipsis after an argument indicates repetition: @racket[...] permits zero
or more arguments, while @racket[...+] requires at least one. A constant's header
gives its name and value contract without an application form.

@section[#:tag "skia-scalars"]{Coordinates and Numeric Limits}

A @deftech{drawing scalar} is a real number in the inclusive range
@racket[-3.402823e38] through @racket[3.402823e38]. The range excludes infinities
and NaNs. Native drawing uses single-precision floating-point coordinates;
exact inputs are not a promise of exact geometry after conversion.

The signatures use @racket[real?] for coordinate arguments. Unless an entry
states otherwise, each such argument must also be a @tech{drawing scalar}.
A nonnegative dimension may be zero. A pixel dimension instead uses an exact
integer and follows the bounds stated by the constructor.

The initial origin of a CPU surface is its upper-left corner. The x coordinate
increases to the right and the y coordinate increases downward. One drawing
unit initially corresponds to one pixel. Canvas transforms change the mapping
for subsequent drawing; they do not move pixels already drawn.

The transform-order coordinate diagram in @secref["skia-canvas-transforms"]
shows the initial rightward-x/downward-y axes and the distinction between call
order and point-application order.

The arguments @racket[_x], @racket[_y], @racket[_width], and @racket[_height]
describe a rectangle by position and size, not by opposite corners. Its computed
right and bottom coordinates must also fit the drawing-scalar range.

@section{Errors and Stability}

Invalid argument types, option symbols, or argument relationships raise an
exception. An entry names a more specific exception class only when that class
is part of its contract. Resource validity is described in @secref["skia-resources"].

The compatibility policy distinguishes stable call boundaries from experimental
GPU, GUI, and interoperability interfaces. Stability does not imply identical
pixels across platforms. The complete policy is described in the
@hyperlink["https://github.com/soegaard/skia-for-racket/blob/main/docs/API-CONTRACTS.md"]{
public API contracts}.

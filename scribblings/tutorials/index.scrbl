#lang scribble/manual

@(require (for-label skia))

@title{Skia Tutorials}

These tutorials are a practical introduction to @racketmodname[skia]. Each one
builds a small, complete result while introducing one main idea. Start with
Quick, then follow the groups below in order or choose the subject that fits
the drawing you want to make.

The tutorials assume basic familiarity with Racket. They teach Skia concepts
through runnable examples and link to complete standalone programs where
appropriate. For exhaustive contracts and API details, use the Guide and API
reference alongside them.

@section{Start Here}

@itemlist[
 @item{@hyperlink["../quick/quick.html"]{Quick: An Introduction to Skia with Pictures} —
       create a surface, draw simple geometry, use paints, and save an image.}
 @item{@hyperlink["../clock/clock.html"]{Transforms: Make an Analog Clock} —
       translate, rotate, scale, and scope canvas state.}
 @item{@hyperlink["../logo/logo.html"]{Paths: Make a Geometric Logo} —
       construct paths from lines and curves, then fill and stroke them.}
]

@section{Paint, Images, and Composition}

@itemlist[
 @item{@hyperlink["../images/images.html"]{Images: Make a Contact Sheet} —
       decode images, inspect their dimensions, crop, scale, and sample them.}
 @item{@hyperlink["../poster/poster.html"]{Paints, Gradients, and Shaders: Make a Poster} —
       combine colors, transparency, gradients, image shaders, and blend shaders.}
 @item{@hyperlink["../effects/effects.html"]{Effects and Filters: Make a Card with Shadows} —
       compare drop shadows, image blur, and mask blur while keeping geometry clear.}
 @item{@hyperlink["../pictures/pictures.html"]{Reusable Drawings: Record and Replay a Picture} —
       record drawing operations once and replay them with different placements and transforms.}
]

@section{Text}

@itemlist[
 @item{@hyperlink["../text/text.html"]{Text and Typography: Make a Type Specimen} —
       position simple text from an origin on a baseline and use measurements and metrics.}
 @item{@hyperlink["../shaping/shaping.html"]{Shaping and Multilingual Text: Make a Language Sampler} —
       shape text, choose font fallback, handle right-to-left runs, and inspect glyph placement.}
 @item{@hyperlink["../paragraph/paragraph.html"]{Paragraph Layout: Make a Multilingual Article Card} —
       wrap mixed-direction text into measured lines with paragraph-level layout.}
]

@section{Documents and Rendering Boundaries}

@itemlist[
 @item{@hyperlink["../pdf-svg/pdf-svg.html"]{PDF and SVG: Make a Printable Diagram} —
       draw in physical units, add page margins, and export the same drawing to vector documents.}
 @item{@hyperlink["../vector-raster/vector-raster.html"]{Vector Output and Raster Fallbacks: What Stays Vector?} —
       distinguish vector operations, embedded images, and deliberate bounded raster fallbacks.}
]

@section{GPU Rendering}

@itemlist[
 @item{@hyperlink["../gpu/gpu.html"]{GPU: Render One Scene on CPU and Metal} —
       reuse one drawing function for CPU and Metal, and return a CPU-owned image after GPU readback.}
 @item{@hyperlink["../animation/animation.html"]{Animation: Orbiting Lights in a Window} —
       draw frames from elapsed time, schedule redraws, pause, and select CPU or GPU presentation.}
]

@section{Choosing a Path}

If you are new to Skia, read Quick, Clock, and Logo first. Follow with Images
and Poster for everyday drawing work. Choose the Text sequence when your work
contains writing, and the document tutorials when you need PDF or SVG output.
The GPU tutorial explains rendering a single image on a GPU. Animation then
shows why maintaining a renderer across successive window frames is useful.

The repository's @filepath{docs/TUTORIAL-GUIDELINES.md} describes the
conventions shared by these examples, including runnable documentation,
resource-lifetime style, and figure generation.

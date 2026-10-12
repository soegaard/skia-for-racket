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
 @item{@seclink[#:doc '(lib "skia/scribblings/quick/quick.scrbl")
          "top"]{Quick: An Introduction to Skia with Pictures} —
       create a surface, draw simple geometry, use paints, and save an image.}
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/clock/clock.scrbl")
          "top"]{Transforms and Coordinate Systems — Build a Clock} —
       translate, rotate, scale, and scope canvas state.}
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/logo/logo.scrbl")
          "top"]{Paths and Geometry — Draw a Logo} —
       construct paths from lines and curves, then fill and stroke them.}
]

@section{Paint, Images, and Composition}

@itemlist[
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/images/images.scrbl")
          "top"]{Images — Build a Contact Sheet} —
       decode images, inspect their dimensions, crop, scale, and sample them.}
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/poster/poster.scrbl")
          "top"]{Paints, Gradients, and Shaders — Make a Poster} —
       combine colors, transparency, gradients, image shaders, and blend shaders.}
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/effects/effects.scrbl")
          "top"]{Effects and Filters — Make a Card with Shadows} —
       compare drop shadows, image blur, and mask blur while keeping geometry clear.}
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/pictures/pictures.scrbl")
          "top"]{Reusable Drawings — Record and Replay a Picture} —
       record drawing operations once and replay them with different placements and transforms.}
]

@section{Text}

@itemlist[
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/text/text.scrbl")
          "top"]{Text and Typography — Make a Type Specimen} —
       position simple text from an origin on a baseline and use measurements and metrics.}
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/shaping/shaping.scrbl")
          "top"]{Shaping and Multilingual Text — Make a Language Sampler} —
       shape text, choose font fallback, handle right-to-left runs, and inspect glyph placement.}
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/paragraph/paragraph.scrbl")
          "top"]{Paragraph Layout — Make a Multilingual Article Card} —
       wrap mixed-direction text into measured lines with paragraph-level layout.}
]

@section{Documents and Rendering Boundaries}

@itemlist[
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/pdf-svg/pdf-svg.scrbl")
          "top"]{PDF and SVG — Make a Printable Diagram} —
       draw in physical units, add page margins, and export the same drawing to vector documents.}
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/vector-raster/vector-raster.scrbl")
          "top"]{Vector Output and Raster Fallbacks — What Stays Vector?} —
       distinguish vector operations, embedded images, and deliberate bounded raster fallbacks.}
]

@section{GPU Rendering and Interaction}

@itemlist[
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/gpu/gpu.scrbl")
          "top"]{GPU Rendering — Render the Same Scene on the GPU} —
       reuse one drawing function for CPU and Metal, and return a CPU-owned image after GPU readback.}
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/animation/animation.scrbl")
          "top"]{Animation — Orbiting Lights in a Window} —
       draw frames from elapsed time, schedule redraws, pause, and select CPU or GPU presentation.}
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/interaction/interaction.scrbl")
          "top"]{Interactive Paths — Drag Bézier Control Points} —
       select and drag control points, update a path, and redraw with CPU or GPU rendering.}
]

@section{Further Explorations}

@itemlist[
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/navigation/navigation.scrbl")
          "top"]{Zoom and Pan — Navigate an Interactive Canvas} —
       transform the view, invert pointer coordinates, and keep hit targets usable at every zoom.}
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/shaders/shaders.scrbl")
          "top"]{Runtime Shaders — Animate Prismatic Waves in a Window} —
       compile SkSL once, change a phase uniform over time, and display moving bands.}
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/pixels/pixels.scrbl")
          "top"]{Working with Pixels — Build a Two-Ink Image Processor} —
       distinguish mutable buffers, row strides, borrowed views, and independent snapshots.}
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/color-spaces/color-spaces.scrbl")
          "top"]{Color Spaces — Give Pixel Values Their Meaning} —
       declare sample meaning, convert between encodings, and save matching ICC metadata.}
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/path-ops/path-ops.scrbl")
          "top"]{Path Operations — Construct a Cutout Badge} —
       combine filled geometry with union, intersection, difference, exclusive-or, and simplification.}
]

@section{Sprite Atlases and Games}

@itemlist[
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/sprites/sprites.scrbl")
          "top"]{Sprite Atlases — Animate Bouncing Balls on the GPU} —
       upload a generated atlas once, retain it across frames, and batch sprite placements.}
 @item{@seclink[#:doc '(lib "skia/scribblings/tutorials/squadron/squadron.scrbl")
          "top"]{Star Squadron — Build a Galaga-Inspired Arcade Game} —
       combine sprite animation, fixed-step simulation, diving enemies, collisions, and scoring.}
]

@section{Choosing a Path}

If you are new to Skia, read Quick, Clock, and Logo first. Follow with Images
and Poster for everyday drawing work. Choose the Text sequence when your work
contains writing, and the document tutorials when you need PDF or SVG output.
The GPU tutorial explains rendering a single image on a GPU. Animation then
shows why maintaining a renderer across successive window frames is useful.
Interactive Paths builds on those window callbacks to introduce mouse input,
hit testing, and an editable drawing model.

The repository's @filepath{docs/TUTORIAL-GUIDELINES.md} describes the
conventions shared by these examples, including runnable documentation,
resource-lifetime style, and figure generation.

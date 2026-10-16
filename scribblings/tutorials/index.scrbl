#lang scribble/manual

@(require "support/reader.rkt")

@title{Skia Tutorials}
@(tutorial-navigation #f #:index? #t)

Skia lets Racket programs draw shapes, text, and images on CPU surfaces, GPU
frames, and documents. Each tutorial builds a complete result around one main
idea. Begin with @tutorial-link["quick"], then choose a route for the work you
want to do. The routes are suggestions, not one mandatory sequence of 22 lessons.

The tutorials assume basic Racket knowledge: function calls, definitions, and
module imports. Each lesson names the drawing concepts it needs and links to
the lessons that introduce them. Skip a prerequisite when you already know
those concepts. Complete source files and the required fixtures are available
in every lesson's Complete Example section.

@section{Start with Drawing}

The foundation route introduces surfaces and paints, then coordinates, paths,
images, and shaders. Clock and Logo both build on Quick; neither requires the other.

@tutorial-route['("quick" "clock" "logo" "images" "poster")]

@section{Text and Printable Documents}

Start with Quick's drawing basics. The text route proceeds from simple text to
single shaped runs and then paragraphs. The printable diagram uses text placement
and single-font paragraph wrapping; its caption does not require mixed-script layout.

@tutorial-route['("text" "shaping" "paragraph" "pdf-svg")]

@section{Effects and Reusable Drawings}

Effects builds on Poster's paints. Pictures uses Clock's transforms to place
recorded drawings. Vector Output combines the document and effects lessons.

@tutorial-route['("effects" "pictures" "vector-raster")]

@section{Windows and Interactive Drawings}

Use Quick's drawing basics and Clock's coordinate transforms. GPU Rendering
first draws one image; Animation retains a renderer across window frames.
The editors then add pointer input and a transformed view.

@tutorial-route['("gpu" "animation" "interaction" "navigation")]

@section{Pixels and Color}

Use Images to learn image dimensions and sampling. Working with Pixels then
introduces mutable storage; Color Spaces explains what the sample values mean.

@tutorial-route['("images" "pixels" "color-spaces")]

@section{Programmable Paints}

Use Poster for shader coordinates and Animation for the window and timer.
Runtime Shaders combines those ideas in an animated, adjustable SkSL effect.

@tutorial-route['("poster" "shaders")]

@section{Constructed Geometry}

Use Logo to understand paths and fill rules. Path Operations combines filled
regions instead of placing each contour command by command.

@tutorial-route['("logo" "path-ops")]

@section{Sprite Animation and Games}

Use Images for source rectangles and sampling, and Animation for frame scheduling.
Sprite Atlases adds a retained GPU image; Star Squadron reuses that ownership
model for a playable game. The game does not require the editor or pixel lessons.

@tutorial-route['("images" "animation" "sprites" "squadron")]

@section[#:tag "running-examples"]{Running the Examples}

Install Skia and its native libraries before running the drawing programs. The
repository's @hyperlink["https://github.com/soegaard/skia-for-racket#readme"]{installation
instructions} describe the supported platforms and native-library setup. Shaped
text also needs HarfBuzz and suitable system fonts. Each lesson identifies extra
requirements such as a graphical session or a platform-specific GPU backend.

@subsection{From an Installed Package}

Use the example copier to create an editable directory containing the complete
program and its dependencies. For example, copy the contact sheet and its four
image fixtures:

@verbatim{
raco skia-examples images my-images
cd my-images
racket images/contact-sheet.rkt
}

The destination must not already exist. The copier preserves subdirectories
and writes a @filepath{README.txt} with the appropriate run commands. List all
available example names with @command-text["raco skia-examples --list"].

The copy contains example sources and fixtures, not a second Skia installation,
native libraries, or fonts. Keep Skia installed. Generated output files are
written relative to the directory from which you run the program, except where
a program accepts an explicit output path.

The Complete Example section of each lesson also links to every source file.
Those links are useful for inspecting individual files. When saving them by
hand, preserve the displayed directory names, especially @filepath{fixtures/}
and the @filepath{support/} directory shared by the two sprite examples.

@subsection{From a Repository Checkout}

Install or link the checkout as the Skia package using the repository's
installation instructions. From the repository root, the copier can also run
directly without waiting for the new @command-text["raco skia-examples"] command
to be indexed:

@verbatim{
racket tools/copy-tutorial-examples.rkt images ../my-images
cd ../my-images
racket images/contact-sheet.rkt
}

Create copies outside the checkout to keep generated images and edited examples
separate from the package sources. Repository-root commands shown inside a
lesson refer to the checkout, not to a copied example directory.

@subsection{Follow the Snippets}

To assemble a program from the teaching snippets, create a @tt{#lang racket}
file that requires @tt{skia}. Keep it in the copied example's own subdirectory
when a snippet imports a local file such as @filepath{scene.rkt}. Add other
imports where the lesson introduces them. An excerpt from a local GUI callback
is not a standalone program; the complete file provides its enclosing state.

@subsection{Choose a Renderer}

A CPU image example needs no graphical session. A CPU window still needs one.
The window examples accept @command-text["--renderer raster"] and
@command-text["--renderer gpu"]. GPU mode selects a platform backend; it is not
a promise that the hardware or driver is available, and it does not silently
retry a failed draw on the CPU.

Use @tutorial-link["gpu"] for the platform-specific image routes and
@tutorial-link["animation"] for window presentation and cleanup.

@section{Look Up an API}

The tutorials explain selected concepts through examples. The existing
@api-link[] provides function contracts and options. Follow a named tutorial above
to learn a concept, or consult that reference for the details of a particular operation.

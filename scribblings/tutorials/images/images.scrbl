#lang scribble/manual

@title{Images — Build a Contact Sheet}

@(require "eval.rkt"
          (for-label racket
                     skia))

This tutorial builds a contact sheet from several image files. The examples
load images, draw them at different sizes, compare sampling modes, crop images,
and arrange the results in a grid.

The tutorial assumes that you know the basics from
@italic{Quick: An Introduction to Skia with Pictures}.

The main idea is simple:

@centered{@bold{An image stores pixels. Drawing an image decides where and how
those pixels appear on a canvas.}}

@section{The Image Files}

This tutorial includes four small image files:

@itemlist[
 @item{@filepath{mountains.jpg} is a 360 by 240 JPEG.}
 @item{@filepath{flower.png} is a 240 by 320 PNG.}
 @item{@filepath{pattern.webp} is a 320 by 200 WebP image.}
 @item{@filepath{pixel-art.png} is a 24 by 24 PNG.}
]

The files are bundled with the documentation, so the examples do not need a
network connection.

The examples use @racket[tutorial-fixture] only to locate those bundled files.
In an ordinary program, pass your own path to @racket[image-from-file].

@section{Load an Image}

The @racket[image-from-file] function decodes an image file and returns an
owned Skia image.

@images-interaction[
(let ()
  (define image (image-from-file
    (tutorial-fixture "mountains.jpg")))
  (list (image-width image)
        (image-height image)))
]

The @racket[image-width] and @racket[image-height] functions report the image
dimensions in pixels.

The example uses an ordinary Racket binding. This CPU image has fallback
cleanup and can be reclaimed after it becomes unreachable. Use
@racket[with-skia] when prompt release matters, for example when processing many
large images in a loop.

@section{Draw at the Natural Size}

The @racket[draw-image] function places an image at its natural size.

@images-racketblock+eval[
(define (draw-natural-size canvas)
  (let ()
    (define image (image-from-file
      (tutorial-fixture "mountains.jpg")))
    (draw-image canvas image 80 40)))
]

@images-image[
(images-render-pict 520 320 draw-natural-size)
]

The position gives the upper-left corner of the image. The image itself is
still 360 pixels wide and 240 pixels high.

@section{Choose a Destination Size}

The @racket[draw-image-rect] function maps the complete source image to a
destination rectangle.

The following example puts the portrait image into a wide rectangle:

@images-racketblock+eval[
(define (draw-stretched-image canvas)
  (let ()
    (define image (image-from-file
      (tutorial-fixture "flower.png")))
    (draw-image-rect canvas image
                     70 55 380 180
                     #:sampling 'linear)))
]

@images-image[
(images-render-pict 520 290 draw-stretched-image)
]

The source image is 240 by 320, but the destination rectangle is 380 by 180.
The different aspect ratio stretches the image.

A small helper can preserve the aspect ratio:

@images-racketblock+eval[
(define (draw-image-fit canvas image x y width height
                        #:sampling [sampling 'linear])
  (define scale
    (min (/ width (image-width image))
         (/ height (image-height image))))
  (define draw-width (* scale (image-width image)))
  (define draw-height (* scale (image-height image)))
  (define draw-x (+ x (/ (- width draw-width) 2)))
  (define draw-y (+ y (/ (- height draw-height) 2)))
  (draw-image-rect canvas
                   image
                   draw-x draw-y
                   draw-width draw-height
                   #:sampling sampling))
]

The helper chooses one scale for both dimensions and centers the result inside
the destination rectangle.

@images-racketblock+eval[
(define (draw-fitted-image canvas)
  (let ()
    (define image (image-from-file
      (tutorial-fixture "flower.png")))
    (draw-image-fit canvas image
                    70 55 380 180)))
]

@images-image[
(images-render-pict 520 290 draw-fitted-image)
]

@section{Sampling Matters}

Resizing requires Skia to decide how source pixels contribute to destination
pixels. The @racket[#:sampling] argument has two choices: @racket['nearest]
and @racket['linear].

Nearest sampling keeps hard pixel boundaries. Linear sampling blends
neighboring pixels.

The difference is easy to see with the 24 by 24 pixel-art image:

@images-racketblock+eval[
(define (draw-sampling-demo canvas)
  (let ()
    (define image (image-from-file
      (tutorial-fixture "pixel-art.png")))
    (define font (make-font #:size 18))
    (define text (make-paint #:color "#26333D"))
    (draw-image-rect canvas image
                     35 45 220 220
                     #:sampling 'nearest)
    (draw-image-rect canvas image
                     285 45 220 220
                     #:sampling 'linear)
    (draw-simple-text canvas "'nearest"
                      105 292 font text)
    (draw-simple-text canvas "'linear"
                      360 292 font text)))
]

@images-image[
(images-render-pict 540 320 draw-sampling-demo)
]

The default sampling mode for @racket[draw-image-rect] is @racket['linear].
The default for @racket[draw-image] is @racket['nearest].

@section{Crop an Image}

The @racket[image-subset] function creates a new owned immutable image for a
rectangular part of another image.

Its source rectangle uses exact integer coordinates and must stay inside the
source image.

@images-racketblock+eval[
(define (draw-crop-demo canvas)
  (let ()
    (define image (image-from-file
      (tutorial-fixture "mountains.jpg")))
    (define crop (image-subset image
      120 45 150 135))
    (draw-image-fit canvas image
                    25 35 300 210)
    (draw-image-fit canvas crop
                    355 35 180 210)))
]

@images-image[
(images-render-pict 560 280 draw-crop-demo)
]

The crop is a separate owned Skia image. Both the source and the crop use
ordinary Racket bindings here. Each can be reclaimed after it becomes
unreachable.

@section{Build One Cell}

The contact sheet will repeat the same layout for several images. Each cell
contains a card, one fitted image, and a label.

@images-racketblock+eval[
(define card-color "#FFFFFF")
(define frame-color "#CBD0D4")
(define text-color "#26333D")

(define (draw-cell canvas image label x y
                   #:sampling [sampling 'linear])
  (let ()
    (define card (make-paint #:color card-color))
    (define frame (make-paint #:color frame-color
      #:style 'stroke
      #:stroke-width 2))
    (define text (make-paint #:color text-color))
    (define font (make-font #:size 16))
    (draw-rounded-rect canvas x y 260 250 14 14 card)
    (draw-rounded-rect canvas x y 260 250 14 14 frame)
    (draw-image-fit canvas image
                    (+ x 15) (+ y 15)
                    230 185
                    #:sampling sampling)
    (draw-simple-text canvas label
                      (+ x 16) (+ y 229)
                      font text)))
]

The function receives an image. It does not need to know which file produced
that image.

@section{Build the Contact Sheet}

The final sheet uses four complete images and two crops.

@images-racketblock+eval[
(define (draw-contact-sheet canvas
                            mountains flower pattern pixels
                            mountain-crop flower-crop)
  (draw-cell canvas mountains "mountains.jpg" 30 30)
  (draw-cell canvas flower "flower.png" 320 30)
  (draw-cell canvas pattern "pattern.webp" 610 30)
  (draw-cell canvas pixels "pixel-art.png" 30 320
             #:sampling 'nearest)
  (draw-cell canvas mountain-crop "mountain crop" 320 320)
  (draw-cell canvas flower-crop "flower crop" 610 320))
]

@images-racketblock+eval[
(define (draw-complete-sheet canvas)
  (let ()
    (define mountains (image-from-file
      (tutorial-fixture "mountains.jpg")))
    (define flower (image-from-file
      (tutorial-fixture "flower.png")))
    (define pattern (image-from-file
      (tutorial-fixture "pattern.webp")))
    (define pixels (image-from-file
      (tutorial-fixture "pixel-art.png")))
    (define mountain-crop (image-subset mountains
      120 45 150 135))
    (define flower-crop (image-subset flower
      45 35 150 150))
    (draw-contact-sheet canvas
                        mountains flower pattern pixels
                        mountain-crop flower-crop)))
]

@images-image[
(images-render-pict 900 600 draw-complete-sheet)
]

The source images and crops remain reachable for the whole drawing operation.
After the drawing function returns, ordinary garbage collection can reclaim
them when they are no longer referenced.

@section{Save the Result}

The finished contact sheet is a raster surface, so @racket[save-png] can save
it directly:

@racketblock[
(let ()
  (define surface (make-surface 900 600
    #:background "#ECE8DF"))
  (draw-complete-sheet (surface-canvas surface))
  (save-png surface "contact-sheet.png"
            #:exists 'replace))
]

The @racket[save-image] function is useful when you already have an image
instead of a surface. It can encode PNG, JPEG, or WebP:

@racketblock[
(let ()
  (define image (image-from-file "photo.png"))
  (save-image image "photo.webp" 'webp
              #:exists 'replace))
]

Encoding options such as JPEG quality, WebP lossless mode, and color-space
metadata belong in the Guide.

@section{Try It}

Try replacing one bundled fixture with one of your own image files.

Try changing the pixel-art cell from @racket['nearest] to @racket['linear].
Compare the result at a large size.

Try changing the crop rectangle. Remember that the rectangle must remain
inside the source image.

Try changing @racket[draw-image-fit] so that an image fills the destination
rectangle completely, even when part of the image must be cropped.

@section{Where to Go From Here}

This tutorial used file decoding, image dimensions, natural-size drawing,
destination rectangles, aspect-ratio-preserving fitting, sampling, cropping,
and raster output.

The Guide will cover image metadata, encoded formats, orientation, direct
subrect drawing, pixel access, raster buffers, color spaces, animated images,
and GPU images in more detail.

The complete @filepath{contact-sheet.rkt} example contains the finished
program from this tutorial.

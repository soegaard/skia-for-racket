#lang racket/base

;;;
;;; Document Pages and Encoding
;;;

;; Describes physical output pages and renders them to images, PDF, or SVG.
;; This public output layer applies units, margins, backgrounds, and page callbacks before encoding
;; or saving the requested result.

;;;
;;; Imports and Exports
;;;

(require file/convertible
         "color.rkt" "private/core.rkt" "private/check.rkt"
         "private/output-util.rkt" "private/pdf-util.rkt" "private/svg-util.rkt"
         "private/audit-trace.rkt")
(provide unit->points output-page? make-output-page
         output-page-width output-page-height output-page-unit
         output-page-margins output-page-background output-page-clip?
         output-page-size-in-points output-page-content-size
         draw-output-page output-page->image output->bytes save-output)

;; A page describes how to draw; it owns no native resource. The callback can
;; close over resources, whose lifetimes remain the caller's responsibility.
(struct output-page (width height unit margins background clip? draw)
  #:transparent #:constructor-name make-output-page-record
  #:property prop:convertible
  (lambda (value request default)
    ;; Do not validate or draw for a request this page does not support. The
    ;; scoped image owns the rasterization result only long enough to encode it.
    (case request
      [(png-bytes)
       (with-skia ([image (output-page->image value)])
         (image->png-bytes image))]
      [(pdf-bytes) (output->bytes value 'pdf)]
      [(svg-bytes) (output->bytes value 'svg)]
      [else default])))
;; An output-page describes reusable authoring instructions, not a native page.
;;  - width       positive real  Full page width in the chosen unit.
;;  - height      positive real  Full page height in the chosen unit.
;;  - unit        symbol?        'pt, 'in, 'mm, 'cm, or 'px.
;;  - margins     (listof real?) Four nonnegative insets, left, top, right, bottom;
;;                              paired insets must leave positive content extents.
;;  - background  #f or rgba?    Copied page color; #f leaves the background alone.
;;  - clip?       boolean?       Whether the drawing callback is clipped to content.
;;  - draw        procedure?    Callback accepting a borrowed canvas in page units.
;; Construction validates the description but does not invoke the callback. The
;; caller keeps any resources captured by draw valid for every rendering.

; unit->points : real? [(or/c 'pt 'in 'mm 'cm 'px)] -> real?
;;   Converts a length to points.
(define (unit->points value [unit 'pt])
  (define factor (output-unit-factor 'unit->points unit))
  (scalar 'unit->points value)
  (define points (* value factor))
  (scalar 'unit->points points)
  points)

; make-output-page : (and/c real? (>/c 0)) (and/c real? (>/c 0)) (-> canvas? any) [#:unit (or/c 'pt
;   'in 'mm 'cm 'px)] [#:margins (or/c real? list?)] [#:background (or/c color? #f)] [#:clip?
;   boolean?] -> output-page?
;;   Returns a page description without invoking draw or allocating native storage.
(define (make-output-page width height draw #:unit [unit 'pt]
                          #:margins [margins 0] #:background [background #f]
                          #:clip? [clip? #t])
  (define who 'make-output-page)
  (define factor (output-unit-factor who unit))
  (positive-scalar who width)
  (positive-scalar who height)
  ;; Use the shared PDF/SVG size domain, without allocating an RGBA page.
  (pdf-page-dimension who (* width factor))
  (pdf-page-dimension who (* height factor))
  (output-drawing-procedure who draw)
  (boolean who clip?)
  (define insets (output-insets who margins))
  (unless (and (< (+ (car insets) (caddr insets)) width)
               (< (+ (cadr insets) (cadddr insets)) height))
    (raise-arguments-error who "margins must leave a positive content area"
                           "page size" (list width height) "margins" insets))
  (define bg (and background (color->rgba background)))
  (make-output-page-record width height unit insets bg clip? draw))

; check-page : symbol? output-page? -> output-page?
;;   Checks a reusable page description without running its drawing callback.
(define (check-page who p)
  (unless (output-page? p) (raise-argument-error who "output-page?" p))
  p)

; output-page-size-in-points : output-page? -> (values real? real?)
;;   Returns the full page width and height converted to points, without subtracting margins.
(define (output-page-size-in-points page)
  (check-page 'output-page-size-in-points page)
  (define factor (output-unit-factor 'output-page-size-in-points (output-page-unit page)))
  (values (* (output-page-width page) factor) (* (output-page-height page) factor)))

; output-page-content-size : output-page? -> (values real? real?)
;;   Returns width and height after subtracting margins, in the page's own units, not points.
(define (output-page-content-size page)
  (check-page 'output-page-content-size page)
  (define m (output-page-margins page))
  (values (- (output-page-width page) (car m) (caddr m))
          (- (output-page-height page) (cadr m) (cadddr m))))

; page-raster-scale : symbol? output-page? real? -> real?
;;   Converts document DPI to a checked pixel scale in the page's logical units.
(define (page-raster-scale who page dpi)
  (define scale (* (/ dpi 72) (output-unit-factor who (output-page-unit page))))
  (raster-output-scale who scale))

; draw-output-page : canvas? output-page? [#:text-mode (or/c 'native 'outline)] [#:raster-dpi
;   (real-in 1 9600)] -> void?
;;   Draws the page on a canvas whose current coordinate unit is treated as a point.
(define (draw-output-page c page #:text-mode [mode 'native] #:raster-dpi [dpi 144])
  (define who 'draw-output-page)
  (check-page who page)
  (output-text-mode who mode)
  (pdf-raster-dpi who dpi)
  (define scale (page-raster-scale who page dpi))
  (define factor (output-unit-factor who (output-page-unit page)))
  (define m (output-page-margins page))
  (define-values (cw ch) (output-page-content-size page))
  (with-canvas-state c
    (canvas-scale! c factor)
    ;; Drawing a background is not canvas-clear!: it does not replace content
    ;; that the caller previously drew outside this page's rectangle.
    (when (output-page-background page)
      (with-skia ([paint (make-paint #:color (output-page-background page))])
        (draw-rect c 0 0 (output-page-width page) (output-page-height page) paint)))
    (canvas-translate! c (car m) (cadr m))
    (when (output-page-clip? page) (canvas-clip-rect! c 0 0 cw ch))
    (parameterize ([current-text-output-mode mode]
                   [current-raster-output-scale scale])
      (call-with-values (lambda () ((output-page-draw page) c))
                        (lambda ignored (void)))))
  (void))

; output-page->image : output-page? [#:dpi (real-in 1 9600)] [#:text-mode (or/c 'native 'outline)]
;   [#:color-space (or/c color-space? #f)] -> image?
;;   Returns an owned raster image of the page.
(define (output-page->image page #:dpi [dpi 96] #:text-mode [mode 'native]
                            #:color-space [cs #f])
  (define who 'output-page->image)
  (check-page who page)
  (output-text-mode who mode)
  (pdf-raster-dpi who dpi)
  (page-raster-scale who page dpi)
  (define-values (w h) (output-page-size-in-points page))
  (define pw (inexact->exact (ceiling (* w (/ dpi 72)))))
  (define ph (inexact->exact (ceiling (* h (/ dpi 72)))))
  (check-dimensions who pw ph)
  (with-skia ([surface (make-surface pw ph #:color-space cs)])
    (define c (surface-canvas surface))
    ;; Preserve logical dimensions when the enclosing raster has rounded sizes.
    (canvas-scale! c (/ pw w) (/ ph h))
    (draw-output-page c page #:text-mode mode #:raster-dpi dpi)
    (surface-snapshot surface)))

; check-format : symbol? any/c -> (or/c 'pdf 'svg)
;;   Checks and returns the requested document output format.
(define (check-format who format)
  (unless (memq format '(pdf svg))
    (raise-argument-error who "'pdf or 'svg" format))
  format)

; output-pages : symbol? any/c symbol? -> (listof output-page?)
;;   Normalizes pages in authoring order and requires exactly one viewport for SVG.
(define (output-pages who source format)
  (check-format who format)
  (define pages
    (cond [(output-page? source) (list source)]
          [(and (list? source) (pair? source) (andmap output-page? source)) source]
          [else
           (raise-argument-error who "output-page? or nonempty list of output-page? values" source)]))
  (when (and (eq? format 'svg) (not (= (length pages) 1)))
    (raise-arguments-error who "SVG output requires exactly one page; no page is silently dropped"
                           "page count" (length pages)))
  pages)

; output->bytes : (or/c output-page? (listof output-page?)) (or/c 'pdf 'svg) [#:title string?]
;   [#:description string?] [#:text-mode (or/c 'auto 'native 'outline)] [#:raster-dpi (real-in 1
;   9600)] [#:id-prefix (or/c string? #f)] [#:encoding-quality (or/c (integer-in 0 101) #f)]
;   [#:pdfa? boolean?] -> (and/c bytes? (not/c immutable?))
;;   Returns a completed PDF or SVG byte string.
(define (output->bytes source format #:title [title ""] #:description [description ""]
                       #:text-mode [mode 'auto] #:raster-dpi [dpi 144]
                       #:id-prefix [prefix #f] #:encoding-quality [quality #f]
                       #:pdfa? [pdfa? #f])
  (define who 'output->bytes)
  (boolean who pdfa?)
  (when (and pdfa? (eq? format 'svg))
    (raise-arguments-error who "#:pdfa? is PDF-only" "given" pdfa?))
  (define pages (output-pages who source format))
  (output-text-mode who mode #:auto? #t)
  (pdf-raster-dpi who dpi)
  ;; All pages and export settings are checked before drawing the first page.
  (for ([page (in-list pages)]) (page-raster-scale who page dpi))
  (define effective-mode (if (eq? mode 'auto) (if (eq? format 'svg) 'outline 'native) mode))
  (cond
    [(eq? format 'pdf)
     (when prefix (raise-arguments-error who "#:id-prefix is SVG-only" "given" prefix))
     (define q (if quality (pdf-encoding-quality who quality) 101))
     (pdf-metadata-bytes who (list title description))
     (call-with-pdf-bytes
      (lambda (doc)
        (for ([page (in-list pages)] [index (in-naturals 1)])
          (define-values (w h) (output-page-size-in-points page))
          (parameterize ([audit-page-index index])
            (call-with-document-page
             doc w h
             (lambda (c) (draw-output-page c page #:text-mode effective-mode #:raster-dpi dpi))))))
      #:title title #:subject description #:raster-dpi dpi #:encoding-quality q #:pdfa? pdfa?)]
    [else
     (when quality (raise-arguments-error who "#:encoding-quality is PDF-only" "given" quality))
     (define id (or prefix "skia"))
     (svg-id-prefix who id)
     (define-values (_title _desc) (svg-metadata who title description))
     (define page (car pages))
     (define-values (w h) (output-page-size-in-points page))
     (svg-with-point-size
      who
      (call-with-svg-bytes
       w h (lambda (c) (draw-output-page c page #:text-mode effective-mode #:raster-dpi dpi))
       #:title title #:description description #:id-prefix id)
      w h)]))

; save-output : (or/c output-page? (listof output-page?)) path-string? (or/c 'pdf 'svg) [#:exists
;   (or/c 'error 'replace)] [#:title string?] [#:description string?] [#:text-mode (or/c 'auto
;   'native 'outline)] [#:raster-dpi (real-in 1 9600)] [#:id-prefix (or/c string? #f)]
;   [#:encoding-quality (or/c (integer-in 0 101) #f)] [#:pdfa? boolean?] -> void?
;;   Exports as in output->bytes and publishes the completed file.
(define (save-output source filename format #:exists [exists 'error]
                     #:title [title ""] #:description [description ""]
                     #:text-mode [mode 'auto] #:raster-dpi [dpi 144]
                     #:id-prefix [prefix #f] #:encoding-quality [quality #f]
                       #:pdfa? [pdfa? #f])
  (define who 'save-output)
  (check-format who format)
  ;; Resolve/check the destination before invoking the drawing callback.
  (define target
    ((if (eq? format 'pdf) pdf-output-path svg-output-path) who filename exists))
  (define bytes (output->bytes source format #:title title #:description description
                               #:text-mode mode #:raster-dpi dpi
                               #:id-prefix prefix #:encoding-quality quality #:pdfa? pdfa?))
  ((if (eq? format 'pdf) write-pdf-file-bytes! write-svg-file-bytes!) who bytes target exists))

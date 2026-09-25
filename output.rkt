#lang racket/base
(require "color.rkt" "private/core.rkt" "private/check.rkt"
         "private/output-util.rkt" "private/pdf-util.rkt" "private/svg-util.rkt")
(provide unit->points output-page? make-output-page
         output-page-width output-page-height output-page-unit
         output-page-margins output-page-background output-page-clip?
         output-page-size-in-points output-page-content-size
         draw-output-page output-page->image output->bytes save-output)

;; A page describes how to draw; it owns no native resource. The callback can
;; close over resources, whose lifetimes remain the caller's responsibility.
(struct output-page (width height unit margins background clip? draw)
  #:transparent #:constructor-name make-output-page-record)

(define (unit->points value [unit 'pt])
  (define factor (output-unit-factor 'unit->points unit))
  (scalar 'unit->points value)
  (define points (* value factor))
  (scalar 'unit->points points)
  points)

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

(define (check-page who p)
  (unless (output-page? p) (raise-argument-error who "output-page?" p))
  p)

(define (output-page-size-in-points page)
  (check-page 'output-page-size-in-points page)
  (define factor (output-unit-factor 'output-page-size-in-points (output-page-unit page)))
  (values (* (output-page-width page) factor) (* (output-page-height page) factor)))

(define (output-page-content-size page)
  (check-page 'output-page-content-size page)
  (define m (output-page-margins page))
  (values (- (output-page-width page) (car m) (caddr m))
          (- (output-page-height page) (cadr m) (cadddr m))))

(define (page-raster-scale who page dpi)
  (define scale (* (/ dpi 72) (output-unit-factor who (output-page-unit page))))
  (raster-output-scale who scale))

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

(define (check-format who format)
  (unless (memq format '(pdf svg))
    (raise-argument-error who "'pdf or 'svg" format))
  format)

(define (output-pages who source format)
  (check-format who format)
  (define pages
    (cond [(output-page? source) (list source)]
          [(and (list? source) (pair? source) (andmap output-page? source)) source]
          [else (raise-argument-error who "output-page? or nonempty list of output-page? values" source)]))
  (when (and (eq? format 'svg) (not (= (length pages) 1)))
    (raise-arguments-error who "SVG output requires exactly one page; no page is silently dropped"
                           "page count" (length pages)))
  pages)

(define (output->bytes source format #:title [title ""] #:description [description ""]
                       #:text-mode [mode 'auto] #:raster-dpi [dpi 144]
                       #:id-prefix [prefix #f] #:encoding-quality [quality #f])
  (define who 'output->bytes)
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
        (for ([page (in-list pages)])
          (define-values (w h) (output-page-size-in-points page))
          (call-with-document-page
           doc w h
           (lambda (c) (draw-output-page c page #:text-mode effective-mode #:raster-dpi dpi)))))
      #:title title #:subject description #:raster-dpi dpi #:encoding-quality q)]
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

(define (save-output source filename format #:exists [exists 'error]
                     #:title [title ""] #:description [description ""]
                     #:text-mode [mode 'auto] #:raster-dpi [dpi 144]
                     #:id-prefix [prefix #f] #:encoding-quality [quality #f])
  (define who 'save-output)
  (check-format who format)
  ;; Resolve/check the destination before invoking the drawing callback.
  (define target
    ((if (eq? format 'pdf) pdf-output-path svg-output-path) who filename exists))
  (define bytes (output->bytes source format #:title title #:description description
                               #:text-mode mode #:raster-dpi dpi
                               #:id-prefix prefix #:encoding-quality quality))
  ((if (eq? format 'pdf) write-pdf-file-bytes! write-svg-file-bytes!) who bytes target exists))

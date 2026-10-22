#lang racket/base

;;;
;;; Output Geometry and Policy
;;;

;; Normalizes page units, insets, text modes, labels, and raster fallback dimensions.
;; Provides common settings used by PDF, SVG, and raster exporters.

(require "check.rkt")
(provide output-unit-factor output-insets output-text-mode raster-output-scale
         output-drawing-procedure output-label rasterized-geometry svg-with-point-size)

; output-label : symbol? string? -> (and/c string? immutable?)
;   Checks the shared 1-through-200-character limit and copies a label for reports.
(define (output-label who label)
  (unless (and (string? label) (<= 1 (string-length label) 200))
    (raise-argument-error who "string containing 1 through 200 characters" label))
  (string->immutable-string label))

;; These factors are exact. Convert to C floats only at the drawing boundary.

; output-unit-factor : symbol? symbol? -> (and/c rational? exact?)
;   Returns points per pt, in, mm, cm, or px using exact conversion factors.
(define (output-unit-factor who unit)
  (case unit
    [(pt) 1] [(in) 72] [(mm) 360/127] [(cm) 3600/127] [(px) 3/4]
    [else (raise-argument-error who "'pt, 'in, 'mm, 'cm, or 'px" unit)]))

;; The order is left, top, right, bottom, not CSS's top/right/bottom/left.

; output-insets : symbol? any/c -> (list/c real? real? real? real?)
;   Checks nonnegative padding and returns left, top, right, and bottom in that order; a scalar
;   applies to all four sides.
(define (output-insets who v)
  (define xs
    (cond [(real? v) (list v v v v)]
          [(and (list? v) (= (length v) 4)) v]
          [else (raise-argument-error who
                                     "nonnegative real or (list left top right bottom)" v)]))
  (for/list ([x (in-list xs)])
    (nonnegative-scalar who x)
    x))

; output-text-mode : symbol? symbol? [#:auto? boolean?] -> symbol?
;   Checks native or outline text output, accepting auto only when the caller enables it.
(define (output-text-mode who mode #:auto? [auto? #f])
  (unless (memq mode (if auto? '(auto native outline) '(native outline)))
    (raise-argument-error who (if auto? "'auto, 'native, or 'outline" "'native or 'outline") mode))
  mode)

; raster-output-scale : symbol? real? -> real?
;   Checks an inclusive raster scale of 1/1024 through 1024 before dimension calculations.
(define (raster-output-scale who scale)
  (unless (and (real? scale) (<= 1/1024 scale 1024))
    (raise-argument-error who "finite raster scale from 1/1024 through 1024" scale))
  scale)

; output-drawing-procedure : symbol? procedure? -> procedure?
;   Checks that a drawing callback accepts one canvas argument without required keywords.
(define (output-drawing-procedure who proc)
  (unless (and (procedure? proc) (procedure-arity-includes? proc 1)
               (let-values ([(required allowed) (procedure-keywords proc)])
                 (null? required)))
    (raise-argument-error who
                          "procedure accepting one canvas argument and no required keywords" proc))
  proc)

; rasterized-geometry : symbol? real? real? real? any/c -> (values exact-positive-integer?
;   exact-positive-integer? real? real? real? real?)
;   Returns pixel width, pixel height, left inset, top inset, padded logical width, and padded
;   logical height after checking the RGBA byte budget.
(define (rasterized-geometry who width height scale padding)
  (define w (positive-scalar who width))
  (define h (positive-scalar who height))
  (raster-output-scale who scale)
  (define insets (output-insets who padding))
  (define left (car insets))
  (define top (cadr insets))
  (define bw (positive-scalar who (+ left w (caddr insets))))
  (define bh (positive-scalar who (+ top h (cadddr insets))))
  (define pw (inexact->exact (ceiling (* bw scale))))
  (define ph (inexact->exact (ceiling (* bh scale))))
  (check-dimensions who pw ph)
  (values pw ph left top bw bh))

; svg-with-point-size : symbol? bytes? real? real? -> bytes?
;   Rewrites only the generated SVG root's width and height in points, preserving its viewBox and
;   drawing body.
(define (svg-with-point-size who bs width height)
  ;; Only for completed XML emitted by our SVG backend, not an SVG importer.
  ;; Keep its viewBox and drawing body unchanged. Unit-bearing root dimensions
  ;; give PDF and SVG the same nominal physical size (before viewer CSS/zoom).
  (unless (bytes? bs) (raise-argument-error who "bytes?" bs))
  (define (check-size n)
    (unless (<= n (current-skia-byte-limit))
      (raise-arguments-error who "SVG output exceeds current-skia-byte-limit"
                             "required bytes" n "limit" (current-skia-byte-limit))))
  (check-size (bytes-length bs))
  (for ([n (in-list (list width height))]) (positive-scalar who n))
  (define found (regexp-match-positions #rx#"<svg[ \t\r\n][^>]*>" bs))
  (unless found (error who "completed SVG has no root element"))
  (define start (caar found))
  (define end (cdar found))
  (define root (subbytes bs start end))
  (unless (and (regexp-match? #rx#" width=\"[^\"]*\"" root)
               (regexp-match? #rx#" height=\"[^\"]*\"" root))
    (error who "completed SVG root has no explicit size"))
  (define (pt n) (string->bytes/utf-8 (string-append (number->string (exact->inexact n)) "pt")))
  (define sized
    (regexp-replace #rx#" height=\"[^\"]*\""
                    (regexp-replace #rx#" width=\"[^\"]*\"" root
                                    (lambda (_) (bytes-append #" width=\"" (pt width) #"\"")))
                    (lambda (_) (bytes-append #" height=\"" (pt height) #"\""))))
  (check-size (+ (- (bytes-length bs) (- end start)) (bytes-length sized)))
  (bytes-append (subbytes bs 0 start) sized (subbytes bs end)))

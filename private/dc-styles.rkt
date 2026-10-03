#lang racket/base
;; Public racket/draw objects -> immutable, native-free paint descriptions.
(require racket/class racket/list
         (prefix-in rd: racket/draw)
         (only-in ffi/unsafe/atomic call-as-atomic)
         (only-in "check.rkt" current-skia-byte-limit check-dimensions)
         "dc-support.rkt" "dc-style-math.rkt" "dc-bitmap.rkt")
(provide dc-check-pen dc-check-brush dc-style-ink dc-style-color)
(define (dc-style-color who color)
  (unless (is-a? color rd:color%) (raise-argument-error who "color% object" color))
  (vector-immutable (send color red) (send color green) (send color blue)
                    (dc-unit who (send color alpha))))
(define (check-stipple who b)
  (unless (and (is-a? b rd:bitmap%) (send b ok?))
    (raise-argument-error who "valid stipple bitmap%" b))
  (define s (dc-real who (send b get-backing-scale)))
  (unless (> s 0) (raise-argument-error who "positive bitmap backing scale" s))
  (define w (inexact->exact (ceiling (* s (send b get-width)))))
  (define h (inexact->exact (ceiling (* s (send b get-height)))))
  (check-dimensions who w h)
  (when (> (* 12 w h) (current-skia-byte-limit))
    (raise-arguments-error who "stipple snapshot exceeds current-skia-byte-limit" "bytes" (* 12 w h)))
  (void))
(define (gradient-description who gradient)
  (define linear? (is-a? gradient rd:linear-gradient%))
  (unless (or linear? (is-a? gradient rd:radial-gradient%))
    (raise-argument-error who "linear-gradient% or radial-gradient%" gradient))
  (define geometry
    (for/list ([x (in-list (call-with-values
                           (lambda () (if linear? (send gradient get-line) (send gradient get-circles))) list))])
      (dc-real who x)))
  (unless linear?
    (dc-extent who (list-ref geometry 2)) (dc-extent who (list-ref geometry 5)))
  (define stops (send gradient get-stops))
  (unless (and (list? stops) (<= (* 40 (length stops)) (current-skia-byte-limit)))
    (raise-arguments-error who "gradient stops exceed current-skia-byte-limit" "limit" (current-skia-byte-limit)))
  (define checked
    (dc-gradient-stops who
      (for/list ([s (in-list stops)])
        (unless (and (list? s) (= (length s) 2))
          (raise-argument-error who "gradient stop pair" s))
        (list (car s) (dc-style-color who (cadr s))))
      (current-skia-byte-limit)))
  (vector-immutable (if linear? 'linear 'radial) geometry checked))
(define (check-transform who t)
  (when t
    (define m (dc-effective (dc-transformation who t)))
    ;; A singular pattern map has no inverse for native shader sampling.
    (dc-inverse who m))
  (void))
(define (dc-check-pen p)
  (unless (is-a? p rd:pen%) (raise-argument-error 'set-pen "pen% object" p))
  (unless (memq (send p get-style) dc-pen-styles)
    (raise-argument-error 'set-pen "supported pen style" (send p get-style)))
  (dc-extent 'set-pen (send p get-width)) (dc-style-color 'set-pen (send p get-color))
  (when (send p get-stipple) (check-stipple 'set-pen (send p get-stipple)))
  p)
(define (dc-check-brush b)
  (unless (is-a? b rd:brush%) (raise-argument-error 'set-brush "brush% object" b))
  (unless (memq (send b get-style) dc-brush-styles)
    (raise-argument-error 'set-brush "supported brush style" (send b get-style)))
  (when (send b get-handle)
    (dc-unsupported 'set-brush 'native-cairo-handle-brush "not supported; use public bitmap stipple"))
  (dc-style-color 'set-brush (send b get-color))
  (when (send b get-stipple) (check-stipple 'set-brush (send b get-stipple)))
  (when (send b get-gradient) (gradient-description 'set-brush (send b get-gradient)))
  (check-transform 'set-brush (send b get-transformation))
  b)
(define (dc-style-ink object stroke? old-ink background alpha drawing)
  ;; No native handles escape this function. Gradient colors/transform and
  ;; bitmap bytes are copied anew for each drawing operation. Locking a brush
  ;; does not make its bitmap or its gradient stop colors immutable.
  (call-as-atomic
   (lambda ()
     (define style (send object get-style))
     (define bitmap (send object get-stipple))
     (define gradient (and (not stroke?) (send object get-gradient)))
     (define t (and (not stroke?) (send object get-transformation)))
     (check-transform 'skia-dc-style t)
     (define-values (dashes phase)
       (if stroke? (dc-dash-spec style (send object get-width) bitmap) (values '() 0.0)))
     (define source
       (cond
         [gradient (dc-paint-source 'gradient (gradient-description 'skia-dc-gradient gradient)
                                    (dc-style-local-matrix drawing t 1.0))]
         [bitmap
          (check-stipple 'skia-dc-stipple bitmap)
          (define data (dc-bitmap-snapshot 'skia-dc-stipple bitmap
                                          (if (eq? style 'opaque) 'opaque 'solid)
                                          (send object get-color) #f background))
          (unless data (error 'skia-dc-stipple "stipple became invalid before snapshot"))
          (dc-paint-source 'stipple data
                           (dc-style-local-matrix drawing t (dc-bitmap-data-backing data)))]
         [(and (not stroke?) (memq style dc-hatch-styles))
          (when (> (* 12 12 8) (current-skia-byte-limit))
            (raise-arguments-error 'skia-dc-hatch "hatch tile exceeds current-skia-byte-limit"
                                   "limit" (current-skia-byte-limit)))
          (dc-paint-source 'hatch (vector-immutable style (dc-style-color 'skia-dc-hatch (send object get-color)))
                           dc-identity)]
         [else #f]))
     (define rgba
       (cond [source (vector-immutable 255 255 255 alpha)]
             [(eq? style 'hilite) (vector-immutable 0 0 0 (* 0.3 alpha))]
             [else (dc-ink-rgba old-ink)]))
     (dc-ink/style rgba stroke? (dc-ink-width old-ink) (dc-ink-cap old-ink)
                    (dc-ink-join old-ink) dashes source phase))))

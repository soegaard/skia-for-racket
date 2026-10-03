#lang racket/base
;; Compatibility for region%'s *query* callback. This scratch recording surface
;; never receives the Skia pixels and is never copied/composited to any output.
;; The only caller is the private in-cairo-context member in our region adapter.
(require (prefix-in c: racket/draw/unsafe/cairo)
         (only-in racket/draw/unsafe/cairo-lib cairo-lib)
         (only-in ffi/unsafe get-ffi-obj _fun _pointer _int)
         "dc-support.rkt")
(provide call-with-dc-region-query)
(define context-status (get-ffi-obj 'cairo_status cairo-lib (_fun _pointer -> _int)))
(define (check-context! cr)
  (define status (context-status cr))
  (unless (zero? status) (error 'skia-dc-region-query "Cairo query context failed with status ~a" status)))
(define (install-commands cr commands)
  (c:cairo_new_path cr)
  (for ([v (in-list commands)])
    (case (vector-ref v 0)
      [(move) (c:cairo_move_to cr (vector-ref v 1) (vector-ref v 2))]
      [(line) (c:cairo_line_to cr (vector-ref v 1) (vector-ref v 2))]
      [(cubic) (c:cairo_curve_to cr (vector-ref v 1) (vector-ref v 2) (vector-ref v 3)
                                   (vector-ref v 4) (vector-ref v 5) (vector-ref v 6))]
      [(close) (c:cairo_close_path cr)]
      [else (error 'skia-dc-region-query "invalid internal query path")]))
  (void))
(define (call-with-dc-region-query width height matrix clip proc)
  ;; A continuation cannot resume with a destroyed native context. Breaks are
  ;; deferred over allocation and retirement; dynamic-wind handles exceptions.
  (call-with-continuation-barrier
   (lambda ()
     (parameterize-break #f
       (define extent (c:make-cairo_rectangle_t 0.0 0.0 (exact->inexact width) (exact->inexact height)))
       (define surface (c:cairo_recording_surface_create c:CAIRO_CONTENT_COLOR_ALPHA extent))
       (unless surface (error 'skia-dc-region-query "Cairo recording surfaces are unavailable"))
       (dynamic-wind
        void
        (lambda ()
          (define cr (c:cairo_create surface))
          (dynamic-wind
           void
           (lambda ()
             (check-context! cr)
             (when clip
               (if (null? (dc-clip-paths clip))
                   (begin (c:cairo_new_path cr) (c:cairo_clip cr))
                   (for ([part (in-list (dc-clip-paths clip))])
                     (install-commands cr (dc-clip-path-commands part))
                     (c:cairo_set_fill_rule cr (if (eq? (dc-clip-path-rule part) 'odd-even)
                                                   c:CAIRO_FILL_RULE_EVEN_ODD c:CAIRO_FILL_RULE_WINDING))
                     (c:cairo_clip cr))))
             (c:cairo_set_matrix cr (apply c:make-cairo_matrix_t (vector->list matrix)))
             (check-context! cr)
             (begin0 (proc cr) (check-context! cr)))
           (lambda () (c:cairo_destroy cr))))
        (lambda () (c:cairo_surface_destroy surface)))))))

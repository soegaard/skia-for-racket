#lang racket/base

;;;
;;; Reference Geometry Test
;;;

;; Checks native path/region operations, copied geometry, canvas restoration, drawables, and atlas
;; cropping.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; Opt-in CPU tests for the R3g-a contracts. No GUI, GPU, or font lookup is needed.
(require rackunit racket/list racket/vector skia)


;;;
;;; Diagnostic Operations
;;;

; argb : surface? exact-nonnegative-integer? exact-nonnegative-integer? ->
; exact-nonnegative-integer?
;   Converts a sampled pixel to a packed ARGB value for exact geometry checks.
(define (argb surface x y) (color->argb (surface-pixel surface x y)))

; blue-box : canvas? -> void?
;   Draws an unaliased blue rectangle whose interior and exterior pixels are deterministic.
(define (blue-box canvas)
  (with-skia ([ink (make-paint #:color 'blue #:antialias? #f)])
    (draw-rect canvas 2 2 8 8 ink)))

(module+ test
  (test-case "ordered path operations begin empty and do not mutate input"
    (with-skia ([outer (make-path)] [hole (make-path)])
      (path-add-rect! outer 0 0 40 30)
      (path-add-circle! hole 20 15 5)
      (define before (path->commands outer))
      (with-skia ([result (path-combine
                          (list (list 'union outer) (list 'difference hole)))])
        (check-true (path-contains? result 2 2))
        (check-false (path-contains? result 20 15)))
      (check-equal? (path->commands outer) before)
      (with-skia ([empty (path-combine '())])
        (check-equal? (path-verbs empty) '()))))

  (test-case "rewind resets fill type and leaves detached snapshots intact"
    (with-skia ([path (make-path #:fill-rule 'even-odd)])
      (path-add-rect! path 1 2 8 6)
      (define saved (path->commands path))
      (path-rewind! path)
      (check-equal? (path-fill-rule path) 'winding)
      (check-equal? (path-verbs path) '())
      (check-true (pair? saved))
      (path-add-polygon! path '((0 0) (3 0) (3 3)) #:closed? #f)
      (check-equal? (path-segment-kinds path) '(line))))

  (test-case "recognition values survive source changes"
    (with-skia ([path (make-path)])
      (path-add-rect-start! path 1 2 8 6 2 #:direction 'ccw)
      (define description (path-as-rectangle path))
      (check-true (path-rectangle? description))
      (check-equal? (path-rectangle-direction description) 'ccw)
      (check-true (path-rectangle-closed? description))
      (path-reset! path)
      (check-equal? (path-rectangle-bounds description) #(1.0 2.0 8.0 6.0))
      (check-true (immutable? (path-rectangle-bounds description)))))

  (test-case "quadratic approximation returns copied shared endpoints"
    (define pieces (conic->quadratics '(0 0) '(2 4) '(4 0) 1/2 #:subdivisions 2))
    (check-true (<= 1 (length pieces) 4))
    (for ([piece pieces])
      (check-equal? (vector-length piece) 3)
      (check-true (immutable? piece))
      (for ([point (in-vector piece)]) (check-true (immutable? point))))
    (for ([a (in-list pieces)] [b (in-list (cdr pieces))])
      (check-equal? (vector-ref a 2) (vector-ref b 0))))

  (test-case "native rounded normalization does not mutate the specification"
    (define shape (make-rounded-rect 0 0 20 10 #:radii 30))
    (define normalized (rounded-rect-normalize shape))
    (check-equal? (vector-ref (rounded-rect-radii shape) 0) #(30.0 30.0))
    (check-not-equal? (rounded-rect-radii normalized) (rounded-rect-radii shape))
    (check-equal? (rounded-rect-bounds normalized) #(0.0 0.0 20.0 10.0))
    (check-false (rounded-rect-transform normalized (matrix-rotate-degrees 30)))
    (with-skia ([path (make-path)])
      (path-add-rrect! path normalized)
      (check-true (rounded-rect? (path-as-rounded-rect path)))))

  (test-case "regions use half-open coordinates and detached span snapshots"
    (with-skia ([region (make-region '((0 0 4 3) (6 0 2 3)))])
      (check-true (region-contains-point? region 0 0))
      (check-false (region-contains-point? region 4 1))
      (check-false (region-contains-point? region 2 3))
      (define spans (region-spans region 1 0 8))
      (define sequence (in-region-spans region 1 0 8))
      (check-equal? spans '(#(0 4) #(6 8)))
      (check-equal? (region-spans region 1 3 3) '())
      (region-clear! region)
      (skia-close! region)
      (check-equal? (for/list ([span sequence]) span) spans)))

  (test-case "quick region rejection is not the converse of intersection"
    (with-skia ([region (make-region '((0 0 2 8) (6 0 2 8)))])
      (check-false (region-intersects-rect? region '(3 2 2 2)))
      (check-false (region-quick-reject-rect? region '(3 2 2 2)))
      (check-true (region-quick-reject-rect? region '(20 20 2 2)))
      (with-skia ([other (region-op-rect region '(3 2 2 2) 'union)])
        (check-true (region-contains-point? other 3 2))
        (check-false (region-contains-point? region 3 2)))))

  (test-case "region clips ignore a translated local matrix"
    (with-skia ([surface (make-surface 10 10)]
                [region (make-region '((0 0 4 10)))])
      (define canvas (surface-canvas surface))
      (canvas-translate! canvas 100 100)
      (canvas-clip-region! canvas region)
      (draw-color canvas 'red)
      (check-equal? (argb surface 2 2) #xffff0000)
      (check-equal? (argb surface 7 2) 0)
      (check-equal? (canvas-device-clip-bounds canvas) #(0 0 4 10))))

  (test-case "points validate complete line pairs and portable markers use geometry"
    (with-skia ([surface (make-surface 16 16)]
                [paint (make-paint #:color 'red #:antialias? #f)])
      (define canvas (surface-canvas surface))
      (check-exn exn:fail? (lambda () (draw-points canvas '((1 1)) paint #:mode 'lines)))
      (check-equal? (argb surface 1 1) 0)
      (draw-markers canvas '((4 4) (12 4)) 4 paint #:shape 'square)
      (check-equal? (argb surface 4 4) #xffff0000)
      (check-equal? (argb surface 12 4) #xffff0000)))

  (test-case "vertices retain copied metadata even after native closure"
    (define positions (vector (vector 2 2) (vector 14 2) (vector 2 14)))
    (with-skia ([mesh (make-vertices 'triangles positions #:colors '(red red red))]
                [surface (make-surface 16 16)]
                [paint (make-paint #:color 'white #:antialias? #f)])
      (vector-set! (vector-ref positions 0) 0 99)
      (draw-vertices (surface-canvas surface) mesh paint)
      (check-equal? (argb surface 4 4) #xffff0000)
      (skia-close! mesh)
      (check-equal? (vertices-count mesh) 3)
      (check-equal? (vector-ref (vertices-positions mesh) 0) #(2.0 2.0))
      (check-true (immutable? (vertices-colors mesh)))
      (check-exn exn:fail? (lambda () (draw-vertices (surface-canvas surface) mesh paint)))))

  (test-case "canvas matrix scope restores the full matrix on escape"
    (with-skia ([surface (make-surface 16 16)])
      (define canvas (surface-canvas surface))
      (define before (canvas-matrix4 canvas))
      (check-exn exn:fail?
        (lambda ()
          (with-canvas-matrix canvas (matrix4-translate 3 4 5)
            (check-equal? (matrix4-ref (canvas-matrix4 canvas) 2 3) 5.0)
            (error 'expected "escape"))))
      (check-equal? (canvas-matrix4 canvas) before)
      (check-equal? (canvas-save-count canvas) 1)))

  (test-case "simple layer cleanup composites rather than rolling pixels back"
    (with-skia ([surface (make-surface 16 16)]
                [paint (make-paint #:color 'blue #:antialias? #f)])
      (define canvas (surface-canvas surface))
      (check-exn exn:fail?
        (lambda ()
          (with-canvas-layer canvas #:bounds '(0 0 16 16)
            (draw-rect canvas 2 2 8 8 paint)
            (error 'expected "escape"))))
      (check-equal? (canvas-save-count canvas) 1)
      (check-equal? (argb surface 5 5) #xff0000ff)))

  (test-case "advanced layer clip is explicit and state is restored"
    (with-skia ([surface (make-surface 16 16)]
                [paint (make-paint #:color 'blue #:antialias? #f)])
      (define canvas (surface-canvas surface))
      (check-equal?
       (call-with-values
        (lambda ()
          (call-with-canvas-layer-rec canvas
            (lambda () (draw-rect canvas 0 0 16 16 paint) (values 1 2))
            #:options (make-layer-options #:bounds '(0 0 16 16)) #:clip '(2 2 12 12)))
        list) '(1 2))
      (check-equal? (argb surface 0 0) 0)
      (check-equal? (argb surface 5 5) #xff0000ff)
      (check-equal? (canvas-device-clip-bounds canvas) #(0 0 16 16))))

  (test-case "drawables capture once and keep independent picture snapshots"
    (define calls 0)
    (with-skia ([drawable (call-with-drawable 16 16
                           (lambda (canvas) (set! calls (add1 calls)) (blue-box canvas)))]
                [surface (make-surface 16 16)]
                [picture (drawable->picture drawable)])
      (draw-drawable (surface-canvas surface) drawable)
      (draw-drawable (surface-canvas surface) drawable #:mode 'immediate)
      (check-equal? calls 1)
      (define old-id (drawable-generation-id drawable))
      (drawable-notify-drawing-changed! drawable)
      (check-not-equal? (drawable-generation-id drawable) old-id)
      (skia-close! drawable)
      (canvas-clear! (surface-canvas surface) 'transparent)
      (draw-picture (surface-canvas surface) picture)
      (check-equal? (argb surface 5 5) #xff0000ff)
      (check-equal? calls 1)))

  (test-case "no-draw canvas expires but preserves callback values"
    (define saved #f)
    (check-equal?
     (call-with-values
      (lambda ()
        (call-with-nodraw-canvas 16 16
          (lambda (canvas) (set! saved canvas) (blue-box canvas) (values 3 4))))
      list) '(3 4))
    (check-exn exn:fail? (lambda () (canvas-save-count saved))))

  (test-case "nway callback runs once and restores caller-owned targets"
    (with-skia ([a (make-surface 16 16)] [b (make-surface 16 16)])
      (define calls 0)
      (define saved #f)
      (call-with-nway-canvas (list a b)
        (lambda (canvas)
          (set! calls (add1 calls)) (set! saved canvas)
          (canvas-translate! canvas 1 1)
          (blue-box canvas)))
      (check-equal? calls 1)
      (for ([surface (in-list (list a b))])
        (check-false (skia-closed? surface))
        (check-equal? (argb surface 5 5) #xff0000ff)
        (check-equal? (canvas-matrix4 (surface-canvas surface)) matrix4-identity)
        (check-equal? (canvas-save-count (surface-canvas surface)) 1))
      (check-exn exn:fail? (lambda () (canvas-save-count saved)))
      (check-exn exn:fail? (lambda () (call-with-nway-canvas (list a a) void)))))

  (test-case "specialized target state is restored after callback failure"
    (with-skia ([a (make-surface 16 16)] [b (make-surface 16 16)])
      (check-exn exn:fail?
        (lambda ()
          (call-with-nway-canvas (list a b)
            (lambda (canvas) (canvas-translate! canvas 2 3) (error 'expected "escape")))))
      (for ([surface (in-list (list a b))])
        (check-equal? (canvas-matrix4 (surface-canvas surface)) matrix4-identity)
        (check-equal? (canvas-save-count (surface-canvas surface)) 1))))

  (test-case "overdraw requires Alpha8 and leaves target ownership with the caller"
    (with-skia ([rgba (make-surface 16 16)]
                [alpha (make-surface-from-info (make-image-info 16 16 #:color-type 'alpha-8))])
      (check-exn exn:fail? (lambda () (call-with-overdraw-canvas rgba void)))
      (call-with-overdraw-canvas alpha (lambda (canvas) (blue-box canvas) (blue-box canvas)))
      (check-false (skia-closed? alpha))
      (check-true (positive? (rgba-alpha (surface-pixel alpha 5 5))))))

  (test-case "portable atlas crops use integer inputs and restore matrix state"
    (with-skia ([tile (make-surface 2 2 #:background 'red)]
                [image (surface-snapshot tile)] [surface (make-surface 12 6)])
      (define canvas (surface-canvas surface))
      (draw-atlas/portable canvas image
        (list (make-atlas-transform 1 1) (make-atlas-transform 7 1 #:scale 2))
        '((0 0 2 2) (0 0 2 2)))
      (check-equal? (argb surface 1 1) #xffff0000)
      (check-equal? (argb surface 8 2) #xffff0000)
      (check-equal? (canvas-matrix4 canvas) matrix4-identity)
      (check-exn exn:fail?
        (lambda () (draw-atlas/portable canvas image (list (make-atlas-transform 0 0))
                                        '((0.5 0 1 1)))))))
)

#lang racket/base

;;;
;;; Bad Apple!! Native Scene
;;;

;; This module owns the native paths and paints for the player. Call it only on the GUI eventspace
;; handler that will draw and close the resources. Its incremental builder keeps a full preload from
;; monopolising that eventspace.

(require racket/list
         racket/vector
         "../../main.rkt"
         "data.rkt")

(provide bad-apple-scene?
         bad-apple-scene-frame-count
         bad-apple-scene-path-count
         bad-apple-scene-builder?
         bad-apple-scene-builder-asset
         make-bad-apple-scene-builder
         bad-apple-scene-builder-done?
         bad-apple-scene-builder-cancel!
         bad-apple-scene-builder-close!
         bad-apple-scene-builder-step!
         bad-apple-scene-builder-progress
         compile-bad-apple-scene
         bad-apple-scene-close!
         draw-bad-apple-frame)

(struct bad-apple-scene (frames fill white source->view-box path-count closed?) #:mutable #:transparent)

;; `paths-rev` contains newly constructed native paths for the frame currently being compiled.
;; Every path is registered immediately, making error/cancellation cleanup straightforward.
(struct bad-apple-scene-builder (asset frames frame-index path-index paths-rev fill white
                                       completed-paths total-paths scene cancelled? closed?)
  #:mutable
  #:transparent)

(define (bad-apple-scene-frame-count scene)
  (unless (bad-apple-scene? scene)
    (raise-argument-error 'bad-apple-scene-frame-count "bad-apple-scene?" scene))
  (vector-length (bad-apple-scene-frames scene)))

(define (close-paths! frames)
  (for ([frame (in-vector frames)] #:when frame)
    (for ([path (in-vector frame)] #:when path)
      (unless (skia-closed? path) (skia-close! path)))))

(define (close-path-list! paths)
  (for ([path (in-list paths)])
    (when (and path (not (skia-closed? path))) (skia-close! path))))

(define (make-bad-apple-scene-builder asset)
  (unless (bad-apple-asset? asset)
    (raise-argument-error 'make-bad-apple-scene-builder "bad-apple-asset?" asset))
  (define all-frames (bad-apple-asset-frames asset))
  (bad-apple-scene-builder
   asset (make-vector (vector-length all-frames) #f) 0 0 '()
   (make-paint #:color 'black #:antialias? #t)
   (make-paint #:color 'white #:antialias? #f)
   0 (for/sum ([frame (in-vector all-frames)]) (vector-length frame)) #f #f #f))

(define (bad-apple-scene-builder-done? builder)
  (and (bad-apple-scene-builder? builder) (bad-apple-scene-builder-scene builder)))

(define (bad-apple-scene-builder-progress builder)
  (unless (bad-apple-scene-builder? builder)
    (raise-argument-error 'bad-apple-scene-builder-progress "bad-apple-scene-builder?" builder))
  (values (bad-apple-scene-builder-completed-paths builder)
          (bad-apple-scene-builder-total-paths builder)
          (bad-apple-scene-builder-frame-index builder)
          (bad-apple-asset-frame-count (bad-apple-scene-builder-asset builder))))

(define (bad-apple-scene-builder-cancel! builder)
  (unless (bad-apple-scene-builder? builder)
    (raise-argument-error 'bad-apple-scene-builder-cancel! "bad-apple-scene-builder?" builder))
  (set-bad-apple-scene-builder-cancelled?! builder #t)
  (void))

(define (bad-apple-scene-builder-close! builder)
  (unless (bad-apple-scene-builder? builder)
    (raise-argument-error 'bad-apple-scene-builder-close! "bad-apple-scene-builder?" builder))
  (unless (bad-apple-scene-builder-closed? builder)
    (set-bad-apple-scene-builder-closed?! builder #t)
    (unless (bad-apple-scene-builder-scene builder)
      (close-paths! (bad-apple-scene-builder-frames builder))
      (close-path-list! (bad-apple-scene-builder-paths-rev builder))
      (for ([resource (list (bad-apple-scene-builder-fill builder)
                            (bad-apple-scene-builder-white builder))]
            #:when resource)
        (unless (skia-closed? resource) (skia-close! resource)))))
  (void))

(define (finish-current-frame! builder)
  (define frame-index (bad-apple-scene-builder-frame-index builder))
  (vector-set! (bad-apple-scene-builder-frames builder) frame-index
               (vector->immutable-vector
                (list->vector (reverse (bad-apple-scene-builder-paths-rev builder)))))
  (set-bad-apple-scene-builder-frame-index! builder (add1 frame-index))
  (set-bad-apple-scene-builder-path-index! builder 0)
  (set-bad-apple-scene-builder-paths-rev! builder '()))

(define (finish-scene! builder)
  (define scene
    (bad-apple-scene
     (vector->immutable-vector (bad-apple-scene-builder-frames builder))
     (bad-apple-scene-builder-fill builder)
     (bad-apple-scene-builder-white builder)
     (apply make-matrix
            (vector->list
             (bad-apple-asset-source->view-box
              (bad-apple-scene-builder-asset builder))))
     (bad-apple-scene-builder-completed-paths builder)
     #f))
  (set-bad-apple-scene-builder-scene! builder scene)
  scene)

;; bad-apple-scene-builder-step! : builder? [#:path-limit positive-integer?]
;;                                  [#:time-limit-ms positive-real?] -> (or/c #f scene?)
;; Compiles a bounded amount of native geometry. It must be invoked on the same thread that will
;; later draw and close the resulting scene.
(define (bad-apple-scene-builder-step! builder #:path-limit [path-limit 64]
                                      #:time-limit-ms [time-limit-ms 4.0])
  (unless (bad-apple-scene-builder? builder)
    (raise-argument-error 'bad-apple-scene-builder-step! "bad-apple-scene-builder?" builder))
  (unless (exact-positive-integer? path-limit)
    (raise-argument-error 'bad-apple-scene-builder-step! "exact positive integer" path-limit))
  (unless (and (real? time-limit-ms) (positive? time-limit-ms))
    (raise-argument-error 'bad-apple-scene-builder-step! "positive real" time-limit-ms))
  (cond
    [(bad-apple-scene-builder-closed? builder)
     (error 'bad-apple-scene-builder-step! "builder is closed")]
    [(bad-apple-scene-builder-cancelled? builder)
     (bad-apple-scene-builder-close! builder)
     #f]
    [(bad-apple-scene-builder-scene builder) (bad-apple-scene-builder-scene builder)]
    [else
     (define started (current-inexact-monotonic-milliseconds))
     (define source-frames (bad-apple-asset-frames (bad-apple-scene-builder-asset builder)))
     (define parsed 0)
     (with-handlers ([exn?
                      (lambda (error)
                        (bad-apple-scene-builder-close! builder)
                        (raise error))])
       (let loop ()
         (cond
           [(bad-apple-scene-builder-cancelled? builder)
            (bad-apple-scene-builder-close! builder)
            #f]
           [(= (bad-apple-scene-builder-frame-index builder) (vector-length source-frames))
            (finish-scene! builder)]
           [(and (positive? parsed)
                 (or (>= parsed path-limit)
                     (>= (- (current-inexact-monotonic-milliseconds) started) time-limit-ms)))
            #f]
           [else
            (define frame-index (bad-apple-scene-builder-frame-index builder))
            (define source-frame (vector-ref source-frames frame-index))
            (define path-index (bad-apple-scene-builder-path-index builder))
            (if (= path-index (vector-length source-frame))
                (begin (finish-current-frame! builder) (loop))
                (let ([path (svg-path->path (vector-ref source-frame path-index)
                                             #:fill-rule 'winding)])
                  ;; Register immediately, so cleanup covers a path if later builder work fails.
                  (set-bad-apple-scene-builder-paths-rev!
                   builder (cons path (bad-apple-scene-builder-paths-rev builder)))
                  (set-bad-apple-scene-builder-path-index! builder (add1 path-index))
                  (set-bad-apple-scene-builder-completed-paths!
                   builder (add1 (bad-apple-scene-builder-completed-paths builder)))
                  (set! parsed (add1 parsed))
                  (loop)))])))]))

(define (compile-bad-apple-scene asset)
  (define builder (make-bad-apple-scene-builder asset))
  (let loop ()
    (or (bad-apple-scene-builder-step! builder #:path-limit 4096 #:time-limit-ms 1000.0)
        (loop))))

(define (bad-apple-scene-close! scene)
  (unless (bad-apple-scene? scene)
    (raise-argument-error 'bad-apple-scene-close! "bad-apple-scene?" scene))
  (unless (bad-apple-scene-closed? scene)
    (set-bad-apple-scene-closed?! scene #t)
    (close-paths! (bad-apple-scene-frames scene))
    (for ([resource (list (bad-apple-scene-fill scene) (bad-apple-scene-white scene))])
      (unless (skia-closed? resource) (skia-close! resource))))
  (void))

;; draw-bad-apple-frame : canvas? scene? exact-nonnegative-integer? real? real? -> void?
;; Draws only immutable prepared geometry. It has no clock, timer, file, JSON, XML, or parsing work.
(define (draw-bad-apple-frame canvas scene frame-index logical-width logical-height)
  (unless (bad-apple-scene? scene)
    (raise-argument-error 'draw-bad-apple-frame "bad-apple-scene?" scene))
  (unless (exact-nonnegative-integer? frame-index)
    (raise-argument-error 'draw-bad-apple-frame "exact nonnegative integer" frame-index))
  (unless (< frame-index (vector-length (bad-apple-scene-frames scene)))
    (raise-arguments-error 'draw-bad-apple-frame "frame index is outside the prepared sequence"
                           "frame" frame-index))
  (when (bad-apple-scene-closed? scene)
    (error 'draw-bad-apple-frame "scene is closed"))
  (when (and (positive? logical-width) (positive? logical-height))
    (define source-width 480.0)
    (define source-height 360.0)
    (define scale (min (/ logical-width source-width) (/ logical-height source-height)))
    (define x-offset (/ (- logical-width (* source-width scale)) 2.0))
    (define y-offset (/ (- logical-height (* source-height scale)) 2.0))
    (canvas-clear! canvas 'black)
    (with-canvas-state canvas
      (canvas-translate! canvas x-offset y-offset)
      (canvas-scale! canvas scale scale)
      (canvas-clip-rect! canvas 0 0 source-width source-height)
      (draw-rect canvas 0 0 source-width source-height (bad-apple-scene-white scene))
      ;; Keep source coordinates in the prepared native paths. The conversion then costs one
      ;; canvas concatenation per painted frame instead of one native path mutation per path at
      ;; startup; the scoped canvas state restores the display transform afterward.
      (with-canvas-state canvas
        (canvas-concat! canvas (bad-apple-scene-source->view-box scene))
        (for ([path (in-vector (vector-ref (bad-apple-scene-frames scene) frame-index))])
          (draw-path canvas path (bad-apple-scene-fill scene))))))
  (void))

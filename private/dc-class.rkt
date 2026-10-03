#lang racket/base
(require racket/class racket/future racket/list racket/math racket/vector
         (prefix-in rd: racket/draw) "dc-support.rkt" "dc-geometry.rkt"
         "dc-region-adapter.rkt" "dc-text-spec.rkt" "dc-bitmap.rkt"
         "dc-replay-adapter.rkt" "dc-alpha.rkt" "dc-styles.rkt" "dc-style-math.rkt"
         (only-in "check.rkt" check-dimensions current-skia-byte-limit))
(provide make-skia-dc-class)
(define-local-member-name dc-push-layer! dc-pop-layer!
                          dc-replace-backing! dc-paint-scope dc-clear-root!)

;; The canvas bridge can resize and scope the same DC without adding ordinary
;; public method names to dc<%>. A program importing skia/dc cannot accidentally
;; dispatch these operations using a symbol with the same spelling.
(module* canvas #f
  (provide dc-resize-backing! call-with-dc-canvas-paint dc-clear-backing!)
  (define (dc-resize-backing! dc width height backing-scale)
    (send dc dc-replace-backing! width height backing-scale))
  (define (call-with-dc-canvas-paint dc thunk)
    (send dc dc-paint-scope thunk))
  (define (dc-clear-backing! dc)
    (send dc dc-clear-root!)))

(define (color-value who v)
  (define c
    (cond [(string? v) (or (send rd:the-color-database find-color v)
                          (send rd:the-color-database find-color "black"))]
          [(is-a? v rd:color%) v]
          [else (raise-argument-error who "color% object or color name" v)]))
  (vector-immutable (send c red) (send c green) (send c blue) (dc-unit who (send c alpha))))
(define (color-object v)
  ;; A detached public object: mutating a returned color cannot change the DC.
  (make-object rd:color% (vector-ref v 0) (vector-ref v 1) (vector-ref v 2) (vector-ref v 3)))
(define (with-opacity rgba alpha)
  (vector-immutable (vector-ref rgba 0) (vector-ref rgba 1) (vector-ref rgba 2)
                    (* (vector-ref rgba 3) alpha)))
(define check-pen dc-check-pen)
(define check-brush dc-check-brush)
(define (smoothing-value s)
  (unless (memq s '(unsmoothed smoothed aligned))
    (raise-argument-error 'set-smoothing "'unsmoothed, 'smoothed, or 'aligned" s)) s)

(define (make-skia-dc-class renderer)
  (unless (dc-renderer? renderer) (raise-argument-error 'make-skia-dc-class "private DC renderer" renderer))
  ;; Alpha default implementations are part of draw-lib 1.22 / Racket 8.18.
  ;; Leave those methods out of the base and override the interface defaults
  ;; in the final class. No compatibility branch for older interfaces.
  (define implementation%
    (class object%
      (init [(logical-width width) 640] [(logical-height height) 480]
            [(requested-backing backing-scale) 1.0]
            [background "white"] [smoothing 'unsmoothed])
      (define owner (current-thread))
      (define-values (pixel-w pixel-h backing)
        (dc-physical-size 'skia-dc% logical-width logical-height requested-backing))
      (define w logical-width)
      (define h logical-height)
      (define transform-state (vector-immutable dc-identity 0.0 0.0 1.0 1.0 0.0))
      (define alignment 1.0)
      (define alpha-state 1.0)
      (define pen-state (rd:make-pen #:color "black" #:width 1 #:style 'solid))
      (define brush-state (rd:make-brush #:color "white" #:style 'solid))
      (define font-state (rd:make-font #:size 12 #:family 'default))
      (define background-state (color-value 'skia-dc% background))
      (define text-fg (color-value 'skia-dc% "black"))
      (define text-bg (color-value 'skia-dc% "white"))
      (define text-mode-state 'transparent)
      (define smoothing-state (smoothing-value smoothing))
      (define clip-region #f)
      (define clip-commands #f)
      (define target #f)
      (define groups #f)
      (define closed? #f)
      ;; Drawing is allowed during the callback, but retirement/allocation
      ;; callbacks cannot reenter the DC while its backing is being changed.
      (define backing-operation #f)
      (super-new)
      (define region-lease (make-dc-region-lease this))
      (define style-lease (make-dc-style-lease this))
      ;; Allocate only after every construction argument is validated. Merely
      ;; requiring skia/dc or constructing its class does not load libSkiaSharp.
      (when (current-future) (error 'skia-dc% "construction in a future is not supported"))
      (set! target ((dc-renderer-create renderer) pixel-w pixel-h))
      (unless target (error 'skia-dc% "raster renderer returned no surface"))
      (set! groups
        (make-dc-alpha target pixel-w pixel-h
                       (dc-renderer-create renderer) (dc-renderer-close renderer)
                       (and (dc-renderer/alpha? renderer) (dc-renderer/alpha-composite renderer))
                       (lambda () (current-skia-byte-limit))))
      (dc-style-select! style-lease 0 pen-state check-pen void)
      (dc-style-select! style-lease 1 brush-state check-brush void)

      (define/private (owner! who)
        (unless (and (eq? owner (current-thread)) (not (current-future)))
          (error who "skia-dc% belongs to another Racket thread; futures are not supported")))
      (define/private (check! who)
        (owner! who)
        (when closed? (error who "skia-dc% is closed"))
        (when (and backing-operation (not (eq? backing-operation 'paint)))
          (error who "skia-dc% backing is busy with ~a" backing-operation)))
      (define/private (idle-backing! who)
        (check! who)
        (when backing-operation
          (error who "skia-dc% paint callback is already active")))
      (define/private (discard-layers!)
        (dynamic-wind
         void
         (lambda () (dc-alpha-discard! groups (lambda (a) (set! alpha-state a))))
         (lambda () (set! target (dc-alpha-target groups)))))
      (define/public (dc-replace-backing! width height requested-scale)
        (idle-backing! 'dc-resize-backing!)
        (define-values (next-pixel-w next-pixel-h next-backing)
          (dc-physical-size 'dc-resize-backing! width height requested-scale))
        (cond
          [(and (= width w) (= height h) (= next-backing backing)) #f]
          [else
           ;; Validate the new physical transform and selected logical clip
           ;; before allocating or modifying any state. The selection remains
           ;; frozen in logical device coordinates across backing changes.
           (dc-multiply (vector next-backing 0 0 next-backing 0 0) (effective))
           (define next-clip (dc-scale-clip clip-commands next-backing))
           (define next-alpha (dc-alpha-root-alpha groups alpha-state))
           (define next-bytes (check-dimensions 'dc-resize-backing! next-pixel-w next-pixel-h))
           (define required-bytes
             (+ next-bytes (* 4 pixel-w pixel-h (add1 (dc-alpha-depth groups)))))
           (when (> required-bytes (current-skia-byte-limit))
             (raise-arguments-error 'dc-resize-backing!
               "current and replacement backings exceed current-skia-byte-limit"
               "required RGBA bytes" required-bytes "limit" (current-skia-byte-limit)))
           (call-with-continuation-barrier
            (lambda ()
              (parameterize-break #f
                (define replacement #f)
                (define next-groups #f)
                (define committed? #f)
                (dynamic-wind
                 (lambda () (set! backing-operation 'resize))
                 (lambda ()
                   (set! replacement ((dc-renderer-create renderer) next-pixel-w next-pixel-h))
                   (unless replacement (error 'dc-resize-backing! "raster renderer returned no surface"))
                   (set! next-groups
                     (make-dc-alpha replacement next-pixel-w next-pixel-h
                       (dc-renderer-create renderer) (dc-renderer-close renderer)
                       (and (dc-renderer/alpha? renderer) (dc-renderer/alpha-composite renderer))
                       (lambda () (current-skia-byte-limit))))
                   (dc-alpha-set-clip! next-groups next-clip)
                   (define previous-groups groups)
                   ;; Commit only after complete allocation and validation.
                   ;; Discarding a child also restores the root's saved
                   ;; per-draw alpha. At depth zero it remains unchanged.
                   (set! groups next-groups)
                   (set! target replacement)
                   (set! w width) (set! h height)
                   (set! pixel-w next-pixel-w) (set! pixel-h next-pixel-h)
                   (set! backing next-backing)
                   (set! alpha-state next-alpha)
                   (set! committed? #t)
                   ;; Old root and children are detached before retirement.
                   ;; If release fails, the new backing stays usable; every
                   ;; old target is still attempted exactly once.
                   (dc-alpha-close! previous-groups)
                   #t)
                 (lambda ()
                   (dynamic-wind
                    void
                    (lambda ()
                      (unless committed?
                        (cond [next-groups (dc-alpha-close! next-groups)]
                              [replacement ((dc-renderer-close renderer) replacement)])))
                    (lambda () (set! backing-operation #f))))))))]))
      (define/public (dc-paint-scope thunk)
        (idle-backing! 'call-with-dc-canvas-paint)
        (unless (and (procedure? thunk) (procedure-arity-includes? thunk 0))
          (raise-argument-error 'call-with-dc-canvas-paint "procedure accepting zero arguments" thunk))
        (call-with-continuation-barrier
         (lambda ()
           (define entered? #f)
           (dynamic-wind
            (lambda ()
              (when entered? (error 'call-with-dc-canvas-paint "paint callback cannot be reentered"))
              (set! entered? #t)
              (set! backing-operation 'cleanup))
            (lambda ()
              ;; A callback always starts at the root, including after direct
              ;; get-dc drawing left an unfinished group between GUI paints.
              (discard-layers!)
              (set! backing-operation 'paint)
              (thunk))
            (lambda ()
              (parameterize-break #f
                (set! backing-operation 'cleanup)
                (dynamic-wind
                 void
                 (lambda () (discard-layers!))
                 (lambda () (set! backing-operation #f)))))))))
      (define/public (dc-clear-root!)
        (check! 'dc-clear-backing!)
        (unless (zero? (dc-alpha-depth groups))
          (error 'dc-clear-backing! "cannot clear the root with unfinished alpha groups"))
        (define previous-operation backing-operation)
        (call-with-continuation-barrier
         (lambda ()
           (parameterize-break #f
             (dynamic-wind
              (lambda () (set! backing-operation 'clear))
              (lambda ()
                (define root (dc-alpha-root groups))
                ((dc-renderer-clear renderer) root #f '#(0 0 0 0.0) #t)
                ((dc-renderer-clear renderer) root #f background-state #f)
                (void))
              (lambda () (set! backing-operation previous-operation)))))))
      (define/private (compat! who)
        (unless (dc-renderer+? renderer)
          (dc-unsupported who 'recording-renderer-without-compatibility-callbacks "private test renderer")))
      (define/private (physical-clip) (dc-alpha-clip groups))
      (define/public (dc-push-layer! a)
        (check! 'start-alpha)
        (unless (dc-renderer/alpha? renderer)
          (dc-unsupported 'start-alpha 'renderer-without-alpha "private test renderer"))
        (parameterize-break #f
          (set! alpha-state (dc-alpha-start! groups (dc-unit 'start-alpha a) alpha-state))
          (set! target (dc-alpha-target groups)))
        (void))
      (define/public (dc-pop-layer!)
        (check! 'end-alpha)
        (parameterize-break #f
          (dynamic-wind
           void
           (lambda () (dc-alpha-end! groups (lambda (a) (set! alpha-state a))))
           (lambda () (set! target (dc-alpha-target groups)))))
        (void))
      (define/private (effective) (dc-effective transform-state))
      (define/private (backed m) (dc-multiply (vector backing 0 0 backing 0 0) m))
      (define/private (set-transform! who v)
        (check! who)
        (define next (dc-transformation who v))
        (backed (dc-effective next)) ; reject overflow before changing any field
        (set! transform-state next)
        (void))
      (define/private (changed indices values-list)
        (define v (vector-copy transform-state))
        (for ([i (in-list indices)] [value (in-list values-list)]) (vector-set! v i value)) v)
      (define/private (aligners who)
        (dc-alignment-functions who (effective) alignment (send pen-state get-width) smoothing-state))
      (define/private (ink stroke?)
        (define obj (if stroke? pen-state brush-state))
        (define col (with-opacity (color-value 'skia-dc% (send obj get-color)) alpha-state))
        (define width (if stroke? (send pen-state get-width) 0.0))
        (define m (effective))
        (define axis-scale (* alignment (sqrt (+ (sqr (vector-ref m 0)) (sqr (vector-ref m 2))))))
        (define actual-width
          (cond [(not stroke?) 0.0]
                [(eq? smoothing-state 'smoothed) (if (= width 0) (/ 1.0 axis-scale) width)]
                [else (/ (max 1.0 (floor (* width axis-scale))) axis-scale)]))
        (dc-style-ink obj stroke?
          (dc-ink col stroke? actual-width
                  (if (and stroke? (<= (* width axis-scale) 1)) 'round
                      (if stroke? (case (send pen-state get-cap) [(projecting) 'square] [else (send pen-state get-cap)]) 'round))
                  (if stroke? (send pen-state get-join) 'round) '())
          (color-object background-state) alpha-state m))
      (define/private (emit! who fill-commands stroke-commands [rule 'winding])
        (check! who)
        (unless (memq rule '(winding odd-even)) (raise-argument-error who "'winding or 'odd-even" rule))
        (unless (dc-singular? (effective))
          ;; Build and validate the entire batch before the first native draw.
          (define batch
            (for/list ([commands (in-list (list fill-commands stroke-commands))]
                       [stroke? (in-list '(#f #t))]
                       #:when (and (pair? commands)
                                   (not (eq? (send (if stroke? pen-state brush-state) get-style) 'transparent))))
              (define checked-commands
                (dc-path-map commands (lambda (x y) (values (dc-real who x) (dc-real who y)))))
              (define paint (ink stroke?))
              (dc-real who (dc-ink-width paint))
              (dc-draw checked-commands rule (backed (effective))
                       (physical-clip)
                       paint (not (eq? smoothing-state 'unsmoothed)))))
          (for ([command (in-list batch)]) ((dc-renderer-draw renderer) target command)))
        (void))
      (define/private (paint-path! who commands rule [aligned-fill? #f] [fill? #t])
        (check! who)
        (unless (dc-singular? (effective))
          (define-values (ax ay _x _y) (aligners who))
          (define snapped (dc-path-map commands (lambda (x y) (values (ax x) (ay y)))))
          (emit! who (and fill? (if aligned-fill? snapped commands)) snapped rule))
        (void))
      (define/private (rectangle! who x y width height [radius #f])
        (check! who)
        (dc-real who x) (dc-real who y) (dc-extent who width) (dc-extent who height)
        (when radius (dc-real who radius))
        (unless (dc-singular? (effective))
          (define-values (ax ay ux uy) (aligners who))
          (define sw (max 0 (- width ux)))
          (define sh (max 0 (- height uy)))
          (define (path ww hh)
            (if radius
                (let ([p (new rd:dc-path%)])
                  (send p rounded-rectangle x y ww hh radius)
                  (dc-path-commands who p))
                (dc-rectangle x y ww hh)))
          (emit! who (path width height)
                 (if (and (> sw 0) (> sh 0))
                     (dc-path-map (path sw sh) (lambda (x y) (values (ax x) (ay y)))) '())))
        (void))
      (define/private (arc! who x y width height start end)
        (check! who)
        (dc-real who x) (dc-real who y) (dc-extent who width) (dc-extent who height)
        (dc-real who start) (dc-real who end)
        (unless (dc-singular? (effective))
          (define-values (ax ay ux uy) (aligners who))
          (define tau (* 2.0 pi))
          (define a (- start (* tau (floor (/ start tau)))))
          (define delta (- end start))
          (define wrapped (- delta (* tau (floor (/ delta tau)))))
          (define b (+ a (if (= wrapped 0) tau wrapped)))
          (define (path xx yy ww hh fill?)
            (if (and (> ww 0) (> hh 0))
                (let ([p (new rd:dc-path%)])
                  (when fill? (send p move-to (+ xx (/ ww 2)) (+ yy (/ hh 2))))
                  (send p arc xx yy ww hh a b #t)
                  (when fill? (send p close))
                  (dc-path-commands who p)) '()))
          (emit! who (path x y width height #t)
                 (path (ax x) (ay y) (max 0 (- (ax (+ x width)) (ax x) ux))
                       (max 0 (- (ay (+ y height)) (ay y) uy)) #f)))
        (void))

      (define/public (ok?) (and (not closed?) (eq? owner (current-thread)) (not (current-future)) #t))
      (define/public (close)
        (owner! 'close)
        (when (and (not closed?) backing-operation)
          (error 'close "cannot close skia-dc% during backing ~a" backing-operation))
        (unless closed?
          (set! closed? #t)
          (set! target #f)
          (dynamic-wind
           void
           (lambda ()
             (dc-region-install! region-lease #f)
             (dc-style-release! style-lease)
             (set! clip-region #f) (set! clip-commands #f)
             (set! pen-state #f) (set! brush-state #f))
           (lambda () (dc-alpha-close! groups))))
        (void))
      (define/public (get-size) (check! 'get-size) (values (exact->inexact w) (exact->inexact h)))
      (define/public (get-pixel-size) (check! 'get-pixel-size) (values pixel-w pixel-h))
      (define/public (get-backing-scale) (check! 'get-backing-scale) backing)
      (define/public (get-device-scale) (check! 'get-device-scale) (values 1.0 1.0))
      (define/public (get-gl-context) (check! 'get-gl-context) #f)
      (define/public (cache-font-metrics-key) (check! 'cache-font-metrics-key) 0)
      (define/public (get-capabilities) (check! 'get-capabilities) (dc-capabilities))
      (define/public (snapshot) (check! 'snapshot) ((dc-renderer-snapshot renderer) (dc-alpha-root groups)))
      (define/public (get-png-bytes) (check! 'get-png-bytes) ((dc-renderer-png renderer) (dc-alpha-root groups)))
      (define/public (get-rgba-bytes #:premultiplied? [premultiplied? #f])
        (check! 'get-rgba-bytes)
        (unless (boolean? premultiplied?) (raise-argument-error 'get-rgba-bytes "boolean?" premultiplied?))
        ((dc-renderer-rgba renderer) (dc-alpha-root groups) premultiplied?))
      (define/public (get-initial-matrix) (check! 'get-initial-matrix) (vector-ref transform-state 0))
      (define/public (get-transformation) (check! 'get-transformation) transform-state)
      (define/public (get-origin) (check! 'get-origin) (values (vector-ref transform-state 1) (vector-ref transform-state 2)))
      (define/public (get-scale) (check! 'get-scale) (values (vector-ref transform-state 3) (vector-ref transform-state 4)))
      (define/public (get-rotation) (check! 'get-rotation) (vector-ref transform-state 5))
      (define/public (get-clipping-matrix) (check! 'get-clipping-matrix) (effective))
      (define/public (set-initial-matrix m) (set-transform! 'set-initial-matrix (changed '(0) (list m))))
      (define/public (set-origin x y) (set-transform! 'set-origin (changed '(1 2) (list x y))))
      (define/public (set-scale x y) (set-transform! 'set-scale (changed '(3 4) (list x y))))
      (define/public (set-rotation a) (set-transform! 'set-rotation (changed '(5) (list a))))
      (define/public (set-transformation t) (set-transform! 'set-transformation t))
      (define/public (transform m)
        (check! 'transform)
        (set-transform! 'transform (vector (dc-multiply (effective) (dc-matrix 'transform m)) 0 0 1 1 0)))
      (define/public (translate x y) (transform (vector 1 0 0 1 x y)))
      (define/public (scale x y) (transform (vector x 0 0 y 0 0)))
      (define/public (rotate angle)
        (define a (dc-real 'rotate angle))
        (transform (vector (cos a) (- (sin a)) (sin a) (cos a) 0 0)))
      (define/public (set-alignment-scale v)
        (check! 'set-alignment-scale)
        (define a (dc-real 'set-alignment-scale v))
        (unless (> a 0) (raise-argument-error 'set-alignment-scale "positive finite real" v))
        (set! alignment a) (void))
      (define/public (get-smoothing) (check! 'get-smoothing) smoothing-state)
      (define/public (set-smoothing s) (check! 'set-smoothing) (set! smoothing-state (smoothing-value s)) (void))
      (define/public (get-alpha) (check! 'get-alpha) alpha-state)
      (define/public (set-alpha a) (check! 'set-alpha) (set! alpha-state (dc-unit 'set-alpha a)) (void))
      (define/public (get-background) (check! 'get-background) (color-object background-state))
      (define/public (set-background c) (check! 'set-background) (set! background-state (color-value 'set-background c)) (void))
      (define/public (get-pen) (check! 'get-pen) pen-state)
      (define/public set-pen
        (case-lambda
          [(p) (check! 'set-pen)
               (dc-style-select! style-lease 0 p check-pen (lambda (v) (set! pen-state v)))]
          [(c width style) (check! 'set-pen)
                          (set-pen (rd:make-pen #:color c #:width width #:style style))]))
      (define/public (get-brush) (check! 'get-brush) brush-state)
      (define/public set-brush
        (case-lambda
          [(b) (check! 'set-brush)
               (dc-style-select! style-lease 1 b check-brush (lambda (v) (set! brush-state v)))]
          [(c style) (check! 'set-brush)
                     (set-brush (rd:make-brush #:color c #:style style))]))
      (define/public (get-font) (check! 'get-font) font-state)
      (define/public (set-font f)
        (check! 'set-font)
        (unless (is-a? f rd:font%) (raise-argument-error 'set-font "font% object" f))
        (set! font-state f) (void))
      (define/public (get-text-foreground) (check! 'get-text-foreground) (color-object text-fg))
      (define/public (set-text-foreground c) (check! 'set-text-foreground) (set! text-fg (color-value 'set-text-foreground c)) (void))
      (define/public (get-text-background) (check! 'get-text-background) (color-object text-bg))
      (define/public (set-text-background c) (check! 'set-text-background) (set! text-bg (color-value 'set-text-background c)) (void))
      (define/public (get-text-mode) (check! 'get-text-mode) text-mode-state)
      (define/public (set-text-mode mode)
        (check! 'set-text-mode)
        (unless (memq mode '(transparent solid)) (raise-argument-error 'set-text-mode "'transparent or 'solid" mode))
        (set! text-mode-state mode) (void))
      (define/public (try-color c dest)
        (check! 'try-color)
        (unless (and (is-a? c rd:color%) (is-a? dest rd:color%))
          (raise-arguments-error 'try-color "source and destination must be color% objects" "source" c "destination" dest))
        (send dest set (send c red) (send c green) (send c blue) (send c alpha)) (void))
      (define/public (get-clipping-region) (check! 'get-clipping-region) clip-region)
      (define/public (set-clipping-region r)
        (check! 'set-clipping-region)
        (dc-region-select! 'set-clipping-region region-lease r this (effective) backing
          (lambda (data)
            (set! clip-region r) (set! clip-commands data)
            (dc-alpha-set-clip! groups (dc-scale-clip data backing))))
        (void))
      (define/public (set-clipping-rect x y width height)
        (check! 'set-clipping-rect)
        (dc-real 'set-clipping-rect x) (dc-real 'set-clipping-rect y)
        (dc-extent 'set-clipping-rect width) (dc-extent 'set-clipping-rect height)
        (define r (new rd:region% [dc this]))
        (send r set-rectangle x y width height)
        (set-clipping-region r))
      (define/private (clear! who color)
        (check! who)
        ((dc-renderer-clear renderer) target
         (physical-clip)
         color (eq? who 'erase)) (void))
      (define/public (clear) (clear! 'clear (with-opacity background-state alpha-state)))
      (define/public (erase) (clear! 'erase '#(0 0 0 0.0)))
      (define/public (draw-line x1 y1 x2 y2)
        (check! 'draw-line)
        (for ([x (in-list (list x1 y1 x2 y2))]) (dc-real 'draw-line x))
        (if (and (= x1 x2) (= y1 y2)) (draw-point x1 y1)
            (paint-path! 'draw-line (list (vector 'move x1 y1) (vector 'line x2 y2)) 'winding #f #f))
        (void))
      (define/public (draw-point x y)
        (check! 'draw-point) (dc-real 'draw-point x) (dc-real 'draw-point y)
        (unless (dc-singular? (effective))
          (define-values (ax ay _x _y) (aligners 'draw-point))
          (define m (effective))
          (define sx (sqrt (+ (sqr (vector-ref m 0)) (sqr (vector-ref m 2)))))
          (define sy (sqrt (+ (sqr (vector-ref m 1)) (sqr (vector-ref m 3)))))
          (emit! 'draw-point #f (list (vector 'move (ax x) (ay y))
                                     (vector 'line (+ (ax x) (/ 0.1 sx)) (+ (ay y) (/ 0.1 sy))))))
        (void))
      (define/public (draw-lines points [x 0] [y 0])
        (check! 'draw-lines)
        (paint-path! 'draw-lines (dc-polyline 'draw-lines points x y #f) 'winding #f #f))
      (define/public (draw-polygon points [x 0] [y 0] [rule 'odd-even])
        (check! 'draw-polygon)
        (paint-path! 'draw-polygon (dc-polyline 'draw-polygon points x y #t) rule #t))
      (define/public (draw-path path [x 0] [y 0] [rule 'odd-even])
        (check! 'draw-path) (paint-path! 'draw-path (dc-path-commands 'draw-path path x y) rule))
      (define/public (draw-rectangle x y width height) (rectangle! 'draw-rectangle x y width height))
      (define/public (draw-rounded-rectangle x y width height [radius -0.25])
        (rectangle! 'draw-rounded-rectangle x y width height radius))
      (define/public (draw-ellipse x y width height) (arc! 'draw-ellipse x y width height 0 (* 2 pi)))
      (define/public (draw-arc x y width height a b) (arc! 'draw-arc x y width height a b))
      (define/public (draw-spline x1 y1 x2 y2 x3 y3)
        (check! 'draw-spline)
        (for ([x (in-list (list x1 y1 x2 y2 x3 y3))]) (dc-real 'draw-spline x))
        (define xa (/ (+ x1 x2) 2)) (define ya (/ (+ y1 y2) 2))
        (define xb (/ (+ x2 x3) 2)) (define yb (/ (+ y2 y3) 2))
        (paint-path! 'draw-spline
                     (list (vector 'move x1 y1) (vector 'line xa ya)
                           (vector 'cubic (/ (+ xa x2) 2) (/ (+ ya y2) 2)
                                   (/ (+ x2 xb) 2) (/ (+ y2 yb) 2) xb yb)
                           (vector 'line x3 y3)) 'winding #f #f))
      ;; Raster DCs do not represent documents or a GUI flush queue.
      (define/public (start-doc title) (check! 'start-doc)
        (unless (string? title) (raise-argument-error 'start-doc "string?" title)) (void))
      (define/public (end-doc) (check! 'end-doc) (void))
      (define/public (start-page) (check! 'start-page) (void))
      (define/public (end-page) (check! 'end-page) (void))
      (define/public (flush) (check! 'flush) (void))
      (define/public (suspend-flush) (check! 'suspend-flush) (void))
      (define/public (resume-flush) (check! 'resume-flush) (void))
      ;; Explicit unsupported methods, never silent no-ops or Cairo rendering.
      ;; start-alpha/end-alpha are intentionally *not* defined in this base
      ;; class. dc<%> supplies default implementations for those methods, so
      ;; defining them here would conflict when the final class attaches dc<%>.
      ;; The final class* below overrides the interface defaults instead.
      (define/public (draw-text str x y [combine #f] [offset 0] [angle 0])
        (check! 'draw-text) (compat! 'draw-text)
        (dc-real 'draw-text x) (dc-real 'draw-text y) (dc-real 'draw-text angle)
        (define request (dc-text-description 'draw-text str font-state combine offset))
        (unless (dc-singular? (effective))
          ((dc-renderer+-draw-text renderer) target request (backed (effective)) (physical-clip)
           x y angle (with-opacity text-fg alpha-state) (with-opacity text-bg alpha-state)
           (eq? text-mode-state 'solid)))
        (void))
      (define/public (get-text-extent str [font #f] [combine #f] [offset 0])
        (check! 'get-text-extent) (compat! 'get-text-extent)
        ((dc-renderer+-measure-text renderer) target
         (dc-text-description 'get-text-extent str (or font font-state) combine offset)))
      (define/private (font-extent who)
        (check! who) (compat! who)
        (call-with-values
         (lambda () ((dc-renderer+-measure-text renderer) target (dc-font-description who font-state)))
         list))
      (define/public (get-char-width) (car (font-extent 'get-char-width)))
      (define/public (get-char-height) (cadr (font-extent 'get-char-height)))
      (define/public (glyph-exists? c)
        (check! 'glyph-exists?) (compat! 'glyph-exists?)
        (unless (char? c) (raise-argument-error 'glyph-exists? "char?" c))
        ((dc-renderer+-glyph-exists? renderer) target (dc-font-description 'glyph-exists? font-state) c))
      (define/private (bitmap! who bitmap x y sx sy sw sh dw dh style color mask smooth?)
        (check! who) (compat! who)
        (for ([v (in-list (list x y sx sy))]) (dc-real who v))
        (for ([v (in-list (list sw sh dw dh))]) (dc-extent who v))
        (define data (dc-bitmap-snapshot who bitmap style color mask (color-object background-state)))
        (cond
          [(not data) #f]
          [else
           (define rect (dc-bitmap-source-rect who data sx sy sw sh x y dw dh))
           (when (and rect (not (dc-singular? (effective))))
             (for ([n (in-vector rect)]) (dc-real who n))
             ((dc-renderer+-draw-bitmap renderer) target data rect (backed (effective)) (physical-clip)
              alpha-state (if (or smooth? (not (eq? smoothing-state 'unsmoothed))) 'linear 'nearest)))
           #t]))
      (define/public (draw-bitmap bitmap x y [style 'solid]
                                  [color (color-object '#(0 0 0 1.0))] [mask #f])
        (check! 'draw-bitmap)
        (unless (is-a? bitmap rd:bitmap%) (raise-argument-error 'draw-bitmap "bitmap% object" bitmap))
        (define sw (send bitmap get-width)) (define sh (send bitmap get-height))
        (bitmap! 'draw-bitmap bitmap x y 0 0 sw sh sw sh style color mask #f))
      (define/public (draw-bitmap-section bitmap x y sx sy width height [style 'solid]
                                          [color (color-object '#(0 0 0 1.0))] [mask #f])
        (bitmap! 'draw-bitmap-section bitmap x y sx sy width height width height style color mask #f))
      (define/public (draw-bitmap-section-smooth bitmap x y dw dh sx sy sw sh [style 'solid]
                                                 [color (color-object '#(0 0 0 1.0))] [mask #f])
        (bitmap! 'draw-bitmap-section-smooth bitmap x y sx sy sw sh dw dh style color mask #t))
      (define/public (copy x y width height x2 y2)
        (check! 'copy) (compat! 'copy)
        (for ([v (in-list (list x y x2 y2))]) (dc-real 'copy v))
        (dc-extent 'copy width) (dc-extent 'copy height)
        (when (and (> width 0) (> height 0) (not (dc-singular? (effective))))
          ((dc-renderer+-copy renderer) target (backed (effective)) (physical-clip) x y width height x2 y2))
        (void))
      (define/public (get-path-bounding-box path kind)
        (check! 'get-path-bounding-box)
        (unless (memq kind '(path fill stroke))
          (raise-argument-error 'get-path-bounding-box "'path, 'fill, or 'stroke" kind))
        (define commands (dc-path-commands 'get-path-bounding-box path))
        (unless (dc-renderer/styles? renderer)
          (dc-unsupported 'get-path-bounding-box 'renderer-without-path-bounds "private test renderer"))
        (cond
          [(or (dc-singular? (effective)) (null? commands)
               (and (eq? kind 'stroke) (zero? (send pen-state get-width))))
           (values 0.0 0.0 0.0 0.0)]
          [else
           (define-values (ax ay _x _y) (aligners 'get-path-bounding-box))
           (define snapped (dc-path-map commands (lambda (x y) (values (ax x) (ay y)))))
           ;; Bounds do not inspect the brush/stipple, allocate a target, or
           ;; use the current clip. They describe geometric ink only.
           (define w (send pen-state get-width))
           (define-values (sx sy) (dc-axis-scales (effective) alignment))
           (define-values (dashes phase) (dc-dash-spec (send pen-state get-style) w (send pen-state get-stipple)))
           (define width (if (eq? smoothing-state 'smoothed) w (/ (max 1.0 (floor (* w sx))) sx)))
           (define cap (if (<= (* w sx) 1) 'round
                           (case (send pen-state get-cap) [(projecting) 'square] [else (send pen-state get-cap)])))
           ((dc-renderer/styles-path-bounds renderer) snapped kind
             (dc-ink/style '#(0 0 0 1.0) #t width cap (send pen-state get-join) dashes #f phase))]))
      (define/public (dc-region-query-info)
        (check! 'region-query)
        (values (/ pixel-w backing) (/ pixel-h backing) (effective)
                (dc-scale-clip (physical-clip) (/ 1.0 backing))))))
  (dc-replay-mixin
   (dc-region-mixin
    (class* implementation% (rd:dc<%>)
      (super-new)
      ;; Override the draw-lib 1.22 interface defaults, never its no-op body.
      (define/override (start-alpha a) (send this dc-push-layer! a))
      (define/override (end-alpha) (send this dc-pop-layer!))))))

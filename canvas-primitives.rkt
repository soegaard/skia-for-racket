#lang racket/base
(require ffi/unsafe racket/list racket/vector
         "color.rkt" "private/core.rkt" "private/native.rkt" "private/types.rkt"
         "private/check.rkt" "private/lifetime.rkt" "private/path-matrix.rkt"
         (submod "private/core.rkt" canvas-primitive-internals))
(provide rounded-rect? make-rounded-rect rounded-rect-bounds rounded-rect-radii
         draw-point draw-points draw-arc draw-rrect draw-double-rounded-rect draw-color
         canvas-clip-rounded-rect! canvas-local-clip-bounds canvas-device-clip-bounds
         canvas-clip-empty? canvas-clip-rect? canvas-quick-reject?
         canvas-save-layer! call-with-canvas-layer with-canvas-layer)

;; Pure immutable specifications; native normalization happens on submission.
;; No SkRRect pointer or native resource is retained by these values.
(struct rounded-rect (bounds radii) #:transparent #:constructor-name make-rounded-rect-record)
(define (sequence-list who v)
  (cond [(list? v) v] [(vector? v) (vector->list v)]
        [else (raise-argument-error who "list? or vector?" v)]))
(define (rectangle-spec who v)
  (define xs (sequence-list who v))
  (unless (= (length xs) 4)
    (raise-argument-error who "four-element (x y width height) list/vector" v))
  (apply rect who xs))
(define (rect-values r)
  (vector-immutable (sk-rect-left r) (sk-rect-top r)
                    (- (sk-rect-right r) (sk-rect-left r))
                    (- (sk-rect-bottom r) (sk-rect-top r))))
(define (make-rounded-rect x y width height #:radii [radii 0])
  (define who 'make-rounded-rect)
  (define rr (rect who x y width height))
  (define rs
    (if (real? radii)
        (let ([v (nonnegative-scalar who radii)]) (make-list 4 (list v v)))
        (let ([xs (sequence-list who radii)])
          (unless (= (length xs) 4)
            (raise-argument-error who "nonnegative radius or four (rx ry) pairs: TL TR BR BL" radii))
          (for/list ([pair (in-list xs)])
            (define xy (sequence-list who pair))
            (unless (= (length xy) 2)
              (raise-argument-error who "two-element corner radius pair" pair))
            (map (lambda (v) (nonnegative-scalar who v)) xy)))))
  (make-rounded-rect-record (rect-values rr)
                            (vector->immutable-vector
                             (list->vector (map (lambda (xy) (apply vector-immutable xy)) rs)))))
(define (check-rounded-rect who rr)
  (unless (rounded-rect? rr) (raise-argument-error who "rounded-rect?" rr)))
(define (call-with-rrect who rr proc)
  (define bounds (rectangle-spec who (rounded-rect-bounds rr)))
  (define radii (malloc 32 'atomic))
  (for* ([i (in-range 4)] [j (in-range 2)])
    (ptr-set! radii _float (+ (* i 2) j) (vector-ref (vector-ref (rounded-rect-radii rr) i) j)))
  (call-with-native-temporary
   who 'rrect sk_rrect_new sk_rrect_delete
   (lambda (rp)
     (sk_rrect_set_rect_radii rp bounds radii)
     (begin0 (proc rp) (void/reference-sink radii bounds rr)))))

(define point-modes (hasheq 'points 0 'lines 1 'polygon 2))
(define (checked-points who points mode)
  (define xs (sequence-list who points))
  (define n (length xs))
  (define submitted (if (eq? mode 'polygon) (* 2 (max 0 (sub1 n))) n))
  (define budget-count (max n submitted))
  (unless (and (<= budget-count #x7fffffff)
               (<= (* budget-count 8) (current-skia-byte-limit)))
    (raise-arguments-error who "point buffer exceeds native count or current-skia-byte-limit"
                           "count" n "submitted count" submitted
                           "required bytes" (* budget-count 8)))
  (when (and (eq? mode 'lines) (odd? n))
    (raise-arguments-error who "'lines requires an even point count (independent pairs)" "count" n))
  (for/list ([point (in-list xs)])
    (define xy (sequence-list who point))
    (unless (= (length xy) 2)
      (raise-argument-error who "two-element point list/vector" point))
    (map (lambda (v) (scalar who v)) xy)))
(define (draw-point c x y paint)
  (define who 'draw-point)
  (define fx (scalar who x))
  (define fy (scalar who y))
  (call-on-canvas who c (list (paint-h who paint))
                  (lambda (cp pp) (sk_canvas_draw_point cp fx fy pp))))
(define (draw-points c points paint #:mode [mode 'points])
  (define who 'draw-points)
  (define requested-mode (choice who mode point-modes))
  (define source (checked-points who points mode))
  ;; Point-mode polygons are independent capped segments, not joined paths.
  ;; The pinned SVG writer joins mode-2 vertices, so submit explicit line pairs
  ;; on every backend (and in recordings) to preserve the specified semantics.
  (define xy
    (if (and (eq? mode 'polygon) (pair? source))
        (append* (for/list ([a (in-list source)] [b (in-list (cdr source))]) (list a b)))
        source))
  (define m (if (eq? mode 'polygon) 1 requested-mode))
  (define n (if (and (eq? mode 'polygon) (= (length source) 1)) 0 (length xy)))
  (call-on-canvas
   who c (list (paint-h who paint))
   (lambda (cp pp)
     ;; A zero-sized set still validates both live, same-thread resources.
     (unless (zero? n)
       (define data (malloc (* n 8) 'atomic))
       (for ([p (in-list xy)] [i (in-naturals)])
         (ptr-set! data _float (* i 2) (car p))
         (ptr-set! data _float (add1 (* i 2)) (cadr p)))
       (sk_canvas_draw_points cp m n data pp)
       (void/reference-sink data xy))))
  (void))
(define (draw-arc c x y width height start sweep paint #:use-center? [use-center? #f])
  (define who 'draw-arc)
  (define bounds (rect who x y width height))
  (define a (scalar who start))
  (define b (scalar who sweep))
  (boolean who use-center?)
  (call-on-canvas who c (list (paint-h who paint))
                  (lambda (cp pp) (sk_canvas_draw_arc cp bounds a b use-center? pp))))
(define (draw-rrect c rr paint)
  (define who 'draw-rrect)
  (check-rounded-rect who rr)
  (call-on-canvas who c (list (paint-h who paint))
    (lambda (cp pp) (call-with-rrect who rr (lambda (rp) (sk_canvas_draw_rrect cp rp pp))))))
(define (draw-double-rounded-rect c outer inner paint)
  (define who 'draw-double-rounded-rect)
  (check-rounded-rect who outer)
  (check-rounded-rect who inner)
  (define ib (rectangle-spec who (rounded-rect-bounds inner)))
  (call-on-canvas
   who c (list (paint-h who paint))
   (lambda (cp pp)
     (call-with-rrect
      who outer
      (lambda (op)
        (cond
          [(or (zero? (vector-ref (rounded-rect-bounds inner) 2))
               (zero? (vector-ref (rounded-rect-bounds inner) 3)))
           (sk_canvas_draw_rrect cp op pp)]
          [else
           ;; Sufficient, deliberately conservative containment test. Skia says
           ;; a non-contained inner shape has undefined drawing behavior.
           (unless (sk_rrect_contains op ib)
             (raise-arguments-error who "inner bounding rectangle must fit wholly inside outer rounded shape"
                                    "inner bounds" (rounded-rect-bounds inner)))
           (call-with-rrect who inner (lambda (ip) (sk_canvas_draw_drrect cp op ip pp)))])))))
  (void))
(define (draw-color c color #:blend-mode [mode 'src-over])
  (define argb (color->argb color))
  (define m (choice 'draw-color mode blend-values))
  ;; The color covers the device clip, independent of the local transform.
  ;; SkSVGDevice implements drawPaint as a transformed device-sized rect; reset
  ;; only the matrix while keeping the existing device-space clip intact.
  (call-with-canvas-state
   c (lambda ()
       (canvas-reset-transform! c)
       (call-on-canvas 'draw-color c '() (lambda (cp) (sk_canvas_draw_color cp argb m))))))
(define (canvas-clip-rounded-rect! c rr #:operation [operation 'intersect]
                                   #:antialias? [aa? #f])
  (define who 'canvas-clip-rounded-rect!)
  (check-rounded-rect who rr)
  (define op (choice who operation clip-values))
  (boolean who aa?)
  (call-on-canvas
   who c '()
   (lambda (cp)
     (call-with-rrect
      who rr
      (lambda (rp)
        (with-skia ([shape (make-path)])
          (call-with-owned who (list (path-h who shape))
                           (lambda (pp) (sk_path_add_rrect pp rp 0)))
          ;; SkSVGDevice's direct RRect clip writes only one rx/ry pair. Rebuild
          ;; the normalized verbs so SkClipStack retains a general path instead
          ;; of the special RRect tag. This also survives recording/replay.
          (with-skia ([plain (make-path (path->commands shape))])
            (call-with-owned
             who (list (path-h who plain))
             (lambda (pp) (sk_canvas_clip_path_with_operation cp pp op aa?))))))))))

;; Query rectangles are detached values. Local bounds may be conservatively
;; expanded; device bounds are integral and do not follow the current CTM.
(define (canvas-local-clip-bounds c)
  (define bounds (make-sk-rect 0.0 0.0 0.0 0.0))
  (call-on-canvas 'canvas-local-clip-bounds c '()
    (lambda (cp) (and (sk_canvas_get_local_clip_bounds cp bounds) (rect-values bounds)))))
(define (canvas-device-clip-bounds c)
  (define bounds (make-sk-irect 0 0 0 0))
  (call-on-canvas 'canvas-device-clip-bounds c '()
    (lambda (cp)
      (and (sk_canvas_get_device_clip_bounds cp bounds)
           (vector-immutable (sk-irect-left bounds) (sk-irect-top bounds)
                             (- (sk-irect-right bounds) (sk-irect-left bounds))
                             (- (sk-irect-bottom bounds) (sk-irect-top bounds)))))))
(define (canvas-clip-empty? c)
  (call-on-canvas 'canvas-clip-empty? c '() sk_canvas_is_clip_empty))
(define (canvas-clip-rect? c)
  (call-on-canvas 'canvas-clip-rect? c '() sk_canvas_is_clip_rect))
(define (canvas-quick-reject? c x y width height)
  (define bounds (rect 'canvas-quick-reject? x y width height))
  (call-on-canvas 'canvas-quick-reject? c '() (lambda (cp) (sk_canvas_quick_reject cp bounds))))

(define (layer-arguments who bounds paint)
  (values (and bounds (rectangle-spec who bounds)) (and paint (paint-h who paint))))
(define (save-layer/checked who c bounds ph)
  (call-on-canvas who c (if ph (list ph) '())
    (lambda (cp . ps) (sk_canvas_save_layer cp bounds (and ph (car ps))))))
(define (canvas-save-layer! c #:bounds [bounds #f] #:paint [paint #f])
  (define-values (b ph) (layer-arguments 'canvas-save-layer! bounds paint))
  (save-layer/checked 'canvas-save-layer! c b ph))
(define (call-with-canvas-layer c thunk #:bounds [bounds #f] #:paint [paint #f])
  (define who 'call-with-canvas-layer)
  (define owner (canvas-owner who c))
  (unless (and (procedure? thunk) (procedure-arity-includes? thunk 0))
    (raise-argument-error who "procedure accepting zero arguments" thunk))
  (define-values (b ph) (layer-arguments who bounds paint))
  (define old-count #f)
  (call-with-continuation-barrier
   (lambda ()
     (dynamic-wind
       (lambda ()
         (parameterize-break #f
           (set! old-count (save-layer/checked who c b ph))
           (set-owner-floors! owner (cons (add1 old-count) (owner-floors owner)))))
       thunk
       (lambda ()
         (parameterize-break #f
           ;; Restore composites even after a raised value/escape. This is state
           ;; cleanup, not pixel rollback. Enclosing document helpers may abort.
           (dynamic-wind
             void
             (lambda ()
               (unless (skia-closed? c)
                 (call-on-canvas who c '()
                   (lambda (cp) (sk_canvas_restore_to_count cp old-count)))))
             (lambda () (set-owner-floors! owner (cdr (owner-floors owner)))))))))))
(define-syntax with-canvas-layer
  (syntax-rules ()
    [(_ c #:bounds b #:paint p body ...)
     (call-with-canvas-layer c (lambda () body ...) #:bounds b #:paint p)]
    [(_ c #:paint p #:bounds b body ...)
     (call-with-canvas-layer c (lambda () body ...) #:bounds b #:paint p)]
    [(_ c #:bounds b body ...)
     (call-with-canvas-layer c (lambda () body ...) #:bounds b)]
    [(_ c #:paint p body ...)
     (call-with-canvas-layer c (lambda () body ...) #:paint p)]
    [(_ c body ...) (call-with-canvas-layer c (lambda () body ...))]))

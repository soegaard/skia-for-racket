#lang racket/base
(require ffi/unsafe racket/list
         "private/core.rkt" "private/check.rkt" "private/types.rkt"
         "private/native.rkt" "private/lifetime.rkt" "private/picture-util.rkt"
         "matrix.rkt" (prefix-in raw: (submod "private/core.rkt" picture-internals)))
(provide picture->bytes picture-from-bytes picture-from-file save-picture
         picture-cull-bounds picture-unique-id picture-approximate-op-count
         picture-approximate-bytes-used make-picture-shader)

(define (native-cull-bounds who pp)
  (define bounds (make-sk-rect 0.0 0.0 0.0 0.0))
  (sk_picture_get_cull_rect pp bounds)
  (define x (scalar who (sk-rect-left bounds)))
  (define y (scalar who (sk-rect-top bounds)))
  (define right (scalar who (sk-rect-right bounds)))
  (define bottom (scalar who (sk-rect-bottom bounds)))
  (vector-immutable x y (nonnegative-scalar who (- right x))
                       (nonnegative-scalar who (- bottom y))))

(define (picture-cull-bounds pic)
  (define who 'picture-cull-bounds)
  (call-with-owned who (list (raw:picture-h who pic))
    (lambda (pp) (native-cull-bounds who pp))))
(define (picture-unique-id pic)
  (define who 'picture-unique-id)
  (call-with-owned who (list (raw:picture-h who pic)) sk_picture_get_unique_id))
(define (picture-approximate-op-count pic #:nested? [nested? #f])
  (define who 'picture-approximate-op-count)
  (boolean who nested?)
  (call-with-owned who (list (raw:picture-h who pic))
    (lambda (pp) (sk_picture_approximate_op_count pp nested?))))
(define (picture-approximate-bytes-used pic)
  (define who 'picture-approximate-bytes-used)
  (call-with-owned who (list (raw:picture-h who pic)) sk_picture_approximate_bytes_used))

(define (picture->bytes pic)
  (define who 'picture->bytes)
  (call-with-owned who (list (raw:picture-h who pic))
    (lambda (pp)
      (raw:call-with-native-temporary
       who 'picture-data (lambda () (sk_picture_serialize_to_data pp)) sk_data_unref
       (lambda (dp)
         ;; Bound the copied result, not Skia's allocations while serializing.
         (define out (raw:copy-native-data who dp))
         (picture-header who out)
         out)))))

(define (load-snapshot who bs size)
  (skia-check!)
  (define handle
    (raw:call-with-native-temporary
     who 'picture-data (lambda () (sk_data_new_with_copy bs (bytes-length bs))) sk_data_unref
     (lambda (dp)
       (new-owned who 'picture
         (lambda ()
           (or (sk_picture_deserialize_from_data dp)
               (error who "native decoder rejected invalid or unsupported SKP payload")))
         sk_picture_unref))))
  (with-handlers ([(lambda (_) #t) (lambda (e) (owned-close! who handle) (raise e))])
    (define bounds
      (call-with-owned who (list handle) (lambda (pp) (native-cull-bounds who pp))))
    ;; SKP stores native cull bounds, not the Racket recorder's nominal extent.
    ;; An optional nominal size preserves scaled-placement conventions for a
    ;; cache made from an R-tree recording whose native cull was tightened.
    ;; Neither choice translates/recenters the picture's coordinate system.
    (raw:make-picture-record handle
      (if size (vector-ref size 0) (vector-ref bounds 2))
      (if size (vector-ref size 1) (vector-ref bounds 3)))))

(define (picture-from-bytes bs #:trusted? [trusted? #f]
                            #:width [width #f] #:height [height #f])
  (define who 'picture-from-bytes)
  (check-picture-trust who trusted?)
  (define size (picture-size-override who width height))
  (load-snapshot who (picture-data-snapshot who bs) size))
(define (picture-from-file filename #:trusted? [trusted? #f]
                           #:width [width #f] #:height [height #f])
  (define who 'picture-from-file)
  (check-picture-trust who trusted?)
  (define size (picture-size-override who width height))
  (load-snapshot who (read-picture-file-bytes who filename) size))
(define (save-picture pic filename #:exists [exists 'error])
  (define who 'save-picture)
  (raw:picture-h who pic)
  (define target (picture-output-path who filename exists))
  (write-picture-file-bytes! who (picture->bytes pic) target exists))

(define (picture-local-matrix who m)
  (cond [(not m) #f]
        [else
         (unless (matrix? m) (raise-argument-error who "#f or affine matrix?" m))
         (unless (matrix-invert m)
           (raise-arguments-error who "local matrix must have a representable inverse" "matrix" m))
         (make-sk-matrix (matrix-xx m) (matrix-xy m) (matrix-x0 m)
                         (matrix-yx m) (matrix-yy m) (matrix-y0 m) 0.0 0.0 1.0)]))
(define (picture-tile-rect who tile)
  (cond [(not tile) #f]
        [else
         (define values (cond [(list? tile) tile] [(vector? tile) (vector->list tile)]
                              [else (raise-argument-error who "#f or (x y width height) list/vector" tile)]))
         (unless (= (length values) 4)
           (raise-argument-error who "four-element tile rectangle" tile))
         (define r (apply rect who values))
         (unless (and (< (sk-rect-left r) (sk-rect-right r))
                      (< (sk-rect-top r) (sk-rect-bottom r)))
           (raise-argument-error who "nonempty tile rectangle" tile))
         r]))
(define (make-picture-shader pic #:tile-x [tile-x 'clamp] #:tile-y [tile-y 'clamp]
                             #:sampling [mode 'nearest] #:local-matrix [matrix #f]
                             #:tile-rect [tile #f])
  (define who 'make-picture-shader)
  (define ph (raw:picture-h who pic))
  (define tx (choice who tile-x tile-mode-values))
  (define ty (choice who tile-y tile-mode-values))
  (define filter (choice who mode sampling-values))
  (define local (picture-local-matrix who matrix))
  (define bounds (picture-tile-rect who tile))
  (call-with-owned who (list ph)
    (lambda (pp)
      ;; Creation occurs inside the picture's live owned scope. Skia keeps a
      ;; reference; the audit independently snapshots the symbolic dependencies.
      (raw:new-shader who
        (lambda () (sk_picture_make_shader pp tx ty filter local bounds))))))

(module* testing #f (provide picture-local-matrix picture-tile-rect))

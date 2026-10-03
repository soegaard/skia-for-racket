#lang racket/base
;; Headless ownership and presentation for skia/canvas. Requiring this module
;; initializes neither racket/gui nor the lazy native Skia renderer.
(require racket/class racket/future
         (prefix-in rd: racket/draw)
         "../dc.rkt" "dc-support.rkt"
         (submod "dc-class.rkt" canvas)
         (only-in "check.rkt" check-dimensions current-skia-byte-limit))
(provide canvas-backing% rgba->argb!)

;; The input and output are both premultiplied; only the channel order changes.
;; Read the complete pixel first so a caller may use the same byte string for
;; source and destination. All validation precedes the first write.
(define (rgba->argb! rgba argb)
  (unless (bytes? rgba)
    (raise-argument-error 'rgba->argb! "bytes?" rgba))
  (unless (and (bytes? argb) (not (immutable? argb)))
    (raise-argument-error 'rgba->argb! "mutable byte string" argb))
  (unless (and (zero? (remainder (bytes-length rgba) 4))
               (= (bytes-length rgba) (bytes-length argb)))
    (raise-arguments-error 'rgba->argb!
                           "equal byte lengths that are multiples of four required"
                           "RGBA length" (bytes-length rgba)
                           "ARGB length" (bytes-length argb)))
  (for ([i (in-range 0 (bytes-length rgba) 4)])
    (define r (bytes-ref rgba i))
    (define g (bytes-ref rgba (+ i 1)))
    (define b (bytes-ref rgba (+ i 2)))
    (define a (bytes-ref rgba (+ i 3)))
    (bytes-set! argb i a)
    (bytes-set! argb (+ i 1) r)
    (bytes-set! argb (+ i 2) g)
    (bytes-set! argb (+ i 3) b))
  (void))

;; Account for the cached bitmap and ARGB transfer storage plus a copied RGBA
;; readback. Replacement temporarily retains the previous bitmap and transfer
;; storage. The DC checks its native root/alpha surfaces separately; snapshots
;; retained by callers and draw-lib/allocator overhead are outside this budget.
(define (check-presentation-size who pixel-width pixel-height [retained-bytes 0])
  (define n (check-dimensions who pixel-width pixel-height))
  (define needed (max (* 3 n) (+ retained-bytes (* 2 n))))
  (unless (<= needed (current-skia-byte-limit))
    (raise-arguments-error who "canvas presentation exceeds current-skia-byte-limit"
                           "required presentation bytes" needed
                           "limit" (current-skia-byte-limit)))
  n)

(define (make-presentation who width height backing bytes-count)
  ;; Allocate before touching an existing DC. A failed bitmap allocation cannot
  ;; leave the native surface and the presentation bitmap at different sizes.
  (define argb (make-bytes bytes-count))
  (define bitmap (rd:make-bitmap width height #t #:backing-scale backing))
  (unless (send bitmap ok?)
    (error who "could not allocate the canvas presentation bitmap"))
  (values bitmap argb))

(define canvas-backing%
  (class object%
    (init [width 1] [height 1] [backing-scale 1.0]
          [background "white"] [smoothing 'unsmoothed]
          [dc-class skia-dc%])
    (define owner (current-thread))
    (define closed-state #f)
    (define w width)
    (define h height)
    (define-values (pixel-w pixel-h backing)
      (dc-physical-size 'canvas-backing% width height backing-scale))
    (super-new)
    (when (current-future)
      (error 'canvas-backing% "construction in a future is not supported"))
    (unless (class? dc-class)
      (raise-argument-error 'canvas-backing% "class?" dc-class))
    (define byte-count (check-presentation-size 'canvas-backing% pixel-w pixel-h))
    (define-values (bitmap argb)
      (make-presentation 'canvas-backing% w h backing byte-count))
    ;; The public DC identity survives every successful resize.
    (define dc (new dc-class [width w] [height h] [backing-scale backing]
                    [background background] [smoothing smoothing]))

    (define/private (owner! who)
      (unless (and (eq? owner (current-thread)) (not (current-future)))
        (error who "canvas backing belongs to another Racket thread; futures are not supported")))
    (define/private (check! who)
      (owner! who)
      (when (or closed-state (not (send dc ok?)))
        (error who "canvas backing is closed")))

    (define/public (get-dc)
      (check! 'canvas-backing-get-dc)
      dc)

    (define/public (resize! width height scale)
      (check! 'canvas-backing-resize!)
      (define-values (next-pixel-w next-pixel-h next-backing)
        (dc-physical-size 'canvas-backing-resize! width height scale))
      (cond
        [(and (= w width) (= h height) (= backing next-backing))
         ;; Let the DC enforce its paint-scope guard even for an allocation-free
         ;; no-op. No new bitmap, byte string, or native surface is created.
         (dc-resize-backing! dc width height next-backing)]
        [else
         (define next-byte-count
           (check-presentation-size 'canvas-backing-resize! next-pixel-w next-pixel-h
                                    (* 2 byte-count)))
         (define-values (next-bitmap next-argb)
           (make-presentation 'canvas-backing-resize! width height next-backing
                              next-byte-count))
         (define (commit!)
           (set! w width)
           (set! h height)
           (set! pixel-w next-pixel-w)
           (set! pixel-h next-pixel-h)
           (set! backing next-backing)
           (set! byte-count next-byte-count)
           (set! bitmap next-bitmap)
           (set! argb next-argb))
         ;; The native replacement is transactional. Once it succeeds, prevent
         ;; an asynchronous break between the DC and presentation-state commits.
         (parameterize-break #f
           (with-handlers ([(lambda (_) #t)
                            (lambda (failure)
                              ;; An injected renderer can fail while releasing
                              ;; the OLD surface after the replacement commits.
                              ;; Keep both halves at the committed geometry and
                              ;; still propagate the original release failure.
                              (with-handlers ([(lambda (_) #t) void])
                                (define-values (actual-w actual-h) (send dc get-size))
                                (when (and (= width actual-w) (= height actual-h)
                                           (= next-backing (send dc get-backing-scale)))
                                  (commit!)))
                              (raise failure))])
             (dc-resize-backing! dc width height next-backing)
             (commit!)))
         #t]))

    (define/public (paint! thunk [clear? #t])
      (check! 'canvas-backing-paint!)
      (unless (and (procedure? thunk) (procedure-arity-includes? thunk 0))
        (raise-argument-error 'canvas-backing-paint! "procedure accepting zero arguments" thunk))
      (unless (boolean? clear?)
        (raise-argument-error 'canvas-backing-paint! "boolean?" clear?))
      ;; DC scope cleanup discards unfinished alpha groups on normal return,
      ;; exceptions, and continuation escapes; caller-selected drawing state
      ;; otherwise stays attached to the same DC.
      (call-with-dc-canvas-paint
       dc
       (lambda ()
         (when clear? (dc-clear-backing! dc))
         (thunk))))

    (define/public (get-bitmap)
      (check! 'canvas-backing-get-bitmap)
      ;; Recheck a dynamically lowered byte limit before allocating readback.
      (check-presentation-size 'canvas-backing-get-bitmap pixel-w pixel-h)
      ;; The exposed DC can change outside paint!, so every request refreshes
      ;; pixels. The bitmap and channel-reordering storage remain reusable.
      (define rgba (send dc get-rgba-bytes #:premultiplied? #t))
      (rgba->argb! rgba argb)
      (send bitmap set-argb-pixels 0 0 pixel-w pixel-h argb #f #t #:unscaled? #t)
      bitmap)

    (define/public (get-info)
      (check! 'canvas-backing-get-info)
      (hasheq 'width w 'height h 'pixel-width pixel-w 'pixel-height pixel-h
              'backing-scale backing 'transfer "copied-premultiplied-rgba-to-argb"
              'presentation-bytes (* 2 byte-count)))

    (define/public (closed?)
      (owner! 'canvas-backing-closed?)
      (or closed-state (not (send dc ok?))))

    (define/public (close)
      (owner! 'canvas-backing-close)
      (unless closed-state
        ;; Close first: an attempted close inside a paint callback is rejected
        ;; by the DC and must leave the backing usable for the next paint.
        (parameterize-break #f
          (dynamic-wind
           void
           (lambda () (send dc close))
           (lambda ()
             ;; DC closure commits before renderer teardown. Even when that
             ;; teardown raises, release the cached presentation storage; a
             ;; rejected close that leaves the DC live must preserve it.
             (unless (send dc ok?)
               (set! closed-state #t)
               (set! bitmap #f)
               (set! argb #f))))))
      (void))))

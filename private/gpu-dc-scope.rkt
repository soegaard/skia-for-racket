#lang racket/base
;; Frame DC state and lifetime, without a GUI or native GPU initialization.
;; The ordinary DC keeps its logical state. Only renderer-bound commands are
;; mapped to the authoritative physical extent supplied by the GPU target.
(require racket/class racket/future racket/list
         "dc-class.rkt" "dc-support.rkt"
         (submod "dc-class.rkt" canvas)
         (only-in "check.rkt" check-dimensions))
(provide skia-gpu-dc? skia-gpu-dc-capabilities gpu-dc-scope-active?
         checked-frame-size (struct-out dc-frame-size)
         scale-dc-renderer call-with-frame-dc/renderer)

(define skia-gpu-dc<%> (interface ()))
(define (skia-gpu-dc? value) (is-a? value skia-gpu-dc<%>))
(define current-frame-dc (make-parameter #f))
(define (gpu-dc-scope-active?) (and (current-frame-dc) #t))
(struct dc-frame-size (pixel-width pixel-height logical-width logical-height scale-x scale-y)
  #:transparent)

(define (checked-frame-size pw ph lw lh)
  (define who 'call-with-gpu-dc)
  (check-dimensions who pw ph)
  (define w (dc-real who lw))
  (define h (dc-real who lh))
  (unless (and (> w 0) (> h 0))
    (raise-arguments-error who "logical dimensions must be positive finite reals"
                           "width" lw "height" lh))
  (define sx (dc-real who (/ pw w)))
  (define sy (dc-real who (/ ph h)))
  (unless (and (> sx 0) (> sy 0))
    (error who "logical-to-physical scale must be positive"))
  (dc-frame-size pw ph w h sx sy))

(define (skia-gpu-dc-capabilities)
  (hash-set* (dc-capabilities)
    'stage "0.59" 'class "frame-scoped-skia-gpu-dc" 'storage "frame-scoped-gpu-offscreen"
    'alpha_groups "same-context isolated GPU surfaces; discard unfinished groups on scope exit"
    'lifetime "callback only; closed on every exit; never reactivated"
    'coordinates "logical drawing coordinates; independent X/Y device scales from actual target extents"
    'backing_scale 1.0 'device_scale "pixel-width/logical-width, pixel-height/logical-height"
    'presentation "GPU snapshot and GPU-to-GPU draw; no automatic CPU readback"
    'snapshot "explicit synchronous transfer to an independent CPU image"
    'native_probe_performed #f 'gui_initialized 'not-probed
    'deferred '(native-handle-brushes arbitrary-combined-text-breaks persistent-gpu-dc)))

(define (scaled-clip clip sx sy)
  (and clip
       (dc-clip
        (for/list ([path (in-list (dc-clip-paths clip))])
          (dc-clip-path
           (dc-path-map (dc-clip-path-commands path)
                        (lambda (x y)
                          (values (dc-real 'gpu-dc-clip (* sx x))
                                  (dc-real 'gpu-dc-clip (* sy y)))))
           (dc-clip-path-rule path))))))

(define (scale-dc-renderer renderer sx sy
                           #:create [create (dc-renderer-create renderer)]
                           #:close [close (dc-renderer-close renderer)])
  (unless (dc-renderer/styles? renderer)
    (raise-argument-error 'scale-dc-renderer "dc-renderer/styles?" renderer))
  (define device (dc-matrix 'scale-dc-renderer (vector sx 0 0 sy 0 0)))
  (define (matrix m) (dc-multiply device m))
  (define (clip c) (scaled-clip c sx sy))
  (dc-renderer/styles
   create close
   (lambda (target command)
     ((dc-renderer-draw renderer) target
      (dc-draw (dc-draw-commands command) (dc-draw-rule command)
               (matrix (dc-draw-matrix command)) (clip (dc-draw-clip command))
               (dc-draw-ink command) (dc-draw-antialias? command))))
   (lambda (target clipping rgba erase?)
     ((dc-renderer-clear renderer) target (clip clipping) rgba erase?))
   (dc-renderer-snapshot renderer) (dc-renderer-rgba renderer) (dc-renderer-png renderer)
   (dc-renderer+-measure-text renderer)
   (lambda (target request m clipping x y angle foreground background solid?)
     ((dc-renderer+-draw-text renderer) target request (matrix m) (clip clipping)
      x y angle foreground background solid?))
   (dc-renderer+-glyph-exists? renderer)
   (lambda (target data rect m clipping opacity sampling)
     ((dc-renderer+-draw-bitmap renderer) target data rect (matrix m) (clip clipping)
      opacity sampling))
   (lambda (target m clipping x y width height x2 y2)
     ((dc-renderer+-copy renderer) target (matrix m) (clip clipping) x y width height x2 y2))
   (lambda (parent child clipping opacity)
     ;; Child pixels already have device scaling. Only the parent clip scales.
     ((dc-renderer/alpha-composite renderer) parent child (clip clipping) opacity))
   (dc-renderer/styles-path-bounds renderer)))

(define (call-with-frame-dc/renderer renderer extent proc commit
                                     #:background [background "white"]
                                     #:smoothing [smoothing 'smoothed]
                                     #:clear? [clear? #t])
  (define who 'call-with-gpu-dc)
  (when (or (gpu-dc-scope-active?) (current-future))
    (error who "nested GPU DC scopes and construction in futures are not supported"))
  (unless (dc-renderer/styles? renderer)
    (raise-argument-error who "dc-renderer/styles?" renderer))
  (unless (dc-frame-size? extent) (raise-argument-error who "dc-frame-size?" extent))
  ;; Revalidate even a privately constructed extent before allocating anything.
  (define checked
    (checked-frame-size (dc-frame-size-pixel-width extent) (dc-frame-size-pixel-height extent)
                        (dc-frame-size-logical-width extent) (dc-frame-size-logical-height extent)))
  (unless (equal? checked extent) (error who "inconsistent GPU target geometry"))
  (for ([p (in-list (list proc commit))])
    (unless (and (procedure? p) (procedure-arity-includes? p 1))
      (raise-argument-error who "procedure accepting one argument" p)))
  (unless (boolean? clear?) (raise-argument-error who "boolean?" clear?))
  (define root #f)
  (define live (make-hasheq))
  (define creation-order '())
  (define dc #f)
  (define primary-failure? #f)
  (define entered? #f)
  (define (create width height)
    (define target ((dc-renderer-create renderer) width height))
    (when target
      (when (hash-has-key? live target) (error who "renderer reused a live target"))
      (hash-set! live target #t)
      (set! creation-order (cons target creation-order))
      (unless root (set! root target)))
    target)
  (define (close target)
    (when (hash-has-key? live target)
      ;; Detach before the callback; a throwing close is not invoked twice.
      (hash-remove! live target)
      ((dc-renderer-close renderer) target)))
  (define sx (dc-frame-size-scale-x extent))
  (define sy (dc-frame-size-scale-y extent))
  (define base% (make-skia-dc-class
                 (scale-dc-renderer renderer sx sy #:create create #:close close)))
  (define frame-dc%
    (class* base% (skia-gpu-dc<%>)
      (super-new)
      ;; Super calls perform the ordinary owner/closed checks. Drawing state,
      ;; text metrics and region paths remain logical, not pre-scaled.
      (define/override (get-size)
        (super get-size)
        (values (dc-frame-size-logical-width extent) (dc-frame-size-logical-height extent)))
      (define/override (get-device-scale)
        (super get-device-scale)
        (values sx sy))
      (define/override (get-capabilities)
        (super get-capabilities)
        (skia-gpu-dc-capabilities))
      (define/override (dc-region-query-info)
        (define-values (_w _h matrix clipping) (super dc-region-query-info))
        (values (dc-frame-size-logical-width extent) (dc-frame-size-logical-height extent)
                matrix clipping))))
  (define (cleanup)
    (parameterize-break #f
      (define failed? #f)
      (define first-failure #f)
      (define (attempt thunk)
        (with-handlers ([(lambda (_) #t)
                         (lambda (e)
                           (unless failed? (set! failed? #t) (set! first-failure e)))])
          (thunk)))
      (when dc (attempt (lambda () (send dc close))))
      ;; Also covers failure midway through the DC constructor or layer setup.
      (for ([target (in-list creation-order)]) (attempt (lambda () (close target))))
      (set! creation-order '())
      (set! root #f)
      (when (and failed? (not primary-failure?)) (raise first-failure))))
  (call-with-continuation-barrier
   (lambda ()
     (parameterize ([current-frame-dc #t])
       (dynamic-wind
        (lambda ()
          (when entered? (error who "an expired GPU DC scope cannot be reentered"))
          (set! entered? #t))
        (lambda ()
          (with-handlers ([(lambda (_) #t)
                           (lambda (e) (set! primary-failure? #t) (raise e))])
            ;; Physical dimensions are used only for target/alpha allocation.
            ;; Public geometry is supplied by frame-dc% and its renderer map.
            (set! dc (new frame-dc%
                          [width (dc-frame-size-pixel-width extent)]
                          [height (dc-frame-size-pixel-height extent)]
                          [backing-scale 1.0] [background background] [smoothing smoothing]))
            (begin0
              (call-with-dc-canvas-paint dc
                (lambda ()
                  (when clear? (send dc clear))
                  (proc dc)))
              ;; Alpha cleanup has finished before the root is sampled.
              (commit root))))
        cleanup)))))

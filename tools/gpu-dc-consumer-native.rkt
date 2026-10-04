#lang racket/base
;; Mandatory when selected. No optional backend skip and no CPU fallback.
(require racket/class racket/cmdline racket/file racket/list
         (prefix-in sk: "../main.rkt") (prefix-in gpu: "../gpu.rkt")
         "../gpu-egl.rkt" "../gpu-dc.rkt"
         (submod "../private/gpu-presenter.rkt" adapter-internals)
         "../tests/gpu-dc-consumer-fixtures.rkt" "gpu-dc-consumer-common.rkt")
(define (run-native directory token backend adapter)
  (define workloads (make-consumer-workloads))
  (define captures '())
  (define transfers '())
  (define saved-dcs '())
  (define ctx
    (case backend
      [(egl) (make-egl-gpu-context)]
      [(metal) (gpu:make-gpu-context #:backend 'metal)]
      [(direct3d) (gpu:make-gpu-context #:backend 'direct3d #:adapter adapter)]
      [else (error 'gpu-dc-consumers "unsupported native backend ~a" backend)]))
  (define (retain! workload extent target data layout events)
    (set! captures (cons (write-consumer-capture! directory workload extent target data layout events) captures)))
  (dynamic-wind void
    (lambda ()
      (for ([extent (in-list consumer-extents)])
        (define pw (list-ref extent 1)) (define ph (list-ref extent 2))
        (define lw (list-ref extent 3)) (define lh (list-ref extent 4))
        (define target (gpu:call-with-gpu-context ctx (lambda () (gpu:make-gpu-surface ctx pw ph))))
        (define presenter #f)
        (define presents 0)
        (define metrics (presentation-metrics pw ph lw lh))
        (dynamic-wind void
          (lambda ()
            (ensure-consumer! (gpu:gpu-surface? target) "target is not native GPU storage")
            (set! presenter
              (make-presenter
               (presentation-adapter (gpu:gpu-context-backend ctx) ctx (lambda () metrics)
                 (lambda (_metrics receive)
                   (gpu:call-with-gpu-context ctx
                     (lambda ()
                       (receive (sk:surface-canvas target)
                                (hasheq 'backend (symbol->string (gpu:gpu-context-backend ctx))
                                        'target_identity "consumer-offscreen-final-target")
                                (lambda () (gpu:gpu-flush-and-submit! ctx)
                                  (set! presents (add1 presents)))))))
                 (lambda (_callback) (void)) void
                 (lambda () (hasheq 'fixture "native offscreen final target, not a window")))
               void raise))
            (for ([workload (in-list workloads)])
              (call-with-consumer-cpu-dc extent
                (lambda (dc)
                  (define layout (exercise-consumer! workload dc))
                  (retain! workload extent "cpu" (send dc get-rgba-bytes #:premultiplied? #t) layout '())))
              (for ([path (in-list '("surface" "frame"))])
                (define layout #f) (define saved #f)
                (define (draw dc)
                  (set! saved dc)
                  (for ([previous (in-list saved-dcs)])
                    (ensure-consumer! (not (send previous ok?)) "a later frame revived an expired DC"))
                  (set! layout (exercise-consumer! workload dc)))
                (define before presents)
                (define-values (_draw events)
                  (observe-consumer-io!
                   (lambda ()
                     (cond
                       [(equal? path "surface")
                        (gpu:call-with-gpu-context ctx
                          (lambda ()
                            (call-with-gpu-surface-dc target draw
                              #:logical-width lw #:logical-height lh #:clear? #t)))]
                       [else
                        (gpu:gpu-presenter-set-render! presenter
                          (lambda (frame) (call-with-gpu-frame-dc frame draw)))
                        (ensure-consumer! (eq? (gpu:gpu-presenter-render! presenter) 'present-requested)
                                          "consumer frame was not committed")
                        (ensure-consumer! (= presents (add1 before)) "wrong frame commit count")]))))
                (check-consumer-expired! saved)
                (set! saved-dcs (cons saved saved-dcs))
                ;; Read the borrowed root or the FINAL presenter target only
                ;; AFTER DC expiration. This ledger is not the drawing ledger.
                (define-values (pixels capture-events)
                  (observe-consumer-io!
                    (lambda () (gpu:call-with-gpu-context ctx
                      (lambda () (gpu:gpu-surface->rgba-bytes target #:premultiplied? #t))))
                    #:capture? #t))
                (set! transfers (cons (hasheq 'id (workload-id workload extent path)
                                               'io capture-events) transfers))
                (retain! workload extent path pixels layout events))))
          (lambda ()
            (when presenter (gpu:gpu-presenter-close! presenter))
            (sk:skia-close! target)))))
    (lambda () (gpu:gpu-context-close! ctx)))
  ;; Successful context closure is part of acceptance, before a passed marker.
  (finish-consumer-report! directory "native" token (symbol->string backend) (reverse captures)
    (hasheq 'expired_dcs (length saved-dcs) 'context_closed #t 'transfers (reverse transfers)
            'final_target_pixels #t 'window_created #f)))
(module+ main
  (define directory #f) (define token #f) (define backend 'egl) (define adapter 'hardware)
  (command-line #:once-each
    [("--directory") value "New capture directory" (set! directory value)]
    [("--run-token") value "Validation identity" (set! token value)]
    [("--backend") value "egl, metal or direct3d" (set! backend (string->symbol value))]
    [("--adapter") value "hardware or warp" (set! adapter (string->symbol value))]
    #:args () (void))
  (unless (and directory token) (error 'gpu-dc-consumers "--directory and --run-token are required"))
  (make-directory directory)
  (run-native directory token backend adapter))

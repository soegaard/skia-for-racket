#lang racket/base

;;;
;;; Reference DC Integration Pure Test
;;;

;; Checks detached DC capability reports, callback lifetimes, and validation before native drawing.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; Native-free declarations and rejection boundaries for R4e. This suite does
;; not allocate a Skia surface, create a GPU context, render a document, or open
;; a GUI. Native DC/output/GPU execution remains in the repository validators.
(require rackunit racket/class
         skia/dc skia/dc-output skia/gpu-dc skia/output)

(module+ test
  (test-case "raster DC capabilities are detached declarations"
    (define info (skia-dc-capabilities))
    (check-true (immutable? info))
    (check-equal? (hash-ref info 'class) "skia-dc%")
    (check-false (hash-ref info 'native_probe_performed)))

  (test-case "compatibility reports all four declared lifetimes"
    (for ([target '(raster gpu pdf svg)])
      (define report (skia-dc-compatibility target))
      (check-true (immutable? report))
      (check-eq? (hash-ref report 'target) target))
    (check-exn exn:fail? (lambda () (skia-dc-compatibility 'unknown))))

  (test-case "unsupported exception fields are public detached data"
    (define e (exn:fail:skia-dc:unsupported
               "unsupported" (current-continuation-marks)
               'draw 'native-handle "R4e"))
    (check-true (exn:fail:skia-dc:unsupported? e))
    (check-eq? (exn:fail:skia-dc:unsupported-method e) 'draw)
    (check-eq? (exn:fail:skia-dc:unsupported-feature e) 'native-handle)
    (check-equal? (exn:fail:skia-dc:unsupported-stage e) "R4e"))

  (test-case "plain objects are not persistent Skia DCs"
    (check-false (skia-dc? (new object%))))

  (test-case "output command limit is guarded and parameterized"
    (define before (current-output-dc-command-limit))
    (parameterize ([current-output-dc-command-limit 7])
      (check-equal? (current-output-dc-command-limit) 7))
    (check-equal? (current-output-dc-command-limit) before)
    (for ([bad '(0 -1 1.5 #f)])
      (check-exn exn:fail? (lambda () (current-output-dc-command-limit bad)))))

  (test-case "output DC capabilities declare callback-only storage"
    (define info (output-dc-capabilities))
    (check-true (immutable? info))
    (check-equal? (hash-ref info 'storage) "deferred-vector-commands")
    (check-equal? (hash-ref info 'lifetime)
                  "callback only; expired before native document replay"))

  (test-case "plain objects are not output DCs"
    (check-false (skia-output-dc? (new object%))))

  (test-case "DC output pages are detached and do not author at construction"
    (define calls 0)
    (define page
      (make-dc-output-page 20 10 (lambda (_dc) (set! calls (add1 calls)))))
    (check-true (output-page? page))
    (check-equal? calls 0))

  (test-case "GPU DC capabilities are detached declarations"
    (define info (skia-gpu-dc-capabilities))
    (check-true (immutable? info))
    (check-equal? (hash-ref info 'class) "frame-scoped-skia-gpu-dc")
    (check-false (hash-ref info 'native_probe_performed)))

  (test-case "plain objects are not GPU DCs"
    (check-false (skia-gpu-dc? (new object%))))

  (test-case "frame DC rejects a non-frame before loading native GPU drawing"
    (check-exn exn:fail? (lambda () (call-with-gpu-frame-dc #f values))))

  (test-case "GPU DC callback arity rejects before native drawing"
    (check-exn exn:fail?
      (lambda () (call-with-gpu-surface-dc #f (lambda () (void)))))))

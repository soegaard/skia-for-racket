#lang racket/base

;;;
;;; GPU Output Example
;;;

;; Generates output documents using an explicitly selected GPU rendering backend.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;; An explicitly selected backend executes only the bounded raster group.

;;;
;;; Imports and Exports
;;;

(require racket/cmdline racket/file racket/path
         "../main.rkt" "../gpu.rkt" "../gpu-output.rkt" "../tools/gpu-test-host.rkt")

;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; backend : symbol?
  ;   Selects backend for the example.
  (define backend 'metal)

  ; host : symbol?
  ;   Selects host for the example.
  (define host 'gui)

  ; prefix : string?
  ;   Selects the destination used by this example's output.
  (define prefix "output/gpu-output-example")
  (command-line #:once-each
    [("--backend") b "opengl or metal" (set! backend (string->symbol b))]
    [("--host") h "gui or egl" (set! host (string->symbol h))]
    [("--prefix") p "Output file prefix" (set! prefix p)]
    #:args () (void))
  (make-directory* (or (path-only (string->path prefix)) (current-directory)))
  (call-with-gpu-backend-host backend
    (lambda (make-context host-info)
      (call-with-gpu-raster-executor make-context
        (lambda (executor)
          (define page
            (make-output-page 240 160
              (lambda (c)
                (with-skia ([p (make-paint #:color 'blue)] [font (make-font #:size 14)])
                  ;; Text and rule remain outside the raster and stay vector.
                  (draw-simple-text c "Vector page / GPU effect" 20 28 font p)
                  (draw-line c 20 34 220 34 p))
                (draw-output-group c 40 60 140 60
                  (lambda (g)
                    (with-skia ([e (make-runtime-effect
                                   "half4 main(float2 p) { return half4(p.x/140, 0.5, 0.8, 1); }")]
                                [s (runtime-effect->shader e)] [p (make-paint #:shader s)])
                      (draw-rounded-rect g 0 0 140 60 12 12 p)))
                  #:padding 8 #:raster-executor executor #:label "effect"))))
          (for ([format '(pdf svg)])
            (save-output/audit page (string-append prefix "." (symbol->string format)) format
                               #:policy 'error #:exists 'replace #:raster-dpi 144)))))
    #:host host))

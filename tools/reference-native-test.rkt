#lang racket/base

;; Opt-in CPU checks. The Reference build itself does not run these tests.
(require rackunit racket/file racket/list racket/path racket/runtime-path syntax/modread skia)

(define-runtime-path reference-directory "../scribblings/reference")

;; Read and execute the displayed native examples, instead of maintaining copies.
;; Every block runs in a fresh namespace; no chapter inherits another's example state.
(define (run-displayed-examples directory)
  (define (blocks form)
    (cond
      [(not (pair? form)) '()]
      [(memq (car form) '(quote quasiquote examples)) '()]
      [(eq? (car form) 'racketblock) (list (cdr form))]
      [else (append-map blocks form)]))
  (for ([path (in-list (sort (directory-list reference-directory #:build? #t)
                             path<?))]
        #:when (regexp-match? #rx"[.]scrbl$" (path->string path)))
    (define chapter (path->string (file-name-from-path path)))
    (define document
      (call-with-input-file path
        (lambda (in)
          (with-module-reading-parameterization
           (lambda () (syntax->datum (read-syntax path in)))))))
    (for* ([example (in-list (blocks document))] [attempt (in-range 2)])
      (parameterize ([current-namespace (make-base-namespace)]
                     [current-directory directory])
        (namespace-require 'skia)
        (check-not-exn (lambda ()
                         (call-with-values (lambda () (eval `(begin ,@example)))
                                           (lambda ignored (void))))
                       (format "~a, run ~a" chapter (add1 attempt)))))))

(module+ test
  (define directory (make-temporary-file "skia-reference-native-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define path (build-path directory "rectangle.png"))
      (define saved-surface #f)
      (define saved-canvas #f)
      (define saved-paint #f)
      (check-equal?
       (call-with-values
        (lambda ()
          (with-skia ([surface (make-surface 4 3)]
                      [paint (make-paint #:color 'red #:antialias? #f)])
            (define canvas (surface-canvas surface))
            (set! saved-surface surface)
            (set! saved-canvas canvas)
            (set! saved-paint paint)
            (check-false (skia-resource? canvas))
            (draw-rect canvas 1 1 2 1 paint)
            (check-equal? (color->argb (surface-pixel surface 1 1)) #xffff0000)
            (check-equal? (color->argb (surface-pixel surface 0 0)) 0)
            (save-png surface path)
            (define before (file->bytes path))
            (check-equal? (subbytes before 0 8) #"\211PNG\r\n\32\n")
            (check-exn exn:fail? (lambda () (save-png surface path)))
            (check-exn exn:fail?
                       (lambda () (save-png surface path #:exists 'replace #:compression -1)))
            (check-equal? (file->bytes path) before)
            (save-png surface path #:exists 'replace)
            (values 1 2)))
        list)
       '(1 2))
      (check-true (and (surface? saved-surface) (skia-closed? saved-surface)))
      (check-true (and (canvas? saved-canvas) (skia-closed? saved-canvas)))
      (check-true (skia-closed? saved-paint))
      (check-not-exn (lambda () (skia-close! saved-surface)))
      (check-exn exn:fail? (lambda () (surface-canvas saved-surface)))
      (check-exn exn:fail? (lambda () (skia-close! saved-canvas)))
      (define acquired #f)
      (check-exn
       exn:fail?
       (lambda ()
         (with-skia ([surface (make-surface 1 1)]
                     [later (begin (set! acquired surface) (error 'later "initialization failed"))])
           (void))))
      (check-true (skia-closed? acquired))
      (define unlisted #f)
      (with-skia ()
        (define paint (make-paint))
        (set! unlisted paint))
      (check-false (skia-closed? unlisted))
      (skia-close! unlisted)
      (run-displayed-examples directory)
      ;; Both modes multiply RGB, but their alpha rules differ for translucent input.
      (for ([mode '(modulate multiply)] [alpha '(64 192)])
        (with-skia ([surface (make-surface 1 1 #:background (rgba 80 120 200 128))]
                    [paint (make-paint #:color (rgba 240 180 100 128)
                                       #:blend-mode mode #:antialias? #f)])
          (draw-rect (surface-canvas surface) 0 0 1 1 paint)
          (check-= (rgba-alpha (surface-pixel surface 0 0)) alpha 1)))
      (check-exn exn:fail? (lambda () (make-surface 0 1)))
      (parameterize ([current-skia-byte-limit 3])
        (check-exn exn:fail? (lambda () (make-surface 1 1)))))
    (lambda () (delete-directory/files directory))))

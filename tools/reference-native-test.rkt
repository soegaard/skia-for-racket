#lang racket/base

;;;
;;; Displayed Reference Example Checks
;;;

;; Extracts displayed Reference examples and runs them in fresh namespaces or isolated processes.
;; This acceptance runner detects examples that drift from the executable public API.

;;;
;;; Imports and Exports
;;;

;; Opt-in CPU checks. The Reference build itself does not run these tests.
(require rackunit racket/file racket/list racket/path racket/runtime-path racket/system
         syntax/modread skia)


;;;
;;; Example Classification and Isolated Execution
;;;

; reference-directory : path?
;   Locates ../scribblings/reference relative to this module, independent of the invoking
;   directory.
(define-runtime-path reference-directory "../scribblings/reference")

;; Read and execute the displayed native examples, instead of maintaining copies.
;; The live-stream provider installs process-global native callbacks.  It alone
;; needs a fresh Racket process; ordinary examples retain the cheaper fresh-
;; namespace isolation used by this test historically.

; live-native-symbols : (listof symbol?)
;   Identifies callback-based stream APIs whose displayed examples require process isolation.
(define live-native-symbols
  '(make-codec-incremental
    image-from-port picture-from-port copy-port/streaming
    image->port picture->port output->port
    image-write-stream! picture-write-stream! output-write-stream!))


; uses-live-native-callbacks? : any/c -> any/c
;   Finds references to live callback APIs recursively; returns a nonfalse membership tail when
;   present.
(define (uses-live-native-callbacks? form)
  (cond
    [(symbol? form) (memq form live-native-symbols)]
    [(pair? form) (or (uses-live-native-callbacks? (car form))
                      (uses-live-native-callbacks? (cdr form)))]
    [else #f]))


; run-example-in-fresh-process : path-string? list? -> void?
;   Runs a displayed example in a temporary standalone module, isolating native callback service
;   state and deleting the module afterward.
(define (run-example-in-fresh-process directory example)
  (define source (make-temporary-file "skia-reference-native-example-~a.rkt" #f directory))
  (dynamic-wind
    void
    (lambda ()
      (call-with-output-file source
        (lambda (out)
          (display "#lang racket/base\n(require skia)\n" out)
          ;; A displayed block may have top-level `require` forms.  Emit those
          ;; directly in the generated module, then evaluate the remaining
          ;; forms together so its definitions retain their lexical scope.
          (define imports
            (filter (lambda (form) (and (pair? form) (eq? (car form) 'require))) example))
          (define body (filter (lambda (form) (not (member form imports))) example))
          (for ([form (in-list imports)])
            (write form out)
            (newline out))
          (when (pair? body)
            ;; Appending `void` also makes definition-only blocks valid local
            ;; bodies while deliberately discarding displayed return values.
            (write `(call-with-values (lambda () (let () ,@body (void)))
                                      (lambda ignored (void)))
                   out)
            (newline out)))
        #:exists 'truncate/replace)
      (unless (zero?
               (parameterize ([current-directory directory])
                 (system*/exit-code (find-system-path 'exec-file) (path->string source))))
        (error 'run-displayed-examples "fresh example process failed")))
    (lambda ()
      (when (file-exists? source) (delete-file source)))))


; run-example-in-fresh-namespace : path-string? list? -> void?
;   Evaluates a displayed example in a fresh namespace and the designated output directory.
(define (run-example-in-fresh-namespace directory example)
  (parameterize ([current-namespace (make-base-namespace)]
                 [current-directory directory])
    (namespace-require 'skia)
    (call-with-values (lambda () (eval `(begin ,@example)))
                      (lambda ignored (void)))))

;; Every block runs twice without inheriting another chapter's example state.

; run-displayed-examples : path-string? -> void?
;   Runs each Reference racketblock twice with namespace or process isolation appropriate to its
;   native callback use.
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
      (check-not-exn
       (lambda ()
         ((if (uses-live-native-callbacks? example)
              run-example-in-fresh-process
              run-example-in-fresh-namespace)
          directory example))
                     (format "~a, run ~a" chapter (add1 attempt))))))

(module+ test

  ;;;
  ;;; Test Entry Point
  ;;;

  ; directory : path?
  ;   Owns a temporary working directory for displayed-example artifacts, removed after the run.
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
      ;; Conceptual-diagram fixtures retain exact API facts in executable form:
      ;; composition acts right-to-left on points, and final-row padding is
      ;; excluded only from the minimum addressable storage length.
      (for ([actual (in-list
                     (vector->list (matrix-map-point
                         (matrix-compose (matrix-translate 10 20) (matrix-scale 2))
                         3 4)))]
            [expected '(16 28)])
        (check-= actual expected 1e-6))
      (for ([actual (in-list
                     (vector->list (matrix-map-point
                         (matrix-compose (matrix-scale 2) (matrix-translate 10 20))
                         3 4)))]
            [expected '(26 48)])
        (check-= actual expected 1e-6))
      (check-equal?
       (call-with-values
        (lambda () (image-info-storage-layout (make-image-info 3 2) #:row-bytes 16))
        list)
       '(16 28 32))
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

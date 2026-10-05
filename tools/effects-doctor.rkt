#lang racket/base
(require racket/cmdline racket/file racket/list json
         "../main.rkt" "../tests/effects-fixtures.rkt")
(define (write-bytes-file path data)
  (call-with-output-file path (lambda (out) (write-bytes data out)) #:exists 'error))
(define (effect-page name reports calls #:policy [policy 'raster])
  (make-output-page 96 72
    (lambda (c)
      (with-skia ([p (make-paint #:color (rgb 0 255 0) #:antialias? #f)])
        (draw-rect c 2 2 4 4 p))
      (set-box! reports
        (cons (draw-output-group c 8 16 64 48
                (lambda (gc)
                  (set-box! calls (add1 (unbox calls)))
                  (draw-effect-scene name gc))
                #:policy policy #:scale 1 #:label (symbol->string name))
              (unbox reports)))
      (canvas-annotate-url! c 2 2 4 4 (format "https://example.invalid/effects/~a" name)))
    #:background 'white))
(module+ main
  (define directory #f)
  (define token #f)
  (command-line #:once-each
    [("--directory") path "New output directory" (set! directory path)]
    [("--token") value "Invocation identity" (set! token value)]
    #:args () (void))
  (unless (and directory token) (error 'effects-doctor "--directory and --token required"))
  (when (directory-exists? directory) (error 'effects-doctor "directory already exists"))
  (make-directory* directory)
  (define rows '())
  (for ([name (in-list effect-scene-names)])
    (define prefix (symbol->string name))
    ;; One direct raster capture is independent of document replay.
    (with-skia ([surface (make-surface effect-width effect-height)])
      (draw-effect-scene name (surface-canvas surface))
      (write-bytes-file (build-path directory (string-append prefix ".rgba"))
                        (surface->rgba-bytes surface #:premultiplied? #t))
      (save-png surface (build-path directory (string-append prefix ".png"))))
    (for ([fmt (in-list '(pdf svg))])
      (define reports (box '()))
      (define calls (box 0))
      (define page (effect-page name reports calls))
      (define-values (data receipt) (output->bytes/audit page fmt #:policy 'error))
      (unless (= (unbox calls) 1) (error 'effects-doctor "authoring callback was repeated"))
      (unless (and (= (length (unbox reports)) 1)
                   (eq? (output-group-report-strategy (car (unbox reports))) 'raster)
                   (not (output-audit-report-blocking? receipt)))
        (error 'effects-doctor "invalid raster-group/audit report"))
      (define filename (format "~a.~a" prefix fmt))
      (write-bytes-file (build-path directory filename) data)
      ;; Exercise actual capture/preflight rejection, not just a policy table.
      (define rejected? #f)
      (with-handlers ([exn:fail:output-group? (lambda (_e) (set! rejected? #t))])
        (output->bytes/audit (effect-page name (box '()) (box 0) #:policy 'require-vector)
                            fmt #:policy 'error))
      (unless rejected? (error 'effects-doctor "require-vector unexpectedly accepted ~a" name))
      (set! rows
        (cons (hasheq 'name prefix 'format (symbol->string fmt) 'file filename
                      'rgba (string-append prefix ".rgba")
                      'reference_png (string-append prefix ".png")
                      'callback_count (unbox calls) 'vector_rejected #t 'audit_policy "error"
                      'audit (output-audit-report->jsexpr receipt)
                      'group (output-group-report->jsexpr (car (unbox reports)))) rows))))
  (call-with-output-file (build-path directory "documents.json")
    (lambda (out)
      (write-json (hasheq 'schema 1 'stage "0.66" 'run_token token 'status "passed"
                         'documents (reverse rows) 'rendering_executed #t
                         'independent_rendering_executed #f) out))
    #:exists 'error)
  (printf "Effects: ~a native PDF/SVG documents generated; independent inspection still required.\n"
          (length rows)))

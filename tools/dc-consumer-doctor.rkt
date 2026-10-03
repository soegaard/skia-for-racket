#lang racket/base
(require racket/class racket/list racket/file racket/path json rackunit/text-ui
         (prefix-in rd: racket/draw) (prefix-in sk: "../main.rkt") "../dc.rkt"
         "../tests/dc-consumer-fixtures.rkt" "../tests/dc-consumer-native-test.rkt")
(provide dc-consumer-doctor!)
(define (dc-consumer-doctor! directory)
  (define (file name) (build-path directory name))
  (define (publish data)
    (call-with-output-file (file "dc-consumers.json")
      (lambda (out) (write-json data out) (newline out)) #:exists 'replace))
  (define base
    (hasheq 'schema 1 'stage "0.56" 'validation_run (path->string (file-name-from-path directory))
            'racket_version (version) 'os (symbol->string (system-type 'os))
            'architecture (symbol->string (system-type 'arch))
            'gui_initialized #f 'gpu_execution_verified #f 'full_drop_in_compatibility #f
            'reference_pixel_equivalence_claimed #f))
  (with-handlers ([exn:fail? (lambda (e)
                             (publish (hash-set* base 'status "failed" 'error (exn-message e)))
                             (raise e))])
    (define failures (run-tests dc-consumer-native-tests))
    (unless (zero? failures) (error 'dc-consumer-doctor "real consumer suite failed"))
    (define (using f)
      (define dc (new skia-dc% [width consumer-width] [height consumer-height] [smoothing 'smoothed]))
      (dynamic-wind void (lambda () (send dc clear) (f dc)) (lambda () (send dc close))))
    (define picture (using make-consumer-pict))
    (define (render name draw)
      (define layout #f)
      (define image (using (lambda (dc) (set! layout (draw dc)) (send dc snapshot))))
      (sk:with-skia ([im image])
        (call-with-output-file (file name)
          (lambda (out) (write-bytes (sk:image->png-bytes im) out))
          #:mode 'binary #:exists 'error))
      layout)
    (define (reference name draw)
      (define bm (rd:make-bitmap consumer-width consumer-height #t))
      (define dc (new rd:bitmap-dc% [bitmap bm]))
      (define layout
        (dynamic-wind void
          (lambda () (send dc set-smoothing 'smoothed) (send dc clear) (draw dc))
          (lambda () (send dc set-bitmap #f))))
      (unless (send bm save-file (file name) 'png)
        (error 'dc-consumer-doctor "reference PNG encoding failed"))
      layout)
    (define captures
      (append-map
       (lambda (entry)
         (define kind (car entry))
         (define draw (cdr entry))
         (define-values (proc datum recorded-layout) (record-consumer draw))
         (define (name mode) (format "dc-consumer-~a.~a.png" kind mode))
         (define direct-layout (render (name "direct") draw))
         (render (name "procedure") proc)
         (render (name "datum") datum)
         (define reference-layout (reference (name "reference") draw))
         (for/list ([mode (in-list '("direct" "procedure" "datum" "reference"))]
                    [layout (in-list (list direct-layout recorded-layout recorded-layout reference-layout))])
           (hasheq 'kind kind 'mode mode 'file (name mode)
                   'layout (if (equal? kind "plot") layout #f))))
       (list (cons "pict" (lambda (dc) (draw-consumer-pict dc picture)))
             (cons "plot" draw-consumer-plot))))
    (define gui-loaded?
      (with-handlers ([exn:fail? (lambda (_) #f)]) (module->namespace 'racket/gui/base) #t))
    (when gui-loaded? (error 'dc-consumer-doctor "consumer validation initialized racket/gui/base"))
    (publish (hash-set* base 'status "passed" 'native_cases dc-consumer-native-test-count
                        'native_failures failures 'snapshots_encoded_after_dc_close #t
                        'captures captures))
    (displayln "Direct pict/plot and consumer replay suite passed; inspect the retained consumer pixels.")))

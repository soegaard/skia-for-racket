#lang racket/base
(require racket/class racket/file racket/path json rackunit/text-ui
         (prefix-in rd: racket/draw) (prefix-in sk: "../main.rkt") "../dc.rkt"
         "../tests/dc-style-fixtures.rkt" "../tests/dc-style-pure-test.rkt"
         "../tests/dc-style-native-test.rkt" "../examples/dc-replay.rkt")
(provide dc-style-doctor!)
(define (dc-style-doctor! directory)
  (define (file name) (build-path directory name))
  (define base (hasheq 'schema 1 'stage "0.57" 'validation_run (path->string (file-name-from-path directory))
                       'os (symbol->string (system-type 'os)) 'architecture (symbol->string (system-type 'arch))
                       'racket_version (version) 'gui_initialized #f 'gpu_execution_verified #f
                       'full_drop_in_compatibility #f 'cairo_drawing_fallback #f
                       'region_query_scratch_context #t 'reference_pixel_equivalence_claimed #f))
  (define (publish report)
    (call-with-output-file (file "dc-styles.json") (lambda (out) (write-json report out) (newline out)) #:exists 'replace))
  (with-handlers ([exn:fail? (lambda (e) (publish (hash-set* base 'status "failed" 'error (exn-message e))) (raise e))])
    (define pure-failures (run-tests dc-style-pure-tests))
    (define native-failures (run-tests dc-style-native-tests))
    (unless (= (+ pure-failures native-failures) 0) (error 'dc-style-doctor "style regression suite failed"))
    (define (render name draw)
      (define dc (new skia-dc% [width 64] [height 64] [smoothing 'unsmoothed]))
      (define image (dynamic-wind void (lambda () (draw dc) (send dc snapshot)) (lambda () (send dc close))))
      (sk:with-skia ([im image])
        (call-with-output-file (file name) (lambda (out) (write-bytes (sk:image->png-bytes im) out))
                               #:mode 'binary #:exists 'error)))
    (define-values (proc datum) (make-dc-recording style-oracle))
    (render "dc-style.direct.png" style-oracle)
    (render "dc-style.procedure.png" proc)
    (render "dc-style.datum.png" datum)
    (define bm (rd:make-bitmap 64 64 #t))
    (define dc (new rd:bitmap-dc% [bitmap bm]))
    (dynamic-wind void (lambda () (style-oracle dc)) (lambda () (send dc set-bitmap #f)))
    (unless (send bm save-file (file "dc-style.reference.png") 'png) (error 'dc-style-doctor "reference encoding failed"))
    (define gui? (with-handlers ([exn:fail? (lambda (_) #f)]) (module->namespace 'racket/gui/base) #t))
    (when gui? (error 'dc-style-doctor "unexpected GUI initialization"))
    (publish (hash-set* base 'status "passed" 'pure_cases dc-style-pure-test-count 'pure_failures pure-failures
                       'native_cases dc-style-native-test-count 'native_failures native-failures
                       'math_cases 45 'snapshots_encoded_after_dc_close #t
                       'captures '("dc-style.direct.png" "dc-style.procedure.png" "dc-style.datum.png" "dc-style.reference.png")))))

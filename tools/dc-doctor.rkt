#lang racket/base
(require racket/class racket/cmdline racket/file racket/path json rackunit/text-ui
         (prefix-in rd: racket/draw) (prefix-in sk: "../main.rkt") "../dc.rkt"
         (only-in "../private/native.rkt" skia-native-version native-package-version)
         "../tests/dc-pure-test.rkt" "../tests/dc-native-test.rkt"
         "../examples/dc-primitives.rkt" "../examples/dc-compatibility.rkt"
         "../tests/dc-compat-pure-test.rkt" "../tests/dc-compat-native-test.rkt")
(provide dc-doctor!)
(define (dc-doctor! directory)
  (define (file name) (build-path directory name))
  (define base
    (hasheq 'schema 1 'stage "0.54" 'storage "persistent-cpu-raster"
            'validation_run (path->string (file-name-from-path (simplify-path directory)))
            'os (symbol->string (system-type 'os)) 'architecture (symbol->string (system-type 'arch))
            'racket_version (version) 'gpu_execution_verified #f 'gui_initialized #f
            'full_drop_in_compatibility #f 'universal_pixel_identity_claimed #f))
  (define (publish data)
    (call-with-output-file (file "dc.diagnostic.json")
      (lambda (out) (write-json data out) (newline out)) #:exists 'replace))
  (with-handlers ([exn:fail? (lambda (e) (publish (hash-set* base 'status "failed" 'error (exn-message e))) (raise e))])
    (define pure-failures (run-tests dc-pure-tests))
    (define native-failures (run-tests dc-native-tests))
    (define compat-pure-failures (run-tests dc-compat-pure-tests))
    (define compat-native-failures (run-tests dc-compat-native-tests))
    (unless (= (+ pure-failures native-failures compat-pure-failures compat-native-failures) 0) (error 'dc-doctor "DC regression suite failed"))
    (define (render name width height scale draw)
      (define dc (new skia-dc% [width width] [height height] [backing-scale scale]))
      (define image
        (dynamic-wind void (lambda () (draw dc) (send dc snapshot)) (lambda () (send dc close))))
      ;; The encoder sees an independently retained image after DC destruction.
      (sk:with-skia ([im image])
        (call-with-output-file (file name)
          (lambda (out) (write-bytes (sk:image->png-bytes im) out)) #:mode 'binary #:exists 'error)))
    (render "dc-oracle.png" 24 20 2 draw-dc-oracle)
    (render "dc-compat-oracle.png" 64 48 1 draw-dc-compat-oracle)
    (render "dc-text.skia.png" 320 104 1 draw-dc-text-sample)
    (render "dc-primitives.skia.png" 460 320 1 draw-dc-primitives)
    (define bitmap (rd:make-bitmap 460 320 #t))
    (define reference (new rd:bitmap-dc% [bitmap bitmap]))
    (dynamic-wind void (lambda () (draw-dc-primitives reference)) (lambda () (send reference set-bitmap #f)))
    (unless (send bitmap save-file (file "dc-primitives.racket.png") 'png) (error 'dc-doctor "reference PNG encoding failed"))
    (define gui-loaded?
      (with-handlers ([exn:fail? (lambda (_) #f)])
        (module->namespace 'racket/gui/base)
        #t))
    (when gui-loaded? (error 'dc-doctor "raster validation unexpectedly initialized racket/gui/base"))
    (publish
     (hash-set* base 'status "passed" 'native_package native-package-version 'native_version (skia-native-version)
                'pure_cases dc-pure-test-count 'pure_failures pure-failures
                'native_cases dc-native-test-count 'native_failures native-failures
                'compat_pure_cases dc-compat-pure-test-count 'compat_pure_failures compat-pure-failures
                'compat_native_cases dc-compat-native-test-count 'compat_native_failures compat-native-failures
                'compat_oracle "dc-compat-oracle.png" 'text_sample "dc-text.skia.png"

                'snapshots_encoded_after_dc_close #t
                'oracle "dc-oracle.png" 'skia_demo "dc-primitives.skia.png" 'reference_demo "dc-primitives.racket.png"
                'demo_pixel_equivalence_verified #f))
    (displayln "DC native suites and post-close snapshots passed; inspect the actual PNGs next.")))
(module+ main
  (define directory #f)
  (command-line #:program "dc-doctor.rkt" #:once-each
                [("--directory") path "Fresh output directory" (set! directory (string->path path))]
                #:args () (void))
  (unless directory (error 'dc-doctor "--directory is required"))
  (dc-doctor! directory))

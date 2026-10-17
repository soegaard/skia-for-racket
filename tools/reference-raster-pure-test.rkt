#lang racket/base

;;;
;;; Reference Raster Pure Test
;;;

;; Checks format inventories, surface properties, output policies, and layer syntax without native
;; loading.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; No native allocations or calls are required by these checks.
(require rackunit racket/contract racket/list racket/vector
         skia/image-info skia/surface-properties skia/output-policy skia/native-capabilities
         skia/graphics
         (submod "reference-runtime.rkt" constant-contracts))


;;;
;;; Diagnostic Operations
;;;

; expand-layer : list? -> syntax?
;   Expands layer-scoping forms in a fresh module that imports only canvas primitives.
(define (expand-layer forms)
  (parameterize ([current-namespace (make-base-namespace)])
    (expand `(module layer-form racket/base
               (require skia/canvas-primitives)
               ,@forms))))

(module+ test

  ;;;
  ;;; Pixel Format and Surface Property Declarations
  ;;;

  (test-case "format inventories are immutable and complete"
    (check-true (immutable? integer-pixel-formats))
    (check-true (immutable? float-pixel-formats))
    (check-true (immutable? pixel-formats))
    (check-equal? (vector->list float-pixel-formats) '(rgba-f16 rgba-f32))
    (check-equal? (vector->list pixel-formats)
                  (append (vector->list integer-pixel-formats)
                          (vector->list float-pixel-formats))))

  (test-case "format inventory contracts require immutable symbol vectors"
    (define formats/c (and/c (vectorof symbol?) immutable?))
    (define spec (constant-shape '(and/c (vectorof symbol?) immutable?)))
    (check-equal? (hash-ref spec 'value_contract)
                  '("and/c" ("vectorof" "symbol?") "immutable?"))
    (for ([formats (in-list (list integer-pixel-formats float-pixel-formats pixel-formats))])
      (define checked (contract formats/c formats 'format-inventory 'reference-test))
      (check-true (constant-value-valid? spec 'skia/image-info formats))
      (check-equal? (vector->list checked) (vector->list formats))
      (for ([format (in-vector checked)])
        (check-pred symbol? format)))
    (check-false (constant-value-valid? spec 'skia/image-info (vector 'rgba-8888)))
    (check-false (constant-value-valid? spec 'skia/image-info (vector-immutable 8)))
    (check-true (constant-value-valid? (constant-shape 'list?) 'skia/output-policy '(pdf svg)))
    (check-true (constant-value-valid? (constant-shape 'string?) 'skia/native-capabilities "x"))
    (check-true (constant-value-valid? (constant-shape 'vector?) 'skia/image-info #(a b)))
    (check-exn exn:fail? (lambda () (constant-shape '(and/c number? positive?))))
    (check-exn exn:fail:contract?
               (lambda ()
                 (contract formats/c (vector 'rgba-8888) 'format-inventory 'reference-test)))
    (check-exn exn:fail:contract?
               (lambda ()
                 (vector-ref
                  (contract formats/c (vector-immutable 8) 'format-inventory 'reference-test)
                  0))))

  (test-case "storage description does not imply a drawing target"
    (define info (make-image-info 2 3 #:alpha-type 'unpremul))
    (check-false (image-info-supports? info 'raster-canvas))
    (define-values (stride minimum allocation)
      (image-info-storage-layout info #:row-bytes 12))
    (check-equal? (list stride minimum allocation) '(12 32 36)))

  (test-case "empty image information cannot imply nonempty storage"
    (define info (make-image-info 0 3))
    (define-values (stride minimum allocation) (image-info-storage-layout info))
    (check-equal? (list stride minimum allocation) '(0 0 0)))

  (test-case "surface properties are pure values with explicit masks"
    (define properties
      (make-surface-properties #:pixel-geometry 'bgr-v
                              #:device-independent-fonts? #t #:always-dither? #t))
    (check-equal? (surface-properties-flags properties) 5)
    (check-equal? (surface-properties-pixel-geometry properties) 'bgr-v)
    (check-true (surface-properties-device-independent-fonts? properties))
    (check-false (surface-properties-dynamic-msaa? properties))
    (check-true (surface-properties-always-dither? properties)))

  (test-case "surface property serialization preserves requests"
    (define info (surface-properties->jsexpr (make-surface-properties #:dynamic-msaa? #t)))
    (check-true (immutable? info))
    (check-equal? (hash-ref info 'pixel_geometry) "unknown")
    (check-equal? (hash-ref info 'flags) 2)
    (check-true (hash-ref info 'dynamic_msaa)))

  (test-case "invalid property choices do not require native preflight"
    (check-exn exn:fail:contract?
               (lambda () (make-surface-properties #:pixel-geometry 'rgb)))
    (check-exn exn:fail:contract?
               (lambda () (make-surface-properties #:always-dither? 1))))

  ;;;
  ;;; Output Policies and Capability Claims
  ;;;

  (test-case "output policies distinguish vector geometry and embedded samples"
    (check-equal? (output-capability-status (output-capability-for 'svg 'geometry)) 'vector)
    (check-equal? (output-capability-status (output-capability-for 'pdf 'image))
                  'embedded-raster)
    (check-equal? (output-capability-status (output-capability-for 'svg 'runtime-shader))
                  'needs-raster))

  (test-case "raster boundaries do not erase annotation loss or unknown provenance"
    (check-equal? (output-capability-status (output-capability-for 'raster 'annotation))
                  'discarded)
    (check-equal? (output-capability-status (output-capability-for 'raster 'unknown-resource))
                  'unknown)
    (check-equal? output-backends '(pdf svg raster)))

  (test-case "capability spelling errors are not interpreted as support"
    (check-exn exn:fail:contract?
               (lambda () (output-capability-for 'svg 'not-a-feature)))
    (check-exn exn:fail:contract?
               (lambda () (output-capability-for 'not-a-backend 'geometry)))
    (check-true (and (member 'image-atlas output-feature-names) #t)))

  (test-case "native catalogue reads are not library observations"
    (define catalogue (native-abi-catalog))
    (check-true (immutable? catalogue))
    (check-true (pair? (native-abi-profiles)))
    (check-true (immutable? native-package-version))
    (check-equal? (hash-ref catalogue 'schema) 1)
    (for ([profile (in-list (native-abi-profiles))])
      (check-true (immutable? profile))))

  (test-case "invalid cache and snapshot options fail before loading Skia"
    (check-exn exn:fail:contract? (lambda () (skia-set-font-cache-limit! -1)))
    (check-exn exn:fail:contract? (lambda () (skia-set-font-cache-count-limit! (expt 2 31))))
    (check-exn exn:fail? (lambda () (skia-memory-statistics #:max-entries 65537)))
    (check-exn exn:fail? (lambda () (skia-memory-statistics #:string-limit 65537))))

  ;;;
  ;;; Raster Layer Macro Expansion
  ;;;

  (test-case "all five documented layer option forms expand"
    (for ([options (in-list '(() (#:bounds '(0 0 4 4)) (#:paint #f)
                              (#:bounds '(0 0 4 4) #:paint #f)
                              (#:paint #f #:bounds '(0 0 4 4))))])
      (check-not-exn
       (lambda ()
         (expand-layer `((with-canvas-layer (error 'not-executed) ,@options
                           (define result 3)
                           (values result 4))))))))

  (test-case "duplicated layer options and an empty body fail expansion"
    (for ([body (in-list '((with-canvas-layer #f)
                          (with-canvas-layer #f #:paint #f #:paint #f (void))
                          (with-canvas-layer #f #:bounds #f #:bounds #f (void))))])
      (check-exn exn:fail:syntax? (lambda () (expand-layer (list body)))))))

#lang racket/base

;;;
;;; GPU Backend Registry
;;;

;; Loads immutable backend capabilities and validates backend identifiers.
;; Provides the common backend vocabulary used throughout GPU selection and diagnostics.

;; Source-only wrapper declarations. Loading this module does NOT resolve a
;; native symbol, load a platform DLL, create a context or initialize a GUI.
(require json racket/runtime-path racket/list)
(provide gpu-backends gpu-backend? gpu-backend-capabilities
         check-gpu-backend! gpu-backend-native-id)

;;;
;;; Pinned Backend Registry
;;;

; registry-file : path?
;   Locates the checked-in backend declaration catalog independently of the process working
;   directory.
(define-runtime-path registry-file "gpu-backends.json")

; freeze : hash? -> any
;   Recursively freezes registry strings and hashes so callers cannot mutate shared capability
;   declarations.
(define (freeze v)
  (cond [(hash? v) (for/hasheq ([(k x) (in-hash v)]) (values k (freeze x)))]
        [(list? v) (map freeze v)]
        [(string? v) (string->immutable-string v)]
        [else v]))

; registry : hash?
;   Loads and checks the three backend declaration rows without probing native availability.
(define registry
  (let* ([raw (call-with-input-file registry-file read-json)]
         [rows (and (hash? raw) (hash-ref raw 'backends #f))])
    (unless (and (hash? raw) (equal? (hash-ref raw 'schema #f) 1)
                 (list? rows) (= (length rows) 3)
                 (andmap hash? rows)
                 (equal? (map (lambda (r) (hash-ref r 'backend #f)) rows)
                         '("opengl" "metal" "direct3d")))
      (error 'gpu-backends "invalid wrapper registry"))
    (define ids (map (lambda (r) (hash-ref r 'native_backend #f)) rows))
    (unless (and (andmap exact-nonnegative-integer? ids)
                 (= (length ids) (length (remove-duplicates ids))))
      (error 'gpu-backends "invalid or duplicate native backend IDs"))
    (for/hasheq ([r (in-list rows)])
      (define features (hash-ref r 'features #f))
      (unless (and (equal? (hash-ref r 'engine #f) "ganesh")
                   (boolean? (hash-ref r 'owned_context 'missing))
                   (list? (hash-ref r 'platforms #f))
                   (andmap string? (hash-ref r 'platforms))
                   (string? (hash-ref r 'software_selection #f))
                   (hash? features)
                   (equal? (sort (hash-keys features) symbol<?)
                           (sort '(offscreen images explicit_transfers cache_controls
                                   presentation document_executor external_resource_interop)
                                     symbol<?))
                   (andmap boolean? (hash-values features)))
        (error 'gpu-backends "invalid wrapper capability row"))
      (values (string->symbol (hash-ref r 'backend)) (freeze r)))))

;;;
;;; Backend Selection and Capability Queries
;;;

; gpu-backends : -> (listof (or/c 'opengl 'metal 'direct3d))
;   Returns '(opengl metal direct3d), the backend names supported by the wrapper.
(define (gpu-backends) '(opengl metal direct3d))

; gpu-backend? : any/c -> boolean?
;   Returns #t for 'opengl, 'metal, or 'direct3d, and #f otherwise.
(define (gpu-backend? v) (and (symbol? v) (hash-has-key? registry v)))

; check-gpu-backend! : symbol? any/c -> gpu-backend?
;   Rejects backend names absent from the checked wrapper registry.
(define (check-gpu-backend! who v)
  (unless (gpu-backend? v)
    (raise-argument-error who "'opengl, 'metal, or 'direct3d" v))
  v)

; gpu-backend-native-id : any/c -> any
;   Looks up the pinned native backend enum after validating the public backend symbol.
(define (gpu-backend-native-id backend)
  (check-gpu-backend! 'gpu-backend-native-id backend)
  (hash-ref (hash-ref registry backend) 'native_backend))

; gpu-backend-capabilities : (or/c 'opengl 'metal 'direct3d) -> (and/c hash? immutable?)
;   Returns a detached declaration of the wrapper's support for backend.
(define (gpu-backend-capabilities backend)
  (check-gpu-backend! 'gpu-backend-capabilities backend)
  (hash-set* (hash-ref registry backend)
             'schema 1 'scope "wrapper-declarations"
             'native_probe_performed #f 'runtime_availability "not-probed"
             'hardware_acceleration_verified #f 'visible_pixels_verified #f
             'performance_measured #f))

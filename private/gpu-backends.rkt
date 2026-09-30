#lang racket/base
;; Source-only wrapper declarations. Loading this module does NOT resolve a
;; native symbol, load a platform DLL, create a context or initialize a GUI.
(require json racket/runtime-path racket/list)
(provide gpu-backends gpu-backend? gpu-backend-capabilities
         check-gpu-backend! gpu-backend-native-id)
(define-runtime-path registry-file "gpu-backends.json")
(define (freeze v)
  (cond [(hash? v) (for/hasheq ([(k x) (in-hash v)]) (values k (freeze x)))]
        [(list? v) (map freeze v)]
        [(string? v) (string->immutable-string v)]
        [else v]))
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
                                   presentation document_executor external_resource_interop) symbol<?))
                   (andmap boolean? (hash-values features)))
        (error 'gpu-backends "invalid wrapper capability row"))
      (values (string->symbol (hash-ref r 'backend)) (freeze r)))))
(define (gpu-backends) '(opengl metal direct3d))
(define (gpu-backend? v) (and (symbol? v) (hash-has-key? registry v)))
(define (check-gpu-backend! who v)
  (unless (gpu-backend? v)
    (raise-argument-error who "'opengl, 'metal, or 'direct3d" v))
  v)
(define (gpu-backend-native-id backend)
  (check-gpu-backend! 'gpu-backend-native-id backend)
  (hash-ref (hash-ref registry backend) 'native_backend))
(define (gpu-backend-capabilities backend)
  (check-gpu-backend! 'gpu-backend-capabilities backend)
  (hash-set* (hash-ref registry backend)
             'schema 1 'scope "wrapper-declarations"
             'native_probe_performed #f 'runtime_availability "not-probed"
             'hardware_acceleration_verified #f 'visible_pixels_verified #f
             'performance_measured #f))

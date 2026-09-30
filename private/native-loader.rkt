#lang racket/base
(require ffi/unsafe racket/promise racket/runtime-path racket/path
         "native-platform.rkt" "native-abi.rkt")
(provide native-package-version native-platform native-filename native-library
         native-library-report native-library-profile native-symbol-inventory)

(define-runtime-path native-root "../native")
(define (native-platform) (native-rid (system-type 'os) (system-type 'arch)))
(define (native-filename) (native-library-name 'skia (system-type 'os)))
(struct selection (library requested milestone increment profile) #:transparent)

;; One process-local selection is shared by every CPU and lazy GPU registry.
;; Only the two reviewed scalar bootstrap functions run before ABI selection.
(define selected-library
  (delay/sync
    (define override (getenv "RACKET_SKIA_LIBRARY"))
    (define platform (native-platform))
    (define candidates
      (cond [override (list (path->complete-path override))]
            [platform (list (build-path native-root platform (native-filename)) "libSkiaSharp")]
            [else (error 'skia "unsupported automatic library selection for ~a/~a; set RACKET_SKIA_LIBRARY"
                         (system-type 'os) (system-type 'arch))]))
    (define failures '())
    (define found
      (for/or ([candidate (in-list candidates)])
        (with-handlers ([exn:fail?
                         (lambda (e)
                           ;; Preserve a typed rejection for explicit candidates.
                           ;; Missing files/bootstrap symbols are NOT ABI rejection.
                           (when (and override (exn:fail:native-abi? e)) (raise e))
                           (set! failures (cons (exn-message e) failures))
                           #f)])
          (define library (ffi-lib candidate))
          (define milestone ((get-ffi-obj "sk_version_get_milestone" library (_fun -> _int))))
          (define increment ((get-ffi-obj "sk_version_get_increment" library (_fun -> _int))))
          (define profile (native-abi-require! milestone increment (ctype-sizeof _pointer)))
          (selection library candidate milestone increment profile))))
    (unless found
      (error 'skia
             (string-append "could not load a compatible libSkiaSharp\n"
                            "  run: bash tools/install-native.sh\n"
                            "  Windows x64: powershell -File tools/install-native-windows.ps1\n"
                            "  or set RACKET_SKIA_LIBRARY to the full library filename\n"
                            "  native package: ~a\n  loader errors: ~a")
             native-package-version (reverse failures)))
    found))

;; Preserve the private CPU registry's pair interface, without reopening a path.
(define native-library
  (delay/sync
    (define selected (force selected-library))
    (cons (selection-library selected) (selection-requested selected))))
(define (native-library-profile) (selection-profile (force selected-library)))
(define (native-library-report)
  (define selected (force selected-library))
  (define requested (selection-requested selected))
  (hasheq 'schema 1 'default_package_version native-package-version
          'library_request (if (path? requested) (path->string requested) requested)
          'milestone (selection-milestone selected) 'increment (selection-increment selected)
          'native_version (format "~a.~a" (selection-milestone selected) (selection-increment selected))
          'pointer_bytes (ctype-sizeof _pointer) 'profile (selection-profile selected)
          'package_identity_from_version_functions #f
          'optional_gpu_symbols_probed #f 'backend_creation_verified #f
          'hardware_acceleration_verified #f))

(define (native-symbol-inventory names)
  (unless (and (list? names) (andmap symbol? names))
    (raise-argument-error 'native-symbol-inventory "(listof symbol?)" names))
  (define library (selection-library (force selected-library)))
  (for/list ([name (in-list names)])
    ;; Resolve addresses only. Never invoke an optional entry point or infer
    ;; a backend implementation from a C stub being present.
    (hasheq 'name (symbol->string name)
            'available (and (get-ffi-obj name library _fpointer (lambda () #f)) #t))))

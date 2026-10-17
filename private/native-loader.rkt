#lang racket/base

;;;
;;; Native Library Selection
;;;

;; Resolves platform libraries and validates the selected Skia build.
;; Centralizes lazy native loading for the core and optional API modules.

(require ffi/unsafe racket/promise racket/runtime-path racket/path
         "native-platform.rkt" "native-abi.rkt")
(provide native-package-version native-platform native-filename native-library
         native-library-report native-library-profile native-symbol-inventory)

; native-root : path?
;   Locates platform libraries installed beside the package source.
(define-runtime-path native-root "../native")

; native-platform : -> (or/c #f string?)
;   Selects the bundled native runtime directory for this host OS and architecture.
(define (native-platform) (native-rid (system-type 'os) (system-type 'arch)))

; native-filename : -> string?
;   Returns the platform-specific SkiaSharp shared-library filename.
(define (native-filename) (native-library-name 'skia (system-type 'os)))
(struct selection (library requested milestone increment profile) #:transparent)
;; Fields:
;;   library: selected ffi-lib handle. requested: complete path or library-name string used for
;;   selection. milestone and increment: exact nonnegative values reported by native bootstrap
;;   functions. profile: immutable supported ABI profile matching version and host pointer width.
;;   Selection records keep the library reachable for lazy bindings; version numbers do not prove
;;   the package identity or availability of a working GPU backend.


;; One process-local selection is shared by every CPU and lazy GPU registry.
;; Only the two reviewed scalar bootstrap functions run before ABI selection.

; selected-library : promise?
;   Synchronizes one lazy library selection, preferring an explicit override and rejecting
;   unsupported ABI versions before use.
(define selected-library
  (delay/sync
    (define override (getenv "RACKET_SKIA_LIBRARY"))
    (define platform (native-platform))
    (define candidates
      (cond [override (list (path->complete-path override))]
            [platform (list (build-path native-root platform (native-filename)) "libSkiaSharp")]
            [else (error 'skia
                         "unsupported automatic library selection for ~a/~a; set RACKET_SKIA_LIBRARY"
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

; native-library : promise?
;   Exposes the selected library handle and original request as a lazy pair for native binding
;   modules.
(define native-library
  (delay/sync
    (define selected (force selected-library))
    (cons (selection-library selected) (selection-requested selected))))

; native-library-profile : -> hash?
;   Forces library selection and returns its validated ABI profile.
(define (native-library-profile) (selection-profile (force selected-library)))

; native-library-report : -> hash?
;   Reports selected library and ABI evidence without claiming package identity, optional GPU
;   capability, or hardware acceleration.
(define (native-library-report)
  (define selected (force selected-library))
  (define requested (selection-requested selected))
  (hasheq 'schema 1 'default_package_version native-package-version
          'library_request (if (path? requested) (path->string requested) requested)
          'milestone (selection-milestone selected) 'increment (selection-increment selected)
          'native_version (format "~a.~a" (selection-milestone selected)
                                  (selection-increment selected))
          'pointer_bytes (ctype-sizeof _pointer) 'profile (selection-profile selected)
          'package_identity_from_version_functions #f
          'optional_gpu_symbols_probed #f 'backend_creation_verified #f
          'hardware_acceleration_verified #f))

; native-symbol-inventory : (listof symbol?) -> (listof hash?)
;   Reports entry-point address availability without invoking optional symbols or treating stubs as
;   implemented backends.
(define (native-symbol-inventory names)
  (unless (and (list? names) (andmap symbol? names))
    (raise-argument-error 'native-symbol-inventory "(listof symbol?)" names))
  (define library (selection-library (force selected-library)))
  (for/list ([name (in-list names)])
    ;; Resolve addresses only. Never invoke an optional entry point or infer
    ;; a backend implementation from a C stub being present.
    (hasheq 'name (symbol->string name)
            'available (and (get-ffi-obj name library _fpointer (lambda () #f)) #t))))

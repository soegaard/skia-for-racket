#lang racket/base

;;;
;;; Native Library Selection
;;;

;; Resolves platform libraries and validates the selected Skia build.
;; Centralizes lazy native loading for the core and optional API modules.

(require ffi/unsafe racket/promise racket/runtime-path racket/path
         (only-in setup/dirs get-share-search-dirs)
         "native-platform.rkt" "native-abi.rkt" "native-package-paths.rkt" "native-fontconfig.rkt")
(provide native-package-version native-platform native-filename native-library
         native-library-report native-library-profile native-symbol-inventory)

;;;
;;; Platform Selection and Library Loading
;;;

; native-root : path?
;   Locates platform libraries installed beside the package source.
(define-runtime-path native-root "../native")

; native-platform : -> (or/c #f string?)
;   Selects the bundled native runtime directory for this host OS and architecture.
(define (native-platform) (native-rid (system-type 'os) (system-type 'arch)))

; native-filename : -> string?
;   Returns the platform-specific SkiaSharp shared-library filename.
(define (native-filename) (native-library-name 'skia (system-type 'os)))
(struct selection (library requested milestone increment profile request support) #:transparent)
(struct support-selection (library path configuration) #:transparent)

(define (configure-natipkg-fontconfig request)
  ;; Fontconfig reads the native process environment, including inside Scribble
  ;; evaluators whose Racket environment-variable objects are private copies.
  (define native-getenv (get-ffi-obj "getenv" #f (_fun _bytes -> _bytes)))
  (define native-setenv (get-ffi-obj "setenv" #f (_fun _bytes _bytes _int -> _int)))
  (define (preexisting value)
    (hasheq 'origin "native-environment" 'configuration_request (bytes->string/utf-8 value #\uFFFD)))
  (define existing (native-getenv #"FONTCONFIG_FILE\0"))
  (define existing-path (native-getenv #"FONTCONFIG_PATH\0"))
  (define existing-sysroot (native-getenv #"FONTCONFIG_SYSROOT\0"))
  (cond
    [existing (preexisting existing)]
    [(or existing-path existing-sysroot)
     (hasheq 'origin "native-environment" 'configuration_request #f
             'fontconfig_path (and existing-path (bytes->string/utf-8 existing-path #\uFFFD))
             'fontconfig_sysroot (and existing-sysroot (bytes->string/utf-8 existing-sysroot #\uFFFD)))]
    [else
     (define fonts
       (for/first ([directory (in-list (get-share-search-dirs))]
                   #:when (for/and ([name '("FreeSans.ttf" "FreeSerif.ttf" "FreeMono.ttf")])
                            (file-exists? (build-path directory "fonts" name))))
         (build-path directory "fonts")))
     (define prepared
       (prepare-managed-fontconfig (managed-fontconfig-template request)
                                   (if fonts (list fonts) '())
                                   (build-path (find-system-path 'addon-dir) "font-cache")))
     (define target (string->path (hash-ref prepared 'materialized_path)))
     (unless (zero? (native-setenv #"FONTCONFIG_FILE\0" (bytes-append (path->bytes target) #"\0") 0))
       (error 'skia "could not select managed natipkg fontconfig configuration: ~a" target))
     (define chosen (native-getenv #"FONTCONFIG_FILE\0"))
     (unless chosen (error 'skia "native fontconfig environment did not retain its configuration"))
     (if (bytes=? chosen (path->bytes target))
         (hash-set prepared 'configuration_request (path->string target))
         (preexisting chosen))]))
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
    (define request (native-library-request 'skia native-root))
    (define candidate (native-request-filename request))
    (with-handlers ([exn:fail?
                     (lambda (e)
                       (when (exn:fail:native-abi? e) (raise e))
                       (error 'skia
                              "could not load selected ~a library ~a (SkiaSharp ~a): ~a. Managed packages: reinstall the native dependency and run raco setup. Developer builds: tools/install-native.sh or RACKET_SKIA_LIBRARY"
                              (native-request-origin request) candidate native-package-version (exn-message e)))])
      (define support-path (managed-support-path request))
      (define support (and support-path (ffi-lib support-path)))
      (define configuration (and support (configure-natipkg-fontconfig request)))
      (define library (ffi-lib candidate))
      (define milestone ((get-ffi-obj "sk_version_get_milestone" library (_fun -> _int))))
      (define increment ((get-ffi-obj "sk_version_get_increment" library (_fun -> _int))))
      (define profile (native-abi-require! milestone increment (ctype-sizeof _pointer)))
      (selection library candidate milestone increment profile request
                 (and support (support-selection support support-path configuration))))))

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

;;;
;;; Detached Loader Diagnostics
;;;

; native-library-report : -> hash?
;   Reports selected library and ABI evidence without claiming package identity, optional GPU
;   capability, or hardware acceleration.
(define (native-library-report)
  (define selected (force selected-library))
  (define requested (selection-requested selected))
  (hasheq 'schema 1 'default_package_version native-package-version
          'loader (native-request-report (selection-request selected))
          'support_library (and (selection-support selected)
                                (path->string (support-selection-path (selection-support selected))))
          'support_library_sha256 (and (selection-support selected)
                                      (native-file-sha256 (support-selection-path (selection-support selected))))
          'fontconfig (and (selection-support selected)
                           (support-selection-configuration (selection-support selected)))
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

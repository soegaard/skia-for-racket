#lang racket/base

;; Lazy, paired discovery. No ffi-lib, font probing, GUI, context creation or
;; network operation is performed here. The first native use validates the
;; whole selected pair, so a partial user directory never borrows installation
;; files or falls through to a host library.
(require json racket/file racket/list racket/path racket/promise racket/string racket/port racket/runtime-path
         (only-in file/sha1 bytes->hex-string)
         (only-in setup/dirs get-lib-search-dirs)
         "native-platform.rkt" "native-pins.rkt")
(provide (struct-out managed-pair) (struct-out native-request)
         managed-package-name discover-managed-pair native-library-request
         native-request-report native-file-sha256 managed-support-path managed-fontconfig-template)

(struct managed-pair (directory manifest manifest-sha256 paths hashes) #:transparent)
(struct native-request (origin filename pair) #:transparent)
(define generation-directory "skia-native-1")
(define max-manifest (* 1024 1024))
(define-runtime-path this-module "native-package-paths.rkt")

(define (managed-package-name subpath)
  (cond [(regexp-match? #rx"^(aarch64|x86_64)-macosx$" subpath) "skia-native-macos-1"]
        [(equal? subpath "win32\\x86_64") "skia-native-win32-x86_64-1"]
        [(regexp-match? #rx"^x86_64-linux(-natipkg)?$" subpath) "skia-native-x86_64-linux-1"]
        [else #f]))

(define (native-file-sha256 path)
  (call-with-input-file path (lambda (in) (bytes->hex-string (sha256-bytes in)))))
(define (absolute path) (simplify-path (path->complete-path path)))
(define (bad directory format-string . args)
  (error 'skia-native-package
         "selected managed payload ~a is broken: ~a; reinstall its native dependency and run raco setup. No host-library fallback is permitted"
         directory (apply format format-string args)))

(define (discover-managed-pair directories
                               #:os [os (system-type 'os)]
                               #:subpath [subpath (path->string (system-library-subpath #f))])
  (define selected
    (for/first ([base (in-list directories)]
                #:when (let ([p (build-path base generation-directory)])
                         (or (directory-exists? p) (file-exists? p) (link-exists? p))))
      (absolute (build-path base generation-directory))))
  (and selected
       (let ()
         (define package (managed-package-name subpath))
         (unless package (bad selected "unqualified interpreter target ~a" subpath))
         (unless (and (eq? (system-type 'vm) 'chez-scheme) (= (system-type 'word) 64))
           (bad selected "automatic packages require a qualified 64-bit Racket CS interpreter"))
         (unless (and (directory-exists? selected) (not (link-exists? selected)))
           (bad selected "generation entry must be a real directory"))
         (define manifest-path (build-path selected "manifest.json"))
         (unless (and (file-exists? manifest-path) (not (link-exists? manifest-path))
                      (<= (file-size manifest-path) max-manifest))
           (bad selected "missing, linked or oversized manifest.json"))
         (define manifest
           (with-handlers ([exn:fail? (lambda (e) (bad selected "invalid manifest: ~a" (exn-message e)))])
             (call-with-input-file manifest-path
               (lambda (in)
                 (define value (read-json in))
                 (unless (regexp-match? #px"^\\s*$" (port->string in))
                   (error 'manifest "trailing data"))
                 value))))
         (unless (and (hash? manifest) (equal? (hash-ref manifest 'schema #f) 1)
                      (equal? (hash-ref manifest 'generation #f) 1)
                      (equal? (hash-ref manifest 'package #f) package)
                      (equal? (hash-ref manifest 'target #f)
                              (cond [(equal? os 'macosx) "macos"] [(equal? os 'windows) "win32"] [else "linux"]))
                      (equal? (hash-ref manifest 'upstream_versions #f)
                              (hasheq 'skia native-skia-version 'harfbuzz native-harfbuzz-version)))
           (bad selected "wrong generation, package or upstream asset pair"))
         (define files (hash-ref manifest 'files #f))
         (unless (and (hash? files) (= (hash-count files) 2))
           (bad selected "manifest must identify exactly both native libraries"))
         (define paths (make-hasheq))
         (define hashes (make-hasheq))
         (for ([kind '(skia harfbuzz)] [version (list native-skia-version native-harfbuzz-version)])
           (define record (hash-ref files kind #f))
           (define filename (native-library-name kind os))
           (define path (build-path selected filename))
           (unless (and (hash? record) (equal? (hash-ref record 'filename #f) filename)
                        (equal? (hash-ref record 'asset_version #f) version)
                        (exact-positive-integer? (hash-ref record 'size #f))
                        (string? (hash-ref record 'sha256 #f))
                        (regexp-match? #px"^[0-9a-f]{64}$" (hash-ref record 'sha256)))
             (bad selected "invalid ~a member record" kind))
           (unless (and (file-exists? path) (not (link-exists? path))
                        (= (file-size path) (hash-ref record 'size)))
             (bad selected "missing, linked or wrong-sized ~a" filename))
           (define digest (native-file-sha256 path))
           (unless (equal? digest (hash-ref record 'sha256))
             (bad selected "SHA-256 mismatch for ~a" filename))
           (hash-set! paths kind path)
           (hash-set! hashes kind digest))
         (when (equal? package "skia-native-x86_64-linux-1")
           (define config (hash-ref manifest 'support_configuration #f))
           (define folder (build-path selected "fontconfig"))
           (define path (build-path folder "fonts.conf.in"))
           (unless (and (hash? config) (equal? (hash-ref config 'filename #f) "fontconfig/fonts.conf.in")
                        (exact-positive-integer? (hash-ref config 'size #f))
                        (directory-exists? folder) (not (link-exists? folder))
                        (file-exists? path) (not (link-exists? path))
                        (<= (file-size path) (* 64 1024))
                        (equal? (file-size path) (hash-ref config 'size #f))
                        (equal? (native-file-sha256 path) (hash-ref config 'sha256 #f)))
             (bad selected "missing or corrupt support configuration template")))
         (managed-pair selected manifest (native-file-sha256 manifest-path)
                       (make-immutable-hasheq (hash->list paths))
                       (make-immutable-hasheq (hash->list hashes))))))

;; This promise is shared by both loaders and fixes one search-order selection
;; for the process. Hashing is deferred to first native use, never import.
(define installed-pair (delay/sync (discover-managed-pair (get-lib-search-dirs))))

(define (native-library-request kind native-root)
  (define override (getenv (if (eq? kind 'skia) "RACKET_SKIA_LIBRARY" "RACKET_HARFBUZZ_LIBRARY")))
  (cond
    [override (native-request 'override (absolute override) #f)]
    [(force installed-pair)
     => (lambda (pair) (native-request 'managed (hash-ref (managed-pair-paths pair) kind) pair))]
    [else
     (define subpath (path->string (system-library-subpath #f)))
     (define package (managed-package-name subpath))
     (when (and package
                (with-handlers ([exn:fail? (lambda (_) #f)]) (collection-path package)))
       (bad generation-directory "~a is installed but its managed generation is absent" package))
     (define rid (native-rid (system-type 'os) (system-type 'arch)))
     (unless rid
       (error 'skia-native-package "unsupported automatic selection for ~a; use explicit RACKET_SKIA_LIBRARY / RACKET_HARFBUZZ_LIBRARY" subpath))
     (define local (absolute (build-path native-root rid (native-library-name kind (system-type 'os)))))
     (if (file-exists? local)
         (native-request 'legacy local #f)
         (begin
           (unless package
             (error 'skia-native-package
                    "no qualified automatic native package for ~a; use the developer installer or explicit RACKET_SKIA_LIBRARY / RACKET_HARFBUZZ_LIBRARY"
                    subpath))
           ;; A registered 0.79 source package declares a native dependency.
           ;; Its absence is a broken install, not authority to use a host DLL.
           ;; Package ownership is queried lazily; cwd and .git are irrelevant.
           (when (and package ((dynamic-require 'pkg/path 'path->pkg) this-module))
             (bad generation-directory "declared dependency ~a is absent from this installed package environment" package))
           (native-request 'system (if (eq? kind 'skia) "libSkiaSharp" "libHarfBuzzSharp") #f)))]))

(define (managed-support-path request)
  ;; An absolute Skia dlopen does not search Racket's library directories for
  ;; DT_NEEDED. The native Linux dependency declares draw's natipkg package;
  ;; preload its fontconfig once and retain the FFI handle in the Skia loader.
  (and (eq? (native-request-origin request) 'managed)
       (regexp-match? #rx"^x86_64-linux-natipkg$" (path->string (system-library-subpath #f)))
       (or (for/first ([directory (in-list (get-lib-search-dirs))]
                       #:when (file-exists? (build-path directory "libfontconfig.so.1")))
             (absolute (build-path directory "libfontconfig.so.1")))
           (error 'skia-native-package "declared natipkg support library libfontconfig.so.1 is absent from Racket's library directories"))))

(define (managed-fontconfig-template request)
  (define pair (native-request-pair request))
  (unless pair (error 'skia-native-package "fontconfig template requires a selected managed pair"))
  (build-path (managed-pair-directory pair) "fontconfig" "fonts.conf.in"))

(define (native-request-report request)
  (define pair (native-request-pair request))
  (define filename (native-request-filename request))
  (hasheq 'origin (symbol->string (native-request-origin request))
          'library_request (if (path? filename) (path->string filename) filename)
          'absolute_path (and (path? filename) (path->string filename))
          'native_generation (and pair 1)
          'managed_directory (and pair (path->string (managed-pair-directory pair)))
          'manifest_sha256 (and pair (managed-pair-manifest-sha256 pair))
          'manifest (and pair (managed-pair-manifest pair))))

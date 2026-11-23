#lang racket/base

(require rackunit racket/file racket/path racket/runtime-path syntax/modread json
         setup/getinfo setup/matching-platform
         "../private/native-package-paths.rkt" "../private/native-pins.rkt"
         "../private/native-fontconfig.rkt")

; collection-root : path?
;   Locates the metadata and tutorial catalogue without relying on the process directory.
(define-runtime-path collection-root "..")

(define (write-manifest directory [edit values] #:windows? [windows? #f]
                        #:upstream? [upstream? windows?])
  (make-directory* directory)
  (define files
    (for/hasheq ([kind '(skia harfbuzz)]
                [name (if windows? '("libSkiaSharp.dll" "libHarfBuzzSharp.dll")
                          '("libSkiaSharp.dylib" "libHarfBuzzSharp.dylib"))]
                [version (list native-skia-version native-harfbuzz-version)])
      (define path (build-path directory name))
      (call-with-output-file path #:exists 'truncate (lambda (out) (write-bytes #"fixture" out)))
      (values kind (hasheq 'filename name 'asset_version version 'size 7 'sha256 (native-file-sha256 path)))))
  (call-with-output-file (build-path directory "manifest.json") #:exists 'truncate
    (lambda (out)
      (write-json (edit (hasheq 'schema 1 'generation 1
                               'package (if windows?
                                            (if upstream? "skia-upstream-win32-x86_64-1"
                                                "skia-native-win32-x86_64-1")
                                            "skia-native-macos-1")
                               'target (if windows? "win32" "macos")
                               'acquisition (hasheq 'route "direct-nuget") 'upstream_versions
                               (hasheq 'skia native-skia-version 'harfbuzz native-harfbuzz-version)
                               'files files)) out))))

(module+ test
  (define root (make-temporary-file "skia pair ~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define user (build-path root "user with spaces æ"))
      (define installation (build-path root "installation"))
      (define user-pair (build-path user "skia-native-1"))
      (define install-pair (build-path installation "skia-native-1"))
      (define (discover) (discover-managed-pair (list user installation) #:os 'macosx #:subpath "aarch64-macosx"))
      (test-case "no managed payload is a pure absent result"
        (check-false (discover)))
      (write-manifest install-pair)
      (test-case "installation directory selected with both members"
        (define pair (discover))
        (check-equal? (managed-pair-directory pair) install-pair)
        (check-equal? (hash-count (managed-pair-paths pair)) 2))
      (write-manifest user-pair)
      (test-case "user generation shadows the complete installation pair"
        (check-equal? (managed-pair-directory (discover)) user-pair))
      (test-case "partial user pair cannot borrow installation HarfBuzz"
        (delete-file (build-path user-pair "libHarfBuzzSharp.dylib"))
        (check-exn #rx"selected managed payload.*broken" discover))
      (write-manifest user-pair)
      (test-case "corrupt member cannot fall back to installation or host"
        (call-with-output-file (build-path user-pair "libSkiaSharp.dylib") #:exists 'truncate
          (lambda (out) (write-bytes #"changed" out)))
        (check-exn #rx"SHA-256 mismatch" discover))
      (write-manifest user-pair (lambda (m) (hash-set m 'upstream_versions (hasheq 'skia "0.0.0" 'harfbuzz native-harfbuzz-version))))
      (test-case "asset pair identity is enforced"
        (check-exn #rx"upstream asset pair" discover))
      (write-manifest user-pair (lambda (m) (hash-set m 'generation 2)))
      (test-case "wrong generation is enforced"
        (check-exn #rx"wrong generation" discover))
      (write-manifest user-pair)
      (test-case "missing manifest is selected broken data"
        (delete-file (build-path user-pair "manifest.json"))
        (check-exn #rx"missing.*manifest" discover))
      (write-manifest user-pair)
      (test-case "an unqualified target cannot use a managed payload"
        (check-exn #rx"unqualified interpreter target"
                   (lambda () (discover-managed-pair (list user) #:subpath "aarch64-linux"))))
      (test-case "bare system requests are never labelled absolute paths"
        (check-false (hash-ref (native-request-report (native-request 'system "libSkiaSharp" #f)) 'absolute_path)))
      (define windows-user (build-path user "skia-upstream-1"))
      (define windows-installation (build-path installation "skia-upstream-1"))
      (define (windows-discover)
        (discover-managed-pair (list user installation) #:os 'windows #:subpath "win32\\x86_64"
                               #:directory-name "skia-upstream-1" #:upstream-download? #t))
      (test-case "Windows x86-64 selects its automatic native dependency"
        (check-equal? (managed-package-name "win32\\x86_64") "skia-native-win32-x86_64-1")
        (check-false (managed-package-name "win32\\aarch64"))
        (check-false (windows-discover)))
      (test-case "Windows metadata selects only the qualified x86-64 target"
        (define info (get-info/full collection-root))
        (define dependency
          (for/first ([row (in-list (info 'deps))]
                      #:when (and (pair? row) (equal? (car row) "skia-native-win32-x86_64-1")))
            row))
        (check-not-false dependency)
        (define selector (cadr (memq '#:platform dependency)))
        (for ([row '((windows "win32\\x86_64" #t) (windows "win32\\aarch64" #f)
                     (windows "win32\\i386" #f) (macosx "aarch64-macosx" #f)
                     (unix "x86_64-linux" #f))])
          (check-equal? (matching-platform? selector #:system-type (car row)
                                           #:system-library-subpath (string->path (cadr row)))
                        (caddr row))))
      (write-manifest windows-installation #:windows? #t)
      (test-case "Windows selects an explicitly installed upstream pair"
        (define pair (windows-discover))
        (check-equal? (managed-pair-directory pair) windows-installation)
        (define report (native-request-report
                        (native-request 'upstream-download
                                        (hash-ref (managed-pair-paths pair) 'skia) pair)))
        (check-equal? (hash-ref report 'origin) "upstream-download")
        (check-false (hash-ref report 'managed_directory))
        (check-equal? (hash-ref report 'download_directory) (path->string windows-installation)))
      (write-manifest windows-user #:windows? #t)
      (test-case "Windows partial user data cannot borrow the installation pair"
        (delete-file (build-path windows-user "libHarfBuzzSharp.dll"))
        (check-exn #rx"selected upstream payload.*broken" windows-discover))
      (write-manifest windows-user (lambda (m) (hash-remove m 'acquisition)) #:windows? #t)
      (test-case "Windows requires direct acquisition provenance"
        (check-exn #rx"NuGet acquisition provenance" windows-discover))
      (define windows-root (build-path root "Windows managed selection"))
      (define managed-windows (build-path windows-root "skia-native-1"))
      (define upstream-windows (build-path windows-root "skia-upstream-1"))
      (define (windows-select [installed? #f])
        (discover-installed-pair (list windows-root) #:os 'windows #:subpath "win32\\x86_64"
                                 #:managed-installed? installed?))
      (write-manifest upstream-windows #:windows? #t)
      (write-manifest managed-windows #:windows? #t #:upstream? #f)
      (test-case "Windows managed payload takes precedence over the optional installer"
        (check-equal? (managed-pair-directory (windows-select)) managed-windows))
      (test-case "a selected broken Windows managed pair cannot use the upstream cache"
        (delete-file (build-path managed-windows "libHarfBuzzSharp.dll"))
        (check-exn #rx"selected managed payload.*broken" windows-select))
      (delete-directory/files managed-windows)
      (test-case "an installed Windows native package cannot hide missing data with the upstream cache"
        (check-exn #rx"installed but its managed generation is absent"
                   (lambda () (windows-select #t))))
      (test-case "an unregistered Windows checkout retains its optional installer route"
        (check-equal? (managed-pair-directory (windows-select)) upstream-windows))
      (test-case "natipkg configuration is escaped content-addressed derived data"
        (define fonts (build-path root "fonts & æ"))
        (make-directory fonts)
        (for ([name '("FreeSans.ttf" "FreeSerif.ttf" "FreeMono.ttf")])
          (call-with-output-file (build-path fonts name) (lambda (out) (write-bytes #"fixture" out))))
        (define template (build-path root "fonts.conf.in"))
        (call-with-output-file template
          (lambda (out) (display "<fontconfig>@FONT_DIRECTORIES@<cachedir>@CACHE_DIRECTORY@</cachedir></fontconfig>" out)))
        (define cache (build-path root "cache & æ"))
        (define (prepare) (prepare-managed-fontconfig template (list fonts) cache))
        (define first (prepare))
        (define configured (string->path (hash-ref first 'materialized_path)))
        (check-equal? (hash-ref first 'origin) "managed-cache")
        (check-equal? (hash-ref first 'materialized_sha256) (native-file-sha256 configured))
        (check-true (regexp-match? #rx"&amp;" (file->string configured)))
        (check-false (regexp-match? #rx"@FONT_" (file->string configured)))
        (check-equal? (prepare) first)
        (call-with-output-file configured #:exists 'truncate (lambda (out) (display "corrupt cache" out)))
        (check-equal? (prepare) first)
        (check-equal? (native-file-sha256 configured) (hash-ref first 'materialized_sha256))
        (delete-file (build-path fonts "FreeSans.ttf"))
        (check-exn #rx"draw-ttf data is incomplete" prepare)))
    (lambda () (delete-directory/files root))))

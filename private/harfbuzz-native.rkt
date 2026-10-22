#lang racket/base

;;;
;;; Native HarfBuzz Bindings
;;;

;; Loads shaping and Unicode-query entry points lazily.
;; Supplies native text shaping used by Skia text runs and layout.

(require ffi/unsafe
         racket/list
         racket/promise
         racket/runtime-path
         racket/path
         (only-in setup/dirs get-lib-search-dirs)
         "native-platform.rkt"
         "harfbuzz-types.rkt")
(provide harfbuzz-package-version harfbuzz-platform harfbuzz-filename
         harfbuzz-check! harfbuzz-available? harfbuzz-native-version
         harfbuzz-native-library-path)

;;;
;;; Platform Selection and Isolated Loading
;;;

; harfbuzz-package-version : string?
;   Pins the HarfBuzzSharp package whose embedded HarfBuzz version and ABI this binding expects.
(define harfbuzz-package-version "8.3.1.2")

; native-root : path?
;   Locates bundled platform-native libraries relative to this module rather than the process
;   working directory.
(define-runtime-path native-root "../native")

; harfbuzz-platform : -> (or/c #f string?)
;   Maps the interpreter's operating system and architecture to the supported native package
;   identifier.
(define (harfbuzz-platform)
  (native-rid (system-type 'os) (system-type 'arch)))

; harfbuzz-filename : -> string?
;   Chooses the HarfBuzzSharp shared-library filename for the interpreter's operating system.
(define (harfbuzz-filename)
  (native-library-name 'harfbuzz (system-type 'os)))

; linux-loader : promise?
;   Lazily resolves dlopen, dlclose, and dlerror in that order for isolated Linux HarfBuzz loading.
(define linux-loader
  (delay/sync
    (vector (get-ffi-obj 'dlopen #f (_fun _path _int -> _pointer))
            (get-ffi-obj 'dlclose #f (_fun _pointer -> _int))
            (get-ffi-obj 'dlerror #f (_fun -> _string/utf-8)))))

; linux-library-candidates : any/c -> list?
;   Preserves versionless FFI search order across Racket library directories, loader names, and
;   absolute current-directory paths.
(define (linux-library-candidates candidate)
  ;; Preserve ffi-lib's default, versionless search: configured Racket library
  ;; directories, OS loader search, then the current directory. Explicit
  ;; overrides and the bundled candidate are already absolute paths.
  (define original (path->string (cleanse-path candidate)))
  (define names
    (remove-duplicates
     (list (if (regexp-match? #rx"[.]so$" original) original
               (string-append original ".so"))
           original)))
  (remove-duplicates
   (append
    (if (absolute-path? candidate) '()
        (for*/list ([directory (in-list (get-lib-search-dirs))]
                    [name (in-list names)])
          (path->string (build-path directory name))))
    names
    (for/list ([name (in-list names)])
      (path->string (path->complete-path name))))))

; load-harfbuzz-library : path-string? -> ffi-lib?
;   Loads HarfBuzz locally and, on Linux, uses deep binding to prevent incompatible GTK/Pango
;   symbol interposition.
(define (load-harfbuzz-library candidate)
  (cond
    [(eq? (system-type 'os*) 'linux)
     ;; GTK/Pango may already have loaded another HarfBuzz globally. Linux
     ;; loader traces show this binary's internal hb_* relocations otherwise
     ;; resolving to that copy while get-ffi-obj resolves to this one, mixing
     ;; incompatible objects. Local visibility alone does not prevent that
     ;; interposition: DEEPBIND keeps internal calls within this ABI.
     ;; Keep the resulting library local so the reverse load order cannot
     ;; redirect GTK/Pango into HarfBuzzSharp either.
     (define loader (force linux-loader))
     (define open-library (vector-ref loader 0))
     (define close-library (vector-ref loader 1))
     (define loader-error (vector-ref loader 2))
     (define failures '())
     (or
      (for/or ([filename (in-list (linux-library-candidates candidate))])
        (parameterize-break #f
          (call-with-continuation-barrier
           (lambda ()
             ;; Linux RTLD_NOW=2, RTLD_DEEPBIND=8, RTLD_LOCAL=0.
             (define temporary (open-library filename #xA))
             (cond
               [temporary
                (dynamic-wind
                 void
                 (lambda ()
                   ;; Acquire Racket's independently retained library
                   ;; reference to exactly the name successfully opened.
                   (ffi-lib filename '() #:get-lib-dirs (lambda () '()) #:global? #f))
                 (lambda ()
                   (unless (zero? (close-library temporary))
                     (error 'harfbuzz "could not release temporary loader reference for ~a: ~a"
                            filename (or (loader-error) "unknown dlclose error")))))]
               [else
                (set! failures
                  (cons (format "~a: ~a" filename (or (loader-error) "unknown dlopen error"))
                    failures))
                #f])))))
      ;; Never retry without isolation after a Linux loader failure.
      (error 'harfbuzz "could not load isolated HarfBuzzSharp: ~a" (reverse failures)))]
    [else (ffi-lib candidate #:global? #f)]))

; hb-library : promise?
;   Selects an override, bundled, or system HarfBuzzSharp library and requires native HarfBuzz
;   version 8.3.1.
(define hb-library
  (delay/sync
    (define override (getenv "RACKET_HARFBUZZ_LIBRARY"))
    (define platform (harfbuzz-platform))
    (define candidates
      (cond
        [override (list (path->complete-path override))]
        [platform
         (list (build-path native-root platform (harfbuzz-filename))
               "libHarfBuzzSharp")]
        [else
         (error 'harfbuzz
                "unsupported automatic library selection for ~a/~a; set RACKET_HARFBUZZ_LIBRARY"
                (system-type 'os) (system-type 'arch))]))
    (define failures '())
    (define found
      (for/or ([candidate (in-list candidates)])
        (with-handlers ([exn:fail?
                         (lambda (e)
                           (set! failures (cons (exn-message e) failures))
                           #f)])
          (define lib (load-harfbuzz-library candidate))
          (define version-fn
            (get-ffi-obj "hb_version" lib
                         (_fun _pointer _pointer _pointer -> _void)))
          (define major (malloc _uint32 'atomic))
          (define minor (malloc _uint32 'atomic))
          (define micro (malloc _uint32 'atomic))
          (version-fn major minor micro)
          (define got (list (ptr-ref major _uint32)
                            (ptr-ref minor _uint32)
                            (ptr-ref micro _uint32)))
          (unless (equal? got '(8 3 1))
            (error 'harfbuzz
                   "incompatible native HarfBuzz ~a.~a.~a; this binding requires 8.3.1 (HarfBuzzSharp ~a)"
                   (car got) (cadr got) (caddr got) harfbuzz-package-version))
          (cons lib candidate))))
    (unless found
      (error 'harfbuzz
             (string-append
              "could not load compatible libHarfBuzzSharp\n"
              "  run: bash tools/install-harfbuzz.sh\n"
              "  Windows x64: powershell -File tools/install-native-windows.ps1\n"
              "  Windows: check interpreter/DLL architecture and dependent DLLs; see docs/GPU-TESTING.md\n"
              "  or set RACKET_HARFBUZZ_LIBRARY to the full library filename\n"
              "  native package: ~a\n  loader errors: ~a")
             harfbuzz-package-version (reverse failures)))
    found))

;;;
;;; Lazy HarfBuzz Registry and Shaping Bindings
;;;

; hb-bindings : list?
;   Accumulates named shaping-symbol promises in reverse declaration order for a later complete
;   readiness check.
(define hb-bindings '())

; define-hb-native : syntax transformer
;   Declares a lazily resolved native procedure and registers its symbol for readiness and
;   inventory checks.
(define-syntax-rule (define-hb-native name signature)
  (begin
    (provide name)
    (define delayed-procedure
      (delay/sync
        (get-ffi-obj 'name (car (force hb-library)) signature)))
    (set! hb-bindings (cons (cons 'name delayed-procedure) hb-bindings))
    (define (name . args) (apply (force delayed-procedure) args))))

; hb_version : (_fun _pointer _pointer _pointer -> _void) (FFI)
;   Calls the native hb_version entry point using the declared FFI layout.
(define-hb-native hb_version (_fun _pointer _pointer _pointer -> _void))

; hb_blob_create : (_fun _bytes _uint32 _int _pointer _pointer -> _pointer) (FFI)
;   Calls the native hb_blob_create entry point using the declared FFI layout.
(define-hb-native hb_blob_create
  (_fun _bytes _uint32 _int _pointer _pointer -> _pointer))

; hb_blob_destroy : (_fun _pointer -> _void) (FFI)
;   Calls the native hb_blob_destroy entry point using the declared FFI layout.
(define-hb-native hb_blob_destroy (_fun _pointer -> _void))

; hb_face_create : (_fun _pointer _uint32 -> _pointer) (FFI)
;   Calls the native hb_face_create entry point using the declared FFI layout.
(define-hb-native hb_face_create (_fun _pointer _uint32 -> _pointer))

; hb_face_destroy : (_fun _pointer -> _void) (FFI)
;   Calls the native hb_face_destroy entry point using the declared FFI layout.
(define-hb-native hb_face_destroy (_fun _pointer -> _void))

; hb_face_set_upem : (_fun _pointer _uint32 -> _void) (FFI)
;   Calls the native hb_face_set_upem entry point using the declared FFI layout.
(define-hb-native hb_face_set_upem (_fun _pointer _uint32 -> _void))

; hb_font_create : (_fun _pointer -> _pointer) (FFI)
;   Calls the native hb_font_create entry point using the declared FFI layout.
(define-hb-native hb_font_create (_fun _pointer -> _pointer))

; hb_font_destroy : (_fun _pointer -> _void) (FFI)
;   Calls the native hb_font_destroy entry point using the declared FFI layout.
(define-hb-native hb_font_destroy (_fun _pointer -> _void))

; hb_font_set_scale : (_fun _pointer _int _int -> _void) (FFI)
;   Calls the native hb_font_set_scale entry point using the declared FFI layout.
(define-hb-native hb_font_set_scale (_fun _pointer _int _int -> _void))

; hb_ot_font_set_funcs : (_fun _pointer -> _void) (FFI)
;   Calls the native hb_ot_font_set_funcs entry point using the declared FFI layout.
(define-hb-native hb_ot_font_set_funcs (_fun _pointer -> _void))

; hb_buffer_create : (_fun -> _pointer) (FFI)
;   Calls the native hb_buffer_create entry point using the declared FFI layout.
(define-hb-native hb_buffer_create (_fun -> _pointer))

; hb_buffer_destroy : (_fun _pointer -> _void) (FFI)
;   Calls the native hb_buffer_destroy entry point using the declared FFI layout.
(define-hb-native hb_buffer_destroy (_fun _pointer -> _void))

; hb_buffer_add_utf8 : (_fun _pointer _bytes _int _uint32 _int -> _void) (FFI)
;   Calls the native hb_buffer_add_utf8 entry point using the declared FFI layout.
(define-hb-native hb_buffer_add_utf8
  (_fun _pointer _bytes _int _uint32 _int -> _void))

; hb_buffer_guess_segment_properties : (_fun _pointer -> _void) (FFI)
;   Calls the native hb_buffer_guess_segment_properties entry point using the declared FFI layout.
(define-hb-native hb_buffer_guess_segment_properties (_fun _pointer -> _void))

; hb_buffer_get_direction : (_fun _pointer -> _int) (FFI)
;   Reads the direction resolved for a shaped buffer.
(define-hb-native hb_buffer_get_direction (_fun _pointer -> _int))

; hb_buffer_set_direction : (_fun _pointer _int -> _void) (FFI)
;   Calls the native hb_buffer_set_direction entry point using the declared FFI layout.
(define-hb-native hb_buffer_set_direction (_fun _pointer _int -> _void))

; hb_buffer_set_script : (_fun _pointer _uint32 -> _void) (FFI)
;   Calls the native hb_buffer_set_script entry point using the declared FFI layout.
(define-hb-native hb_buffer_set_script (_fun _pointer _uint32 -> _void))

; hb_buffer_set_language : (_fun _pointer _pointer -> _void) (FFI)
;   Calls the native hb_buffer_set_language entry point using the declared FFI layout.
(define-hb-native hb_buffer_set_language (_fun _pointer _pointer -> _void))

; hb_buffer_get_length : (_fun _pointer -> _uint32) (FFI)
;   Calls the native hb_buffer_get_length entry point using the declared FFI layout.
(define-hb-native hb_buffer_get_length (_fun _pointer -> _uint32))

; hb_buffer_get_glyph_infos : (_fun _pointer _pointer -> _pointer) (FFI)
;   Calls the native hb_buffer_get_glyph_infos entry point using the declared FFI layout.
(define-hb-native hb_buffer_get_glyph_infos (_fun _pointer _pointer -> _pointer))

; hb_buffer_get_glyph_positions : (_fun _pointer _pointer -> _pointer) (FFI)
;   Calls the native hb_buffer_get_glyph_positions entry point using the declared FFI layout.
(define-hb-native hb_buffer_get_glyph_positions (_fun _pointer _pointer -> _pointer))

; hb_direction_from_string : (_fun _bytes _int -> _int) (FFI)
;   Calls the native hb_direction_from_string entry point using the declared FFI layout.
(define-hb-native hb_direction_from_string (_fun _bytes _int -> _int))

; hb_script_from_string : (_fun _bytes _int -> _uint32) (FFI)
;   Calls the native hb_script_from_string entry point using the declared FFI layout.
(define-hb-native hb_script_from_string (_fun _bytes _int -> _uint32))

; hb_language_from_string : (_fun _bytes _int -> _pointer) (FFI)
;   Calls the native hb_language_from_string entry point using the declared FFI layout.
(define-hb-native hb_language_from_string (_fun _bytes _int -> _pointer))

; hb_feature_from_string : (_fun _bytes _int _pointer -> _stdbool) (FFI)
;   Calls the native hb_feature_from_string entry point using the declared FFI layout.
(define-hb-native hb_feature_from_string (_fun _bytes _int _pointer -> _stdbool))
;; Borrowed default Unicode property provider; do not destroy it.

; hb_unicode_funcs_get_default : (_fun -> _pointer) (FFI)
;   Calls the native hb_unicode_funcs_get_default entry point using the declared FFI layout.
(define-hb-native hb_unicode_funcs_get_default (_fun -> _pointer))

; hb_unicode_script : (_fun _pointer _uint32 -> _uint32) (FFI)
;   Calls the native hb_unicode_script entry point using the declared FFI layout.
(define-hb-native hb_unicode_script (_fun _pointer _uint32 -> _uint32))

; hb_shape : (_fun _pointer _pointer _pointer _uint32 -> _void) (FFI)
;   Calls the native hb_shape entry point using the declared FFI layout.
(define-hb-native hb_shape (_fun _pointer _pointer _pointer _uint32 -> _void))

;;;
;;; Readiness and Library Diagnostics
;;;

; hb-ready : promise?
;   Memoizes successful library/version validation and resolution of every required shaping entry
;   point.
(define hb-ready
  (delay/sync
    (force hb-library)
    (for ([entry (in-list (reverse hb-bindings))])
      (force (cdr entry)))
    #t))

; harfbuzz-check! : -> void?
;   Loads the selected HarfBuzz library, verifies its native version, and resolves the required
;   shaping entry points.
(define (harfbuzz-check!) (force hb-ready) (void))

; harfbuzz-available? : -> boolean?
;   Reports whether library selection, version checks, and required shaping-symbol resolution
;   succeed.
(define (harfbuzz-available?)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (harfbuzz-check!) #t))

; harfbuzz-native-version : -> string?
;   Returns the loaded native HarfBuzz version as a dotted major/minor/micro string after
;   preflight, not the package version.
(define (harfbuzz-native-version)
  (harfbuzz-check!)
  (define major (malloc _uint32 'atomic))
  (define minor (malloc _uint32 'atomic))
  (define micro (malloc _uint32 'atomic))
  (hb_version major minor micro)
  (format "~a.~a.~a" (ptr-ref major _uint32)
          (ptr-ref minor _uint32) (ptr-ref micro _uint32)))

; harfbuzz-native-library-path : -> path-string?
;   Returns the selected HarfBuzz library request after preflight.
(define (harfbuzz-native-library-path)
  (harfbuzz-check!)
  (cdr (force hb-library)))

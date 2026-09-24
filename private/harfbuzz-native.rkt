#lang racket/base
(require ffi/unsafe
         racket/promise
         racket/runtime-path
         racket/path
         "harfbuzz-types.rkt")
(provide harfbuzz-package-version harfbuzz-platform harfbuzz-filename
         harfbuzz-check! harfbuzz-available? harfbuzz-native-version
         harfbuzz-native-library-path)

(define harfbuzz-package-version "8.3.1.2")
(define-runtime-path native-root "../native")

(define (harfbuzz-platform)
  (case (system-type 'os)
    [(macosx) "osx"]
    [(unix)
     (case (system-type 'arch)
       [(x86_64) "linux-x64"]
       [(aarch64) "linux-arm64"]
       [else #f])]
    [else #f]))

(define (harfbuzz-filename)
  (if (eq? (system-type 'os) 'macosx)
      "libHarfBuzzSharp.dylib"
      "libHarfBuzzSharp.so"))

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
          (define lib (ffi-lib candidate))
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
              "  or set RACKET_HARFBUZZ_LIBRARY to the full library filename\n"
              "  native package: ~a\n  loader errors: ~a")
             harfbuzz-package-version (reverse failures)))
    found))

(define hb-bindings '())
(define-syntax-rule (define-hb-native name signature)
  (begin
    (provide name)
    (define delayed-procedure
      (delay/sync
        (get-ffi-obj 'name (car (force hb-library)) signature)))
    (set! hb-bindings (cons (cons 'name delayed-procedure) hb-bindings))
    (define (name . args) (apply (force delayed-procedure) args))))

(define-hb-native hb_version (_fun _pointer _pointer _pointer -> _void))
(define-hb-native hb_blob_create
  (_fun _bytes _uint32 _int _pointer _pointer -> _pointer))
(define-hb-native hb_blob_destroy (_fun _pointer -> _void))
(define-hb-native hb_face_create (_fun _pointer _uint32 -> _pointer))
(define-hb-native hb_face_destroy (_fun _pointer -> _void))
(define-hb-native hb_face_set_upem (_fun _pointer _uint32 -> _void))
(define-hb-native hb_font_create (_fun _pointer -> _pointer))
(define-hb-native hb_font_destroy (_fun _pointer -> _void))
(define-hb-native hb_font_set_scale (_fun _pointer _int _int -> _void))
(define-hb-native hb_ot_font_set_funcs (_fun _pointer -> _void))
(define-hb-native hb_buffer_create (_fun -> _pointer))
(define-hb-native hb_buffer_destroy (_fun _pointer -> _void))
(define-hb-native hb_buffer_add_utf8
  (_fun _pointer _bytes _int _uint32 _int -> _void))
(define-hb-native hb_buffer_guess_segment_properties (_fun _pointer -> _void))
(define-hb-native hb_buffer_set_direction (_fun _pointer _int -> _void))
(define-hb-native hb_buffer_set_script (_fun _pointer _uint32 -> _void))
(define-hb-native hb_buffer_set_language (_fun _pointer _pointer -> _void))
(define-hb-native hb_buffer_get_length (_fun _pointer -> _uint32))
(define-hb-native hb_buffer_get_glyph_infos (_fun _pointer _pointer -> _pointer))
(define-hb-native hb_buffer_get_glyph_positions (_fun _pointer _pointer -> _pointer))
(define-hb-native hb_direction_from_string (_fun _bytes _int -> _int))
(define-hb-native hb_script_from_string (_fun _bytes _int -> _uint32))
(define-hb-native hb_language_from_string (_fun _bytes _int -> _pointer))
(define-hb-native hb_feature_from_string (_fun _bytes _int _pointer -> _stdbool))
;; Borrowed default Unicode property provider; do not destroy it.
(define-hb-native hb_unicode_funcs_get_default (_fun -> _pointer))
(define-hb-native hb_unicode_script (_fun _pointer _uint32 -> _uint32))
(define-hb-native hb_shape (_fun _pointer _pointer _pointer _uint32 -> _void))

(define hb-ready
  (delay/sync
    (force hb-library)
    (for ([entry (in-list (reverse hb-bindings))])
      (force (cdr entry)))
    #t))

(define (harfbuzz-check!) (force hb-ready) (void))
(define (harfbuzz-available?)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (harfbuzz-check!) #t))
(define (harfbuzz-native-version)
  (harfbuzz-check!)
  (define major (malloc _uint32 'atomic))
  (define minor (malloc _uint32 'atomic))
  (define micro (malloc _uint32 'atomic))
  (hb_version major minor micro)
  (format "~a.~a.~a" (ptr-ref major _uint32)
          (ptr-ref minor _uint32) (ptr-ref micro _uint32)))
(define (harfbuzz-native-library-path)
  (harfbuzz-check!)
  (cdr (force hb-library)))

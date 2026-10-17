#lang racket/base

;;;
;;; GPU Diagnostics Native Test
;;;

;; Covers gPU diagnostic ABI and shared collector (GPU execution separate).
;; This native regression layer checks behavior and resource ownership against the installed
;; implementation.

;;;
;;; Imports and Exports
;;;
;; Real native symbols and shared callback execution; no GPU context is created.
(require rackunit rackunit/text-ui ffi/unsafe racket/list json
         (only-in "../private/native.rkt" skia-check! skia-native-version
           sk_graphics_dump_memory_statistics)
         "../private/gpu-native.rkt"
         "../private/graphics-data.rkt" "../private/graphics-trace-native.rkt")
(provide gpu-diagnostics-native-tests gpu-diagnostics-native-test-count)

;;;
;;; Fixtures and Assertions
;;;

; collector-call : symbol? [#:entries exact-positive-integer? #:strings exact-positive-integer?
; #:bytes exact-positive-integer? #:detailed? boolean?] -> any
;   Runs the native memory-statistics collector with explicit entry/string/byte bounds.
(define (collector-call scope #:entries [entries 4096] #:strings [strings 4096]
                         #:bytes [bytes 1048576] #:detailed? [detailed? #f])
  ;; A real global native dump exercises the shared collector, not GPU memory.
  (collect-memory-statistics/native 'collector-test scope
    sk_graphics_dump_memory_statistics detailed? #f entries strings bytes))

; gpu-diagnostics-native-test-count : exact-nonnegative-integer?
;   Records the expected test count used by external acceptance-report checks.
(define gpu-diagnostics-native-test-count 13)

;;;
;;; Regression Suite
;;;

; gpu-diagnostics-native-tests : test-suite?
;   Collects the regression cases for gPU diagnostic ABI and shared collector (GPU execution
;   separate).
(define gpu-diagnostics-native-tests
  (test-suite "GPU diagnostic ABI and shared collector (GPU execution separate)"
    (test-case "pinned native ABI"
      (skia-check!) (check-equal? (skia-native-version) "119.0"))
    (test-case "context diagnostic symbol is common"
      (for ([backend '(opengl metal direct3d)])
        (check-not-false
          (member 'gr_direct_context_dump_memory_statistics (gpu-symbol-names backend)))))
    (test-case "all four additional GL symbols resolve"
      (define rows (gpu-native-inventory 'opengl))
      (for ([name '("gr_glinterface_assemble_interface" "gr_glinterface_assemble_gles_interface"
                    "gr_glinterface_assemble_webgl_interface" "gr_glinterface_has_extension")])
        (define row (findf (lambda (r) (equal? (hash-ref r 'name) name)) rows))
        (check-not-false row) (when row (check-true (hash-ref row 'available)))))
    (test-case "auto assembly safely rejects an empty resolver"
      (check-false (gr_glinterface_assemble_interface #f (lambda (_ name) #f))))
    (test-case "desktop assembly safely rejects an empty resolver"
      (check-false (gr_glinterface_assemble_gl_interface #f (lambda (_ name) #f))))
    (test-case "GLES assembly safely rejects an empty resolver"
      (check-false (gr_glinterface_assemble_gles_interface #f (lambda (_ name) #f))))
    (test-case "desktop WebGL factory reports no browser host"
      (check-false (gr_glinterface_assemble_webgl_interface #f (lambda (_ name) #f))))
    (test-case "global report scope is unchanged after shared refactor"
      (define report (global-memory-statistics/native #f #f 4096 4096 1048576))
      (check-eq? (memory-statistics-scope report) 'process-global-skia-caches)
      (check-false (memory-statistics-truncated? report))
      (check-true (positive? (vector-length (memory-statistics-entries report)))))
    (test-case "private collector keeps its requested scope"
      (define report (collector-call 'gpu-context-skia-resources))
      (check-eq? (memory-statistics-scope report) 'gpu-context-skia-resources)
      (check-equal? (hash-ref (memory-statistics->jsexpr report) 'scope)
        "gpu-context-skia-resources"))
    (test-case "entry budget produces explicit truncation"
      (define report (collector-call 'gpu-context-skia-resources #:entries 0))
      (check-equal? (memory-statistics-entries report) '#())
      (check-true (memory-statistics-truncated? report))
      (check-true (positive? (memory-statistics-dropped-count report))))
    (test-case "string and byte limits omit complete records"
      (for ([report (in-list (list (collector-call 'gpu-context-skia-resources #:strings 0)
                                  (collector-call 'gpu-context-skia-resources #:bytes 0)))])
        (check-equal? (memory-statistics-entries report) '#())
        (check-equal? (memory-statistics-string-bytes report) 0)
        (check-true (memory-statistics-truncated? report))))
    (test-case "detached reports survive GC and subsequent dumps"
      (define report (collector-call 'gpu-context-skia-resources #:detailed? #t))
      (define before (memory-statistics->jsexpr report))
      (collect-garbage)
      (collector-call 'process-global-skia-caches)
      (check-equal? (memory-statistics->jsexpr report) before)
      (check-true (immutable? (memory-statistics-entries report))))
    (test-case "private invocation failure cleans up before the next dump"
      (check-exn #rx"deliberate"
        (lambda ()
          (collect-memory-statistics/native 'test 'gpu-context-skia-resources
            (lambda (_) (error 'test "deliberate invocation failure")) #f #f 10 100 1000)))
      (check-true (memory-statistics? (collector-call 'process-global-skia-caches))))
  ))
(module+ main

  ;;;
  ;;; Command-Line Run
  ;;;

  ; failures : exact-nonnegative-integer?
  ;   Counts failed or errored RackUnit cases for the command-line exit status.
  (define failures (run-tests gpu-diagnostics-native-tests))
  (printf "gpu-diagnostics-native: ~a cases, ~a failures\n" gpu-diagnostics-native-test-count
    failures)
  (exit (if (zero? failures) 0 1)))

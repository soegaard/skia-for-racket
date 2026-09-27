#lang racket/base
(require rackunit rackunit/text-ui racket/file racket/path
         "../main.rkt" "../private/picture-util.rkt" "../private/types.rkt"
         "../private/audit-trace.rkt" (submod "../private/audit-trace.rkt" testing)
         (submod "../pictures.rkt" testing))
(provide picture-pure-tests)
;; Header-only fixture: deliberately not claimed to be a complete native SKP.
(define (header #:version [version 103] #:kind [kind 1] #:bounds [bounds '(0 0 20 10)])
  (bytes-append #"skiapict" (integer->integer-bytes version 4 #f (system-big-endian?))
                (apply bytes-append (map (lambda (v) (real->floating-point-bytes v 4 (system-big-endian?))) bounds))
                (bytes kind)))
(define (temporary-directory proc)
  (define dir (make-temporary-file "skia-picture-pure-~a" 'directory))
  (dynamic-wind void (lambda () (proc dir)) (lambda () (delete-directory/files dir))))
(define (fake-picture who)
  (audit-allocate who 'picture (lambda () (gensym 'picture))))
(define picture-pure-tests
  (test-suite "Persistent pictures: bounded framing, file publication, and conservative policy"
   (test-case "the standard native header records version and cull bounds"
     (define-values (version bounds) (picture-header 'test (header)))
     (check-equal? version 103)
     (check-equal? bounds #(0.0 0.0 20.0 10.0))
     (check-true (immutable? bounds)))
   (test-case "supported historical endpoints use the same header"
     (for ([v '(82 103)])
       (define-values (version bounds) (picture-header 'test (header #:version v)))
       (check-equal? version v)))
   (test-case "unsupported and foreign-endian version words fail early"
     (for ([v '(0 81 104 4294967295)])
       (check-exn exn:fail? (lambda () (picture-header 'test (header #:version v)))))
     (define foreign (header))
     (bytes-copy! foreign 8 (integer->integer-bytes 103 4 #f (not (system-big-endian?))))
     (check-exn exn:fail? (lambda () (picture-header 'test foreign))))
   (test-case "every truncated header is rejected"
     (for ([n (in-range 29)])
       (check-exn exn:fail? (lambda () (picture-header 'test (subbytes (header) 0 n))))))
   (test-case "wrong magic and unsupported custom payload kinds fail"
     (define bad (header)) (bytes-set! bad 0 0)
     (check-exn exn:fail? (lambda () (picture-header 'test bad)))
     (for ([kind '(0 2 255)])
       (check-exn exn:fail? (lambda () (picture-header 'test (header #:kind kind))))))
   (test-case "cull bounds must be finite and ordered"
     (for ([b (in-list (list '(0 0 +inf.0 20) '(0 +nan.0 20 30) '(10 0 2 20)))])
       (check-exn exn:fail? (lambda () (picture-header 'test (header #:bounds b))))))
   (test-case "empty and nonzero-origin cull rectangles are representable"
     (define-values (v bounds) (picture-header 'test (header #:bounds '(-10 5 10 15))))
     (check-equal? bounds #(-10.0 5.0 20.0 10.0))
     (define-values (v0 b0) (picture-header 'test (header #:bounds '(0 0 0 0))))
     (check-equal? b0 #(0.0 0.0 0.0 0.0)))
   (test-case "data snapshots are detached and immutable"
     (define input (header)) (define snapshot (picture-data-snapshot 'test input))
     (bytes-set! input 0 0)
     (check-equal? (subbytes snapshot 0 8) #"skiapict")
     (check-true (immutable? snapshot)))
   (test-case "encoded length is bounded before the snapshot"
     (parameterize ([current-skia-byte-limit 28])
       (check-exn exn:fail? (lambda () (picture-data-snapshot 'test (header)))))
     (parameterize ([current-skia-byte-limit 29])
       (check-equal? (picture-data-snapshot 'test (header)) (header))))
   (test-case "trust is an explicit boolean opt-in"
     (check-exn exn:fail? (lambda () (check-picture-trust 'test #f)))
     (check-exn exn:fail? (lambda () (check-picture-trust 'test 'yes)))
     (check-not-exn (lambda () (check-picture-trust 'test #t))))
   (test-case "public loaders reject missing trust without native loading or file reads"
     (check-exn #rx"trusted" (lambda () (picture-from-bytes (header))))
     (check-exn #rx"trusted" (lambda () (picture-from-file "this-file-does-not-exist.skp"))))
   (test-case "public loaders reject malformed framing without native loading"
     (check-exn exn:fail? (lambda () (picture-from-bytes #"no" #:trusted? #t))))
   (test-case "nominal size is optional but both dimensions are required"
     (check-false (picture-size-override 'test #f #f))
     (check-equal? (picture-size-override 'test 100 50) #(100.0 50.0))
     (check-exn exn:fail? (lambda () (picture-size-override 'test 100 #f)))
     (check-exn exn:fail? (lambda () (picture-size-override 'test #f 50))))
   (test-case "nominal sizes reject negative and nonfinite values, not zero"
     (check-equal? (picture-size-override 'test 0 0) #(0.0 0.0))
     (for ([v '(-1 +inf.0 +nan.0 bad)])
       (check-exn exn:fail? (lambda () (picture-size-override 'test v 10)))))
   (test-case "local picture-shader matrices retain the existing affine ABI"
     (check-false (picture-local-matrix 'test #f))
     (define m (picture-local-matrix 'test (matrix-translate 5 6)))
     (check-equal? (sk-matrix-x0 m) 5.0)
     (check-equal? (sk-matrix-y0 m) 6.0))
   (test-case "singular or nonaffine picture-shader matrices are rejected"
     (check-exn exn:fail? (lambda () (picture-local-matrix 'test (matrix-scale 0))))
     (check-exn exn:fail? (lambda () (picture-local-matrix 'test matrix4-identity))))
   (test-case "tile bounds copy list and vector coordinates including negative origins"
     (define tile (vector -2 -3 12 14))
     (define r (picture-tile-rect 'test tile))
     (vector-set! tile 0 99)
     (check-equal? (sk-rect-left r) -2.0)
     (check-equal? (sk-rect-bottom r) 11.0)
     (check-false (picture-tile-rect 'test #f)))
   (test-case "tiles must be finite nonempty rectangles"
     (for ([tile (in-list (list '(0 0 0 4) '(0 0 -2 4) '(0 0 4) '(0 0 +inf.0 4) 'bad))])
       (check-exn exn:fail? (lambda () (picture-tile-rect 'test tile)))))
   (test-case "bad spatial-index choices fail before native creation"
     (check-exn exn:fail? (lambda () (call-with-picture 20 10 void #:spatial-index 'octree)))
     (check-exn exn:fail? (lambda () (picture-recorder-begin-recording! #f 0 0 20 10 #:spatial-index #t))))
   (test-case "file reader copies a complete bounded stream"
     (temporary-directory
      (lambda (dir)
        (define file (build-path dir "cache.skp"))
        (call-with-output-file file (lambda (out) (write-bytes (header) out)))
        (check-equal? (read-picture-file-bytes 'test file) (header)))))
   (test-case "file reader rejects oversize data while reading"
     (temporary-directory
      (lambda (dir)
        (define file (build-path dir "cache.skp"))
        (call-with-output-file file (lambda (out) (write-bytes (bytes-append (header) (make-bytes 100)) out)))
        (parameterize ([current-skia-byte-limit 40])
          (check-exn exn:fail? (lambda () (read-picture-file-bytes 'test file)))))))
   (test-case "atomic writer enforces error then replacement"
     (temporary-directory
      (lambda (dir)
        (define file (build-path dir "cache.skp"))
        (write-picture-file-bytes! 'test (header) file 'error)
        (check-exn exn:fail? (lambda () (write-picture-file-bytes! 'test (header) file 'error)))
        (write-picture-file-bytes! 'test (header #:bounds '(0 0 30 10)) file 'replace)
        (check-equal? (file->bytes file) (header #:bounds '(0 0 30 10)))
        (check-equal? (length (directory-list dir)) 1))))
   (test-case "failed replacement preserves the previous file and leaves no temporary"
     (temporary-directory
      (lambda (dir)
        (define file (build-path dir "cache.skp"))
        (write-picture-file-bytes! 'test (header) file 'error)
        (check-exn exn:fail? (lambda () (write-picture-file-bytes! 'test #"bad" file 'replace)))
        (check-equal? (file->bytes file) (header))
        (check-equal? (length (directory-list dir)) 1))))
   (test-case "bad output modes, directories, parents and NULs fail"
     (temporary-directory
      (lambda (dir)
        (check-exn exn:fail? (lambda () (picture-output-path 'test dir 'replace)))
        (check-exn exn:fail? (lambda () (picture-output-path 'test (build-path dir "missing" "x.skp") 'replace)))
        (check-exn exn:fail? (lambda () (picture-output-path 'test (build-path dir "x.skp") 'append)))
        (check-exn exn:fail? (lambda () (picture-output-path 'test "x\0.skp" 'error))))))
   (test-case "deserialized pictures have unknown capabilities on every backend"
     (for ([backend '(pdf svg raster)])
       (check-eq? (output-capability-status (output-capability-for backend 'deserialized-picture)) 'unknown)))
   (test-case "picture-shader rendering requires document fallback"
     (for ([backend '(pdf svg)])
       (check-eq? (output-capability-status (output-capability-for backend 'picture-shader)) 'needs-raster))
     (check-eq? (output-capability-status (output-capability-for 'raster 'picture-shader)) 'rasterized))
   (test-case "sampled annotation loss remains explicit on every backend"
     (for ([backend '(pdf svg raster)])
       (check-eq? (output-capability-status (output-capability-for backend 'picture-shader-annotation)) 'discarded)))
   (test-case "both native import paths start with opaque provenance"
     (for ([who '(picture-from-bytes picture-from-file)])
       (check-not-false (memq 'deserialized-picture (features (fake-picture who))))))
   (test-case "shader creation copies opaque provenance without a strong child reference"
     (define child (fake-picture 'picture-from-bytes))
     (define result
       (audit-use (list child) (list (gensym 'ptr))
         (lambda () (audit-allocate 'make-picture-shader 'shader (lambda () (gensym 'shader))))))
     (check-not-false (memq 'picture-shader (features result)))
     (check-not-false (memq 'deserialized-picture (features result))))
   (test-case "shader creation converts annotation provenance to semantic loss"
     (define child (fake-picture 'picture-recorder-finish-recording!))
     (hash-set! resources child (provenance 'picture '(picture annotation) (hasheq)))
     (define result
       (audit-use (list child) (list (gensym 'ptr))
         (lambda () (audit-allocate 'make-picture-shader 'shader (lambda () (gensym 'shader))))))
     (check-false (memq 'annotation (features result)))
     (check-not-false (memq 'picture-shader-annotation (features result))))
   (test-case "R-tree begin clears the recorder summary just like ordinary begin"
     (for ([name '(sk_picture_recorder_begin_recording sk_picture_recorder_begin_recording_with_bbh_factory)])
       (define h (gensym 'recorder)) (define ptr (gensym 'ptr))
       (hash-set! resources h (provenance 'picture-recorder '(runtime-shader) (hasheq)))
       (audit-use (list h) (list ptr) (lambda () (after-native! name (list ptr #f #f))))
       (check-equal? (features h) '())))))
(module+ test (run-tests picture-pure-tests))

#lang racket/base
(require rackunit "../private/raster-buffer-util.rkt" "../private/check.rkt")
(provide raster-buffer-pure-tests)
(define (layout w h [rb #f]) (call-with-values (lambda () (raster-layout 'test w h rb)) list))
(define (input w h bs [rb #f] [pm? #f]) (prepare-raster-input 'test w h bs rb pm?))
(define raster-buffer-pure-tests
  (test-suite
   "Raster storage: checked layout and detached input"
   (test-case "tight layout" (check-equal? (layout 3 2) '(12 24 24)))
   (test-case "padded layout includes last padding" (check-equal? (layout 3 2 20) '(20 32 40)))
   (test-case "one row distinguishes minimum and allocation" (check-equal? (layout 1 1 64) '(64 4 64)))
   (test-case "zero dimensions rejected" (for ([wh '((0 1) (1 0))]) (check-exn exn:fail? (lambda () (apply layout wh)))))
   (test-case "negative dimensions rejected" (check-exn exn:fail? (lambda () (layout -1 1))))
   (test-case "inexact dimensions rejected" (check-exn exn:fail? (lambda () (layout 2.0 1))))
   (test-case "dimension upper limit" (check-exn exn:fail? (lambda () (layout 32769 1))))
   (test-case "short stride rejected" (check-exn exn:fail? (lambda () (layout 3 2 8))))
   (test-case "unaligned stride rejected" (check-exn exn:fail? (lambda () (layout 3 2 13))))
   (test-case "inexact stride rejected" (check-exn exn:fail? (lambda () (layout 3 2 16.0))))
   (test-case "negative stride rejected" (check-exn exn:fail? (lambda () (layout 1 1 -4))))
   (test-case "padding counts toward limit"
     (parameterize ([current-skia-byte-limit 32]) (check-exn exn:fail? (lambda () (layout 3 2 20)))))
   (test-case "exact allocation limit allowed"
     (parameterize ([current-skia-byte-limit 40]) (check-equal? (layout 3 2 20) '(20 32 40))))
   (test-case "huge stride rejected without native allocation"
     (parameterize ([current-skia-byte-limit (expt 2 200)])
       (check-exn exn:fail? (lambda () (layout 1 2 (expt 2 128))))))
   (test-case "corner pixels valid" (check-not-exn (lambda () (raster-point 't 0 0 3 2))) (check-not-exn (lambda () (raster-point 't 2 1 3 2))))
   (test-case "pixel outside half-open bounds"
     (for ([xy '((3 0) (0 2) (-1 0) (0 -1) (1.0 0))])
       (check-exn exn:fail? (lambda () (apply raster-point 't (append xy '(3 2)))))))
   (test-case "subset at lower right" (check-not-exn (lambda () (raster-subset 't 2 1 1 1 3 2))))
   (test-case "subset cannot be empty" (check-exn exn:fail? (lambda () (raster-subset 't 0 0 0 1 3 2))))
   (test-case "subset does not silently clip" (check-exn exn:fail? (lambda () (raster-subset 't 2 0 2 1 3 2))))
   (test-case "subset must use exact coordinates" (check-exn exn:fail? (lambda () (raster-subset 't 0.0 0 1 1 3 2))))
   (test-case "callback arity checked" (check-exn exn:fail? (lambda () (raster-procedure 't (lambda () 1)))))
   (test-case "variadic callback accepted" (check-not-exn (lambda () (raster-procedure 't list))))
   (test-case "opaque input unchanged" (check-equal? (input 1 1 (bytes 12 24 48 255)) (bytes 12 24 48 255)))
   (test-case "transparent RGB discarded" (check-equal? (input 1 1 (bytes 255 64 128 0)) (bytes 0 0 0 0)))
   (test-case "premultiplication rounds to nearest" (check-equal? (input 1 1 (bytes 255 128 64 128)) (bytes 128 64 32 128)))
   (test-case "valid premultiplied input preserved" (check-equal? (input 1 1 (bytes 64 32 16 64) #f #t) (bytes 64 32 16 64)))
   (test-case "invalid premultiplied input rejected" (check-exn exn:fail? (lambda () (input 1 1 (bytes 65 0 0 64) #f #t))))
   (test-case "truncated last row rejected" (check-exn exn:fail? (lambda () (input 1 2 (make-bytes 11) 8))))
   (test-case "last input padding optional"
     (check-equal? (input 1 2 (bytes 10 20 30 255 99 99 99 99 40 50 60 255) 8)
                   (bytes 10 20 30 255 40 50 60 255)))
   (test-case "source padding ignored"
     (check-equal? (input 1 1 (bytes 10 20 30 255 99 98 97 96) 8) (bytes 10 20 30 255)))
   (test-case "input is detached"
     (define bs (bytes 10 20 30 255)) (define out (input 1 1 bs #f #t))
     (bytes-set! bs 0 200) (check-equal? out (bytes 10 20 30 255)))
   (test-case "byte input required" (check-exn exn:fail? (lambda () (input 1 1 '(0 0 0 0)))))
   (test-case "premultiply flag must be boolean" (check-exn exn:fail? (lambda () (input 1 1 (bytes 0 0 0 0) #f 'yes)))))
)

#lang racket/base

;;;
;;; Pict Pure Test
;;;

;; Covers skia/pict pure validation and explicit-transfer boundaries.
;; This source-only regression layer checks contracts and lifecycle rules before native rendering
;; is involved.

;;;
;;; Imports and Exports
;;;

;; These checks use only pure helper values. Requiring skia/pict must not load
;; Skia, create a GUI, or create a GPU context merely to validate requests.
(require rackunit rackunit/text-ui racket/list pict/convert
         "../pict.rkt" "../main.rkt"
         "../private/pict-util.rkt")

(provide pict-pure-tests)


;;;
;;; Regression Suite
;;;

; pict-pure-tests : test-suite?
;;   Collects the regression cases for skia/pict pure validation and explicit-transfer boundaries.
(define pict-pure-tests
  (test-suite
   "skia/pict pure validation and explicit-transfer boundaries"
   (test-case "backing scales and bridge scratch buffers are checked before native work"
     (check-exn exn:fail:contract? (lambda () (checked-backing-scale 'pict 0)))
     (check-exn exn:fail:contract? (lambda () (checked-backing-scale 'pict +nan.0)))
     (check-exn exn:fail:contract? (lambda () (checked-backing-scale 'pict +inf.0)))
     (parameterize ([current-skia-byte-limit 7])
       (check-exn exn:fail? (lambda () (checked-image-pict-geometry 'pict 1 1 1))))
     (parameterize ([current-skia-byte-limit 16])
       (check-equal? (call-with-values (lambda () (checked-image-pict-geometry 'pict 2 1 2)) list)
                     '(1 1/2))))
   (test-case "bounds are copied, finite, positive, and preserve logical fractions"
     (define supplied (vector 1 2 101/2 71/3))
     (define bounds (checked-picture-bounds 'pict supplied 0 0))
     (vector-set! supplied 2 999)
     (check-equal? bounds '#(1 2 101/2 71/3))
     (check-true (immutable? bounds))
     (for ([bad (in-list (list '#(0 0 0 1) '#(0 0 -1 1) '#(0 0 1 +inf.0)
                               '(0 0 1 1) '#(0 0 1)))])
       (check-exn exn:fail? (lambda () (checked-picture-bounds 'pict bad 1 1))))
     (for ([scale (in-list '(1 3/2 2))])
       (define geometry
         (call-with-values (lambda () (checked-picture-pict-geometry 'pict bounds scale)) list))
       (check-equal? (drop geometry 2) '(101/2 71/3))))
   (test-case "the bridge leaves non-pict values without pict conversion"
     (check-false (pict-convertible? 'not-a-pict))
     ;; Type checks occur before any Skia operation, native load, or implicit
     ;; GPU transfer.
     (check-exn exn:fail:contract? (lambda () (image->pict 'not-an-image)))
     (check-exn exn:fail:contract? (lambda () (surface->pict 'not-a-surface)))
     (check-exn exn:fail:contract? (lambda () (picture->pict 'not-a-picture))))
   (test-case "the opt-in module imports without GUI or native initialization"
     (check-true (procedure? image->pict))
     (check-true (procedure? surface->pict))
     (check-true (procedure? picture->pict)))))

(module+ test

  ;;;
  ;;; Test Entry Point
  ;;;

  ; failures : exact-nonnegative-integer?
  ;;   Counts failed or errored RackUnit cases for the command-line exit status.
  (define failures (run-tests pict-pure-tests))
  (unless (zero? failures) (error 'pict-pure-test "~a failures" failures)))

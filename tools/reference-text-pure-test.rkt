#lang racket/base

;;;
;;; Reference Text Pure Test
;;;

;; Checks font-style normalization, OpenType tag conversion, and deferred break-position validation.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; Pure R3a values and checks. Importing Skia does not construct native fonts.
(require rackunit skia)

(module+ test
  (test-case "font style names normalize to detached numeric values"
    (for ([name '(invisible thin extra-light light normal medium semi-bold
                           bold extra-bold black extra-black)]
          [weight (in-range 0 1100 100)])
      (define style (make-font-style #:weight name))
      (check-true (font-style? style))
      (check-false (skia-resource? style))
      (check-equal? (font-style-weight style) weight)
      (check-equal? (font-style-width style) 5)
      (check-equal? (font-style-slant style) 'upright))
    (for ([name '(ultra-condensed extra-condensed condensed semi-condensed normal
                                 semi-expanded expanded extra-expanded ultra-expanded)]
          [width (in-range 1 10)])
      (check-equal? (font-style-width (make-font-style #:width name)) width))
    (check-equal? (make-font-style #:weight 'bold #:width 'condensed)
                  (make-font-style #:weight 700 #:width 3))
    (for ([value '(-1 1001 400.0 heavy)])
      (check-exn exn:fail? (lambda () (make-font-style #:weight value)))))
  (test-case "table tags have asymmetric conversion contracts"
    (check-equal? (font-table-tag "head") #x68656164)
    (check-equal? (font-table-tag #"OS/2") #x4f532f32)
    (check-equal? (font-table-tag #xffffffff) #xffffffff)
    (check-equal? (font-table-tag->bytes #x68656164) #"head")
    (check-true (immutable? (font-table-tag->bytes 0)))
    (check-not-equal? (font-table-tag "head") (font-table-tag "HEAD"))
    (for ([value (list 'head "abc" #"abcde" -1 #x100000000)])
      (check-exn exn:fail? (lambda () (font-table-tag value))))
    (for ([value (list 'head "head" #"head" -1)])
      (check-exn exn:fail? (lambda () (font-table-tag->bytes value)))))
  (test-case "break positions are validated against a paragraph only at layout time"
    (define opportunity (make-layout-break-opportunity 0 "-"))
    (check-true (layout-break-opportunity? opportunity))
    (check-false (skia-resource? opportunity))
    (check-equal? (layout-break-opportunity-index opportunity) 0)
    (check-equal? (layout-break-opportunity-insert opportunity) "-")
    (check-exn exn:fail? (lambda () (make-layout-break-opportunity -1)))
    (check-exn exn:fail? (lambda () (make-layout-break-opportunity 1 "\n")))
    (check-exn exn:fail? (lambda () (make-layout-break-opportunity 1 "\u202e")))))

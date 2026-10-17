#lang racket/base

;;;
;;; Accessible Figures Test
;;;

;; Checks accessible figure conversion and preview handling using native-free Racket picts.
;; This module guards the documentation's examples and support code against regressions.


;; These tests use Racket picts, not Skia. Rendering the complete tutorials is a separate check.

;;;
;;; Imports and Exports
;;;

(require racket/file racket/list
         rackunit file/convertible
         (prefix-in pict: pict)
         scribble/core scribble/eval
         "accessible-figures.rkt")

;;;
;;; Regression Checks
;;;

(module+ test

  ; created : list?
  ;   Tracks temporary figure files so the regression test can clean them up.
  (define created '())

  ; keep : any/c -> image-element?
  ;   Records a generated figure's temporary path and returns the figure unchanged.
  (define (keep figure)
    (set! created (cons (image-element-path figure) created))
    figure)
  (dynamic-wind
    void
    (lambda ()
      (test-case "direct pict has a literal, descriptive alternative"
        (define figure
          (keep (tutorial-figure "Two axes -- origin & scale." (pict:blank 32 20))))
        (check-true (image-element? figure))
        (check-equal? (content->string (element-content figure))
                      "Two axes -- origin & scale.")
        (define image-style (element-style figure))
        (check-equal? (if (style? image-style) (style-name image-style) image-style)
                      "skia-tutorial-figure")
        (check-true (file-exists? (image-element-path figure)))
        (check-equal? (image-element-scale figure) 1/2))
      (test-case "evaluated pict is unwrapped without another evaluation"
        (define evaluator (make-base-eval))
        (dynamic-wind
          void
          (lambda ()
            (interaction-eval #:eval evaluator
                              (require pict)
                              (define draws 0))
            (define result
              (interaction-eval-show #:eval evaluator
                                     (begin (set! draws (add1 draws)) (blank 32 20))))
            (define figure (keep (tutorial-figure "One evaluated panel." result)))
            (check-true (image-element? figure))
            (check-equal? (evaluator 'draws) 1))
          (lambda () (close-eval evaluator))))
      (test-case "a one-density converter keeps its display scale"
        (struct one-density (picture)
          #:property prop:convertible
          (lambda (self request default)
            (if (eq? request 'png-bytes)
                (convert (one-density-picture self) request default)
                default)))
        ;; picture: wrapped pict value. The converter deliberately offers only png-bytes so this
        ;; fixture exercises single-density display scaling without a high-density alternative.
        (define figure
          (keep (tutorial-figure "A single-density panel."
                                 (one-density (pict:blank 32 20)))))
        (check-equal? (image-element-scale figure) 1))
      (test-case "empty or generic descriptions are rejected"
        (for ([alternative '("" "   " "image" "PICTURE")])
          (check-exn exn:fail:contract?
                     (lambda () (tutorial-figure alternative (pict:blank 10 10))))))
      (test-case "missing, multiple, and non-picture results are rejected"
        (for ([value (list #f "a message" (list (pict:blank 1 1) (pict:blank 1 1)))])
          (check-exn exn:fail? (lambda () (tutorial-figure "A panel." value)))))
      (test-case "preview slots are independent and accept their result once"
        (define-values (preview-a finish-a) (make-figure-preview))
        (define-values (preview-b finish-b) (make-figure-preview))
        (define figure-a (keep (tutorial-figure "First finished panel." (pict:blank 20 10))))
        (define figure-b (keep (tutorial-figure "Second finished panel." (pict:blank 40 30))))
        (check-true (delayed-element? preview-a))
        (check-true (delayed-element? preview-b))
        (check-equal? (content->string preview-a) "")
        (check-eq? (finish-a figure-a) figure-a)
        (check-eq? (finish-b figure-b) figure-b)
        (check-equal? (content->string preview-a) "First finished panel.")
        (check-equal? (content->string preview-b) "Second finished panel.")
        (check-exn exn:fail? (lambda () (finish-a figure-b)))))
    (lambda ()
      (for ([path (in-list created)] #:when (file-exists? path))
        (delete-file path)))))

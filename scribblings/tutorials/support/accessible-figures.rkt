#lang racket/base

;;;
;;; Accessible Figures
;;;

;; Converts evaluated pictures into figures with required alternative text.
;; This module supports documentation assembly and shared examples rather than the public Skia
;; API.


;; Documentation presentation only. The existing evaluators still draw every figure.

;;;
;;; Imports and Exports
;;;

(require racket/file racket/list racket/string
         file/convertible
         (only-in scribble/base image literal)
         (only-in scribble/core element? element-content image-element?
                  make-delayed-element))

(provide tutorial-figure make-figure-preview)

;;;
;;; Accessible Figure Markup and Previews
;;;

;; Scribble/eval wraps a pict in elements; the later lessons return the pict directly.
;; Refuse multiple results rather than silently dropping a panel or other content.

; figure-pictures : real? -> list?
;   Collects convertible pictures from evaluated Scribble content.
(define (figure-pictures value)
  (cond
    [(convertible? value) (list value)]
    [(element? value) (figure-pictures (element-content value))]
    [(list? value) (append-map figure-pictures value)]
    [(or (equal? value "") (not value)) '()]
    [else (error 'tutorial-figure "expected a picture or an evaluated picture, got ~e" value)]))

; tutorial-figure : string? real? -> image-element?
;   Renders one evaluated picture and requires meaningful alternative text.
(define (tutorial-figure alternative value)
  (unless (and (string? alternative)
               (not (string=? (string-trim alternative) ""))
               (not (member (string-downcase (string-trim alternative)) '("image" "picture"))))
    (raise-argument-error 'tutorial-figure "descriptive nonempty alternative text" alternative))
  (define pictures (figure-pictures value))
  (unless (= (length pictures) 1)
    (error 'tutorial-figure "expected exactly one picture, got ~a" (length pictures)))
  (define picture (car pictures))
  ;; Match Scribble's preference for high-density PNGs without doubling display size.
  (define double-density (convert picture 'png@2x-bytes #f))
  (define pixels (or double-density (convert picture 'png-bytes #f)))
  (unless (bytes? pixels)
    (error 'tutorial-figure "picture cannot be converted to PNG"))
  (define path (make-temporary-file "skia-tutorial-figure-~a.png"))
  (with-handlers ([exn:fail? (lambda (exception)
                             (delete-file path)
                             (raise exception))])
    (call-with-output-file path #:exists 'truncate/replace
      (lambda (out) (write-bytes pixels out))))
  ;; The renderer copies this file into its output. Keep the temporary original alive
  ;; until rendering is complete; deleting it here would leave a broken image element.
  (image path #:scale (if double-density 1/2 1)
         #:style "skia-tutorial-figure" (literal alternative)))

;; The opening can display the completed figure without evaluating later definitions
;; early, importing a second scene, or drawing the finished result a second time.
;; Each document gets its own slot; there is no shared cross-document figure registry.

; make-figure-preview : -> (values procedure? procedure?)
;   Returns paired preview and completion helpers that share the finished figure.
(define (make-figure-preview)
  (define finished #f)
  (define (require-finished)
    (unless finished
      (error 'make-figure-preview "the document never supplied its finished figure"))
    finished)
  (define preview
    (make-delayed-element
     (lambda (_renderer _part _resolve-info) (require-finished))
     (lambda () "")
     (lambda () (if finished (element-content finished) ""))))
  (define (finish figure)
    (when finished
      (error 'make-figure-preview "the finished figure was supplied more than once"))
    (unless (image-element? figure)
      (raise-argument-error 'make-figure-preview "figure element" figure))
    (set! finished figure)
    figure)
  (values preview finish))

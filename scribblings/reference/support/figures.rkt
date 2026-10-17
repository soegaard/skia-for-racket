#lang racket/base

;;;
;;; Figures
;;;

;; Embeds checked reference images with meaningful alternative text.
;; This module supports documentation assembly and shared examples rather than the public Skia
;; API.


;;;
;;; Imports and Exports
;;;

(require racket/runtime-path
         racket/string
         (only-in scribble/base image literal))

(provide reference-figure)

;;;
;;; Documentation Data and Helpers
;;;

; reference-image-directory : path?
;;   Locates reference image directory relative to this module rather than the current directory.
(define-runtime-path reference-image-directory "../images")

; reference-figure : path-string? string? -> image-element?
;;   Embeds a reference image after checking its filename and alternative text.
(define (reference-figure filename alternative)
  (unless (and (string? filename)
               (regexp-match? #px"^[A-Za-z0-9][A-Za-z0-9._-]*\\.png$" filename))
    (raise-argument-error 'reference-figure "simple PNG filename" filename))
  (unless (and (string? alternative)
               (not (string=? (string-trim alternative) ""))
               (not (member (string-downcase (string-trim alternative))
                            '("image" "picture"))))
    (raise-argument-error 'reference-figure
                          "descriptive nonempty alternative text"
                          alternative))
  (define path (build-path reference-image-directory filename))
  (unless (file-exists? path)
    (error 'reference-figure
           "missing generated reference image ~a; run `racket tools/render-reference-images.rkt`"
           path))
  ;; The maintainer generator renders at 2x device resolution. Display at the
  ;; logical size used by the code example.
  (image path #:scale 1/2 #:style "skia-reference-figure" (literal alternative)))

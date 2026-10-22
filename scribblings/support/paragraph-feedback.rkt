#lang racket/base

;; Adds per-paragraph feedback controls to Scribble HTML documentation.

(require scribble/core
         scribble/html-properties
         racket/runtime-path)

(provide feedback-style
         skia-feedback-style)

(define-runtime-path feedback-js "paragraph-feedback.js")
(define-runtime-path feedback-css "paragraph-feedback.css")

(define (feedback-meta name value)
  (and value (head-extra `(meta ([name ,name] [content ,value])))))

;; feedback-style : #:github [string?] #:email [string?] #:name [style-name?]
;;                  #:extra [list?] -> style?
;; Adds the browser assets and their delivery configuration to a document style.
(define (feedback-style #:github [repo #f]
                        #:email [email #f]
                        #:name [name #f]
                        #:extra [extra '()])
  (unless (or repo email)
    (error 'feedback-style "expected at least one of #:github or #:email"))
  (make-style
   name
   (append (list (js-addition feedback-js)
                 (css-addition feedback-css))
           (filter values
                   (list (feedback-meta "feedback-github" repo)
                         (feedback-meta "feedback-email" email)))
           extra)))

;; skia-feedback-style : #:name [style-name?] #:extra [list?] -> style?
;; Configures feedback for this project's public issue tracker.
(define (skia-feedback-style #:name [name #f]
                             #:extra [extra '()])
  (feedback-style #:github "soegaard/skia-for-racket"
                  #:name name
                  #:extra extra))

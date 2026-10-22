#lang racket/base

;; Adds per-paragraph feedback controls to Scribble HTML documentation.

(require scribble/core
         scribble/html-properties
         racket/runtime-path)

(provide feedback-style
         skia-feedback-style
         documentation-notice)

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

;; notice-element : string? string? -> element?
;; Produces a block-styled inline element, so the notice does not introduce
;; nested block elements into Scribble's generated paragraph flow.
(define (notice-element class text)
  (make-element
   (make-style class (list (make-alt-tag "span")))
   (list text)))

;; documentation-notice : (or/c 'reference 'guide 'tutorial 'tutorials) -> paragraph?
;; Displays the short AI-authorship and feedback invitation using the colour
;; family for a documentation collection.
(define (documentation-notice collection)
  (define-values (kind label)
    (case collection
      [(reference) (values "reference" "reference")]
      [(guide) (values "guide" "guide")]
      [(tutorial tutorials) (values "tutorials" "tutorial")]
      [else
       (raise-argument-error 'documentation-notice
                             "'reference, 'guide, 'tutorial, or 'tutorials"
                             collection)]))
  (define notice-style
    (make-style
     (string-append "skia-ai-notice skia-ai-notice--" kind)
     (list (make-alt-tag "div")
           (make-attributes
            (list (cons 'role "note")
                  (cons 'aria-label "Notice"))))))
  (make-paragraph
   notice-style
   (list
    (notice-element "skia-ai-notice__title" "Notice")
    (notice-element "skia-ai-notice__item"
                    (string-append "This " label " is mostly written by AI."))
    (notice-element "skia-ai-notice__item"
                    "Although I spent much time and effort editing it, there is still plenty of room for improvements.")
    (notice-element "skia-ai-notice__item"
                    "Please flag any overly dense or unintelligible sentences.")
    (notice-element "skia-ai-notice__item"
                    "It is enough to write “check” as a comment."))))

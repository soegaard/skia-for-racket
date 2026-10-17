#lang racket/base

;;;
;;; Source
;;;

;; Extracts a definition from example source without evaluating the program.
;; This module supports documentation assembly and shared examples rather than the public Skia
;; API.


;;;
;;; Imports and Exports
;;;

(require racket/file)
(provide source-definition)

;; Read, but do not evaluate, an example. Display its actual definition rather
;; than maintaining a second copy in the manual. Nested local helpers count.
;;;
;;; Documentation Data and Helpers
;;;

; source-definition : path-string? any/c -> string?
;;   Returns the actual source text of a named definition without evaluating it.
(define (source-definition path name)
  (define source (file->string path))
  (define (find-definition form)
    (define pieces (syntax->list form))
    (cond
      [(not pieces) #f]
      [(and (pair? pieces) (eq? (syntax-e (car pieces)) 'quote)) #f]
      [(and (>= (length pieces) 3) (eq? (syntax-e (car pieces)) 'define)
            (let ([left (syntax->datum (cadr pieces))])
              (equal? (if (pair? left) (car left) left) name)))
       form]
      [else (for/or ([piece (in-list pieces)]) (find-definition piece))]))
  (define definition
    (call-with-input-file path
      (lambda (in)
        (port-count-lines! in)
        (read-line in) ; Every example begins with its #lang line.
        (for/or ([form (in-port (lambda (in) (read-syntax path in)) in)])
          (find-definition form)))))
  (unless definition
    (error 'source-definition "missing definition ~a in ~a" name path))
  (define start (sub1 (syntax-position definition)))
  (substring source start (+ start (syntax-span definition))))

;;;
;;; Regression Checks
;;;

(module+ test
  (require rackunit racket/runtime-path)
  ; model : path?
  ;;   Locates model relative to this module rather than the current directory.
  (define-runtime-path model "../navigation/model.rkt")
  ; window : path?
  ;;   Locates window relative to this module rather than the current directory.
  (define-runtime-path window "../navigation/navigate.rkt")
  (check-equal? (caadr (read (open-input-string (source-definition model 'zoom-at)))) 'zoom-at)
  (check-equal? (caadr (read (open-input-string (source-definition window 'drag-to!)))) 'drag-to!)
  (check-exn exn:fail? (lambda () (source-definition model 'no-such-definition))))

#lang racket/base

;;;
;;; PDF Doctor
;;;

;; Exercises PDF documents, page scopes, metadata, and finish-time output and reports native
;; diagnostic evidence.
;; The validation workflow uses this focused probe alongside automated regression suites.

;;;
;;; Imports and Exports
;;;
(require ffi/unsafe "../main.rkt" "../private/types.rkt")
(provide pdf-doctor!)


;;;
;;; Diagnostic Operations
;;;

; pdf-doctor! : -> void?
;   Checks multipage PDF serialization, copied output bytes, native metadata layouts, and expired
;   page-canvas rejection.
(define (pdf-doctor!)
  (define expired #f)
  (define bs
    (call-with-pdf-bytes
     (lambda (doc)
       (with-pdf-page (c doc 200 100)
         (set! expired c)
         (with-skia ([paint (make-paint #:color 'red)])
           (draw-circle c 50 50 25 paint)))
       (with-pdf-page (c doc 100 200)
         (unless (skia-closed? expired)
           (error 'doctor "ended PDF canvas became live on the next page"))
         (define rejected?
           (with-handlers ([exn:fail? (lambda (_) #t)])
             (canvas-save! expired) #f))
         (unless rejected? (error 'doctor "expired PDF canvas was accepted"))
         (with-canvas-state c (canvas-translate! c 10 10)))
       (unless (= (pdf-document-page-count doc) 2)
         (error 'doctor "wrong PDF page count")))
     #:title "Racket Skia PDF doctor"))
  (unless (and (regexp-match? #rx#"^%PDF-" bs)
               (regexp-match? #rx#"%%EOF[ \t\r\n]*$" bs)
               (= 2 (length (regexp-match* #rx#"/Type[ \t\r\n]*/Page[ \t\r\n/>]" bs))))
    (error 'doctor "PDF framing or page-tree smoke check failed"))
  (printf "PDF documents passed: two pages, copied bytes, expired-canvas rejection; ABI metadata=~a timestamp=~a; ~a bytes\n"
          (ctype-sizeof _sk-pdf-metadata) (ctype-sizeof _sk-pdf-datetime) (bytes-length bs)))

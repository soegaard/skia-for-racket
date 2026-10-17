#lang racket/base

;;;
;;; GPU Render Scopes
;;;

;; Validates context-bound drawing procedures and executes GPU rendering scopes.
;; Provides shared execution rules for public GPU rendering helpers.


(provide call-with-rendered-gpu-image)

;; Private lifetime worker. Injected operations allow failure-path tests without
;; a driver, while the public entry point supplies only the real GPU operations.
;; Factories must clean up their own partially constructed resources on failure.
; call-with-rendered-gpu-image : any/c any/c any/c any/c any/c any/c any/c -> any
;;   Scopes context and surface creation, drawing, explicit readback, and cleanup through injected
;;   operations.
(define (call-with-rendered-gpu-image make-context activate make-surface
                                      draw readback close-resource close-context)
  (define image #f)
  (define delivered? #f)
  (call-with-continuation-barrier
   (lambda ()
     ;; Keep the downloaded image owned here until BOTH GPU cleanup scopes have
     ;; completed. In particular, failed context teardown must not leak a copy
     ;; that the caller will never receive.
     (dynamic-wind
       void
       (lambda ()
         (define context #f)
         (dynamic-wind
           ;; Acquisition in the pre-thunk has breaks disabled through the
           ;; assignment, leaving no allocation-to-cleanup-registration gap.
           (lambda () (set! context (make-context)))
           (lambda ()
             (activate
              context
              (lambda ()
                (define surface #f)
                (dynamic-wind
                  (lambda () (set! surface (make-surface context)))
                  (lambda ()
                    ;; Drawing may return zero, one, or many values. They are
                    ;; not the result of this helper and are not retained.
                    (call-with-values
                     (lambda () (draw context surface))
                     (lambda ignored (void)))
                    ;; The native transfer is synchronous. Register the new
                    ;; CPU image before a pending break can interrupt us.
                    (parameterize-break #f
                      (set! image (readback surface))))
                  (lambda () (close-resource surface))))))
           ;; This runs after activation exit, including on raises/escapes.
           (lambda () (close-context context)))
         (set! delivered? #t)
         image)
       (lambda ()
         (when (and image (not delivered?))
           (close-resource image)))))))

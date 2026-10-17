#lang racket/base

;;;
;;; GPU Gl Fixtures
;;;

;; Provides shared inputs and drawing fixtures for independently owned OpenGL textures and
;; framebuffer fixtures.
;; Regression suites and diagnostic programs import these fixtures to compare behavior using
;; consistent inputs.

;;;
;;; Imports and Exports
;;;

(require ffi/unsafe racket/list "../gpu.rkt" "../gpu-gl-interop.rkt"
         "../private/gpu-gl-queries.rkt" "../private/gpu-context.rkt"
         (submod "../private/gpu-domain.rkt" gl-interop-internals))
(provide make-gl-fixture delete-gl-fixture! gl-fixture-pixels gl-fixture-fill!
         gl-fixture-alive? gl-pattern-bytes (struct-out gl-fixture))

;;;
;;; GL Resource Allocation and Ownership
;;;

(struct gl-fixture (context queries texture framebuffer stencil width height [closed? #:mutable]))
;; context: borrowed GPU context; it must outlive every GL object in this fixture.
;; queries: GL query/binding bundle resolved for that context's native domain.
;; texture: owned nonzero GL texture name containing the RGBA test pattern.
;; framebuffer: owned nonzero GL framebuffer name with the texture attached.
;; stencil: owned packed depth/stencil renderbuffer attached to the framebuffer.
;; width, height: positive pixel dimensions shared by all three GL objects.
;; closed?: mutable boolean preventing repeated deletion. Deletion runs with the
;; context current and retires framebuffer, renderbuffer, then texture; the
;; record does not close the borrowed context.

; gl-pattern-bytes : exact-positive-integer? exact-positive-integer? -> bytes?
;   Builds four opaque colored quadrants in row-major RGBA storage.
(define (gl-pattern-bytes w h)
  (apply bytes
    (for*/list ([y (in-range h)] [x (in-range w)] [k (in-range 4)])
      (list-ref (cond [(< y (quotient h 2)) (if (< x (quotient w 2)) '(255 0 0 255) '(0 255 0 255))]
                     [else (if (< x (quotient w 2)) '(0 0 255 255) '(255 255 0 255))]) k))))

; raw-bind : gl-fixture? string? ctype? -> procedure?
;   Resolves a GL entry point through the fixture's context-specific binding bundle.
(define (raw-bind fixture name type) ((gl-queries-bind (gl-fixture-queries fixture)) name type))

; make-gl-fixture : gpu-context? [exact-positive-integer? exact-positive-integer?] -> gl-fixture?
;   Allocates a texture, framebuffer, and depth/stencil attachment, cleaning partial construction
;   on failure.
(define (make-gl-fixture context [w 8] [h 8])
  (define queries (make-gl-queries (domain-gl-resolver (context-domain 'test context))))
  (define bind (gl-queries-bind queries))
  (define (gen name)
    (define p (malloc _uint32 'atomic)) (ptr-set! p _uint32 0)
    ((bind name (_fun _int _pointer -> _void)) 1 p) (ptr-ref p _uint32))
  (define fixture #f)
  (call-with-gpu-external-gl context
    (lambda ()
      (define tex 0) (define fbo 0) (define rb 0) (define success? #f)
      (dynamic-wind void
        (lambda ()
          (set! tex (gen "glGenTextures"))
          (set! fbo (gen "glGenFramebuffers"))
          (set! rb (gen "glGenRenderbuffers"))
          (set! fixture (gl-fixture context queries tex fbo rb w h #f))
          ((bind "glActiveTexture" (_fun _uint32 -> _void)) #x84C0)
          ((bind "glBindTexture" (_fun _uint32 _uint32 -> _void)) #x0DE1 tex)
          ((bind "glTexParameteri" (_fun _uint32 _uint32 _int -> _void)) #x0DE1 #x2801 #x2600)
          ((bind "glTexParameteri" (_fun _uint32 _uint32 _int -> _void)) #x0DE1 #x2800 #x2600)
          ((bind "glBindBuffer" (_fun _uint32 _uint32 -> _void)) #x88EC 0)
          (for ([pair (in-list '((#x0CF5 1) (#x0CF2 0) (#x0CF3 0) (#x0CF4 0)))])
            ((bind "glPixelStorei" (_fun _uint32 _int -> _void)) (car pair) (cadr pair)))
          (define pixels (gl-pattern-bytes w h))
          ((bind "glTexImage2D"
             (_fun _uint32 _int _int _int _int _int _uint32 _uint32 _bytes -> _void))
           #x0DE1 0 #x8058 w h 0 #x1908 #x1401 pixels)
          ((bind "glBindRenderbuffer" (_fun _uint32 _uint32 -> _void)) #x8D41 rb)
          ((bind "glRenderbufferStorage" (_fun _uint32 _uint32 _int _int -> _void)) #x8D41 #x88F0 w h)
          ((bind "glBindFramebuffer" (_fun _uint32 _uint32 -> _void)) #x8D40 fbo)
          ((bind "glFramebufferTexture2D" (_fun _uint32 _uint32 _uint32 _uint32 _int -> _void))
           #x8D40 #x8CE0 #x0DE1 tex 0)
          ((bind "glFramebufferRenderbuffer" (_fun _uint32 _uint32 _uint32 _uint32 -> _void))
           #x8D40 #x821A #x8D41 rb)
          ((bind "glDrawBuffer" (_fun _uint32 -> _void)) #x8CE0)
          ((bind "glReadBuffer" (_fun _uint32 -> _void)) #x8CE0)
          ((gl-queries-framebuffer queries) fbo w h)
          (set! success? #t)
          fixture)
        (lambda ()
          (unless success?
            (for
              ([name (in-list '("glDeleteFramebuffers" "glDeleteRenderbuffers" "glDeleteTextures"))]
                  [id (in-list (list fbo rb tex))] #:when (positive? id))
              (define p (malloc _uint32 'atomic)) (ptr-set! p _uint32 id)
              ((bind name (_fun _int _pointer -> _void)) 1 p))))))))

; delete-gl-fixture! : gl-fixture? -> void?
;   Deletes owned GL objects once while their context is active, then marks the fixture closed.
(define (delete-gl-fixture! f)
  (unless (gl-fixture-closed? f)
    (call-with-gpu-external-gl (gl-fixture-context f)
      (lambda ()
        (for ([name (in-list '("glDeleteFramebuffers" "glDeleteRenderbuffers" "glDeleteTextures"))]
              [id
                (in-list (list (gl-fixture-framebuffer f) (gl-fixture-stencil f)
                           (gl-fixture-texture f)))])
          (define p (malloc _uint32 'atomic)) (ptr-set! p _uint32 id)
          ((raw-bind f name (_fun _int _pointer -> _void)) 1 p))
        (set-gl-fixture-closed?! f #t)) #:wait? #t)))

; gl-fixture-alive? : gl-fixture? -> boolean?
;   Checks that texture, framebuffer, and renderbuffer names remain live in their owning context.
(define (gl-fixture-alive? f)
  (call-with-gpu-external-gl (gl-fixture-context f)
    (lambda ()
      (and ((raw-bind f "glIsTexture" (_fun _uint32 -> _stdbool)) (gl-fixture-texture f))
           ((raw-bind f "glIsFramebuffer" (_fun _uint32 -> _stdbool)) (gl-fixture-framebuffer f))
           ((raw-bind f "glIsRenderbuffer" (_fun _uint32 -> _stdbool)) (gl-fixture-stencil f))))))

;;;
;;; Texture Mutation and Readback
;;;

; gl-fixture-fill! : gl-fixture? real? real? real? real? -> any
;   Clears the external framebuffer with explicit color-mask, scissor, and sRGB state.
(define (gl-fixture-fill! f red green blue alpha)
  (call-with-gpu-external-gl (gl-fixture-context f)
    (lambda ()
      ((raw-bind f "glBindFramebuffer" (_fun _uint32 _uint32 -> _void)) #x8D40
        (gl-fixture-framebuffer f))
      ((raw-bind f "glDisable" (_fun _uint32 -> _void)) #x0C11)
      ((raw-bind f "glDisable" (_fun _uint32 -> _void)) #x8DB9)
      ((raw-bind f "glColorMask" (_fun _stdbool _stdbool _stdbool _stdbool -> _void)) #t #t #t #t)
      ((raw-bind f "glClearColor" (_fun _float _float _float _float -> _void)) red green blue alpha)
      ((raw-bind f "glClear" (_fun _uint32 -> _void)) #x4000))))

; gl-fixture-pixels : gl-fixture? -> bytes?
;   Reads tightly packed RGBA bytes with explicit pack state and waits for completion.
(define (gl-fixture-pixels f)
  (call-with-gpu-external-gl (gl-fixture-context f)
    (lambda ()
      ((raw-bind f "glBindFramebuffer" (_fun _uint32 _uint32 -> _void)) #x8CA8
        (gl-fixture-framebuffer f))
      ((raw-bind f "glReadBuffer" (_fun _uint32 -> _void)) #x8CE0)
      ((raw-bind f "glBindBuffer" (_fun _uint32 _uint32 -> _void)) #x88EB 0)
      (for ([pair (in-list '((#x0D05 1) (#x0D02 0) (#x0D03 0) (#x0D04 0)))])
        ((raw-bind f "glPixelStorei" (_fun _uint32 _int -> _void)) (car pair) (cadr pair)))
      (define data (make-bytes (* 4 (gl-fixture-width f) (gl-fixture-height f))))
      ((raw-bind f "glReadPixels" (_fun _int _int _int _int _uint32 _uint32 _bytes -> _void))
       0 0 (gl-fixture-width f) (gl-fixture-height f) #x1908 #x1401 data)
      data) #:wait? #t))

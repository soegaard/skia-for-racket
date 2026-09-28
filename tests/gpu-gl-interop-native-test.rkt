#lang racket/base
(require ffi/unsafe rackunit racket/list
         "../main.rkt" "../gpu.rkt" "../gpu-gl-interop.rkt" "gpu-gl-fixtures.rkt"
         "../private/gpu-gl-queries.rkt" "../private/gpu-io-trace.rkt")
(provide make-gpu-gl-interop-native-tests gpu-gl-interop-native-test-count)
(define gpu-gl-interop-native-test-count 32)
(define (make-gpu-gl-interop-native-tests gpu other)
  (define (fixture proc)
    (call-with-gpu-context gpu
      (lambda ()
        (define f (make-gl-fixture gpu))
        (dynamic-wind void (lambda () (proc f)) (lambda () (delete-gl-fixture! f))))))
  (define (borrow f proc #:wait? [wait? #t])
    (call-with-gpu-gl-framebuffer gpu (gl-fixture-framebuffer f) 8 8 proc #:origin 'top-left #:wait? wait?))
  (define (copy f #:origin [origin 'top-left] #:wait? [wait? #t])
    (gpu-copy-gl-texture gpu (gl-fixture-texture f) 8 8 #:origin origin #:wait? wait?))
  (define blue (apply bytes (apply append (make-list 64 '(0 0 255 255)))))
  (test-suite
   "External GL: borrowed framebuffer, owned texture copy and state handoff"
   (test-case "borrowed target provides an ordinary OpenGL canvas"
     (fixture (lambda (f) (borrow f (lambda (c)
       (check-true (canvas? c)) (check-eq? (canvas-execution-backend c) 'opengl))))))
   (test-case "Skia draws into the actual external color attachment"
     (fixture (lambda (f) (borrow f (lambda (c) (canvas-clear! c 'blue)))
       (check-equal? (gl-fixture-pixels f) blue))))
   (test-case "framebuffer and attachments remain host-owned"
     (fixture (lambda (f) (borrow f (lambda (c) (canvas-clear! c 'blue)))
       (check-true (gl-fixture-alive? f)))))
   (test-case "framebuffer scope preserves multiple return values"
     (fixture (lambda (f)
       (check-equal? (call-with-values (lambda () (borrow f (lambda (_) (values 3 7)))) list) '(3 7)))))
   (test-case "borrowed canvas expires at return inside a surviving outer activation"
     (fixture (lambda (f)
       (define c (borrow f values))
       (check-true (skia-closed? c))
       (check-exn exn:fail? (lambda () (canvas-clear! c 'red))))))
   (test-case "callback exception retires the borrowed surface"
     (fixture (lambda (f)
       (check-exn #rx"intentional" (lambda () (borrow f (lambda (c) (canvas-clear! c 'blue) (error 'test "intentional")))))
       (check-true (gl-fixture-alive? f))
       (check-equal? (hash-ref (gpu-context-info gpu) 'live_children) 0))))
   (test-case "unbalanced canvas state is rejected and cleaned"
     (fixture (lambda (f)
       (check-exn #rx"unbalanced" (lambda () (borrow f (lambda (c) (canvas-save! c)))))
       (check-equal? (hash-ref (gpu-context-info gpu) 'pending_releases) 0))))
   (test-case "nested framebuffer borrows are rejected"
     (fixture (lambda (f) (borrow f (lambda (_) (check-exn #rx"nested" (lambda () (borrow f void))))))))
   (test-case "external native mutation is rejected inside a framebuffer borrow"
     (fixture (lambda (f) (borrow f (lambda (_) (check-exn #rx"nested" (lambda () (call-with-gpu-external-gl gpu void))))))))
   (test-case "default framebuffer zero is not imported"
     (call-with-gpu-context gpu (lambda ()
       (check-exn exn:fail? (lambda () (call-with-gpu-gl-framebuffer gpu 0 8 8 void))))))
   (test-case "wrong declared framebuffer extent is rejected"
     (fixture (lambda (f)
       (check-exn #rx"extent" (lambda () (call-with-gpu-gl-framebuffer gpu (gl-fixture-framebuffer f) 9 8 void))))))
   (test-case "a missing external stencil attachment is not silently allocated"
     (fixture (lambda (f)
       (define bind (gl-queries-bind (gl-fixture-queries f)))
       (call-with-gpu-external-gl gpu (lambda ()
         ((bind "glBindFramebuffer" (_fun _uint32 _uint32 -> _void)) #x8D40 (gl-fixture-framebuffer f))
         ((bind "glFramebufferRenderbuffer" (_fun _uint32 _uint32 _uint32 _uint32 -> _void)) #x8D40 #x821A #x8D41 0)))
       (check-exn #rx"stencil" (lambda () (borrow f void))))))
   (test-case "explicit same-context nonwaiting framebuffer return performs no readback"
     (fixture (lambda (f)
       (define ledger (box '()))
       (parameterize ([current-gpu-io-ledger ledger]) (borrow f (lambda (c) (canvas-clear! c 'blue)) #:wait? #f))
       (check-false (for/or ([e (in-list (unbox ledger))]) (equal? (hash-ref e 'kind) "readback")))
       (check-false (for/or ([e (in-list (unbox ledger))]) (hash-ref e 'wait_requested #f))))))
   (test-case "texture copy yields an ordinary independently owned GPU image"
     (fixture (lambda (f) (with-skia ([im (copy f)])
       (check-true (image? im)) (check-true (gpu-image? im))
       (check-eq? (skia-resource-gpu-context im) gpu)
       (check-true (hash-ref (gpu-image-info im) 'texture_backed))))))
   (test-case "top-left external texture preserves exact asymmetric pixels"
     (fixture (lambda (f) (with-skia ([im (copy f)])
       (check-equal? (gpu-image->rgba-bytes im) (gl-pattern-bytes 8 8))))))
   (test-case "bottom-left external texture flips rows explicitly"
     (fixture (lambda (f) (with-skia ([im (copy f #:origin 'bottom-left)])
       (define pixels (gl-pattern-bytes 8 8))
       (check-equal? (gpu-image->rgba-bytes im)
         (apply bytes-append (for/list ([y (in-range 7 -1 -1)]) (subbytes pixels (* y 32) (* (+ y 1) 32)))))))))
   (test-case "external source mutation does not alter the returned copy"
     (fixture (lambda (f) (with-skia ([im (copy f)])
       (gl-fixture-fill! f 0.0 0.0 1.0 1.0)
       (check-equal? (gpu-image->rgba-bytes im) (gl-pattern-bytes 8 8))))))
   (test-case "external source deletion does not invalidate the returned copy"
     (fixture (lambda (f) (with-skia ([im (copy f)])
       (delete-gl-fixture! f)
       (check-equal? (gpu-image->rgba-bytes im) (gl-pattern-bytes 8 8))))))
   (test-case "retained shader uses the copy after source and original image close"
     (fixture (lambda (f)
       (with-skia ([im (copy f)]
                   [sh (make-image-shader im)] [p (make-paint #:shader sh #:antialias? #f)]
                   [s (make-gpu-surface gpu 8 8)])
         (skia-close! im) (delete-gl-fixture! f)
         (draw-rect (surface-canvas s) 0 0 8 8 p)
         (check-equal? (gpu-surface->rgba-bytes s) (gl-pattern-bytes 8 8))))))
   (test-case "wrong declared texture extent is rejected"
     (fixture (lambda (f)
       (check-exn #rx"extent" (lambda () (gpu-copy-gl-texture gpu (gl-fixture-texture f) 7 8))))))
   (test-case "non-identity swizzle is rejected"
     (fixture (lambda (f)
       (define bind (gl-queries-bind (gl-fixture-queries f)))
       (call-with-gpu-external-gl gpu (lambda ()
         ((bind "glBindTexture" (_fun _uint32 _uint32 -> _void)) #x0DE1 (gl-fixture-texture f))
         ((bind "glTexParameteri" (_fun _uint32 _uint32 _int -> _void)) #x0DE1 #x8E42 #x1905)))
       (check-exn #rx"swizzle" (lambda () (copy f))))))
   (test-case "unsupported sized texture format is rejected before copying"
     (fixture (lambda (f)
       (define bind (gl-queries-bind (gl-fixture-queries f)))
       (call-with-gpu-external-gl gpu (lambda ()
         ((bind "glBindTexture" (_fun _uint32 _uint32 -> _void)) #x0DE1 (gl-fixture-texture f))
         ((bind "glBindBuffer" (_fun _uint32 _uint32 -> _void)) #x88EC 0)
         ((bind "glTexImage2D" (_fun _uint32 _int _int _int _int _int _uint32 _uint32 _pointer -> _void))
          #x0DE1 0 #x8051 8 8 0 #x1907 #x1401 #f)))
       (check-exn #rx"GL_RGBA8" (lambda () (copy f))))))
   (test-case "unpremultiplied alpha is explicitly interpreted on GPU copy"
     (fixture (lambda (f)
       (define bind (gl-queries-bind (gl-fixture-queries f)))
       (define red-alpha (apply bytes (apply append (make-list 64 '(255 0 0 128)))))
       (call-with-gpu-external-gl gpu (lambda ()
         ((bind "glBindTexture" (_fun _uint32 _uint32 -> _void)) #x0DE1 (gl-fixture-texture f))
         ((bind "glBindBuffer" (_fun _uint32 _uint32 -> _void)) #x88EC 0)
         ((bind "glTexSubImage2D" (_fun _uint32 _int _int _int _int _int _uint32 _uint32 _bytes -> _void))
          #x0DE1 0 0 0 8 8 #x1908 #x1401 red-alpha)))
       (with-skia ([im (gpu-copy-gl-texture gpu (gl-fixture-texture f) 8 8
                         #:origin 'top-left #:premultiplied? #f)])
         (check-equal? (gpu-image->rgba-bytes im) red-alpha)))))
   (test-case "deleted texture names are rejected"
     (fixture (lambda (f)
       (define id (gl-fixture-texture f)) (delete-gl-fixture! f)
       (check-exn #rx"live texture" (lambda () (gpu-copy-gl-texture gpu id 8 8))))))
   (test-case "texture copy itself has no CPU readback"
     (fixture (lambda (f)
       (define ledger (box '()))
       (with-skia ([im (parameterize ([current-gpu-io-ledger ledger]) (copy f))])
         (check-false (for/or ([e (in-list (unbox ledger))]) (equal? (hash-ref e 'kind) "readback")))))))
   (test-case "wrong currently active context is rejected"
     (fixture (lambda (f)
       (check-exn exn:fail? (lambda () (gpu-copy-gl-texture other (gl-fixture-texture f) 8 8)))
       (check-exn exn:fail? (lambda () (call-with-gpu-gl-framebuffer other (gl-fixture-framebuffer f) 8 8 void))))))
   (test-case "external callback preserves multiple values"
     (call-with-gpu-context gpu (lambda ()
       (check-equal? (call-with-values (lambda () (call-with-gpu-external-gl gpu (lambda () (values 4 9)))) list) '(4 9)))))
   (test-case "external callback cannot invoke a Skia GPU operation"
     (fixture (lambda (f)
       (check-exn #rx"external OpenGL callback"
         (lambda () (call-with-gpu-external-gl gpu (lambda () (gpu-flush! gpu)))))
       (borrow f (lambda (c) (canvas-clear! c 'blue))))))
   (test-case "alternating host and Skia writes reset cached GL state"
     (fixture (lambda (f)
       (for ([i (in-range 3)])
         (gl-fixture-fill! f 1.0 0.0 0.0 1.0)
         (borrow f (lambda (c) (canvas-clear! c 'blue)))
         (check-equal? (gl-fixture-pixels f) blue)))))
   (test-case "borrow and copy restore the documented external bindings"
     (fixture (lambda (f)
       (define q (gl-fixture-queries f))
       (define (bindings)
         (for/list ([token (in-list '(#x8CA6 #x8CAA #x84E0 #x8069 #x8CA7))])
           ((gl-queries-integer q) token)))
       (define before (bindings))
       (borrow f (lambda (c) (canvas-clear! c 'blue)))
       (check-equal? (bindings) before)
       (with-skia ([im (copy f)]) (check-equal? (bindings) before)))))
   (test-case "texture copy leaves no borrowed descriptor references"
     (fixture (lambda (f)
       (define initial (hash-ref (gpu-context-info gpu) 'live_children))
       (with-skia ([im (copy f)])
         (check-equal? (hash-ref (gpu-context-info gpu) 'live_children) (+ initial 1)))
       (gpu-drain-releases! gpu)
       (check-equal? (hash-ref (gpu-context-info gpu) 'live_children) initial))))
   (test-case "borrowed native targets can be used repeatedly without name deletion"
     (fixture (lambda (f)
       (for ([i (in-range 6)]) (borrow f (lambda (c) (canvas-clear! c 'blue))))
       (check-true (gl-fixture-alive? f))
       (check-equal? (hash-ref (gpu-context-info gpu) 'pending_releases) 0))))))

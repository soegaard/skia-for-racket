#lang racket/base
(require ffi/unsafe "gpu-native.rkt" "gpu-provider.rkt" "gpu-domain.rkt"
         "gpu-types.rkt" (only-in "native.rkt" native-package-version skia-native-version))
(provide run-metal-construction-probe)
;; A construction diagnostic only; general Metal rendering is milestone 0.41.
;; All Objective-C/Metal loading happens inside this explicitly invoked probe.
(define (run-metal-construction-probe)
  (unless (eq? (system-type 'os) 'macosx)
    (gpu-unavailable 'metal-platform "Metal construction probe requires macOS"))
  (gpu-native-check! 'metal)
  (define objc (ffi-lib "/usr/lib/libobjc.A.dylib"))
  (define metal (ffi-lib "/System/Library/Frameworks/Metal.framework/Metal"))
  (define selector (get-ffi-obj "sel_registerName" objc (_fun _string/utf-8 -> _pointer)))
  (define send-pointer (get-ffi-obj "objc_msgSend" objc (_fun _pointer _pointer -> _pointer)))
  (define send-void (get-ffi-obj "objc_msgSend" objc (_fun _pointer _pointer -> _void)))
  (define push-pool (get-ffi-obj "objc_autoreleasePoolPush" objc (_fun -> _pointer)))
  (define pop-pool (get-ffi-obj "objc_autoreleasePoolPop" objc (_fun _pointer -> _void)))
  (define default-device (get-ffi-obj "MTLCreateSystemDefaultDevice" metal (_fun -> _pointer)))
  (define sel-release (selector "release"))
  (define sel-queue (selector "newCommandQueue"))
  (define sel-name (selector "name"))
  (define sel-utf8 (selector "UTF8String"))
  (define name "")
  (define provider
    (make-gpu-provider
     #:name 'metal-construction-probe #:backend 'metal #:key (gensym 'metal-queue)
     #:current? (lambda () #t)
     #:call-as-current
     (lambda (thunk)
       (define pool (push-pool))
       (dynamic-wind void thunk (lambda () (pop-pool pool))))))
  (define driver
    (gpu-driver
     (lambda ()
       (define device #f)
       (define queue #f)
       (dynamic-wind
         void
         (lambda ()
           (set! device (default-device))
           (unless device (gpu-unavailable 'metal-device "MTLCreateSystemDefaultDevice returned null"))
           (set! queue (send-pointer device sel-queue))
           (unless queue (gpu-unavailable 'metal-queue "newCommandQueue returned null"))
           (define ns-name (send-pointer device sel-name))
           (define utf8 (and ns-name (send-pointer ns-name sel-utf8)))
           (set! name (if utf8 (string->immutable-string (cast utf8 _pointer _string/utf-8)) "unnamed"))
           ;; SOURCE AUDIT: despite the legacy header's transfer wording,
           ;; GrDirectContext.cpp at 40f75dc calls fDevice.retain(device) and
           ;; fQueue.retain(queue); SkCFObject.h implements these with CFRetain.
           ;; Keep/release our own +1 references on BOTH success and null/stub
           ;; failure. Do not donate extra retains based on newer examples.
           (define context (gr_direct_context_make_metal device queue))
           (unless context (gpu-unavailable 'metal-ganesh "Ganesh Metal creation returned null"))
           context)
         (lambda ()
           (when queue (send-void queue sel-release))
           (when device (send-void device sel-release)))))
     gr_recording_context_unref gr_direct_context_abandon_context
     (lambda (_) (void))
     (lambda (context)
       (unless (= (gr_recording_context_get_backend context) gr-metal)
         (error 'metal-probe "native context did not select the Metal backend"))
       (hasheq 'device name 'binding_package native-package-version
               'native_version (skia-native-version) 'native_backend gr-metal
               'max_texture_size (gr_recording_context_max_texture_size context)
               'max_render_target_size (gr_recording_context_max_render_target_size context)
               'ownership_contract "pinned implementation retains both borrowed arguments"
               'construction_only #t 'rendering_verified #f))))
  (define domain (make-gpu-domain provider driver))
  (dynamic-wind
    void
    (lambda () (domain-info domain))
    (lambda () (domain-close! domain)))
  (domain-info domain))

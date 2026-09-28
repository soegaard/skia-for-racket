#lang racket/base
(require ffi/unsafe "gpu-provider.rkt" "gpu-metal-util.rkt"
         "gpu-native-scope.rkt" "gpu-diagnostics.rkt")
(provide load-metal-platform)

;; No Objective-C/framework access at module instantiation or compilation.
;; There is no AppKit, MTKView, CAMetalLayer, GL context or window in this path.
(define (load-metal-platform)
  (unless (and (eq? (system-type 'os) 'macosx)
               (memq (system-type 'arch) '(aarch64 x86_64))
               (= (ctype-sizeof _pointer) 8))
    (gpu-unavailable 'metal-platform "owned Metal contexts require 64-bit macOS Racket"))
  (with-handlers ([exn:fail?
                   (lambda (e) (gpu-unavailable 'metal-framework "Metal/Objective-C initialization: ~a" (exn-message e)))])
    (define objc (ffi-lib "/usr/lib/libobjc.A.dylib"))
    (define metal (ffi-lib "/System/Library/Frameworks/Metal.framework/Metal"))
    (define selector (get-ffi-obj "sel_registerName" objc (_fun _string/utf-8 -> _pointer)))
    (define send-pointer (get-ffi-obj "objc_msgSend" objc (_fun _pointer _pointer -> _pointer)))
    (define send-void (get-ffi-obj "objc_msgSend" objc (_fun _pointer _pointer -> _void)))
    (define push-pool (get-ffi-obj "objc_autoreleasePoolPush" objc (_fun -> _pointer)))
    (define pop-pool (get-ffi-obj "objc_autoreleasePoolPop" objc (_fun _pointer -> _void)))
    (define default-device (get-ffi-obj "MTLCreateSystemDefaultDevice" metal (_fun -> _pointer)))
    ;; Resolve all callouts/selectors before allocating any owned native object.
    (define release-selector (selector "release"))
    (define queue-selector (selector "newCommandQueue"))
    (define name-selector (selector "name"))
    (define utf8-selector (selector "UTF8String"))
    (define scope
      (make-gpu-native-scope
       (lambda () (or (push-pool) (error 'metal-native-scope "autorelease pool creation returned null")))
       pop-pool))
    (metal-platform-ops
     scope default-device
     (lambda (device) (send-pointer device queue-selector))
     (lambda (object) (send-void object release-selector))
     (lambda (device)
       (define name-object (send-pointer device name-selector))
       (define utf8 (and name-object (send-pointer name-object utf8-selector)))
       (define name (if utf8 (string->immutable-string (cast utf8 _pointer _string/utf-8)) "unnamed Metal device"))
       (hasheq 'device name 'renderer name 'vendor "Apple Metal API"
               'renderer_class (renderer-class "" name)
               'renderer_class_evidence "MTLDevice name; not an independent hardware attestation"
               'api_version "Metal (Ganesh m119)" 'shading_language_version #f
               'owns_command_queue #t 'requires_gl_context #f 'requires_window #f
               'presentation_tested #f 'headless #t
               'autorelease_scope "per-native-call; not across application callbacks"
               'ownership_contract "pinned implementation retains both borrowed arguments")))))

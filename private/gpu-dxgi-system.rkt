#lang racket/base
;; Private Win64 DXGI/D3D12 operations. No Skia C++ objects, C++ layouts, global
;; window procedure, native helper DLL, or application callback is installed.
(require ffi/unsafe racket/promise racket/future
         "gpu-d3d12-types.rkt" "gpu-dxgi-types.rkt" "gpu-dxgi-util.rkt"
         "gpu-provider.rkt"
         (submod "gpu-d3d12-system.rkt" dxgi-internals))
(provide make-dxgi-host dxgi-host-acquire! dxgi-host-finish! dxgi-host-close!
         dxgi-host-info dxgi-client-size dxgi-token-resource dxgi-token-index
         dxgi-token-generation dxgi-host-pointer)
(struct dxgi-token (host resource index generation [live? #:mutable]))
(struct dxgi-host
  (device queue hwnd owner sync
   [swap #:mutable] [fence #:mutable] [event #:mutable]
   buffers allocators lists fences
   [width #:mutable] [height #:mutable] [generation #:mutable]
   [serial #:mutable] [active #:mutable] [closed? #:mutable] [broken #:mutable]
   [occluded? #:mutable] [acquired #:mutable] [submitted #:mutable] [occluded #:mutable]
   [cancelled #:mutable] [resizes #:mutable] [waits #:mutable]
   [captures #:mutable] [last #:mutable] [readback #:mutable]))
(define win-api
  (delay/sync
    (define user (ffi-lib "user32"))
    (define kernel (ffi-lib "kernel32"))
    (define dxgi (ffi-lib "dxgi"))
    (hasheq
     'rect (get-ffi-obj "GetClientRect" user (_fun _pointer _pointer -> _int32))
     'create (get-ffi-obj "CreateDXGIFactory1" dxgi (_fun _bytes _pointer -> _int32))
     'event (get-ffi-obj "CreateEventW" kernel (_fun _pointer _int32 _int32 _pointer -> _pointer))
     'close (get-ffi-obj "CloseHandle" kernel (_fun _pointer -> _int32))
     ;; Only native handles cross this blocking call. No event-loop pumping or
     ;; Racket callback can reenter a half-retired swap chain during a fence wait.
     'wait (get-ffi-obj "WaitForSingleObject" kernel
                      (_fun #:blocking? #t _pointer _uint32 -> _uint32)))))
(define (platform!)
  (unless (and (eq? (system-type 'os) 'windows) (eq? (system-type 'arch) 'x86_64))
    (gpu-unavailable 'dxgi-platform "DXGI presentation requires Windows x64"))
  (check-dxgi-layouts!)
  (force win-api))
(define (api key) (hash-ref (force win-api) key))
(define (owner! h)
  (unless (and (eq? (current-thread) (dxgi-host-owner h)) (not (current-future)))
    (error 'direct3d-presentation "DXGI operations require the owning eventspace handler")))
(define (open! h)
  (owner! h)
  (when (dxgi-host-closed? h) (error 'direct3d-presentation "swap chain is closed"))
  (when (dxgi-host-broken h)
    (error 'direct3d-presentation "indeterminate DXGI resources quarantined: ~a" (dxgi-host-broken h))))
(define (checked step hr)
  (unless (zero? hr)
    (error 'direct3d-presentation "~a failed: HRESULT 0x~a" step
           (number->string (bitwise-and hr #xffffffff) 16))))
(define (quarantine! h e)
  (set-dxgi-host-broken! h (if (exn? e) (exn-message e) (format "~s" e))))
(define (device! h)
  (define hr ((method (dxgi-host-device h) device-removed-reason-slot
                      (_fun _pointer -> _int32)) (dxgi-host-device h)))
  (checked 'GetDeviceRemovedReason hr))
(define (dxgi-client-size hwnd)
  (platform!)
  (raw 16
    (lambda (p)
      (when (zero? ((api 'rect) hwnd p)) (error 'direct3d-presentation "GetClientRect failed"))
      (values (- (ptr-ref p _int32 2) (ptr-ref p _int32 0))
              (- (ptr-ref p _int32 3) (ptr-ref p _int32 1))))))
(define (dxgi-host-pointer h)
  ;; The borrowed device is only a non-null domain-resource token. The host
  ;; destructor does not Release it; the owning context driver retains it.
  (dxgi-host-device h))
(define (release-vector! v)
  (for ([i (in-range (vector-length v))])
    (define p (vector-ref v i))
    (when p (vector-set! v i #f) (release p))))
(define (release-buffers! h)
  ;; Command lists can retain indirect buffer references. Release them first.
  (release-vector! (dxgi-host-lists h))
  (release-vector! (dxgi-host-allocators h))
  (release-vector! (dxgi-host-buffers h)))
(define (completed h)
  (define value ((method (dxgi-host-fence h) fence-completed-slot
                         (_fun _pointer -> _uint64)) (dxgi-host-fence h)))
  (dxgi-fence-completed! value 0) ; UINT64_MAX is device loss, not completion.
  value)
(define (wait! h value reason)
  (unless (dxgi-fence-completed! (completed h) value)
    (device! h)
    (checked 'SetEventOnCompletion
      ((method (dxgi-host-fence h) fence-event-slot
               (_fun _pointer _uint64 _pointer -> _int32))
       (dxgi-host-fence h) value (dxgi-host-event h)))
    (define status ((api 'wait) (dxgi-host-event h) dxgi-wait-milliseconds))
    (unless (and (zero? status) (dxgi-fence-completed! (completed h) value))
      (error 'direct3d-presentation "~a fence wait failed/timed out (status ~a); retain native references" reason status))
    (set-dxgi-host-waits! h (add1 (dxgi-host-waits h)))))
(define (signal! h index)
  (define value (dxgi-next-fence (dxgi-host-serial h)))
  (checked 'Signal
    ((method (dxgi-host-queue h) queue-signal-slot
             (_fun _pointer _pointer _uint64 -> _int32))
     (dxgi-host-queue h) (dxgi-host-fence h) value))
  (set-dxgi-host-serial! h value)
  (vector-set! (dxgi-host-fences h) index value)
  value)
(define (make-host/native device queue hwnd sync)
  (platform!) (dxgi-sync-interval! sync)
  (unless (and device queue hwnd) (error 'direct3d-presentation "null native presentation dependency"))
  (define h (dxgi-host device queue hwnd (current-thread) sync #f #f #f
                      (make-vector 2 #f) (make-vector 2 #f) (make-vector 2 #f) (make-vector 2 0)
                      0 0 0 0 #f #f #f #f 0 0 0 0 0 0 0 #f #f))
  (define ok? #f)
  (dynamic-wind void
    (lambda ()
      (set-dxgi-host-fence! h
        (out-interface 'CreateFence
          (lambda (out)
            ((method device device-create-fence-slot
                     (_fun _pointer _uint64 _uint32 _bytes _pointer -> _int32))
             device 0 0 iid-fence out))))
      (set-dxgi-host-event! h ((api 'event) #f 0 0 #f))
      (unless (dxgi-host-event h) (error 'direct3d-presentation "CreateEventW failed"))
      (set! ok? #t) h)
    (lambda ()
      ;; There is no queued work yet. Construction cleanup is owner-side only.
      (unless ok?
        (when (dxgi-host-fence h) (release (dxgi-host-fence h)))
        (when (dxgi-host-event h) ((api 'close) (dxgi-host-event h)))))))
(define (populate-buffers! h)
  (define swap (dxgi-host-swap h))
  (define device (dxgi-host-device h))
  (for ([i (in-range 2)])
    (vector-set! (dxgi-host-buffers h) i
      (out-interface 'GetBuffer
        (lambda (out)
          ((method swap swapchain-get-buffer-slot (_fun _pointer _uint32 _bytes _pointer -> _int32))
           swap i iid-resource out))))
    (define alloc
      (out-interface 'CreateCommandAllocator
        (lambda (out)
          ((method device device-create-allocator-slot (_fun _pointer _int32 _bytes _pointer -> _int32))
           device 0 iid-allocator out))))
    (vector-set! (dxgi-host-allocators h) i alloc)
    (define list
      (out-interface 'CreateCommandList
        (lambda (out)
          ((method device device-create-list-slot
                   (_fun _pointer _uint32 _int32 _pointer _pointer _bytes _pointer -> _int32))
           device 0 0 alloc #f iid-command-list out))))
    (vector-set! (dxgi-host-lists h) i list)
    (checked 'CloseCommandList ((method list list-close-slot (_fun _pointer -> _int32)) list))))
(define (verify-desc! h w height)
  (raw 48
    (lambda (p)
      (checked 'GetDesc1
        ((method (dxgi-host-swap h) swapchain-desc1-slot (_fun _pointer _pointer -> _int32))
         (dxgi-host-swap h) p))
      (define d (cast p _pointer _dxgi-swap-desc-pointer))
      (unless (and (= (dxgi-swap-desc-width d) w) (= (dxgi-swap-desc-height d) height)
                   (= (dxgi-swap-desc-format d) dxgi-format-rgba8)
                   (= (dxgi-swap-desc-samples d) 1) (= (dxgi-swap-desc-quality d) 0)
                   (= (dxgi-swap-desc-buffers d) 2) (= (dxgi-swap-desc-effect d) dxgi-flip-discard)
                   (= (dxgi-swap-desc-stereo d) 0) (= (dxgi-swap-desc-flags d) 0)
                   (= (dxgi-swap-desc-alpha d) dxgi-alpha-ignore))
        (error 'direct3d-presentation "DXGI returned an unexpected swap-chain format or extent")))))
(define (create-swap! h w height)
  (define factory (out-interface 'CreateDXGIFactory1 (lambda (out) ((api 'create) iid-factory4 out))))
  (define initial #f)
  (dynamic-wind void
    (lambda ()
      (checked 'MakeWindowAssociation
        ((method factory factory-window-association-slot (_fun _pointer _pointer _uint32 -> _int32))
         factory (dxgi-host-hwnd h) 3)) ; no automatic window changes or Alt-Enter
      (define desc (make-dxgi-swap-desc w height dxgi-format-rgba8 0 1 0
                                     dxgi-render-target-usage 2 0 dxgi-flip-discard dxgi-alpha-ignore 0))
      (set! initial
        (out-interface 'CreateSwapChainForHwnd
          (lambda (out)
            ((method factory factory-create-hwnd-slot
                     (_fun _pointer _pointer _pointer _dxgi-swap-desc-pointer _pointer _pointer _pointer -> _int32))
             factory (dxgi-host-queue h) (dxgi-host-hwnd h) desc #f #f out))))
      (set-dxgi-host-swap! h
        (out-interface 'QuerySwapChain3
          (lambda (out)
            ((method initial 0 (_fun _pointer _bytes _pointer -> _int32)) initial iid-swapchain3 out)))))
    (lambda () (when initial (release initial)) (release factory)))
  (verify-desc! h w height)
  (populate-buffers! h)
  (set-dxgi-host-width! h w) (set-dxgi-host-height! h height)
  (set-dxgi-host-generation! h 1))
(define (resize! h w height retire-skia)
  (call-with-dxgi-retirement
    (lambda () (wait! h (dxgi-host-serial h) 'resize) (retire-skia))
    (lambda ()
      (release-buffers! h)
      (checked 'ResizeBuffers
        ((method (dxgi-host-swap h) swapchain-resize-slot
                 (_fun _pointer _uint32 _uint32 _uint32 _int32 _uint32 -> _int32))
         (dxgi-host-swap h) 2 w height dxgi-format-rgba8 0))
      (verify-desc! h w height)
      (populate-buffers! h)
      (set-dxgi-host-width! h w) (set-dxgi-host-height! h height)
      (set-dxgi-host-generation! h (add1 (dxgi-host-generation h)))
      (set-dxgi-host-resizes! h (add1 (dxgi-host-resizes h))))
    (lambda (e) (quarantine! h e))))
(define (acquire/native! h w height retire-skia)
  (open! h) (dxgi-extent! w height)
  (when (dxgi-host-active h) (error 'direct3d-presentation "a back buffer is already acquired"))
  (with-handlers ([(lambda (_) #t) (lambda (e) (quarantine! h e) (raise e))])
    (device! h)
    (unless (dxgi-host-swap h) (create-swap! h w height))
    (unless (and (= w (dxgi-host-width h)) (= height (dxgi-host-height h)))
      (resize! h w height retire-skia))
    (when (dxgi-host-occluded? h)
      (define hr ((method (dxgi-host-swap h) swapchain-present-slot
                         (_fun _pointer _uint32 _uint32 -> _int32))
                  (dxgi-host-swap h) 0 dxgi-present-test))
      (set-dxgi-host-occluded?! h (eq? (dxgi-present-result hr) 'occluded)))
    (and (not (dxgi-host-occluded? h))
      (let* ([index (dxgi-buffer-index!
                     ((method (dxgi-host-swap h) swapchain-current-buffer-slot
                              (_fun _pointer -> _uint32)) (dxgi-host-swap h)))]
             [token (dxgi-token h (vector-ref (dxgi-host-buffers h) index)
                                index (dxgi-host-generation h) #t)])
        (wait! h (vector-ref (dxgi-host-fences h) index) 'buffer-reuse)
        (set-dxgi-host-active! h token)
        (set-dxgi-host-acquired! h (add1 (dxgi-host-acquired h)))
        token))))
(define (barrier! list resource before after)
  (define b (make-d3d12-transition 0 0 resource #xffffffff before after))
  ((method list list-barrier-slot (_fun _pointer _uint32 _d3d12-transition-pointer -> _void)) list 1 b))
(define (make-readback h size)
  (define device (dxgi-host-device h))
  (define props (make-d3d12-heap-properties 3 0 0 1 1)) ; READBACK heap
  (define desc (make-d3d12-resource-desc 1 0 size 1 1 1 0 1 0 1 0)) ; row-major BUFFER
  (out-interface 'CreateReadbackResource
    (lambda (out)
      ((method device device-create-resource-slot
               (_fun _pointer _d3d12-heap-properties-pointer _uint32 _d3d12-resource-desc-pointer
                     _uint32 _pointer _bytes _pointer -> _int32))
       device props 0 desc d3d12-state-copy-dest #f iid-resource out))))
(define (copy-readback! h list resource readback pitch)
  (define dest (make-d3d12-copy-location readback 1 0 0 dxgi-format-rgba8
                                       (dxgi-host-width h) (dxgi-host-height h) 1 pitch 0))
  (define src (make-d3d12-copy-location resource 0 0 0 0 0 0 0 0 0))
  ((method list list-copy-texture-slot
           (_fun _pointer _d3d12-copy-location-pointer _uint32 _uint32 _uint32
                 _d3d12-copy-location-pointer _pointer -> _void))
   list dest 0 0 0 src #f))
(define (map-readback h resource pitch)
  (define width (dxgi-host-width h)) (define height (dxgi-host-height h))
  (define range (make-d3d12-range 0 (* pitch height)))
  (raw 8
    (lambda (out)
      (checked 'MapReadback
        ((method resource resource-map-slot (_fun _pointer _uint32 _d3d12-range-pointer _pointer -> _int32))
         resource 0 range out))
      (dynamic-wind void
        (lambda ()
          (define p (ptr-ref out _pointer))
          (unless p (error 'direct3d-presentation "Map returned null"))
          (define result (make-bytes (* 4 width height)))
          (for* ([y (in-range height)] [x (in-range (* 4 width))])
            (bytes-set! result (+ (* y width 4) x) (ptr-ref p _uint8 (+ (* y pitch) x))))
          result)
        (lambda ()
          (define written (make-d3d12-range 0 0))
          ((method resource resource-unmap-slot (_fun _pointer _uint32 _d3d12-range-pointer -> _void))
           resource 0 written))))))
(define (finish/native! h token rendered? present? capture?)
  (open! h)
  (unless (and (eq? token (dxgi-host-active h)) (dxgi-token-live? token)
               (= (dxgi-token-generation token) (dxgi-host-generation h)))
    (error 'direct3d-presentation "stale or foreign DXGI frame"))
  (when (and (or present? capture?) (not rendered?))
    (error 'direct3d-presentation "an unrendered target cannot be presented/captured"))
  (with-handlers ([(lambda (_) #t) (lambda (e) (quarantine! h e) (raise e))])
    (define index (dxgi-token-index token))
    (define resource (dxgi-token-resource token))
    (define pitch (dxgi-row-pitch (dxgi-host-width h)))
    (define value (dxgi-host-serial h))
    (define outcome 'cancelled)
    (define hr #f)
    (define pixels #f)
    (when rendered?
      (define allocator (vector-ref (dxgi-host-allocators h) index))
      (define list (vector-ref (dxgi-host-lists h) index))
      (checked 'ResetCommandAllocator ((method allocator allocator-reset-slot (_fun _pointer -> _int32)) allocator))
      (checked 'ResetCommandList
        ((method list list-reset-slot (_fun _pointer _pointer _pointer -> _int32)) list allocator #f))
      ;; The draw-only Skia target has been flushed/submitted AND its surface
      ;; and descriptor retired by the adapter. Its final access is RENDER_TARGET.
      ;; A fresh PRESENT-state descriptor is created on every subsequent frame.
      ;; No Skia wrapper survives this external resource-state transition.
      (cond
        [capture?
         (define size (* pitch (dxgi-host-height h)))
         (when (> size (* 64 1024 1024)) (error 'direct3d-presentation "validation readback exceeds 64 MiB"))
         (set-dxgi-host-readback! h (make-readback h size))
         (barrier! list resource d3d12-state-render-target d3d12-state-copy-source)
         (copy-readback! h list resource (dxgi-host-readback h) pitch)
         (barrier! list resource d3d12-state-copy-source d3d12-state-present)]
        [else (barrier! list resource d3d12-state-render-target d3d12-state-present)])
      (checked 'CloseCommandList ((method list list-close-slot (_fun _pointer -> _int32)) list))
      (raw 8
        (lambda (lists)
          (ptr-set! lists _pointer list)
          ((method (dxgi-host-queue h) queue-execute-slot (_fun _pointer _uint32 _pointer -> _void))
           (dxgi-host-queue h) 1 lists)))
      (when present?
        (set! hr ((method (dxgi-host-swap h) swapchain-present-slot
                          (_fun _pointer _uint32 _uint32 -> _int32))
                   (dxgi-host-swap h) (dxgi-host-sync h) 0)))
      ;; Signal even when Present returned a failing HRESULT. If signaling itself
      ;; fails, no completion claim is made and every remaining object is rooted.
      (set! value (signal! h index))
      (when present? (set! outcome (dxgi-present-result hr)))
      (when (or capture? (not present?)) (wait! h value (if capture? 'validation-readback 'cancel)))
      (when capture?
        (set! pixels (map-readback h (dxgi-host-readback h) pitch))
        (define rb (dxgi-host-readback h)) (set-dxgi-host-readback! h #f) (release rb)
        (set-dxgi-host-captures! h (add1 (dxgi-host-captures h)))))
    (set-dxgi-host-occluded?! h (eq? outcome 'occluded))
    (case outcome
      [(submitted) (set-dxgi-host-submitted! h (add1 (dxgi-host-submitted h)))]
      [(occluded) (set-dxgi-host-occluded! h (add1 (dxgi-host-occluded h)))]
      [else (set-dxgi-host-cancelled! h (add1 (dxgi-host-cancelled h)))])
    (set-dxgi-token-live?! token #f)
    (set-dxgi-host-active! h #f)
    (define record
      (hasheq 'result (symbol->string outcome) 'hresult hr 'buffer_index index
              'swap_chain_generation (dxgi-host-generation h) 'fence_value value
              'width (dxgi-host-width h) 'height (dxgi-host-height h)
              'format "RGBA8888" 'sample_count 1 'buffer_count 2 'swap_effect "flip-discard"
              'same_queue #t 'skia_wrappers_retired_before_transition #t
              'state_before_transition (if rendered? "render-target" "present")
              'state_at_present "present" 'validation_readback capture?
              'readback_row_pitch (and capture? pitch)
              'visible_pixels_verified #f))
    (set-dxgi-host-last! h record)
    (values outcome pixels record)))
(define (close/native! h)
  (owner! h)
  (unless (dxgi-host-closed? h)
    (open! h)
    (when (dxgi-host-active h) (error 'direct3d-presentation "cannot close an acquired buffer"))
    (call-with-dxgi-retirement
      (lambda () (wait! h (dxgi-host-serial h) 'close))
      (lambda ()
        (release-buffers! h)
        (when (dxgi-host-readback h)
          (define p (dxgi-host-readback h)) (set-dxgi-host-readback! h #f) (release p))
        (when (dxgi-host-swap h)
          (define p (dxgi-host-swap h)) (set-dxgi-host-swap! h #f) (release p))
        (when (dxgi-host-fence h)
          (define p (dxgi-host-fence h)) (set-dxgi-host-fence! h #f) (release p))
        (when (dxgi-host-event h)
          (define p (dxgi-host-event h)) (set-dxgi-host-event! h #f)
          (when (zero? ((api 'close) p)) (error 'direct3d-presentation "CloseHandle failed")))
        (set-dxgi-host-closed?! h #t))
      (lambda (e) (quarantine! h e)))))
(define (dxgi-host-info h)
  (owner! h)
  (hasheq 'state (cond [(dxgi-host-closed? h) "closed"] [(dxgi-host-broken h) "quarantined"] [else "ready"])
          'backend "direct3d" 'window_system "win32-hwnd" 'window_created #t
          'hwnd_ownership "borrowed-racket-gui" 'queue_ownership "context-driver"
          'swap_chain_ownership "presenter" 'buffer_count 2 'format "RGBA8888"
          'swap_effect "flip-discard" 'sync_interval (dxgi-host-sync h)
          'width (dxgi-host-width h) 'height (dxgi-host-height h)
          'swap_chain_generation (dxgi-host-generation h) 'resize_count (dxgi-host-resizes h)
          'frames_acquired (dxgi-host-acquired h) 'presents_submitted (dxgi-host-submitted h)
          'presents_occluded (dxgi-host-occluded h) 'frames_cancelled (dxgi-host-cancelled h)
          'live_drawables (if (dxgi-host-active h) 1 0)
          'live_back_buffers (for/sum ([p (in-vector (dxgi-host-buffers h))]) (if p 1 0))
          'fence_value (dxgi-host-serial h) 'blocking_fence_waits (dxgi-host-waits h)
          'validation_readbacks (dxgi-host-captures h) 'last_submission (dxgi-host-last h)
          'quarantined (and (dxgi-host-broken h) #t)
          'visible_pixels_verified #f 'performance_measured #f))

;; Native transactions contain no application callbacks. Delay asynchronous
;; Racket breaks until owned return values and submission/fence state have
;; been registered. Fence waits remain bounded; user drawing is outside this.
(define (make-dxgi-host device queue hwnd sync)
  (parameterize-break #f (make-host/native device queue hwnd sync)))
(define (dxgi-host-acquire! h w height retire-skia)
  (parameterize-break #f (acquire/native! h w height retire-skia)))
(define (dxgi-host-finish! h token rendered? present? capture?)
  (parameterize-break #f (finish/native! h token rendered? present? capture?)))
(define (dxgi-host-close! h)
  (parameterize-break #f (close/native! h)))

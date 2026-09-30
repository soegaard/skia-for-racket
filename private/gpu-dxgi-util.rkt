#lang racket/base
;; Pure policy: no FFI, window, native library or device initialization.
(provide dxgi-sync-interval! dxgi-extent! dxgi-row-pitch dxgi-present-result
         dxgi-fence-completed! dxgi-next-fence dxgi-buffer-index!
         call-with-dxgi-retirement)
(define (dxgi-sync-interval! n)
  (unless (and (exact-integer? n) (<= 0 n 1))
    (raise-argument-error 'gpu-canvas% "sync interval 0 or 1" n)) n)
(define (dxgi-extent! w h)
  (for ([n (in-list (list w h))])
    (unless (and (exact-positive-integer? n) (<= n 16384))
      (raise-argument-error 'direct3d-presentation "pixel extent in [1, 16384]" n)))
  (void))
(define (dxgi-row-pitch w)
  (dxgi-extent! w 1)
  (* 256 (quotient (+ (* 4 w) 255) 256)))
(define (dxgi-present-result hr)
  (unless (and (exact-integer? hr) (<= (- (expt 2 31)) hr (sub1 (expt 2 31))))
    (raise-argument-error 'direct3d-presentation "signed 32-bit HRESULT" hr))
  (cond [(zero? hr) 'submitted]
        [(= hr #x087a0001) 'occluded]
        [else (error 'direct3d-presentation "Present failed or returned an unreviewed status: 0x~a"
                     (number->string (bitwise-and hr #xffffffff) 16))]))
(define (dxgi-fence-completed! completed required)
  (for ([n (in-list (list completed required))])
    (unless (and (exact-nonnegative-integer? n) (< n #xffffffffffffffff))
      (error 'direct3d-presentation "invalid fence value or removed device: ~e" n)))
  (>= completed required))
(define (dxgi-next-fence previous)
  (unless (and (exact-nonnegative-integer? previous) (< previous #xfffffffffffffffe))
    (error 'direct3d-presentation "fence sequence exhausted or invalid"))
  (add1 previous))
(define (dxgi-buffer-index! index)
  (unless (and (exact-nonnegative-integer? index) (< index 2))
    (error 'direct3d-presentation "invalid swap-chain back-buffer index: ~e" index)) index)
;; Native resources may be destroyed only after completion is established.
;; If wait/retire fails, quarantine roots are retained; never fake a close or
;; destroy potentially in-flight buffers in an exception handler/finalizer.
(define (call-with-dxgi-retirement wait retire quarantine)
  (with-handlers ([(lambda (_) #t) (lambda (e) (quarantine e) (raise e))])
    (wait)
    (retire)))

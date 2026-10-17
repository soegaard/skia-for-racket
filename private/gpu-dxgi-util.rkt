#lang racket/base

;;;
;;; DXGI Presentation Validation
;;;

;; Checks presentation sizes, options, and native integer ranges.
;; Shares pure validation across the Windows presenter and swap-chain system.

;; Pure policy: no FFI, window, native library or device initialization.
(provide dxgi-sync-interval! dxgi-extent! dxgi-row-pitch dxgi-present-result
         dxgi-fence-completed! dxgi-next-fence dxgi-buffer-index!
         call-with-dxgi-retirement)

; dxgi-sync-interval! : exact-integer? -> exact-integer?
;   Restricts presentation synchronization to the reviewed immediate or one-refresh modes.
(define (dxgi-sync-interval! n)
  (unless (and (exact-integer? n) (<= 0 n 1))
    (raise-argument-error 'gpu-canvas% "sync interval 0 or 1" n)) n)

; dxgi-extent! : any/c any/c -> void?
;   Checks positive swap-chain pixel dimensions within the reviewed 16384-pixel limit.
(define (dxgi-extent! w h)
  (for ([n (in-list (list w h))])
    (unless (and (exact-positive-integer? n) (<= n 16384))
      (raise-argument-error 'direct3d-presentation "pixel extent in [1, 16384]" n)))
  (void))

; dxgi-row-pitch : any/c -> any
;   Rounds an RGBA8 scanline up to the 256-byte alignment required by Direct3D readback footprints.
(define (dxgi-row-pitch w)
  (dxgi-extent! w 1)
  (* 256 (quotient (+ (* 4 w) 255) 256)))

; dxgi-present-result : exact-integer? -> symbol?
;   Distinguishes successful submission from occlusion and rejects unreviewed HRESULT statuses.
(define (dxgi-present-result hr)
  (unless (and (exact-integer? hr) (<= (- (expt 2 31)) hr (sub1 (expt 2 31))))
    (raise-argument-error 'direct3d-presentation "signed 32-bit HRESULT" hr))
  (cond [(zero? hr) 'submitted]
        [(= hr #x087a0001) 'occluded]
        [else (error 'direct3d-presentation "Present failed or returned an unreviewed status: 0x~a"
                     (number->string (bitwise-and hr #xffffffff) 16))]))

; dxgi-fence-completed! : any/c any/c -> boolean?
;   Checks completion without accepting the all-ones removed-device sentinel as a valid fence
;   value.
(define (dxgi-fence-completed! completed required)
  (for ([n (in-list (list completed required))])
    (unless (and (exact-nonnegative-integer? n) (< n #xffffffffffffffff))
      (error 'direct3d-presentation "invalid fence value or removed device: ~e" n)))
  (>= completed required))

; dxgi-next-fence : exact-nonnegative-integer? -> any
;   Advances the fence serial while preventing overflow into reserved sentinel values.
(define (dxgi-next-fence previous)
  (unless (and (exact-nonnegative-integer? previous) (< previous #xfffffffffffffffe))
    (error 'direct3d-presentation "fence sequence exhausted or invalid"))
  (add1 previous))

; dxgi-buffer-index! : exact-nonnegative-integer? -> exact-nonnegative-integer?
;   Checks a zero-based index into the two-buffer swap chain.
(define (dxgi-buffer-index! index)
  (unless (and (exact-nonnegative-integer? index) (< index 2))
    (error 'direct3d-presentation "invalid swap-chain back-buffer index: ~e" index)) index)
;; Native resources may be destroyed only after completion is established.
;; If wait/retire fails, quarantine roots are retained; never fake a close or
;; destroy potentially in-flight buffers in an exception handler/finalizer.

; call-with-dxgi-retirement : procedure? procedure? any/c -> any
;   Requires completed GPU work before retirement and quarantines ownership if either step fails.
(define (call-with-dxgi-retirement wait retire quarantine)
  (with-handlers ([(lambda (_) #t) (lambda (e) (quarantine e) (raise e))])
    (wait)
    (retire)))

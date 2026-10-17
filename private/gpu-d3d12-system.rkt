#lang racket/base

;;;
;;; Direct3D Device System
;;;

;; Loads Windows device functions and manages adapter, device, and queue creation.
;; Supplies platform services used by the Direct3D GPU backend.

(require ffi/unsafe racket/promise racket/list
         "gpu-provider.rkt" "gpu-d3d12-types.rkt" "gpu-d3d12-util.rkt")
(provide load-d3d12-platform)
(module* dxgi-internals #f
  (provide method release raw hresult! out-interface))

;; Windows x64 has one calling convention for these C/COM calls. 32-bit and
;; ARM64 hosts are rejected BEFORE either DLL is loaded or a vtable is read.
; method : any/c any/c ctype? -> any
;;   Reads a COM vtable slot and casts it to the explicitly supplied native calling signature.
(define (method object slot type)
  (unless object (error 'direct3d "null COM interface"))
  (cast (ptr-ref (ptr-ref object _pointer) _pointer slot) _fpointer type))
; release : any/c -> void?
;;   Releases one owned COM interface reference through IUnknown's fixed vtable slot.
(define (release object)
  ((method object iunknown-release-slot (_fun _pointer -> _uint32)) object)
  (void))
; raw : any/c any/c -> any
;;   Allocates and frees temporary native output storage around a synchronous COM query.
(define (raw size proc)
  (define p (malloc size 'raw))
  (dynamic-wind void (lambda () (memset p 0 size) (proc p)) (lambda () (free p))))
; hresult! : symbol? any/c -> void?
;;   Converts unsuccessful COM status codes into step-specific backend-availability failures.
(define (hresult! step hr)
  (when (negative? hr)
    (gpu-unavailable step "~a failed with HRESULT 0x~a" step
                     (number->string (bitwise-and hr #xffffffff) 16))))
; out-interface : any/c any/c -> any
;;   Receives a checked COM interface out-parameter and rejects successful calls that returned null.
(define (out-interface step get)
  (raw (ctype-sizeof _pointer)
       (lambda (out)
         (define hr (get out))
         (define p (ptr-ref out _pointer))
         ;; COM specifies null on failure. Defensively release a non-null +1.
         (when (negative? hr)
           (when p (release p))
           (hresult! step hr))
         (unless p (gpu-unavailable step "~a succeeded without returning an interface" step))
         p)))
; dxgi-library : promise?
;;   Loads DXGI lazily so importing platform-independent GPU modules does not load Windows DLLs.
(define dxgi-library (delay/sync (ffi-lib "dxgi")))
; d3d12-library : promise?
;;   Loads the Direct3D 12 DLL only when Windows backend construction is requested.
(define d3d12-library (delay/sync (ffi-lib "d3d12")))
; platform : promise?
;;   Caches the native adapter/device/queue operations after lazy Windows DLL resolution.
(define platform
  (delay/sync
    (define dxgi (force dxgi-library))
    (define d3d12 (force d3d12-library))
    (define create-factory
      (get-ffi-obj "CreateDXGIFactory1" dxgi (_fun _bytes _pointer -> _int32)))
    (define create-device
      (get-ffi-obj "D3D12CreateDevice" d3d12 (_fun _pointer _int32 _bytes _pointer -> _int32)))
    (d3d12-platform-ops
     (lambda (selection index)
       (define factory
         (out-interface 'dxgi-factory (lambda (out) (create-factory iid-factory4 out))))
       (dynamic-wind
         void
         (lambda ()
           (case selection
             [(warp)
              (define enum (method factory factory-enum-warp-slot
                                   (_fun _pointer _bytes _pointer -> _int32)))
              (out-interface 'd3d12-warp-adapter (lambda (out) (enum factory iid-adapter1 out)))]
             [(hardware)
              (define enum (method factory factory-enum-adapters1-slot
                                   (_fun _pointer _uint32 _pointer -> _int32)))
              (out-interface 'd3d12-hardware-adapter (lambda (out) (enum factory index out)))]))
         (lambda () (release factory))))
     (lambda (adapter)
       (out-interface 'd3d12-device
                      (lambda (out) (create-device adapter d3d12-minimum-feature-level iid-device
                        out))))
     (lambda (device)
       (define create (method device device-create-queue-slot
                              (_fun _pointer _pointer _bytes _pointer -> _int32)))
       (raw 16
            (lambda (desc)
              ;; Zero means DIRECT type, NORMAL priority, no flags, single node.
              (out-interface 'd3d12-command-queue
                             (lambda (out) (create device desc iid-queue out))))))
     release
     (lambda (adapter)
       (define get-desc (method adapter adapter-get-desc1-slot
                                (_fun _pointer _pointer -> _int32)))
       (raw 312
            (lambda (buffer)
              (hresult! 'dxgi-adapter-description (get-desc adapter buffer))
              (define desc (cast buffer _pointer _dxgi-adapter-desc1-pointer))
              ;; Bounded UTF-16 array; never follow an untrusted terminator.
              (define units
                (for/list ([i (in-range 128)] #:break (zero? (ptr-ref buffer _uint16 i)))
                  (ptr-ref buffer _uint16 i)))
              (define name
                (list->string
                 (let decode ([rest units])
                   (cond [(null? rest) '()]
                         [(and (<= #xd800 (car rest) #xdbff) (pair? (cdr rest))
                               (<= #xdc00 (cadr rest) #xdfff))
                          (cons (integer->char (+ #x10000 (* #x400 (- (car rest) #xd800))
                                                 (- (cadr rest) #xdc00)))
                                (decode (cddr rest)))]
                         [(<= #xd800 (car rest) #xdfff) (cons #\uFFFD (decode (cdr rest)))]
                         [else (cons (integer->char (car rest)) (decode (cdr rest)))]))))
              (hasheq 'renderer name 'adapter_name name
                      'adapter_flags (dxgi-adapter-desc1-flags desc)
                      'adapter_vendor_id (dxgi-adapter-desc1-vendor desc)
                      'adapter_device_id (dxgi-adapter-desc1-device desc)
                      'adapter_luid_low (dxgi-adapter-desc1-luid-low desc)
                      'adapter_luid_high (dxgi-adapter-desc1-luid-high desc)
                      'minimum_feature_level d3d12-minimum-feature-level
                      'api "D3D12" 'command_queue_type "direct"
                      'command_queue_owned #t))))
     (lambda (device)
       ((method device device-removed-reason-slot (_fun _pointer -> _int32)) device)))))
; load-d3d12-platform : -> any
;;   Returns the checked Windows platform operations, initializing their lazy bindings once.
(define (load-d3d12-platform)
  (unless (and (eq? (system-type 'os) 'windows) (eq? (system-type 'arch) 'x86_64))
    (gpu-unavailable 'd3d12-platform "Direct3D requires Windows x64; no automatic CPU/GL fallback"))
  (check-d3d12-layouts!)
  (force platform))

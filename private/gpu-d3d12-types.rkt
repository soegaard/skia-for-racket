#lang racket/base

;;;
;;; Direct3D Native Layouts
;;;

;; Defines the backend-context, command-queue, and adapter-description C layouts.
;; Keeps Direct3D device setup compatible with the pinned native ABI.

;; Windows x64 layouts only. Importing this file never loads a DLL.
(require ffi/unsafe)
(provide (all-defined-out))
(define-cstruct _gr-d3d-backend-context
  ([adapter _pointer] [device _pointer] [queue _pointer]
   [allocator _pointer] [protected? _stdbool]))
;; Fields:
;;   adapter, device, and queue: retained COM interface pointers. allocator: optional native
;;   allocator pointer. protected?: native protected-context boolean. Pointers must belong to one
;;   compatible device setup and remain live for context creation/use.

(define-cstruct _d3d12-queue-desc
  ([type _int32] [priority _int32] [flags _uint32] [node-mask _uint32]))
;; Fields:
;;   type: command-list type enum. priority: signed queue priority. flags: queue bitmask. node-mask:
;;   device-node selection bitmask. Fields use the Windows SDK order and integer widths.

(define-cstruct _dxgi-adapter-desc1
  ([description (_array _uint16 128)]
   [vendor _uint32] [device _uint32] [subsystem _uint32] [revision _uint32]
   [video-memory _size] [system-memory _size] [shared-memory _size]
   [luid-low _uint32] [luid-high _int32] [flags _uint32]))
;; Fields:
;;   description: fixed array of 128 UTF-16 code units. vendor, device, subsystem, and revision:
;;   unsigned hardware identifiers. video-memory, system-memory, and shared-memory: size_t byte
;;   capacities.
;;   luid-low and luid-high: low unsigned and high signed halves of the adapter LUID. flags: adapter
;;   bitmask. The fixed array and native pointer-size fields determine ABI offsets.


; d3d12-minimum-feature-level : exact-nonnegative-integer?
;;   Encodes d3d12 minimum feature level using the native SDK value rather than a Racket-specific
;;   ordinal.
(define d3d12-minimum-feature-level #xb000) ; D3D_FEATURE_LEVEL_11_0, not a maximum.
; dxgi-adapter-flag-software : exact-nonnegative-integer?
;;   Encodes dxgi adapter flag software using the native SDK value rather than a Racket-specific
;;   ordinal.
(define dxgi-adapter-flag-software 2)
; factory-enum-adapters1-slot : exact-nonnegative-integer?
;;   Selects the factory enum adapters1 COM vtable entry; this index is fixed by the Windows ABI.
(define factory-enum-adapters1-slot 12)
; factory-enum-warp-slot : exact-nonnegative-integer?
;;   Selects the factory enum warp COM vtable entry; this index is fixed by the Windows ABI.
(define factory-enum-warp-slot 27)
; adapter-get-desc1-slot : exact-nonnegative-integer?
;;   Selects the adapter get desc1 COM vtable entry; this index is fixed by the Windows ABI.
(define adapter-get-desc1-slot 10)
; device-create-queue-slot : exact-nonnegative-integer?
;;   Selects the device create queue COM vtable entry; this index is fixed by the Windows ABI.
(define device-create-queue-slot 8)
; device-removed-reason-slot : exact-nonnegative-integer?
;;   Selects the device removed reason COM vtable entry; this index is fixed by the Windows ABI.
(define device-removed-reason-slot 37)
; iunknown-release-slot : exact-nonnegative-integer?
;;   Selects the iunknown release COM vtable entry; this index is fixed by the Windows ABI.
(define iunknown-release-slot 2)

;; Little-endian Windows GUID storage. Check these against the SDK in the
;; Windows C ABI test, not against display-string ordering of the first words.
; iid-factory4 : bytes?
;;   Contains the binary COM interface identifier for factory4, in Windows GUID byte order.
(define iid-factory4 #"\2\352\306\33\66\357\117\106\277\14\41\312\71\345\26\212")
; iid-adapter1 : bytes?
;;   Contains the binary COM interface identifier for adapter1, in Windows GUID byte order.
(define iid-adapter1 #"\141\217\3\51\71\70\46\106\221\375\10\150\171\1\32\5")
; iid-device : bytes?
;;   Contains the binary COM interface identifier for device, in Windows GUID byte order.
(define iid-device #"\361\31\230\30\266\35\127\113\276\124\30\41\63\233\205\367")
; iid-queue : bytes?
;;   Contains the binary COM interface identifier for queue, in Windows GUID byte order.
(define iid-queue #"\246\160\310\16\176\135\42\114\214\374\133\252\340\166\26\355")

; check-d3d12-layouts! : -> void?
;;   Rejects unsupported pointer widths or native structure sizes before Direct3D device creation.
(define (check-d3d12-layouts!)
  (unless (and (= (ctype-sizeof _pointer) 8)
               (= (ctype-sizeof _gr-d3d-backend-context) 40)
               (= (ctype-sizeof _d3d12-queue-desc) 16)
               (= (ctype-sizeof _dxgi-adapter-desc1) 312)
               (= (ctype-sizeof _stdbool) 1))
    (error 'direct3d "unsupported D3D12 layout; this ABI requires 64-bit Windows"))
  (void))

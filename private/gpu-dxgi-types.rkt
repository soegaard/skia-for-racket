#lang racket/base

;;;
;;; DXGI Presentation Layouts
;;;

;; Defines swap-chain, resource, transition, copy, and range records.
;; Supplies exact Windows ABI layouts for Direct3D presentation and readback.

;; Windows x64 PODs. No DLL loads; tools/dxgi-abi checks offsets and COM slots
;; against the Windows SDK, using checks that survive Release/NDEBUG builds.
(require ffi/unsafe)
(provide (all-defined-out))
(define-cstruct _dxgi-swap-desc
  ([width _uint32] [height _uint32] [format _int32] [stereo _int32]
   [samples _uint32] [quality _uint32] [usage _uint32] [buffers _uint32]
   [scaling _int32] [effect _int32] [alpha _int32] [flags _uint32]))
;; Fields:
;;   width and height: unsigned pixel extents. format: DXGI format enum. stereo: Windows BOOL.
;;   samples and quality: sample count and quality. usage: buffer-usage flags. buffers: buffer
;;   count.
;;   scaling, effect, and alpha: presentation/scaling/alpha enums. flags: swap-chain flags. These
;;   fields follow DXGI_SWAP_CHAIN_DESC1 order; stereo is a 32-bit BOOL, not a one-byte C bool.

(define-cstruct _dxgi-client-rect
  ([left _int32] [top _int32] [right _int32] [bottom _int32]))
;; Fields:
;;   left, top, right, and bottom: signed client-area edge coordinates in pixels, in Windows RECT
;;   order. Width and height are edge differences, not stored extents.

(define-cstruct _gr-d3d-texture-info
  ([resource _pointer] [allocation _pointer] [state _uint32] [format _uint32]
   [samples _uint32] [levels _uint32] [quality _uint32] [protected? _stdbool]))
;; Fields:
;;   resource and allocation: native resource and optional allocator handles. state: D3D12
;;   resource-state bitmask. format: DXGI format. samples, levels, and quality: sample count, mip
;;   levels, and sample quality. protected?: C boolean.
;;   The referenced resource outlives its Skia wrapper; native field order matches the pinned Ganesh
;;   texture-info ABI.

(define-cstruct _d3d12-transition
  ([type _int32] [flags _int32] [resource _pointer] [subresource _uint32]
   [before _uint32] [after _uint32]))
;; Fields:
;;   type and flags: barrier enums. resource: borrowed ID3D12Resource pointer. subresource:
;;   subresource index or the all-subresources constant. before and after: old/new resource-state
;;   bitmasks. The wrapper represents the transition arm of the native barrier union.

(define-cstruct _d3d12-heap-properties
  ([type _int32] [cpu-page _int32] [pool _int32] [creation-mask _uint32] [visible-mask _uint32]))
;; Fields:
;;   type, cpu-page, and pool: heap type, CPU page property, and memory-pool enums. creation-mask
;;   and visible-mask: device-node bitmasks. Native declaration order must remain unchanged.

(define-cstruct _d3d12-resource-desc
  ([dimension _int32] [alignment _uint64] [width _uint64] [height _uint32]
   [depth _uint16] [levels _uint16] [format _int32]
   [samples _uint32] [quality _uint32] [layout _int32] [flags _uint32]))
;; Fields:
;;   dimension: resource dimension enum. alignment: byte-alignment request. width: 64-bit extent;
;;   height: 32-bit extent; depth: 16-bit depth/array count. levels: 16-bit mip count.
;;   format: DXGI format. samples and quality: sample description. layout and flags: texture layout
;;   and resource flags. Field widths and padding follow D3D12_RESOURCE_DESC exactly.

;; The trailing union is 32 bytes: a placed footprint, or a subresource index.
(define-cstruct _d3d12-copy-location
  ([resource _pointer] [type _int32] [padding _uint32] [offset _uint64]
   [format _int32] [width _uint32] [height _uint32] [depth _uint32]
   [row-pitch _uint32] [tail-padding _uint32]))
;; Fields:
;;   resource: borrowed resource pointer. type: copy-location discriminator. padding and
;;   tail-padding: explicit ABI padding, not semantic values.
;;   offset: placed-footprint byte offset. format, width, height, and depth: footprint description.
;;   row-pitch: aligned bytes per row. This record represents the placed-footprint arm of the native
;;   union.

(define-cstruct _d3d12-range ([begin _size] [end _size]))
;; Fields:
;;   begin and end: size_t byte offsets describing the half-open [begin,end) mapped-memory range. An
;;   empty range declares no CPU reads/writes as selected by the calling API.


; dxgi-format-rgba8 : exact-nonnegative-integer?
;   Encodes dxgi format rgba8 using the native SDK value rather than a Racket-specific ordinal.
(define dxgi-format-rgba8 28)

; dxgi-flip-discard : exact-nonnegative-integer?
;   Encodes dxgi flip discard using the native SDK value rather than a Racket-specific ordinal.
(define dxgi-flip-discard 4)

; dxgi-render-target-usage : exact-nonnegative-integer?
;   Encodes dxgi render target usage using the native SDK value rather than a Racket-specific
;   ordinal.
(define dxgi-render-target-usage #x20)

; dxgi-alpha-ignore : exact-nonnegative-integer?
;   Encodes dxgi alpha ignore using the native SDK value rather than a Racket-specific ordinal.
(define dxgi-alpha-ignore 3)

; dxgi-buffer-count : exact-nonnegative-integer?
;   Selects two swap-chain buffers; parallel buffer, fence, allocator, and command-list arrays use
;   this count.
(define dxgi-buffer-count 2)

; dxgi-status-occluded : exact-nonnegative-integer?
;   Encodes dxgi status occluded using the native SDK value rather than a Racket-specific ordinal.
(define dxgi-status-occluded #x087a0001)

; dxgi-present-test : exact-nonnegative-integer?
;   Encodes dxgi present test using the native SDK value rather than a Racket-specific ordinal.
(define dxgi-present-test 1)

; d3d12-state-present : exact-nonnegative-integer?
;   Encodes d3d12 state present using the native SDK value rather than a Racket-specific ordinal.
(define d3d12-state-present 0)

; d3d12-state-render-target : exact-nonnegative-integer?
;   Encodes d3d12 state render target using the native SDK value rather than a Racket-specific
;   ordinal.
(define d3d12-state-render-target 4)

; d3d12-state-copy-source : exact-nonnegative-integer?
;   Encodes d3d12 state copy source using the native SDK value rather than a Racket-specific
;   ordinal.
(define d3d12-state-copy-source #x800)

; d3d12-state-copy-dest : exact-nonnegative-integer?
;   Encodes d3d12 state copy dest using the native SDK value rather than a Racket-specific ordinal.
(define d3d12-state-copy-dest #x400)

; dxgi-fence-limit : exact-nonnegative-integer?
;   Bounds unsigned 64-bit fence values before signaling or testing completion.
(define dxgi-fence-limit #xffffffffffffffff) ; also the device-removed sentinel

; dxgi-wait-milliseconds : exact-nonnegative-integer?
;   Bounds native fence waits to five seconds so stalled presentation can report failure.
(define dxgi-wait-milliseconds 5000)

; factory-create-hwnd-slot : exact-nonnegative-integer?
;   Selects the factory create hwnd COM vtable entry; this index is fixed by the Windows ABI.
(define factory-create-hwnd-slot 15)

; factory-window-association-slot : exact-nonnegative-integer?
;   Selects the factory window association COM vtable entry; this index is fixed by the Windows
;   ABI.
(define factory-window-association-slot 8)

; swapchain-present-slot : exact-nonnegative-integer?
;   Selects the swapchain present COM vtable entry; this index is fixed by the Windows ABI.
(define swapchain-present-slot 8)

; swapchain-get-buffer-slot : exact-nonnegative-integer?
;   Selects the swapchain get buffer COM vtable entry; this index is fixed by the Windows ABI.
(define swapchain-get-buffer-slot 9)

; swapchain-resize-slot : exact-nonnegative-integer?
;   Selects the swapchain resize COM vtable entry; this index is fixed by the Windows ABI.
(define swapchain-resize-slot 13)

; swapchain-desc1-slot : exact-nonnegative-integer?
;   Selects the swapchain desc1 COM vtable entry; this index is fixed by the Windows ABI.
(define swapchain-desc1-slot 18)

; swapchain-current-buffer-slot : exact-nonnegative-integer?
;   Selects the swapchain current buffer COM vtable entry; this index is fixed by the Windows ABI.
(define swapchain-current-buffer-slot 36)

; device-create-allocator-slot : exact-nonnegative-integer?
;   Selects the device create allocator COM vtable entry; this index is fixed by the Windows ABI.
(define device-create-allocator-slot 9)

; device-create-list-slot : exact-nonnegative-integer?
;   Selects the device create list COM vtable entry; this index is fixed by the Windows ABI.
(define device-create-list-slot 12)

; device-create-resource-slot : exact-nonnegative-integer?
;   Selects the device create resource COM vtable entry; this index is fixed by the Windows ABI.
(define device-create-resource-slot 27)

; device-create-fence-slot : exact-nonnegative-integer?
;   Selects the device create fence COM vtable entry; this index is fixed by the Windows ABI.
(define device-create-fence-slot 36)

; allocator-reset-slot : exact-nonnegative-integer?
;   Selects the allocator reset COM vtable entry; this index is fixed by the Windows ABI.
(define allocator-reset-slot 8)

; list-close-slot : exact-nonnegative-integer?
;   Selects the list close COM vtable entry; this index is fixed by the Windows ABI.
(define list-close-slot 9)

; list-reset-slot : exact-nonnegative-integer?
;   Selects the list reset COM vtable entry; this index is fixed by the Windows ABI.
(define list-reset-slot 10)

; list-copy-texture-slot : exact-nonnegative-integer?
;   Selects the list copy texture COM vtable entry; this index is fixed by the Windows ABI.
(define list-copy-texture-slot 16)

; list-barrier-slot : exact-nonnegative-integer?
;   Selects the list barrier COM vtable entry; this index is fixed by the Windows ABI.
(define list-barrier-slot 26)

; queue-execute-slot : exact-nonnegative-integer?
;   Selects the queue execute COM vtable entry; this index is fixed by the Windows ABI.
(define queue-execute-slot 10)

; queue-signal-slot : exact-nonnegative-integer?
;   Selects the queue signal COM vtable entry; this index is fixed by the Windows ABI.
(define queue-signal-slot 14)

; fence-completed-slot : exact-nonnegative-integer?
;   Selects the fence completed COM vtable entry; this index is fixed by the Windows ABI.
(define fence-completed-slot 8)

; fence-event-slot : exact-nonnegative-integer?
;   Selects the fence event COM vtable entry; this index is fixed by the Windows ABI.
(define fence-event-slot 9)

; resource-map-slot : exact-nonnegative-integer?
;   Selects the resource map COM vtable entry; this index is fixed by the Windows ABI.
(define resource-map-slot 8)

; resource-unmap-slot : exact-nonnegative-integer?
;   Selects the resource unmap COM vtable entry; this index is fixed by the Windows ABI.
(define resource-unmap-slot 9)

; dxgi-layout-sizes : -> hash?
;   Reports the FFI record sizes used by the reviewed Windows presentation ABI.
(define (dxgi-layout-sizes)
  (hasheq 'swap_desc (ctype-sizeof _dxgi-swap-desc)
          'rect (ctype-sizeof _dxgi-client-rect)
          'texture_info (ctype-sizeof _gr-d3d-texture-info)
          'transition (ctype-sizeof _d3d12-transition)
          'heap_properties (ctype-sizeof _d3d12-heap-properties)
          'resource_desc (ctype-sizeof _d3d12-resource-desc)
          'copy_location (ctype-sizeof _d3d12-copy-location)
          'range (ctype-sizeof _d3d12-range)))

; check-dxgi-layouts! : -> void?
;   Checks native record sizes and platform widths before any swap-chain or readback call.
(define (check-dxgi-layouts!)
  (unless (and (= (ctype-sizeof _pointer) 8)
               (equal? (dxgi-layout-sizes)
                 (hasheq 'swap_desc 48 'rect 16 'texture_info 40 'transition 32
                         'heap_properties 20 'resource_desc 56 'copy_location 48 'range 16)))
    (error 'direct3d-presentation "unsupported DXGI layout; Windows x64 is required")))

;; GUIDs in little-endian Windows memory order, checked by guid.cpp.

; iid-swapchain3 : bytes?
;   Contains the binary COM interface identifier for swapchain3, in Windows GUID byte order.
(define iid-swapchain3 #"\333\233\331\224\370\361\260\112\262\066\175\240\027\016\332\261")

; iid-resource : bytes?
;   Contains the binary COM interface identifier for resource, in Windows GUID byte order.
(define iid-resource #"\276\102\144\151\056\247\131\100\274\171\133\134\230\004\017\255")

; iid-allocator : bytes?
;   Contains the binary COM interface identifier for allocator, in Windows GUID byte order.
(define iid-allocator #"\344\336\002\141\131\257\011\113\271\231\264\115\163\360\233\044")

; iid-command-list : bytes?
;   Contains the binary COM interface identifier for command list, in Windows GUID byte order.
(define iid-command-list #"\017\015\026\133\033\254\205\101\213\250\263\256\102\245\244\125")

; iid-fence : bytes?
;   Contains the binary COM interface identifier for fence, in Windows GUID byte order.
(define iid-fence #"\317\075\165\012\330\304\221\113\255\366\276\132\140\331\132\166")

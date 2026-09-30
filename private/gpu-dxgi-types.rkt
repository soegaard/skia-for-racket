#lang racket/base
;; Windows x64 PODs. No DLL loads; tools/dxgi-abi checks offsets and COM slots
;; against the Windows SDK, using checks that survive Release/NDEBUG builds.
(require ffi/unsafe)
(provide (all-defined-out))
(define-cstruct _dxgi-swap-desc
  ([width _uint32] [height _uint32] [format _int32] [stereo _int32]
   [samples _uint32] [quality _uint32] [usage _uint32] [buffers _uint32]
   [scaling _int32] [effect _int32] [alpha _int32] [flags _uint32]))
(define-cstruct _dxgi-client-rect
  ([left _int32] [top _int32] [right _int32] [bottom _int32]))
(define-cstruct _gr-d3d-texture-info
  ([resource _pointer] [allocation _pointer] [state _uint32] [format _uint32]
   [samples _uint32] [levels _uint32] [quality _uint32] [protected? _stdbool]))
(define-cstruct _d3d12-transition
  ([type _int32] [flags _int32] [resource _pointer] [subresource _uint32]
   [before _uint32] [after _uint32]))
(define-cstruct _d3d12-heap-properties
  ([type _int32] [cpu-page _int32] [pool _int32] [creation-mask _uint32] [visible-mask _uint32]))
(define-cstruct _d3d12-resource-desc
  ([dimension _int32] [alignment _uint64] [width _uint64] [height _uint32]
   [depth _uint16] [levels _uint16] [format _int32]
   [samples _uint32] [quality _uint32] [layout _int32] [flags _uint32]))
;; The trailing union is 32 bytes: a placed footprint, or a subresource index.
(define-cstruct _d3d12-copy-location
  ([resource _pointer] [type _int32] [padding _uint32] [offset _uint64]
   [format _int32] [width _uint32] [height _uint32] [depth _uint32]
   [row-pitch _uint32] [tail-padding _uint32]))
(define-cstruct _d3d12-range ([begin _size] [end _size]))

(define dxgi-format-rgba8 28)
(define dxgi-flip-discard 4)
(define dxgi-render-target-usage #x20)
(define dxgi-alpha-ignore 3)
(define dxgi-buffer-count 2)
(define dxgi-status-occluded #x087a0001)
(define dxgi-present-test 1)
(define d3d12-state-present 0)
(define d3d12-state-render-target 4)
(define d3d12-state-copy-source #x800)
(define d3d12-state-copy-dest #x400)
(define dxgi-fence-limit #xffffffffffffffff) ; also the device-removed sentinel
(define dxgi-wait-milliseconds 5000)

(define factory-create-hwnd-slot 15)
(define factory-window-association-slot 8)
(define swapchain-present-slot 8)
(define swapchain-get-buffer-slot 9)
(define swapchain-resize-slot 13)
(define swapchain-desc1-slot 18)
(define swapchain-current-buffer-slot 36)
(define device-create-allocator-slot 9)
(define device-create-list-slot 12)
(define device-create-resource-slot 27)
(define device-create-fence-slot 36)
(define allocator-reset-slot 8)
(define list-close-slot 9)
(define list-reset-slot 10)
(define list-copy-texture-slot 16)
(define list-barrier-slot 26)
(define queue-execute-slot 10)
(define queue-signal-slot 14)
(define fence-completed-slot 8)
(define fence-event-slot 9)
(define resource-map-slot 8)
(define resource-unmap-slot 9)

(define (dxgi-layout-sizes)
  (hasheq 'swap_desc (ctype-sizeof _dxgi-swap-desc)
          'rect (ctype-sizeof _dxgi-client-rect)
          'texture_info (ctype-sizeof _gr-d3d-texture-info)
          'transition (ctype-sizeof _d3d12-transition)
          'heap_properties (ctype-sizeof _d3d12-heap-properties)
          'resource_desc (ctype-sizeof _d3d12-resource-desc)
          'copy_location (ctype-sizeof _d3d12-copy-location)
          'range (ctype-sizeof _d3d12-range)))
(define (check-dxgi-layouts!)
  (unless (and (= (ctype-sizeof _pointer) 8)
               (equal? (dxgi-layout-sizes)
                 (hasheq 'swap_desc 48 'rect 16 'texture_info 40 'transition 32
                         'heap_properties 20 'resource_desc 56 'copy_location 48 'range 16)))
    (error 'direct3d-presentation "unsupported DXGI layout; Windows x64 is required")))

;; GUIDs in little-endian Windows memory order, checked by guid.cpp.
(define iid-swapchain3 #"\333\233\331\224\370\361\260\112\262\066\175\240\027\016\332\261")
(define iid-resource #"\276\102\144\151\056\247\131\100\274\171\133\134\230\004\017\255")
(define iid-allocator #"\344\336\002\141\131\257\011\113\271\231\264\115\163\360\233\044")
(define iid-command-list #"\017\015\026\133\033\254\205\101\213\250\263\256\102\245\244\125")
(define iid-fence #"\317\075\165\012\330\304\221\113\255\366\276\132\140\331\132\166")

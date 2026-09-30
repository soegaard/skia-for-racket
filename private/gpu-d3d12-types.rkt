#lang racket/base
;; Windows x64 layouts only. Importing this file never loads a DLL.
(require ffi/unsafe)
(provide (all-defined-out))
(define-cstruct _gr-d3d-backend-context
  ([adapter _pointer] [device _pointer] [queue _pointer]
   [allocator _pointer] [protected? _stdbool]))
(define-cstruct _d3d12-queue-desc
  ([type _int32] [priority _int32] [flags _uint32] [node-mask _uint32]))
(define-cstruct _dxgi-adapter-desc1
  ([description (_array _uint16 128)]
   [vendor _uint32] [device _uint32] [subsystem _uint32] [revision _uint32]
   [video-memory _size] [system-memory _size] [shared-memory _size]
   [luid-low _uint32] [luid-high _int32] [flags _uint32]))

(define d3d12-minimum-feature-level #xb000) ; D3D_FEATURE_LEVEL_11_0, not a maximum.
(define dxgi-adapter-flag-software 2)
(define factory-enum-adapters1-slot 12)
(define factory-enum-warp-slot 27)
(define adapter-get-desc1-slot 10)
(define device-create-queue-slot 8)
(define device-removed-reason-slot 37)
(define iunknown-release-slot 2)

;; Little-endian Windows GUID storage. Check these against the SDK in the
;; Windows C ABI test, not against display-string ordering of the first words.
(define iid-factory4 #"\2\352\306\33\66\357\117\106\277\14\41\312\71\345\26\212")
(define iid-adapter1 #"\141\217\3\51\71\70\46\106\221\375\10\150\171\1\32\5")
(define iid-device #"\361\31\230\30\266\35\127\113\276\124\30\41\63\233\205\367")
(define iid-queue #"\246\160\310\16\176\135\42\114\214\374\133\252\340\166\26\355")

(define (check-d3d12-layouts!)
  (unless (and (= (ctype-sizeof _pointer) 8)
               (= (ctype-sizeof _gr-d3d-backend-context) 40)
               (= (ctype-sizeof _d3d12-queue-desc) 16)
               (= (ctype-sizeof _dxgi-adapter-desc1) 312)
               (= (ctype-sizeof _stdbool) 1))
    (error 'direct3d "unsupported D3D12 layout; this ABI requires 64-bit Windows"))
  (void))

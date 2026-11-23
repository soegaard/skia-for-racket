#lang racket/base

;;;
;;; Native Stream Resources
;;;

;; Defines the owned native stream wrapper and its storage-kind metadata.
;; Shares stream lifetime data between core resources and stream operations.

;; Opaque resource metadata. Only core.rkt and streams.rkt import this bridge;
;; native handles and constructors are not exported by the public facade.
(provide native-stream? native-stream-handle native-stream-direction
         native-stream-storage native-stream-limit make-native-stream)
(struct native-stream (handle direction storage limit)
  #:constructor-name make-native-stream)
;; Fields:
;;   handle: owned native stream lifetime cell. direction: 'input or 'output, determining the
;;   permitted operations. storage: 'memory or 'file, describing the native backing rather than
;;   retaining a Racket byte string; memory-only snapshot operations check this tag.
;;   limit: positive byte budget, no greater than the native signed-int maximum. The effective
;;   operation budget also respects the current-skia-byte-limit parameter.

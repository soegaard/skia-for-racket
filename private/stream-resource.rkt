#lang racket/base
;; Opaque resource metadata. Only core.rkt and streams.rkt import this bridge;
;; native handles and constructors are not exported by the public facade.
(provide native-stream? native-stream-handle native-stream-direction
         native-stream-storage native-stream-limit make-native-stream)
(struct native-stream (handle direction storage limit)
  #:constructor-name make-native-stream)

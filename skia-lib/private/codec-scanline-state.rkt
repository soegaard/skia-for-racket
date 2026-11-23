#lang racket/base

;;;
;;; Scanline Decoder State
;;;

;; Defines the owned session record used while decoding image rows.
;; Shares scanline lifecycle bookkeeping with the core resource layer.

;; Pure resource bridge. Core sees only the predicate and owned handle.
(provide scanline-session-record? scanline-session-record-handle
         scanline-session-record-creator scanline-session-record-info
         scanline-session-record-source-info scanline-session-record-order
         scanline-session-record-limit scanline-session-record-position
         scanline-session-record-status set-scanline-session-record-position!
         set-scanline-session-record-status! make-scanline-session-record)
(struct scanline-session-record
  (handle creator info source-info order limit [position #:mutable] [status #:mutable])
  #:constructor-name make-scanline-session-record)
;; Fields:
;;   handle: owned codec lifetime cell. creator: owning thread. info and source-info: destination
;;   and encoded-source descriptions. order: native scanline-order symbol. limit: byte budget.
;;   position: mutable next native row index. status: mutable decoding state. Row requests are
;;   interpreted in the decoder's reported order, not necessarily top-to-bottom display order.

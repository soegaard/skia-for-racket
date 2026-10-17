#lang racket/base

;;;
;;; Incremental Decoder State
;;;

;; Defines mutable cells and owned session records for an incremental decode.
;; Shares decoder lifecycle state between the core resource layer and codec operations.

;; Resource bridge only. No native loading or callback registration on require.
(provide (struct-out incremental-cell)
         incremental-session-record? incremental-session-record-handle
         incremental-session-record-cell incremental-session-record-creator
           make-incremental-session-record)
(struct incremental-cell
  (input template requested-row-bytes limit
         [codec #:mutable] [pixels #:mutable] [info #:mutable] [origin #:mutable]
         [stride #:mutable] [size #:mutable] [started? #:mutable] [status #:mutable]
         [result #:mutable] [rows #:mutable] [last-visible #:mutable]
         [last-final? #:mutable] [header-attempts #:mutable] [starts #:mutable]
         [decodes #:mutable] [allocations #:mutable]))
;; Fields:
;;   input: incremental-input buffer. template: one-pixel image-info carrying requested format and
;;   color interpretation. requested-row-bytes: requested stride or #f for tight rows. limit:
;;   positive byte-allocation limit captured at construction.
;;   codec and pixels: mutable native decoder and pixel-buffer pointers, or #f before
;;   allocation/after release. info and origin: decoded image-info and encoded orientation,
;;   initially #f.
;;   stride and size: allocated row bytes and total pixel bytes. started?: whether native
;;   incremental decoding has started. status and result: session state and latest codec result.
;;   rows: initialized-row count or #f before a native decode result supplies one.
;;   last-visible: previously attempted visible byte count, initially -1; last-final?: previous final
;;   input flag. header-attempts,
;;   starts, decodes, and allocations: diagnostic counters. One owned session controls every native
;;   pointer in the cell.

(struct incremental-session-record (handle creator cell)
  #:constructor-name make-incremental-session-record)
;; Fields:
;;   handle: owned decoder-session lifetime cell. creator: owning Racket thread. cell:
;;   incremental-cell with mutable decoder state. Public operations require the creator thread and a
;;   live handle.

#lang racket/base
;; Resource bridge only. No native loading or callback registration on require.
(provide (struct-out incremental-cell)
         incremental-session-record? incremental-session-record-handle
         incremental-session-record-cell incremental-session-record-creator make-incremental-session-record)
(struct incremental-cell
  (input template requested-row-bytes limit
         [codec #:mutable] [pixels #:mutable] [info #:mutable] [origin #:mutable]
         [stride #:mutable] [size #:mutable] [started? #:mutable] [status #:mutable]
         [result #:mutable] [rows #:mutable] [last-visible #:mutable]
         [last-final? #:mutable] [header-attempts #:mutable] [starts #:mutable]
         [decodes #:mutable] [allocations #:mutable]))
(struct incremental-session-record (handle creator cell)
  #:constructor-name make-incremental-session-record)

#lang racket/base
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

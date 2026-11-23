#lang racket/base

;;;
;;; Text Run Data
;;;

;; Defines glyph-run snapshots and the font references retained with them.
;; Shares text-blob builder data without exposing native run buffers.

;; Pure data shared by core lifecycle/outline replay and the additive builder.
;; The retained record is private; public inspection never reveals its font.
(provide (struct-out retained-text-run)
         (struct-out text-run-info))
(struct text-run-info (positioning glyphs positions transforms utf8 clusters)
  #:transparent)
;; Fields:
;;   positioning: 'default, 'horizontal, 'positioned, or 'transformed. glyphs: immutable vector of
;;   uint16 glyph IDs. positions: immutable vector of immutable #(x y) coordinates, empty for transformed
;;   runs.
;;   transforms: immutable vector of immutable #(scos ssin tx ty) RSXforms only for transformed runs,
;;   otherwise #f. The chosen coordinate vector has one entry per glyph in the same order.
;;   utf8: immutable source bytes or #f. clusters: matching immutable UTF-8 byte-offset vector or #f;
;;   these two fields are present together. Metadata owns no native run buffers.

(struct retained-text-run (font info) #:transparent)
;; Fields:
;;   font: private font snapshot kept for outline replay. info: matching immutable text-run-info.
;;   This internal record keeps fonts alive; public run inspection returns only the metadata.

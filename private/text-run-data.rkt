#lang racket/base
;; Pure data shared by core lifecycle/outline replay and the additive builder.
;; The retained record is private; public inspection never reveals its font.
(provide (struct-out retained-text-run)
         (struct-out text-run-info))
(struct text-run-info (positioning glyphs positions transforms utf8 clusters)
  #:transparent)
(struct retained-text-run (font info) #:transparent)

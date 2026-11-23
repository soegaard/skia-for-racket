#lang racket/base

;; The Scribble source tree is omitted from recursive DrDr traversal so manuals
;; are not rebuilt there. Run its existing focused tests explicitly instead.
(require (submod "../scribblings/tutorials/registration-test.rkt" test)
         (submod "../scribblings/tutorials/support/catalog.rkt" test)
         (submod "../scribblings/tutorials/reader-test.rkt" test)
         (submod "../scribblings/tutorials/support/accessible-figures-test.rkt" test)
         (submod "../scribblings/tutorials/sprites/model-test.rkt" test)
         (submod "../scribblings/tutorials/sprites/initial-bounds-test.rkt" test)
         (submod "../scribblings/tutorials/sprites/native-test.rkt" test)
         (submod "../scribblings/tutorials/squadron/model-test.rkt" test)
         (submod "../scribblings/tutorials/squadron/native-test.rkt" test))

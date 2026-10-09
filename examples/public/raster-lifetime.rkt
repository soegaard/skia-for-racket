#lang racket/base
;; Public modules only. Run after installing the pinned Skia library.
;; The borrowed canvas is usable only while its owning surface remains live.
(require "../../main.rkt")
(module+ main
  (define borrowed #f)
  (define copied #f)
  (with-skia ([surface (make-surface 8 8)])
    (set! borrowed (surface-canvas surface))
    (canvas-clear! borrowed (rgb 17 34 51))
    (set! copied (surface->rgba-bytes surface))
    (unless (equal? (subbytes copied 0 4) (bytes 17 34 51 255))
      (error 'public-raster-example "unexpected raster pixels")))
  (unless (and (skia-closed? borrowed) (= (bytes-length copied) (* 8 8 4)))
    (error 'public-raster-example "borrowed/copy lifetime contract failed"))
  (define rejected?
    (with-handlers ([exn:fail? (lambda (_) #t)])
      (canvas-clear! borrowed (rgb 0 0 0))
      #f))
  (unless rejected? (error 'public-raster-example "expired canvas was accepted"))
  (displayln "public-raster-example: passed"))

#lang racket/base

;;;
;;; Raster Lifetime Example
;;;

;; Contrasts a borrowed surface canvas with detached pixel data after cleanup.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;; Public modules only. Run after installing the pinned Skia library.
;; The borrowed canvas is usable only while its owning surface remains live.
;;;
;;; Imports and Exports
;;;

(require "../../main.rkt")
;;;
;;; Command-Line Entry Point
;;;

(module+ main
  ; borrowed : (or/c canvas? #f)
  ;;   Remembers a borrowed canvas so its invalidity after surface cleanup can be checked.
  (define borrowed #f)
  ; copied : (or/c bytes? #f)
  ;;   Retains detached RGBA bytes that remain valid after the surface is closed.
  (define copied #f)
  (with-skia ([surface (make-surface 8 8)])
    (set! borrowed (surface-canvas surface))
    (canvas-clear! borrowed (rgb 17 34 51))
    (set! copied (surface->rgba-bytes surface))
    (unless (equal? (subbytes copied 0 4) (bytes 17 34 51 255))
      (error 'public-raster-example "unexpected raster pixels")))
  (unless (and (skia-closed? borrowed) (= (bytes-length copied) (* 8 8 4)))
    (error 'public-raster-example "borrowed/copy lifetime contract failed"))
  ; rejected? : #f
  ;;   Starts rejected unset until the example establishes its value.
  (define rejected?
    (with-handlers ([exn:fail? (lambda (_) #t)])
      (canvas-clear! borrowed (rgb 0 0 0))
      #f))
  (unless rejected? (error 'public-raster-example "expired canvas was accepted"))
  (displayln "public-raster-example: passed"))

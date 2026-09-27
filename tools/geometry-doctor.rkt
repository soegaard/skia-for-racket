#lang racket/base
(require ffi/unsafe racket/list "../main.rkt" "../private/types.rkt")
(provide geometry-doctor!)
(define (geometry-doctor!)
  (with-skia ([r (make-region '((0 0 12 10)))] [q (make-region '((4 3 4 4)))]
              [hole (region-difference r q)] [s (make-surface 40 40)]
              [v (make-vertices 'triangles '((0 0) (30 0) (0 30)) #:colors '(red red red))]
              [p (make-paint #:color 'white)])
    (unless (and (region-contains-point? hole 1 1) (not (region-contains-point? hole 5 5)))
      (error 'doctor "region difference/half-open containment failed"))
    (define snapshot (in-region-rectangles hole)) (skia-close! hole)
    (unless (pair? (for/list ([b snapshot]) b)) (error 'doctor "region snapshot failed"))
    (draw-vertices (surface-canvas s) v p)
    (unless (equal? (surface-pixel s 4 4) (rgb 255 0 0))
      (error 'doctor "native colored triangle failed")))
  ;; Discriminator cells at indices 1, 2 and 6 catch int32/uint8 enum-stride bugs.
  (with-skia ([im (rgba-bytes->image 24 24 (apply bytes (apply append (make-list 576 '(255 0 0 255)))))]
              [s (make-surface 60 60)])
    (define lat (make-image-lattice '(6 18) '(6 18)
                  #:cell-types '(default transparent fixed-color default transparent default fixed-color default default)
                  #:colors '(white white blue white white white yellow white white)))
    (draw-image-lattice (surface-canvas s) im lat 0 0 60 60 #:sampling 'nearest)
    (unless (and (= (rgba-alpha (surface-pixel s 30 2)) 0)
                 (equal? (surface-pixel s 58 2) (rgb 0 0 255))
                 (equal? (surface-pixel s 2 58) (rgb 255 255 0)))
      (error 'doctor "lattice default/transparent/fixed-color cells failed")))
  (printf "Structured geometry passed: region boolean/snapshot, colored triangle, uint8 lattice cells; lattice=~a RSXform=~a\n"
          (ctype-sizeof _sk-lattice) (ctype-sizeof _sk-rsxform)))

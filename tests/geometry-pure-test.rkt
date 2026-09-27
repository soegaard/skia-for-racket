#lang racket/base
(require rackunit racket/list ffi/unsafe "../main.rkt" "../private/types.rkt" "../private/geometry-util.rkt")
(provide geometry-pure-tests)
(define triangle '((0 0) (20 0) (0 20)))
(define square-patch '((0 0) (10 0) (20 0) (30 0) (30 10) (30 20)
                       (30 30) (20 30) (10 30) (0 30) (0 20) (0 10)))
(define (validate-vertices mode ps #:tex [tex #f] #:colors [colors #f] #:indices [indices #f])
  (call-with-values (lambda () (geometry-vertices 'test mode ps tex colors indices)) list))
(define geometry-pure-tests
  (test-suite
   "Structured geometry: pure contracts and immutable specifications"
   (test-case "region rectangles reject fractional coordinates"
     (check-exn exn:fail:contract? (lambda () (make-region '((0.5 0 10 10)))))
   )
   (test-case "region rectangles reject negative sizes"
     (check-exn exn:fail:contract? (lambda () (make-region '((0 0 -1 10)))))
   )
   (test-case "region coordinate range excludes sentinel and unsafe widths"
     (check-exn exn:fail:contract? (lambda () (make-region '((1073741823 0 1 1)))))
     (check-exn exn:fail:contract? (lambda () (make-region '((-1073741824 0 1 1)))))
   )
   (test-case "region list shape is validated"
     (check-exn exn:fail:contract? (lambda () (make-region '((1 2 3)))))
     (check-exn exn:fail:contract? (lambda () (make-region 'oops)))
   )
   (test-case "region input obeys byte budget"
     (parameterize ([current-skia-byte-limit 15])
       (check-exn exn:fail:contract? (lambda () (make-region '((0 0 1 1))))))
   )
   (test-case "invalid region operations fail before loading"
     (check-exn exn:fail:contract? (lambda () (region-op #f #f 'add)))
   )
   (test-case "vertices reject unknown topology"
     (check-exn exn:fail:contract? (lambda () (make-vertices 'lines triangle)))
   )
   (test-case "vertices require at least three points"
     (check-exn exn:fail:contract? (lambda () (make-vertices 'triangles '((0 0) (1 1)))))
   )
   (test-case "triangle lists require complete triples"
     (check-exn exn:fail:contract? (lambda () (make-vertices 'triangles (append triangle '((2 2))))))
   )
   (test-case "strip and fan accept four positions"
     (for ([mode '(triangle-strip triangle-fan)])
       (check-equal? (vector-length (car (validate-vertices mode (append triangle '((2 2)))))) 4))
   )
   (test-case "texture coordinate count must match"
     (check-exn exn:fail:contract? (lambda () (make-vertices 'triangles triangle #:texture-coordinates '((0 0)))))
   )
   (test-case "color count must match"
     (check-exn exn:fail:contract? (lambda () (make-vertices 'triangles triangle #:colors '(red green))))
   )
   (test-case "indices must address available vertices"
     (check-exn exn:fail:contract? (lambda () (make-vertices 'triangles triangle #:indices '(0 1 3))))
   )
   (test-case "indices must be exact nonnegative uint16 values"
     (for ([bad '(1.0 -1 65536)])
       (check-exn exn:fail:contract? (lambda () (make-vertices 'triangles triangle #:indices (list 0 1 bad)))))
   )
   (test-case "indices cannot submit incomplete triangles"
     (check-exn exn:fail:contract? (lambda () (make-vertices 'triangles triangle #:indices '(0 1))))
   )
   (test-case "combined vertex storage is budgeted"
     (parameterize ([current-skia-byte-limit 35])
       (check-exn exn:fail:contract? (lambda () (make-vertices 'triangles triangle #:colors '(red green blue)))))
   )
   (test-case "nonfinite positions are rejected"
     (check-exn exn:fail:contract? (lambda () (make-vertices 'triangles '((0 0) (+inf.0 0) (0 10)))))
   )
   (test-case "validated geometry is a detached deep snapshot"
     (define p (vector 1 2)) (define points (vector p #(20 0) #(0 20)))
     (define ps (car (validate-vertices 'triangles points)))
     (vector-set! p 0 99) (vector-set! points 1 #(99 99))
     (check-equal? (vector-ref ps 0) #(1.0 2.0))
     (check-true (immutable? ps)) (check-true (immutable? (vector-ref ps 0)))
   )
   (test-case "lattice divisions must be increasing without repeats"
     (for ([divs '((5 4) (4 4))])
       (check-exn exn:fail:contract? (lambda () (make-image-lattice divs '(4 8)))))
   )
   (test-case "lattice divisions must be exact integers"
     (check-exn exn:fail:contract? (lambda () (make-image-lattice '(4.0) '(4 8))))
   )
   (test-case "a lattice needs a divided axis"
     (check-exn exn:fail:contract? (lambda () (make-image-lattice '() '())))
   )
   (test-case "cell types cover the full grid"
     (check-exn exn:fail:contract? (lambda () (make-image-lattice '(8 16) '(8 16) #:cell-types '(default))))
   )
   (test-case "unknown lattice cell kinds are rejected"
     (check-exn exn:fail:contract? (lambda () (make-image-lattice '(8) '() #:cell-types '(default bogus))))
   )
   (test-case "fixed cells require a color array"
     (check-exn exn:fail:contract? (lambda () (make-image-lattice '(8) '() #:cell-types '(default fixed-color))))
   )
   (test-case "colors without cell types are not silently ignored"
     (check-exn exn:fail:contract? (lambda () (make-image-lattice '(8) '() #:colors '(red blue))))
   )
   (test-case "lattice source bounds must be nonempty"
     (check-exn exn:fail:contract? (lambda () (make-image-lattice '(8) '(8) #:bounds '(0 0 0 24))))
   )
   (test-case "edge divisions are deliberately rejected"
     (check-exn exn:fail:contract? (lambda () (make-image-lattice '(0 8) '(8) #:bounds '(0 0 24 24))))
   )
   (test-case "lattice copies divisions cell types and colors"
     (define xs (vector 8 16)) (define types (vector 'default 'transparent 'fixed-color))
     (define colors (vector 'red 'green 'blue))
     (define l (make-image-lattice xs '() #:cell-types types #:colors colors))
     (vector-set! xs 0 7) (vector-set! types 1 'default) (vector-set! colors 2 'red)
     (check-equal? (image-lattice-x-divisions l) #(8 16))
     (check-equal? (image-lattice-cell-types l) #(default transparent fixed-color))
     (check-equal? (vector-ref (image-lattice-colors l) 2) (color->argb 'blue))
   )
   (test-case "lattice storage is bounded before allocation"
     (parameterize ([current-skia-byte-limit 16])
       (check-exn exn:fail:contract? (lambda () (make-image-lattice '(8 16) '(8 16)))))
   )
   (test-case "atlas identity coefficients"
     (check-equal? (atlas-transform-coefficients (make-atlas-transform 10 20)) #(1.0 0.0 10.0 20.0))
   )
   (test-case "atlas rotation and anchor map the anchor to the supplied point"
     (define v (atlas-transform-coefficients (make-atlas-transform 40 50 #:scale 2 #:rotation 90 #:anchor '(3 4))))
     (check-= (+ (* (vector-ref v 0) 3) (- (* (vector-ref v 1) 4)) (vector-ref v 2)) 40 1e-6)
     (check-= (+ (* (vector-ref v 1) 3) (* (vector-ref v 0) 4) (vector-ref v 3)) 50 1e-6)
   )
   (test-case "atlas invalid scales and anchors reject"
     (check-exn exn:fail:contract? (lambda () (make-atlas-transform 0 0 #:scale -1)))
     (check-exn exn:fail:contract? (lambda () (make-atlas-transform 0 0 #:anchor '(1))))
   )
   (test-case "patch requires exactly twelve points"
     (check-exn exn:fail:contract? (lambda () (make-cubic-patch triangle)))
   )
   (test-case "patch corner arrays require four entries"
     (check-exn exn:fail:contract? (lambda () (make-cubic-patch square-patch #:colors '(red))))
     (check-exn exn:fail:contract? (lambda () (make-cubic-patch square-patch #:texture-coordinates triangle)))
   )
   (test-case "patch snapshots are immutable"
     (define p (make-cubic-patch square-patch #:colors '(red green blue white)))
     (check-true (immutable? (cubic-patch-points p)))
     (check-true (immutable? (cubic-patch-colors p)))
     (check-false (cubic-patch-texture-coordinates p))
   )
   (test-case "new layouts match pinned 64-bit record sizes"
     (check-equal? (ctype-sizeof _sk-rsxform) 16)
     (check-equal? (ctype-sizeof _sk-lattice) (if (= (ctype-sizeof _pointer) 8) 48 28))
   )
   (test-case "meshes patches and atlases require explicit document fallback"
     (for* ([backend '(pdf svg)] [feature '(vertices coons-patch image-atlas)])
       (check-eq? (output-capability-status (output-capability-for backend feature)) 'needs-raster))
   )
   (test-case "image grid and device-region clipping have backend policies"
     (check-eq? (output-capability-status (output-capability-for 'pdf 'image-grid)) 'embedded-raster)
     (check-eq? (output-capability-status (output-capability-for 'svg 'image-grid)) 'needs-raster)
     (check-eq? (output-capability-status (output-capability-for 'pdf 'device-region-clip)) 'vector)
   )
))

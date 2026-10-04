#lang racket/base
;; 0.60 exercises the existing public consumers; never decode recorded datums.
(require racket/class racket/list
         (prefix-in rd: racket/draw)
         "../dc.rkt" "dc-consumer-fixtures.rkt"
         (prefix-in style: "dc-style-fixtures.rkt"))
(provide (struct-out consumer-workload) consumer-extents make-consumer-workloads
         call-with-consumer-cpu-dc exercise-consumer! ensure-consumer!
         check-consumer-expired! consumer-identity)
(struct consumer-workload (scene mode draw restores-state?) #:transparent)
;; name, physical width/height, logical width/height. The last two cases must
;; not be reduced to a scalar backing scale. The scene itself is 320 x 240.
(define consumer-extents
  '(("1x" 320 240 320.0 240.0)
    ("2x" 640 480 320.0 240.0)
    ("asymmetric" 400 360 320.0 240.0)
    ("fractional" 641 481 320.5 240.25)))
(define (ensure-consumer! value message)
  (unless value (error 'gpu-dc-consumers "~a" message)))
(define (consumer-identity)
  (hasheq 'version (version) 'os (symbol->string (system-type 'os))
          'architecture (symbol->string (system-type 'arch))
          'vm (symbol->string (system-type 'vm))))
(define (call-with-consumer-cpu-dc extent proc)
  (define dc (new skia-dc% [width (list-ref extent 1)] [height (list-ref extent 2)]
                         [smoothing 'smoothed] [background "white"]))
  (dynamic-wind void
    (lambda ()
      ;; CPU comparison uses the ordinary raster DC, not the GPU renderer
      ;; adapter. Public get-size differs, but these consumers receive explicit
      ;; scene dimensions; their geometry is mapped by the initial transform.
      (send dc set-initial-matrix
            (vector (/ (list-ref extent 1) (list-ref extent 3)) 0 0
                    (/ (list-ref extent 2) (list-ref extent 4)) 0 0))
      (send dc clear)
      (proc dc))
    (lambda () (send dc close))))
(define (fill dc color x y w h)
  (send dc set-pen "black" 1 'transparent)
  (send dc set-brush color 'solid)
  (send dc draw-rectangle x y w h))
(define (geometry dc)
  (send dc set-smoothing 'unsmoothed)
  (send dc set-clipping-rect 12 12 24 20)
  (fill dc "red" 0 0 64 40)
  (send dc set-clipping-region #f)
  (send dc start-alpha 0.5)
  (fill dc "red" 12 64 40 24)
  (fill dc "blue" 28 64 40 24)
  (send dc end-alpha)
  (fill dc "red" 100 12 16 16)
  (fill dc "blue" 116 12 16 16)
  (define transform (send dc get-transformation))
  (send dc translate 200 120)
  (send dc scale 1.5 1.25)
  (fill dc (make-object rd:color% 0 255 0) 4 4 20 16)
  (send dc set-transformation transform)
  (hash))
(define (record-workload draw)
  (define recorder (new rd:record-dc% [width consumer-width] [height consumer-height]))
  (send recorder set-smoothing 'smoothed)
  (define layout (draw recorder))
  (define out (open-output-string))
  (write (send recorder get-recorded-datum) out)
  ;; Use the public serialization contract, not merely an in-memory datum.
  (define in (open-input-string (get-output-string out)))
  (define datum (read in))
  (ensure-consumer! (eof-object? (read in)) "recorded datum has trailing input")
  (values (send recorder get-recorded-procedure)
          (rd:recorded-datum->procedure datum) layout))
(define (make-consumer-workloads)
  ;; Build the pict with actual Skia metrics. It must remain usable after this
  ;; metric DC closes. Plot direct layout comes from its actual destination;
  ;; recorded plot layout comes from record-dc%, as in the 0.56 CPU fixtures.
  (define picture
    (call-with-consumer-cpu-dc (car consumer-extents) make-consumer-pict))
  (append-map
   (lambda (spec)
     (define scene (car spec))
     (define draw (cadr spec))
     (define-values (procedure datum layout) (record-workload draw))
     (define (post-replay dc)
       ;; Upstream record-dc% does not record copy. Exercise the actual target's
       ;; overlap-safe copy AFTER the replay, without a private datum decoder.
       ;; The source rectangles are part of the recording; copy changes no state.
       (when (equal? scene "geometry") (send dc copy 100 12 32 16 108 12)))
     (list (consumer-workload scene "direct"
             (lambda (dc) (begin0 (draw dc) (post-replay dc)))
             (member scene '("pict" "plot")))
           (consumer-workload scene "procedure"
             (lambda (dc) (procedure dc) (post-replay dc) layout) #t)
           (consumer-workload scene "datum"
             (lambda (dc) (datum dc) (post-replay dc) layout) #t)))
   (list (list "pict" (lambda (dc) (draw-consumer-pict dc picture) (hash)))
         (list "plot" draw-consumer-plot)
         (list "styles" (lambda (dc) (style:style-oracle dc) (hash)))
         (list "geometry" geometry))))
(define (exercise-consumer! workload dc)
  (define before (consumer-state dc))
  (define layout ((consumer-workload-draw workload) dc))
  (when (consumer-workload-restores-state? workload)
    (ensure-consumer! (equal? (consumer-state dc) before)
      (format "~a/~a failed to restore destination state"
              (consumer-workload-scene workload) (consumer-workload-mode workload))))
  layout)
(define (check-consumer-expired! dc)
  (ensure-consumer! (not (send dc ok?)) "retained DC remained live")
  (for ([operation (in-list (list (lambda () (send dc get-size))
                                  (lambda () (send dc draw-line 0 0 1 1))
                                  (lambda () (send dc get-rgba-bytes))))])
    (ensure-consumer!
     (with-handlers ([exn:fail? (lambda (_) #t)]) (operation) #f)
     "operation on expired DC unexpectedly succeeded")))

#lang racket/base
;; Each workload gets a normal, no-readback frame and a separate inspection
;; frame. Pixel captures describe the GPU DC backing, not physical scanout.
(require racket/class racket/cmdline racket/file racket/list
         (prefix-in gui: racket/gui/base)
         "../gpu-canvas.rkt" "../tests/gpu-dc-consumer-fixtures.rkt"
         "gpu-dc-consumer-common.rkt")
(define (run-gui directory token backend adapter)
  (define custodian (make-custodian))
  (define space (parameterize ([current-custodian custodian]) (gui:make-eventspace)))
  (define (on-handler proc)
    (define reply (make-channel))
    (parameterize ([gui:current-eventspace space])
      (gui:queue-callback
       (lambda ()
         (channel-put reply
           (with-handlers ([(lambda (_) #t) (lambda (e) (cons 'error e))])
             (cons 'values (call-with-values proc list))))) #f))
    (define result (sync/timeout 30 reply))
    (unless result (error 'gpu-dc-consumers "GUI handler did not respond"))
    (if (eq? (car result) 'error) (raise (cdr result)) (apply values (cdr result))))
  (define frame #f) (define canvas #f)
  (define captures '()) (define frames '()) (define transfers '())
  (define saved-dcs '())
  (define (retain! workload extent target data layout events)
    (set! captures (cons (write-consumer-capture! directory workload extent target data layout events) captures)))
  (dynamic-wind void
    (lambda ()
      (define workloads (on-handler make-consumer-workloads))
      (on-handler
       (lambda ()
         (set! frame (new gui:frame% [label "Skia GPU consumer acceptance"] [width 380] [height 300]))
         (set! canvas (new skia-gpu-canvas% [parent frame] [backend backend]
                           [adapter (and (eq? backend 'direct3d) adapter)]
                           [automatic? #f] [min-width 320] [min-height 240]))
         (send frame show #t)))
      (for ([geometry (in-list '(("small" 380 300) ("large" 520 400)))])
        (define previous
          (on-handler (lambda () (call-with-values (lambda () (send canvas get-client-size)) list))))
        (on-handler (lambda () (send frame resize (cadr geometry) (caddr geometry))))
        ;; Allow native layout events to run without yielding inside a GPU scope.
        (let loop ([attempts 200])
          (define now
            (on-handler (lambda () (call-with-values (lambda () (send canvas get-client-size)) list))))
          (unless (and (>= (car now) 320) (>= (cadr now) 240)
                       (or (equal? (car geometry) "small") (> (car now) (car previous))))
            (when (zero? attempts) (error 'gpu-dc-consumers "GUI resize did not settle"))
            (sleep 0.01) (loop (sub1 attempts))))
        (for ([workload (in-list workloads)])
          (on-handler
           (lambda ()
             (define extent #f) (define normal-dc #f)
             (define-values (_normal events)
               (observe-consumer-io!
                (lambda ()
                  (send canvas refresh-now
                    (lambda (dc)
                      (set! normal-dc dc)
                      (for ([old (in-list saved-dcs)])
                        (ensure-consumer! (not (send old ok?)) "GUI frame revived an expired DC"))
                      (define-values (pw ph) (send dc get-pixel-size))
                      (define-values (lw lh) (send dc get-size))
                      (set! extent (list (car geometry) pw ph lw lh))
                      (ensure-consumer! (eq? dc (send canvas get-dc)) "widget exposes a different DC")
                      (exercise-consumer! workload dc)))) #:present? #t))
             (ensure-consumer! extent "normal GUI frame did not invoke consumer")
             (check-consumer-expired! normal-dc)
             (set! saved-dcs (cons normal-dc saved-dcs))
             (define id (workload-id workload extent "gui"))
             (set! frames (cons (hasheq 'id id 'io events) frames))
             (define pixels #f) (define layout #f) (define observed-dc #f) (define capture-io #f)
             (send canvas refresh-now
               (lambda (dc)
                 (set! observed-dc dc)
                 (ensure-consumer! (not (eq? dc normal-dc)) "inspection reused a normal frame DC")
                 (define-values (pw ph) (send dc get-pixel-size))
                 (define-values (lw lh) (send dc get-size))
                 (ensure-consumer! (equal? extent (list (car geometry) pw ph lw lh))
                                   "geometry changed between drawing and inspection")
                 (set! layout (exercise-consumer! workload dc))
                 (define-values (data io)
                   (observe-consumer-io! (lambda () (send dc get-rgba-bytes #:premultiplied? #t)) #:capture? #t))
                 (set! pixels data) (set! capture-io io)))
             (check-consumer-expired! observed-dc)
             (set! saved-dcs (cons observed-dc saved-dcs))
             (set! transfers (cons (hasheq 'id id 'io capture-io) transfers))
             (retain! workload extent "gui" pixels layout events)
             (call-with-consumer-cpu-dc extent
               (lambda (dc)
                 (define cpu-layout (exercise-consumer! workload dc))
                 (retain! workload extent "cpu" (send dc get-rgba-bytes #:premultiplied? #t) cpu-layout '())))))))
      (on-handler (lambda () (send canvas close-skia) (send canvas close-skia)
                    (ensure-consumer! (send canvas skia-closed?) "GUI canvas did not close")
                    (send frame show #f)))
      (finish-consumer-report! directory "gui" token (symbol->string backend) (reverse captures)
        (hasheq 'normal_frames (reverse frames) 'expired_dcs (length saved-dcs)
                'transfers (reverse transfers) 'canvas_closed #t 'window_created #t
                'final_target_pixels #f 'inspection "separate frame, GPU DC backing only")))
    (lambda ()
      (dynamic-wind void
        (lambda () (when canvas (on-handler (lambda () (send canvas close-skia) (send frame show #f)))))
        (lambda () (custodian-shutdown-all custodian))))))
(module+ main
  (define directory #f) (define token #f) (define backend 'opengl) (define adapter 'hardware)
  (command-line #:once-each
    [("--directory") value "New capture directory" (set! directory value)]
    [("--run-token") value "Validation identity" (set! token value)]
    [("--backend") value "opengl, metal or direct3d" (set! backend (string->symbol value))]
    [("--adapter") value "hardware or warp" (set! adapter (string->symbol value))]
    #:args () (void))
  (unless (and directory token) (error 'gpu-dc-consumers "--directory and --run-token are required"))
  (make-directory directory)
  (run-gui directory token backend adapter))

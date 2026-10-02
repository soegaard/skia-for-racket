#lang racket/base
;; A small 2D "game frame" demo exercising four techniques together:
;;   1. Shader effects  - an animated SkSL plasma background (time uniform).
;;   2. Static layers   - a picture recorded once, replayed every frame.
;;   3. GPU textures    - a sprite sheet uploaded once to the window's context.
;;   4. Sprite batching - every sprite drawn by one draw-atlas call per frame.
;;
;; Run:  racket examples/gpu-game-demo.rkt [--sprites N] [--backend auto|opengl|metal|direct3d]
(require racket/class racket/cmdline racket/flonum racket/math
         (only-in racket/gui/base frame% timer% queue-callback)
         "../main.rkt" "../gpu.rkt" "../gpu-gui.rkt")

;; Scene coordinates are fixed; each frame scales them to the real pixel size.
(define W 960.0)
(define H 600.0)
(define CELL 32)          ; sprite-sheet cell size in pixels
(define CELLS 4)          ; number of sprite variants in the sheet

;; ---------------------------------------------------------------- 1. shader
(define plasma-source #<<SKSL
uniform float2 resolution;
uniform float time;
half4 main(float2 p) {
  float2 uv = p / resolution;
  float v = sin(uv.x * 10.0 + time)
          + sin((uv.y * 10.0 + time) * 0.7)
          + sin((uv.x * 10.0 + uv.y * 10.0 + time) * 0.5);
  float cx = uv.x - 0.5 + 0.5 * sin(time * 0.33);
  float cy = uv.y - 0.5 + 0.5 * cos(time * 0.5);
  v += sin(sqrt(100.0 * (cx * cx + cy * cy) + 1.0) + time);
  float3 c = float3(0.5 + 0.5 * sin(3.14159 * v),
                    0.5 + 0.5 * sin(3.14159 * v + 2.094),
                    0.5 + 0.5 * sin(3.14159 * v + 4.188));
  return half4(half3(c * 0.35), 1.0);
}
SKSL
  )

;; ----------------------------------------------------------- 2. static layer
(define (record-static-layer font)
  (call-with-picture
   (inexact->exact W) (inexact->exact H)
   (lambda (c)
     (with-skia ([grid (make-paint #:color (rgba 255 255 255 28) #:style 'stroke #:stroke-width 1)]
                 [border (make-paint #:color (rgba 255 255 255 160) #:style 'stroke #:stroke-width 4)]
                 [panel (make-paint #:color (rgba 0 0 0 120))]
                 [ink (make-paint #:color 'white)])
       (for ([x (in-range 0 W 40)]) (draw-line c x 0 x H grid))
       (for ([y (in-range 0 H 40)]) (draw-line c 0 y W y grid))
       (draw-rounded-rect c 8 8 (- W 16) (- H 16) 18 18 border)
       (draw-rounded-rect c 24 24 360 44 10 10 panel)
       (draw-simple-text c "skia-for-racket · sprite demo" 40 54 font ink)))))

;; ------------------------------------------------------------ 3. sprite sheet
;; Drawn on the CPU once; uploaded to the GPU on the first frame.
(define (make-sprite-sheet)
  (define colors '(("#FFE066" "#F08C00") ("#74C0FC" "#1864AB")
                   ("#8CE99A" "#2B8A3E") ("#FFA8A8" "#C92A2A")))
  (with-skia ([s (make-surface (* CELL CELLS) CELL #:background 'transparent)])
    (define c (surface-canvas s))
    (for ([pair (in-list colors)] [i (in-naturals)])
      (define cx (+ (* i CELL) (/ CELL 2)))
      (define cy (/ CELL 2))
      (with-skia ([g (make-radial-gradient-shader cx cy (/ CELL 2)
                                                  (list (car pair) (cadr pair) (rgba 0 0 0 0))
                                                  #:positions '(0 0.75 1))]
                  [orb (make-paint #:shader g)]
                  [spark (make-paint #:color (rgba 255 255 255 200))])
        (draw-circle c cx cy (- (/ CELL 2) 1) orb)
        ;; An off-center highlight makes rotation visible.
        (draw-circle c (- cx 6) (- cy 6) 3 spark)))
    (surface-snapshot s)))

(define sprite-sources
  (for/list ([i (in-range CELLS)]) (list (* i CELL) 0 CELL CELL)))

;; -------------------------------------------------------------- simulation
(struct sprites (n x y vx vy angle spin cell))
(define (make-sprites n)
  (define (fv lo hi) (for/flvector #:length n ([_ (in-range n)]) (+ lo (* (random) (- hi lo)))))
  (sprites n (fv 20.0 (- W 20.0)) (fv 80.0 (- H 20.0))
           (fv -180.0 180.0) (fv -180.0 180.0)
           (fv 0.0 360.0) (fv -240.0 240.0)
           (for/vector #:length n ([_ (in-range n)]) (random CELLS))))

(define (step! s dt)
  (define-values (xs ys vxs vys as ss)
    (values (sprites-x s) (sprites-y s) (sprites-vx s) (sprites-vy s)
            (sprites-angle s) (sprites-spin s)))
  (for ([i (in-range (sprites-n s))])
    (define x (fl+ (flvector-ref xs i) (fl* dt (flvector-ref vxs i))))
    (define y (fl+ (flvector-ref ys i) (fl* dt (flvector-ref vys i))))
    (when (or (fl< x 16.0) (fl> x (fl- W 16.0))) (flvector-set! vxs i (fl- 0.0 (flvector-ref vxs i))))
    (when (or (fl< y 16.0) (fl> y (fl- H 16.0))) (flvector-set! vys i (fl- 0.0 (flvector-ref vys i))))
    (flvector-set! xs i (flmax 16.0 (flmin x (fl- W 16.0))))
    (flvector-set! ys i (flmax 16.0 (flmin y (fl- H 16.0))))
    (flvector-set! as i (fl+ (flvector-ref as i) (fl* dt (flvector-ref ss i))))))

;; ------------------------------------------------------------------- main
(module+ main
  (define sprite-count 1500)
  (define backend 'auto)
  (command-line
   #:once-each
   [("--sprites") n "number of sprites (default 1500)" (set! sprite-count (string->number n))]
   [("--backend") b "auto, opengl, metal or direct3d" (set! backend (string->symbol b))]
   #:args () (void))

  (queue-callback
   (lambda ()
     ;; Everything below is created on the eventspace handler thread, which is
     ;; also the thread that runs the render callback.
     (define font (make-font #:size 20))
     (define hud-paint (make-paint #:color 'white))
     (define plasma (make-runtime-effect plasma-source))
     (define static-layer (record-static-layer font))
     (define sheet-cpu (make-sprite-sheet))
     (define sheet-gpu #f)                      ; uploaded lazily, kept across frames
     (define world (make-sprites sprite-count))
     (define sources                            ; constant per sprite
       (for/list ([k (in-vector (sprites-cell world))]) (list-ref sprite-sources k)))
     (define t0 (current-inexact-milliseconds))
     (define last-t t0)
     (define fps 0.0)

     (define (render frame)
       (define c (gpu-frame-canvas frame))
       (define now (current-inexact-milliseconds))
       (define dt (fl/ (fl- now last-t) 1000.0))
       (set! last-t now)
       (set! fps (if (fl> dt 0.0) (fl+ (fl* 0.9 fps) (fl* 0.1 (fl/ 1.0 dt))) fps))
       (step! world (flmin dt 0.05))

       ;; 3. One upload; later frames reuse the same GPU texture.
       (unless sheet-gpu
         (set! sheet-gpu (gpu-upload-image (gpu-frame-context frame) sheet-cpu)))

       (with-canvas-state c
         (canvas-scale! c (/ (gpu-frame-width frame) W) (/ (gpu-frame-height frame) H))

         ;; 1. Uniforms are snapshots: make a new instance per frame from the
         ;;    same compiled effect. Compilation happened once, above.
         (with-skia ([shader (runtime-effect->shader
                              plasma
                              #:uniforms (hash 'resolution (list W H)
                                               'time (/ (- now t0) 1000.0)))]
                     [bg (make-paint #:shader shader)])
           (draw-rect c 0 0 W H bg))

         ;; 2. Static layer: replay, no re-recording.
         (draw-picture c static-layer)

         ;; 4. One batched call for all sprites.
         (draw-atlas c sheet-gpu
                     (for/list ([i (in-range (sprites-n world))])
                       (make-atlas-transform (flvector-ref (sprites-x world) i)
                                             (flvector-ref (sprites-y world) i)
                                             #:rotation (flvector-ref (sprites-angle world) i)
                                             #:anchor (list (/ CELL 2) (/ CELL 2))))
                     sources
                     #:sampling 'linear)

         (draw-simple-text c (format "~a sprites · ~a fps" (sprites-n world) (exact-round fps))
                           (- W 260) 54 font hud-paint)))

     (define timer #f)
     (define (shutdown!)
       (when timer (send timer stop))
       ;; Retire everything that may hold the presenter's GPU context first;
       ;; the presenter refuses to close a context with live children.
       (for ([r (list sheet-gpu sheet-cpu static-layer plasma hud-paint font)] #:when r)
         (skia-close! r))
       (send canvas close-gpu))

     (define window
       (new (class frame%
              (super-new)
              (define/augment (on-close) (shutdown!)))
            [label "Skia sprite demo"] [width 960] [height 600]))
     (define canvas
       (new gpu-canvas% [parent window] [backend backend] [render render]
            [background 'black]
            [on-error (lambda (e)
                        (when timer (send timer stop))
                        (eprintf "render failed: ~a\n" (if (exn? e) (exn-message e) e)))]))
     ;; The presenter is not an animation clock; drive redraws explicitly.
     ;; Requests coalesce, so a slow frame never queues a backlog.
     (set! timer (new timer% [interval 16]
                      [notify-callback (lambda () (send canvas request-gpu-render))]))
     (send window show #t))))

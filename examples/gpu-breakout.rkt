#lang racket/base
;; Breakout with shader juice.
;;
;;   Mouse or ←/→   move the paddle
;;   Click / SPACE  launch the ball (and restart after game over)
;;   C              toggle the CRT post-effect
;;
;; Juice: an SkSL background with impact shock rings, a CRT post-pass
;; (barrel curvature, scanlines, vignette, chromatic aberration that spikes on
;; hits), screen flash, screen shake, particles, ball trail, glow and paddle
;; squash. The scene is drawn into an offscreen GPU surface; the post shader
;; samples a snapshot of it as an SkSL child shader.
;;
;; Run:  racket examples/gpu-breakout.rkt [--backend auto|opengl|metal|direct3d]
(require racket/class racket/cmdline racket/list racket/math
         (only-in racket/gui/base frame% timer% queue-callback)
         "../main.rkt" "../gpu.rkt" "../gpu-gui.rkt")

(define W 960.0)
(define H 600.0)

;; ------------------------------------------------------------- shaders
(define background-source #<<SKSL
uniform float2 resolution;
uniform float time;
uniform float2 impact;   // scene position of the last brick hit
uniform float age;       // seconds since that hit
half4 main(float2 p) {
  float2 uv = p / resolution;
  float3 base = mix(float3(0.03, 0.02, 0.08), float3(0.10, 0.03, 0.16), uv.y);
  float g = sin(uv.x * 40.0 + time * 0.5) * sin(uv.y * 25.0 - time * 0.7);
  base += float3(0.02, 0.03, 0.06) * (0.5 + 0.5 * g);
  // An expanding, fading shock ring around the last impact.
  float d = (length(p - impact) - age * 600.0) / 14.0;
  base += float3(0.30, 0.60, 1.00) * exp(-d * d) * exp(-age * 3.0);
  return half4(half3(base), 1.0);
}
SKSL
  )

(define crt-source #<<SKSL
uniform shader scene;
uniform float2 resolution;
uniform float aberration;  // pixels; spikes on impacts
uniform float flash;       // 0..1 white flash
half4 main(float2 p) {
  float2 uv = p / resolution;
  float2 d = uv - 0.5;
  float2 cuv = 0.5 + d * (1.0 + 0.12 * dot(d, d));          // barrel curvature
  if (cuv.x < 0.0 || cuv.x > 1.0 || cuv.y < 0.0 || cuv.y > 1.0) {
    return half4(0.0, 0.0, 0.0, 1.0);
  }
  float2 q = cuv * resolution;
  float2 off = d * aberration * 2.0;                          // grows toward edges
  float3 col = float3(scene.eval(q + off).r, scene.eval(q).g, scene.eval(q - off).b);
  col *= 0.86 + 0.14 * sin(q.y * 3.14159);                    // scanlines
  col *= mix(0.55, 1.0, 1.0 - smoothstep(0.25, 0.75, length(d)));  // vignette
  col += float3(flash * 0.35);
  return half4(half3(col), 1.0);
}
SKSL
  )

;; ------------------------------------------------------------- level data
(define COLS 12) (define ROWS 6)
(define BW 64.0) (define BH 22.0) (define GAP 8.0)
(define LEFT (/ (- W (- (* COLS (+ BW GAP)) GAP)) 2.0))
(define TOP 80.0)
(define row-colors
  (vector (rgba 255 107 107 255) (rgba 255 169 77 255) (rgba 255 212 59 255)
          (rgba 105 219 124 255) (rgba 77 171 247 255) (rgba 177 151 252 255)))

(struct brick (x y row [alive? #:mutable]))
(define (make-level)
  (for*/list ([r (in-range ROWS)] [c (in-range COLS)])
    (brick (+ LEFT (* c (+ BW GAP))) (+ TOP (* r (+ BH GAP))) r #t)))

(struct particle ([x #:mutable] [y #:mutable] [vx #:mutable] [vy #:mutable]
                  [life #:mutable] color))

(define PW 120.0) (define PH 16.0) (define PY (- H 50.0)) (define BR 8.0)

(define (clamp v lo hi) (max lo (min hi v)))
(define (rand-range lo hi) (+ lo (* (random) (- hi lo))))
(define (fade c a) (rgba (rgba-red c) (rgba-green c) (rgba-blue c)
                         (exact-round (clamp (* 255 a) 0 255))))

;; ------------------------------------------------------------------ main
(module+ main
  (define backend 'auto)
  (command-line
   #:once-each
   [("--backend") b "auto, opengl, metal or direct3d" (set! backend (string->symbol b))]
   #:args () (void))

  (queue-callback
   (lambda ()
     ;; ---- long-lived resources (handler thread)
     (define small-font (make-font #:size 22))
     (define big-font (make-font #:size 48))
     (define bg-fx (make-runtime-effect background-source))
     (define crt-fx (make-runtime-effect crt-source))
     (define glow-filter (make-blur-mask-filter 10))
     (define fill (make-paint))
     (define glow (make-paint #:mask-filter glow-filter))
     (define offscreen #f)           ; GPU surface, created on the first frame

     ;; ---- game state
     (define bricks (make-level))
     (define level 1) (define score 0) (define lives 3)
     (define state 'serve)           ; serve | play | over
     (define paddle-x (/ W 2)) (define target-x paddle-x)
     (define bx 0.0) (define by 0.0) (define vx 0.0) (define vy 0.0)
     (define speed 420.0)
     (define trail '()) (define particles '())
     (define left? #f) (define right? #f) (define crt? #t)
     ;; juice
     (define shake 0.0) (define flash 0.0) (define aberration 0.0) (define squash 0.0)
     (define impact (list (/ W 2) (- H 100))) (define impact-age 10.0)
     (define t0 (current-inexact-milliseconds)) (define last-t t0)

     (define (kick! amount) (set! shake (max shake amount)))
     (define (launch!)
       (case state
         [(serve) (define a (rand-range -0.5 0.5))
                  (set! vx (* speed (sin a))) (set! vy (- (* speed (cos a))))
                  (set! state 'play)]
         [(over) (set! bricks (make-level)) (set! level 1) (set! score 0)
                 (set! lives 3) (set! speed 420.0) (set! state 'serve)]
         [else (void)]))

     (define (burst! x y color)
       (for ([_ (in-range 16)])
         (define a (rand-range 0 (* 2 pi))) (define v (rand-range 80 360))
         (set! particles (cons (particle x y (* v (cos a)) (* v (sin a)) 1.0 color)
                               particles))))

     (define (hit-brick! b)
       (set-brick-alive?! b #f)
       (set! score (+ score (* 10 (- ROWS (brick-row b)))))
       (define cx (+ (brick-x b) (/ BW 2))) (define cy (+ (brick-y b) (/ BH 2)))
       (burst! cx cy (vector-ref row-colors (brick-row b)))
       (set! impact (list cx cy)) (set! impact-age 0.0)
       (kick! 6.0) (set! flash (max flash 0.35)) (set! aberration 6.0))

     ;; Circle/rectangle overlap; flips the velocity along the shallower axis.
     (define (bounce-off! x y w h)
       (define nx (clamp bx x (+ x w))) (define ny (clamp by y (+ y h)))
       (and (< (+ (sqr (- bx nx)) (sqr (- by ny))) (sqr BR))
            (let ([ox (min (- (+ bx BR) x) (- (+ x w) (- bx BR)))]
                  [oy (min (- (+ by BR) y) (- (+ y h) (- by BR)))])
              (if (< ox oy)
                  (begin (set! vx (- vx)) (set! bx (+ bx (if (< bx (+ x (/ w 2))) (- ox) ox))))
                  (begin (set! vy (- vy)) (set! by (+ by (if (< by (+ y (/ h 2))) (- oy) oy)))))
              #t)))

     (define (step! dt)
       ;; paddle
       (when left?  (set! target-x (- target-x (* 700 dt))))
       (when right? (set! target-x (+ target-x (* 700 dt))))
       (set! target-x (clamp target-x (/ PW 2) (- W (/ PW 2))))
       (set! paddle-x (+ paddle-x (* (- target-x paddle-x) (min 1.0 (* 20 dt)))))
       ;; ball
       (case state
         [(serve) (set! bx paddle-x) (set! by (- PY BR 2))]
         [(play)
          (define sub 4) (define h (/ dt sub))
          (for ([_ (in-range sub)] #:when (eq? state 'play))
            (set! bx (+ bx (* vx h))) (set! by (+ by (* vy h)))
            (when (< bx BR) (set! bx BR) (set! vx (abs vx)) (kick! 2.0))
            (when (> bx (- W BR)) (set! bx (- W BR)) (set! vx (- (abs vx))) (kick! 2.0))
            (when (< by BR) (set! by BR) (set! vy (abs vy)) (kick! 2.0))
            ;; paddle: hit position chooses the outgoing angle
            (when (and (> vy 0)
                       (bounce-off! (- paddle-x (/ PW 2)) PY PW PH))
              (define rel (clamp (/ (- bx paddle-x) (/ PW 2)) -1.0 1.0))
              (define a (* rel 1.05))
              (set! speed (min 900.0 (+ speed 6.0)))
              (set! vx (* speed (sin a))) (set! vy (- (* speed (cos a))))
              (set! by (- PY BR 0.5))
              (set! squash 1.0) (kick! 3.0))
            ;; bricks: at most one per substep
            (for/first ([b (in-list bricks)]
                        #:when (and (brick-alive? b) (bounce-off! (brick-x b) (brick-y b) BW BH)))
              (hit-brick! b))
            ;; lost ball
            (when (> by (+ H BR))
              (set! lives (sub1 lives)) (kick! 14.0) (set! flash 0.8) (set! aberration 10.0)
              (set! state (if (zero? lives) 'over 'serve))))
          (unless (ormap brick-alive? bricks)
            (set! level (add1 level)) (set! speed (+ 420.0 (* 40 level)))
            (set! bricks (make-level)) (set! state 'serve) (set! flash 1.0))]
         [else (void)])
       ;; trail, particles, juice decay
       (set! trail (take (cons (list bx by) trail) (min 12 (add1 (length trail)))))
       (set! particles
             (for/list ([p (in-list particles)] #:when (> (particle-life p) 0))
               (set-particle-vy! p (+ (particle-vy p) (* 700 dt)))
               (set-particle-x! p (+ (particle-x p) (* (particle-vx p) dt)))
               (set-particle-y! p (+ (particle-y p) (* (particle-vy p) dt)))
               (set-particle-life! p (- (particle-life p) (* 1.6 dt)))
               p))
       (set! shake (* shake (exp (* -10 dt))))
       (set! flash (* flash (exp (* -8 dt))))
       (set! aberration (+ 1.2 (* (- aberration 1.2) (exp (* -6 dt)))))
       (set! squash (* squash (exp (* -12 dt))))
       (set! impact-age (+ impact-age dt)))

     (define (center-text c font text y color)
       (paint-set-color! fill color)
       (draw-simple-text c text (/ (- W (measure-simple-text font text)) 2) y font fill))

     (define (draw-scene c time)
       (with-canvas-state c
         (canvas-translate! c (* shake (rand-range -1 1)) (* shake (rand-range -1 1)))
         ;; background shader
         (with-skia ([s (runtime-effect->shader
                         bg-fx #:uniforms (hash 'resolution (list W H) 'time time
                                                'impact impact 'age impact-age))]
                     [p (make-paint #:shader s)])
           (draw-rect c -20 -20 (+ W 40) (+ H 40) p))
         ;; bricks with a highlight strip
         (for ([b (in-list bricks)] #:when (brick-alive? b))
           (define col (vector-ref row-colors (brick-row b)))
           (paint-set-color! glow (fade col 0.35))
           (draw-rounded-rect c (brick-x b) (brick-y b) BW BH 6 6 glow)
           (paint-set-color! fill col)
           (draw-rounded-rect c (brick-x b) (brick-y b) BW BH 6 6 fill)
           (paint-set-color! fill (rgba 255 255 255 70))
           (draw-rounded-rect c (+ (brick-x b) 4) (+ (brick-y b) 3) (- BW 8) 5 2 2 fill))
         ;; particles
         (for ([p (in-list particles)])
           (paint-set-color! fill (fade (particle-color p) (particle-life p)))
           (draw-circle c (particle-x p) (particle-y p) (+ 1.5 (* 2.5 (particle-life p))) fill))
         ;; paddle with squash
         (define pw (* PW (+ 1 (* 0.25 squash)))) (define ph (* PH (- 1 (* 0.4 squash))))
         (define px (- paddle-x (/ pw 2))) (define py (+ PY (- PH ph)))
         (paint-set-color! glow (rgba 120 200 255 140))
         (draw-rounded-rect c px py pw ph 8 8 glow)
         (paint-set-color! fill (rgba 230 245 255 255))
         (draw-rounded-rect c px py pw ph 8 8 fill)
         ;; ball trail, glow, ball
         (for ([pt (in-list (reverse trail))] [i (in-naturals)])
           (define k (/ (add1 i) (add1 (length trail))))
           (paint-set-color! fill (rgba 120 220 255 (exact-round (* 120 k))))
           (draw-circle c (car pt) (cadr pt) (* BR k) fill))
         (paint-set-color! glow (rgba 120 220 255 200))
         (draw-circle c bx by (* BR 1.8) glow)
         (paint-set-color! fill 'white)
         (draw-circle c bx by BR fill))
       ;; HUD (not shaken)
       (paint-set-color! fill (rgba 255 255 255 220))
       (draw-simple-text c (format "SCORE ~a" score) 24 40 small-font fill)
       (draw-simple-text c (format "LEVEL ~a" level) (- (/ W 2) 40) 40 small-font fill)
       (draw-simple-text c (format "BALLS ~a" lives) (- W 130) 40 small-font fill)
       (case state
         [(serve) (center-text c small-font "Click or press SPACE to launch" (+ (/ H 2) 60)
                               (rgba 255 255 255 200))]
         [(over) (center-text c big-font "GAME OVER" (/ H 2) (rgba 255 107 107 255))
                 (center-text c small-font "SPACE to play again" (+ (/ H 2) 50)
                              (rgba 255 255 255 200))]
         [else (void)]))

     (define (render frame)
       (define now (current-inexact-milliseconds))
       (define dt (min 0.05 (/ (- now last-t) 1000.0)))
       (set! last-t now)
       (step! dt)
       (define c (gpu-frame-canvas frame))
       (define time (/ (- now t0) 1000.0))
       (define sx (/ (gpu-frame-width frame) W)) (define sy (/ (gpu-frame-height frame) H))
       (cond
         [crt?
          (unless offscreen
            (set! offscreen (make-gpu-surface (gpu-frame-context frame)
                                              (exact-round W) (exact-round H)
                                              #:background 'black)))
          (define oc (surface-canvas offscreen))
          (canvas-clear! oc 'black)
          (draw-scene oc time)
          ;; Post-pass: the snapshot becomes the CRT shader's child.
          (with-skia ([snap (gpu-surface-snapshot offscreen)]
                      [scene (make-image-shader snap #:sampling 'linear)]
                      [post (runtime-effect->shader
                             crt-fx #:uniforms (hash 'resolution (list W H)
                                                     'aberration aberration 'flash flash)
                             #:children (hash 'scene scene))]
                      [p (make-paint #:shader post)])
            (with-canvas-state c
              (canvas-scale! c sx sy)
              (draw-rect c 0 0 W H p)))]
         [else
          (with-canvas-state c
            (canvas-scale! c sx sy)
            (draw-scene c time)
            ;; Without the post-pass, approximate the flash directly.
            (paint-set-color! fill (rgba 255 255 255 (exact-round (* 90 flash))))
            (draw-rect c 0 0 W H fill))]))

     (define timer #f)
     (define canvas #f)
     (define (shutdown!)
       (when timer (send timer stop))
       ;; Retire resources that may retain the presenter's GPU context first.
       (for ([r (list offscreen glow fill glow-filter crt-fx bg-fx big-font small-font)] #:when r)
         (skia-close! r))
       (send canvas close-gpu))

     (define game-canvas%
       (class gpu-canvas%
         (super-new)
         (define/override (on-event e)
           (define-values (cw ch) (send this get-client-size))
           (when (positive? cw) (set! target-x (* (send e get-x) (/ W cw))))
           (when (send e button-down? 'left) (launch!)))
         (define/override (on-char e)
           (define code (send e get-key-code))
           (define release (send e get-key-release-code))
           (cond
             [(eq? code 'release)
              (case release [(left) (set! left? #f)] [(right) (set! right? #f)] [else (void)])]
             [else
              (case code
                [(left) (set! left? #t)]
                [(right) (set! right? #t)]
                [(#\space) (launch!)]
                [(#\c #\C) (set! crt? (not crt?))]
                [else (void)])]))))

     (define window
       (new (class frame% (super-new) (define/augment (on-close) (shutdown!)))
            [label "Skia Breakout"] [width 960] [height 600]))
     (set! canvas
           (new game-canvas% [parent window] [backend backend] [render render]
                [background 'black]
                [on-error (lambda (e)
                            (when timer (send timer stop))
                            (eprintf "render failed: ~a\n" (if (exn? e) (exn-message e) e)))]))
     (set! timer (new timer% [interval 16]
                      [notify-callback (lambda () (send canvas request-gpu-render))]))
     (send window show #t)
     (send canvas focus))))

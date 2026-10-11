#lang racket

(require skia "model.rkt")
(provide editor-width editor-height header-height footer-height draw-editor)

(define editor-width 800)
(define editor-height 500)
(define header-height 104)
(define footer-height 38)

(define (curve-path points)
  (match-define (list (control-point x0 y0) (control-point x1 y1)
                      (control-point x2 y2) (control-point x3 y3)) points)
  (make-path `((move ,x0 ,y0) (cubic ,x1 ,y1 ,x2 ,y2 ,x3 ,y3))))

(define (draw-model canvas points view width height)
  (define zoom (view-state-zoom view))
  (define grid (make-paint #:color "#20344D" #:style 'stroke #:stroke-width (/ 1 zoom)))
  (define guide (make-paint #:color "#6886A4" #:style 'stroke #:stroke-width (/ 1.5 zoom)))
  (define curve (make-paint #:color "#F1F7FD" #:style 'stroke #:stroke-width 4 #:cap 'round))
  (define-values (left top) (screen->model view 0 header-height))
  (define-values (right bottom) (screen->model view width (- height footer-height)))
  (with-canvas-state canvas
    (canvas-translate! canvas (view-state-pan-x view) (view-state-pan-y view))
    (canvas-scale! canvas zoom zoom)
    (for ([x (in-range (* 50 (floor (/ left 50))) (+ right 50) 50)])
      (draw-line canvas x top x bottom grid))
    (for ([y (in-range (* 50 (floor (/ top 50))) (+ bottom 50) 50)])
      (draw-line canvas left y right y grid))
    (for ([a (in-list (take points 3))] [b (in-list (rest points))])
      (draw-line canvas (control-point-x a) (control-point-y a)
                 (control-point-x b) (control-point-y b) guide))
    (with-skia ([path (curve-path points)])
      (draw-path canvas path curve))))

(define (draw-handles canvas points view selected)
  (define amber (make-paint #:color "#FFBF72"))
  (define cyan (make-paint #:color "#56D3E1"))
  (define ink (make-paint #:color "#F1F7FD"))
  (define ring (make-paint #:color 'white #:style 'stroke #:stroke-width 2))
  (define font (make-font #:size 15))
  ;; This is screen-space decoration: neither marker nor label grows with zoom.
  (for ([point (in-list points)] [index (in-naturals)])
    (define-values (x y)
      (model->screen view (control-point-x point) (control-point-y point)))
    (define label-x (if (= index 2) (- x 37) (+ x 16)))
    (define label-y (if (member index '(1 2)) (+ y 30) (- y 16)))
    (when (equal? index selected) (draw-circle canvas x y 16 ring))
    (draw-circle canvas x y 10 (if (member index '(0 3)) amber cyan))
    (draw-simple-text canvas (format "P~a" index) label-x label-y font ink)))

(define (draw-editor canvas points view width height [selected #f])
  (define text (make-paint #:color "#E6F2FB"))
  (define muted (make-paint #:color "#A0BDD1"))
  (define title-font (make-font #:size 24))
  (define caption-font (make-font #:size 13))
  (canvas-clear! canvas "#0C182B")
  (when (> height (+ header-height footer-height))
    (with-canvas-state canvas
      (canvas-clip-rect! canvas 0 header-height width
                         (- height header-height footer-height))
      (draw-model canvas points view width height)
      (draw-handles canvas points view selected)))
  ;; The header/footer are outside the model transform and content clip.
  (draw-simple-text canvas "NAVIGATE THE CURVE" 28 43 title-font text)
  (draw-simple-text canvas "Drag a point. Shift-drag to pan. Scroll to zoom." 29 75
                    caption-font muted)
  (draw-simple-text canvas
                    (format "ZOOM ~a%   /   MODEL POINTS ARE UNCHANGED BY THE VIEW"
                            (exact-round (* 100 (view-state-zoom view))))
                    28 (- height 15) caption-font muted))

(module+ main
  (define surface (make-surface editor-width editor-height))
  (draw-editor (surface-canvas surface) initial-points home-view editor-width editor-height)
  (save-png surface "navigation.png" #:exists 'replace))

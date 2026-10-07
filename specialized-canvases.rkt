#lang racket/base
;; These constructors borrow native canvases, never adopt caller-owned targets.
;; An application callback runs outside the FFI/atomic allocation sections.
(require ffi/unsafe racket/list
         "private/core.rkt" "private/native.rkt" "private/types.rkt"
         "private/check.rkt" "private/lifetime.rkt" "private/audit-trace.rkt"
         (submod "private/core.rkt" advanced-canvas-internals))
(provide call-with-nodraw-canvas call-with-nway-canvas call-with-overdraw-canvas)
(define (callback! who proc)
  (unless (and (procedure? proc) (procedure-arity-includes? proc 1)
               (let-values ([(required allowed) (procedure-keywords proc)]) (null? required)))
    (raise-argument-error who "procedure accepting one canvas without required keywords" proc)))
(define (root-target! who surface)
  (unless (surface? surface) (raise-argument-error who "surface?" surface))
  (check-unborrowed-target! who surface)
  (define c (surface-canvas surface))
  (call-on-canvas who c '()
    (lambda (cp)
      (define m (make-sk-m44 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0
                              0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0))
      (sk_canvas_get_matrix cp m)
      (define clip (make-sk-irect 0 0 0 0))
      (unless (and (= (sk_canvas_get_save_count cp) 1)
                   (for/and ([i (in-range 16)])
                     (= (ptr-ref m _float i) (if (memv i '(0 5 10 15)) 1 0)))
                   (sk_canvas_is_clip_rect cp)
                   (sk_canvas_get_device_clip_bounds cp clip)
                   (= (sk-irect-left clip) 0) (= (sk-irect-top clip) 0)
                   (= (sk-irect-right clip) (surface-width surface))
                   (= (sk-irect-bottom clip) (surface-height surface)))
        (error who "target must have a balanced root canvas, identity matrix and full rectangular clip"))
      (void/reference-sink m clip)))
  c)
(define (call-special who kind width height surfaces canvases create destroy attach detach proc)
  (audit-specialized-scope!)
  (define handles (map (lambda (s) (surface-h who s)) surfaces))
  ;; Joining every owner validates thread/current-domain and cross-context
  ;; exclusion BEFORE any target is locked or a native wrapper is allocated.
  (call-with-owned who handles (lambda ignored (void)))
  (define domain (and (pair? handles) (owned-gpu-domain (car handles))))
  (define context (and domain (owned-gpu-context (car handles))))
  (define backend (cond [(eq? kind 'nodraw) 'nodraw] [domain 'gpu] [else 'raster]))
  (define execution (if (null? surfaces) 'nodraw (surface-backend (car surfaces))))
  (define pointers
    (for/list ([c (in-list canvases)]) (call-on-canvas who c '() values)))
  (define handle #f) (define owner #f) (define borrowed #f)
  (define saved '()) (define entered? #f)
  (define (cleanup!)
    ;; Keep all underlying surfaces locked until the wrapper no longer holds
    ;; their pointers. Every target's state is restored even after a body error.
    (parameterize-break #f
      (dynamic-wind void
        (lambda ()
          (when handle
            (dynamic-wind void
              (lambda ()
                (call-with-owned who (list handle)
                  (lambda (cp)
                    (sk_canvas_restore_to_count cp 1)
                    (detach cp pointers))))
              (lambda ()
                (when owner
                  (set-specialized-canvas-owner-live?! owner #f)
                  (set-specialized-canvas-owner-dependencies! owner '()))
                (owned-close! who handle)))))
        (lambda ()
          (for ([entry (in-list saved)])
            (dynamic-wind void
              (lambda () (sk_canvas_restore_to_count (cadr entry) (caddr entry)))
              (lambda () (hash-remove! canvas-target-borrows (car entry)))))
          (for ([s (in-list surfaces)]) (hash-remove! canvas-target-borrows s))))))
  (call-with-continuation-barrier
    (lambda ()
      (dynamic-wind
        (lambda ()
          (when entered? (error who "specialized canvas scope cannot be reentered"))
          (set! entered? #t)
          (with-handlers ([(lambda (_) #t) (lambda (e) (cleanup!) (raise e))])
            (parameterize-break #f
              (for ([s (in-list surfaces)] [cp (in-list pointers)])
                (check-unborrowed-target! who s)
                (define count (sk_canvas_save cp))
                (set! saved (cons (list s cp count) saved))
                (hash-set! canvas-target-borrows s #t))
              (set! handle
                (if domain
                    (new-gpu-owned who 'specialized-canvas domain context create destroy)
                    (new-owned who 'specialized-canvas create destroy)))
              (call-with-owned who (list handle) (lambda (cp) (attach cp pointers)))
              (set! owner (specialized-canvas-owner handle kind backend execution canvases '() #t))
              (set! borrowed (make-canvas-record owner)))))
        (lambda () (call-with-output-capture (lambda () (proc borrowed))))
        cleanup!))))
(define (call-with-nodraw-canvas width height proc)
  (define who 'call-with-nodraw-canvas)
  (check-dimensions who width height)
  (callback! who proc)
  (skia-check!)
  (call-special who 'nodraw width height '() '()
    (lambda () (sk_nodraw_canvas_new width height)) sk_nodraw_canvas_destroy
    (lambda ignored (void)) (lambda ignored (void)) proc))
(define (call-with-nway-canvas surfaces proc)
  (define who 'call-with-nway-canvas)
  (callback! who proc)
  (unless (and (list? surfaces) (<= 1 (length surfaces) 64) (andmap surface? surfaces))
    (raise-argument-error who "list of 1 through 64 owned surfaces" surfaces))
  (unless (= (length surfaces) (length (remove-duplicates surfaces eq?)))
    (error who "duplicate target surface"))
  (define width (surface-width (car surfaces)))
  (define height (surface-height (car surfaces)))
  (define execution (surface-backend (car surfaces)))
  (for ([s (in-list surfaces)])
    (unless (and (= width (surface-width s)) (= height (surface-height s))
                 (eq? execution (surface-backend s)))
      (error who "targets must have identical dimensions and execution backends")))
  (define canvases (map (lambda (s) (root-target! who s)) surfaces))
  (call-special who 'nway width height surfaces canvases
    (lambda () (sk_nway_canvas_new width height)) sk_nway_canvas_destroy
    (lambda (cp targets) (for ([target (in-list targets)]) (sk_nway_canvas_add_canvas cp target)))
    (lambda (cp targets)
      (for ([target (in-list targets)]) (sk_nway_canvas_remove_canvas cp target))
      (sk_nway_canvas_remove_all cp))
    proc))
(define (call-with-overdraw-canvas surface proc)
  (define who 'call-with-overdraw-canvas)
  (callback! who proc)
  (define c (root-target! who surface))
  ;; Alpha8 gives a direct 8-bit, saturating count channel. This is a diagnostic
  ;; of native overdraw approximations, not hardware fragment/occlusion counts.
  (call-with-owned who (list (surface-h who surface))
    (lambda (sp)
      (call-with-native-temporary who 'overdraw-format-snapshot
        (lambda () (sk_surface_new_image_snapshot sp)) sk_image_unref
        (lambda (ip)
          (unless (= (sk_image_get_color_type ip) 1)
            (error who "overdraw requires an Alpha8 target; initialize it to zero first"))))))
  (define cp (call-on-canvas who c '() values))
  (call-special who 'overdraw (surface-width surface) (surface-height surface)
    (list surface) (list c)
    (lambda () (sk_overdraw_canvas_new cp)) sk_overdraw_canvas_destroy
    (lambda ignored (void)) (lambda (wrapper targets) (sk_nway_canvas_remove_all wrapper)) proc))

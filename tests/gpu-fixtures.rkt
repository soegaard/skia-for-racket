#lang racket/base
(require "../private/gpu-provider.rkt" "../private/gpu-domain.rkt")
(provide current-mock make-mock call-with-mock mock-resource events event-count in-worker collect-until)
(define current-mock (make-parameter #f))
(define (make-mock #:key [key (gensym 'host)] #:create [create #f]
                   #:describe [describe #f] #:release [release #f])
  (define log (box '()))
  (define abandoned? (box #f))
  (define (emit event) (set-box! log (cons event (unbox log))))
  (define provider
    (make-gpu-provider
     #:name 'mock #:backend 'opengl #:key key
     #:current? (lambda () (eq? key (current-mock)))
     #:call-as-current
     (lambda (thunk)
       (dynamic-wind
         (lambda () (emit 'activate))
         (lambda () (parameterize ([current-mock key]) (thunk)))
         (lambda () (emit 'deactivate))))))
  (define driver
    (gpu-driver
     (lambda () (emit 'create) (if create (create) (gensym 'native)))
     (lambda (p)
       (unless (or (unbox abandoned?) (eq? key (current-mock)))
         (error 'mock "context release without native activation"))
       (emit 'release-context)
       (when release (release p)))
     (lambda (_) (emit 'abandon) (set-box! abandoned? #t))
     (lambda (_) (emit 'reset))
     (lambda (_) (emit 'describe) (if describe (describe) (hasheq 'renderer "mock")))))
  (values provider driver log abandoned?))
(define (call-with-mock proc)
  (define-values (provider driver log abandoned?) (make-mock))
  (define domain (make-gpu-domain provider driver))
  (dynamic-wind void (lambda () (proc domain provider driver log abandoned?))
                (lambda () (domain-close! domain))))
(define (mock-resource domain log abandoned? [kind 'child])
  (domain-new-resource
   domain kind (lambda () (gensym kind))
   (lambda (_)
     (unless (or (unbox abandoned?) (current-mock))
       (error 'mock "child release without native activation"))
     (set-box! log (cons kind (unbox log))))))
(define (events log) (reverse (unbox log)))
(define (event-count log event)
  (for/sum ([item (in-list (unbox log))]) (if (eq? item event) 1 0)))
(define (in-worker thunk)
  (define channel (make-channel))
  (define worker
    (thread (lambda ()
              (channel-put channel
                (with-handlers ([exn:fail? (lambda (e) e)])
                  (thunk) 'returned)))))
  (define value (sync/timeout 5 channel))
  (unless value (kill-thread worker) (error 'in-worker "worker timed out"))
  (thread-wait worker)
  value)
(define (collect-until pred)
  (let loop ([remaining 40])
    (cond [(pred) #t]
          [(zero? remaining) #f]
          [else (collect-garbage) (sleep 0.01) (loop (sub1 remaining))])))

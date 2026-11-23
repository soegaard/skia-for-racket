#lang racket/base

;;;
;;; Optional mpv Audio Adapter
;;;

;; This module intentionally has no static dependency on racket/unix-socket. A normal package
;; compile and the silent player therefore work without unix-socket-lib; the dependency is resolved
;; only when an explicitly requested macOS/Linux audio session starts.

(require json
         racket/async-channel
         racket/file
         racket/format
         racket/list
         racket/math
         racket/match
         racket/port
         racket/system)

(provide mpv-audio?
         mpv-audio-snapshot?
         mpv-audio-snapshot-state
         mpv-audio-snapshot-media-time
         mpv-audio-snapshot-clock-ms
         mpv-audio-snapshot-eof?
         mpv-audio-snapshot-error
         start-mpv-audio
         mpv-audio-current-snapshot
         mpv-audio-play!
         mpv-audio-pause!
         mpv-audio-seek!
         mpv-audio-close!)

;; Snapshots contain ordinary immutable data and are safe to read from the GUI eventspace.
(struct mpv-audio-snapshot (state media-time clock-ms eof? error) #:transparent)
(struct mpv-audio (process commands lock snapshot-box closed? worker endpoint media-path)
  #:mutable
  #:transparent)

(define (now) (current-inexact-monotonic-milliseconds))

(define (set-snapshot! audio state #:media-time [media-time #f] #:eof? [eof? #f]
                       #:error [error #f])
  (call-with-semaphore (mpv-audio-lock audio)
    (lambda ()
      (define prior (unbox (mpv-audio-snapshot-box audio)))
      (set-box! (mpv-audio-snapshot-box audio)
                (mpv-audio-snapshot state
                                    (if (eq? media-time 'keep)
                                        (mpv-audio-snapshot-media-time prior)
                                        media-time)
                                    (now) eof? error)))))

(define (mpv-audio-current-snapshot audio)
  (unless (mpv-audio? audio)
    (raise-argument-error 'mpv-audio-current-snapshot "mpv-audio?" audio))
  (call-with-semaphore (mpv-audio-lock audio)
    (lambda () (unbox (mpv-audio-snapshot-box audio)))))

(define (socket-endpoint)
  ;; macOS limits Unix-domain socket paths to about 104 bytes. Use a short, private temp location.
  (build-path (find-system-path 'temp-dir)
              (format "ba-~a-~a.sock" (current-process-milliseconds) (random 1000000))))

(define (dynamic-unix-connect)
  (with-handlers ([exn:fail?
                   (lambda (error)
                     (raise-arguments-error
                      'start-mpv-audio
                      "audio needs the optional unix-socket-lib package on this platform"
                      "detail" (exn-message error)))])
    (dynamic-require 'racket/unix-socket 'unix-socket-connect)))

(define (connect-with-retry connect endpoint audio)
  (let loop ([attempt 0])
    (when (mpv-audio-closed? audio)
      (error 'start-mpv-audio "audio startup was cancelled"))
    (with-handlers ([exn:fail?
                     (lambda (error)
                       (if (< attempt 100)
                           (begin (sleep 0.02) (loop (add1 attempt)))
                           (raise-arguments-error 'start-mpv-audio
                                                  "mpv did not create its IPC endpoint"
                                                  "endpoint" endpoint
                                                  "detail" (exn-message error))))])
      (connect endpoint))))

(define (write-command output command)
  (write-json (hasheq 'command command) output)
  (newline output)
  (flush-output output))

(define (message-position message)
  (define event (hash-ref message 'event #f))
  (define name (hash-ref message 'name #f))
  (define value (hash-ref message 'data #f))
  (and (string? event) (string? name) (string=? event "property-change")
       (member name '("audio-pts" "time-pos"))
       (real? value)
       value))

(define (run-audio-worker audio connect media-path)
  (define input #f)
  (define output #f)
  (define endpoint (mpv-audio-endpoint audio))
  (define (stop-ports!)
    (when input (close-input-port input) (set! input #f))
    (when output (close-output-port output) (set! output #f)))
  (dynamic-wind
    void
    (lambda ()
      (with-handlers ([exn:fail?
                       (lambda (error)
                         (unless (mpv-audio-closed? audio)
                           (set-snapshot! audio 'error #:media-time 'keep
                                          #:error (exn-message error))))])
        (define-values (in out) (connect-with-retry connect endpoint audio))
        (set! input in)
        (set! output out)
        ;; Load the supplied absolute media path while paused, then request both a presentation-time
        ;; property and a documented fallback. mpv events and replies are newline-delimited JSON.
        (write-command output (list "loadfile" (path->string (path->complete-path media-path)) "replace"))
        (write-command output (list "observe_property" 1 "audio-pts"))
        (write-command output (list "observe_property" 2 "time-pos"))
        (set-snapshot! audio 'ready #:media-time #f)
        (let loop ()
          (define event
            (sync (handle-evt input (lambda (_) 'input))
                  (handle-evt (mpv-audio-commands audio)
                              (lambda (command) (cons 'command command)))))
          (match event
            ['input
             (define line (read-line input 'any))
             (cond
               [(eof-object? line)
                (unless (mpv-audio-closed? audio)
                  (set-snapshot! audio 'error #:media-time 'keep #:error "mpv IPC disconnected"))]
               [else
                (with-handlers ([exn:fail? (lambda (_error) (void))])
                  (define message (read-json (open-input-string line)))
                  (define position (message-position message))
                  (cond
                    [position
                     (set-snapshot! audio
                                    (mpv-audio-snapshot-state (mpv-audio-current-snapshot audio))
                                    #:media-time position)]
                    [(and (string=? (hash-ref message 'event "") "end-file")
                          (string=? (hash-ref message 'reason "") "eof"))
                     (set-snapshot! audio 'ended #:media-time 'keep #:eof? #t)]))
                (unless (mpv-audio-closed? audio) (loop))])]
            [(cons 'command command)
             (if (eq? command 'quit)
                 (begin (write-command output '("quit")) (set-mpv-audio-closed?! audio #t))
                 (begin (write-command output command) (loop)))]))))
    (lambda ()
      (stop-ports!)
      (when (file-exists? endpoint) (delete-file endpoint))
      (when (and (subprocess? (mpv-audio-process audio))
                 (not (subprocess-status (mpv-audio-process audio))))
        (subprocess-kill (mpv-audio-process audio) #t))
      (when (mpv-audio-closed? audio) (set-snapshot! audio 'closed #:media-time 'keep)))))

;; start-mpv-audio : path-string? [#:executable path-string?] -> mpv-audio?
;; Starts an owned, paused, audio-only mpv process. Socket I/O and process supervision remain on a
;; worker; callers must never wait on this adapter from a drawing callback.
(define (start-mpv-audio media-path #:executable [executable "mpv"])
  (when (eq? (system-type 'os) 'windows)
    (error 'start-mpv-audio "Windows mpv named-pipe audio is not implemented; run silently"))
  (unless (file-exists? media-path)
    (raise-arguments-error 'start-mpv-audio "media file does not exist" "path" media-path))
  (define connect (dynamic-unix-connect))
  (define program (or (find-executable-path executable)
                      (raise-arguments-error 'start-mpv-audio "mpv executable was not found"
                                             "executable" executable)))
  (define endpoint (socket-endpoint))
  (define endpoint-option (string-append "--input-ipc-server=" (path->string endpoint)))
  (define-values (process output input error)
    (subprocess #f #f #f program "--no-config" "--load-scripts=no" "--vid=no" "--terminal=no"
                "--idle=yes" "--pause=yes" endpoint-option))
  ;; mpv's conventional stdout/stderr are not used for control; close their inherited ports so the
  ;; process lifecycle is governed solely by its private IPC endpoint.
  (when output (close-input-port output))
  (when input (close-output-port input))
  (when error (close-input-port error))
  (letrec ([audio (mpv-audio process (make-async-channel) (make-semaphore 1)
                            (box (mpv-audio-snapshot 'starting #f (now) #f #f)) #f #f endpoint
                            (path->complete-path media-path))])
    (set-mpv-audio-worker! audio (thread (lambda () (run-audio-worker audio connect media-path))))
    audio))

(define (enqueue! who audio command new-state)
  (unless (mpv-audio? audio) (raise-argument-error who "mpv-audio?" audio))
  (unless (mpv-audio-closed? audio)
    (set-snapshot! audio new-state #:media-time 'keep)
    (async-channel-put (mpv-audio-commands audio) command))
  (void))

(define (reload-if-eof! audio)
  ;; With --idle=yes, mpv unloads its file after natural EOF. Reopen the owned media before a
  ;; restart/loop command instead of assuming a bare seek can resurrect the stream.
  (when (mpv-audio-snapshot-eof? (mpv-audio-current-snapshot audio))
    (async-channel-put (mpv-audio-commands audio)
                       (list "loadfile" (path->string (mpv-audio-media-path audio)) "replace"))))

(define (mpv-audio-play! audio)
  (unless (mpv-audio? audio) (raise-argument-error 'mpv-audio-play! "mpv-audio?" audio))
  (reload-if-eof! audio)
  (enqueue! 'mpv-audio-play! audio '("set_property" "pause" #f) 'playing))
(define (mpv-audio-pause! audio) (enqueue! 'mpv-audio-pause! audio '("set_property" "pause" #t) 'paused))

(define (mpv-audio-seek! audio seconds)
  (unless (and (real? seconds) (not (nan? seconds)) (not (infinite? seconds)))
    (raise-argument-error 'mpv-audio-seek! "finite real seconds" seconds))
  (unless (mpv-audio? audio) (raise-argument-error 'mpv-audio-seek! "mpv-audio?" audio))
  (reload-if-eof! audio)
  (enqueue! 'mpv-audio-seek! audio (list "seek" (max 0 seconds) "absolute+exact") 'paused))

(define (mpv-audio-close! audio)
  (unless (mpv-audio? audio) (raise-argument-error 'mpv-audio-close! "mpv-audio?" audio))
  (unless (mpv-audio-closed? audio)
    (set-mpv-audio-closed?! audio #t)
    (async-channel-put (mpv-audio-commands audio) 'quit))
  (void))

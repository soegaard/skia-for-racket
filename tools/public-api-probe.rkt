#lang racket/base

;;;
;;; Public API Reflection Probe
;;;

;; Reflects requested public modules in an isolated process and emits their export shapes.
;; The API inventory workflow uses this process boundary to observe loading and GUI side effects.

;;;
;;; Imports and Exports
;;;

;; Run in a fresh subprocess. This program writes only an observation, never the
;; checked-in expected snapshot. The Python gate verifies its token and coverage.
(require racket/cmdline racket/file racket/path racket/list json
         "public-api-reflect.rkt")

;;;
;;; Public API Probe Worker
;;;

(module+ main

  ;;;
  ;;; Command-Line Run
  ;;;

  ; root : (or/c path-string? #f)
  ;   Holds the checkout root against which all policy module paths are resolved.
  (define root #f)

  ; policy-path : (or/c path-string? #f)
  ;   Selects the JSON policy describing public modules and their allowed load groups.
  (define policy-path #f)

  ; group : (or/c string? #f)
  ;   Selects the policy load group to reflect in this isolated process.
  (define group #f)

  ; output : (or/c path-string? #f)
  ;   Holds the destination for reflected public-export evidence.
  (define output #f)

  ; token : (or/c string? #f)
  ;   Carries the caller's run identifier into evidence so independent validation can match
  ;   artifacts.
  (define token #f)
  (command-line
   #:once-each
   [("--root") value "Source root" (set! root (path->complete-path value))]
   [("--policy") value "Reviewed module policy" (set! policy-path (path->complete-path value))]
   [("--group") value "headless or gui" (set! group value)]
   [("--output") value "New observation file" (set! output (path->complete-path value))]
   [("--token") value "Invocation identity" (set! token value)]
   #:args () (void))
  (unless (and root policy-path output token (member group '("headless" "gui")))
    (error 'public-api-probe "--root, --policy, --group, --output and --token are required"))

  ; policy : hash?
  ;   Contains the decoded module and load-group policy.
  (define policy (call-with-input-file policy-path read-json))

  ; modules : (listof hash?)
  ;   Selects policy entries belonging to this worker's load group.
  (define modules
    (filter (lambda (row) (string=? (hash-ref row 'load_group) group))
            (hash-ref policy 'modules)))
  (when (null? modules) (error 'public-api-probe "empty selected module group"))
  ;; Caller sets deliberately invalid library overrides. Reject a direct probe
  ;; invocation without them rather than implying native-free evidence.
  (for ([name '("RACKET_SKIA_LIBRARY" "RACKET_HARFBUZZ_LIBRARY")])
    (define value (getenv name))
    (unless (and value (not (file-exists? value)) (not (directory-exists? value)))
      (error 'public-api-probe "~a must name a nonexistent path" name)))

  ; observations : (listof hash?)
  ;   Records reflected module exports after validating safe paths and headless GUI constraints.
  (define observations
    (for/list ([row (in-list modules)])
      (define name (hash-ref row 'path))
      (unless (and (string? name)
                   (not (regexp-match? #rx"(^/|\\\\|:|(^|/)\\.\\.?(/|$))" name)))
        (error 'public-api-probe "unsafe module name"))
      (define path (build-path root name))
      (define result (reflect-public-module path name))
      (when (and (string=? group "headless") (gui-instantiated?))
        (error 'public-api-probe "headless module instantiated GUI: ~a" name))
      result))

  ; result : hash?
  ;   Packages export observations, runtime identity, and explicit non-rendering scope into the
  ;   evidence report.
  (define result
    (hasheq 'schema 1 'stage "0.78c" 'status "passed" 'run_token token
            'group group 'modules observations
            'gui_instantiated (gui-instantiated?)
            'native_overrides "nonexistent" 'exported_procedures_called #f
            'rendering_executed #f 'release_ready #f
            'runtime (hasheq 'racket (version) 'os (symbol->string (system-type 'os))
                             'vm (symbol->string (system-type 'vm)))))
  (call-with-output-file output
    (lambda (out) (write-json result out) (newline out)) #:exists 'error)
  ;; Optional GUI imports may create an eventspace; no exported GUI class is
  ;; instantiated, and an eventspace must not keep a completed probe alive.
  (exit 0))

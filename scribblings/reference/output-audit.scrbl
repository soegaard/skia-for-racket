#lang scribble/manual

@(require scribble/eval
          (for-label racket/base racket/contract skia skia/output-policy skia/output-audit))

@(define policy-eval (make-base-eval))
@(policy-eval '(require skia/output-policy))

@title[#:tag "skia-output-audit"]{Output Policies and Auditing}

@defmodule[skia/output-policy #:no-declare]
@defmodule[skia/output-audit #:no-declare]
@(declare-exporting skia skia/output-policy skia/output-audit #:use-sources (skia/output-policy
                    skia/output-audit))

An @deftech{output audit} records known representation risks encountered while an output
callback executes. It is not static analysis, a pixel comparison, a font-embedding check, an ICC
validator, or a PDF/A conformance test. The policy table describes the supported serialization
policy; it does not probe arbitrary native builds or predict a viewer's exact output.

A preflight executes the callback too. Metrics, resource construction, graphics-state changes,
and explicit raster work still occur. Ordinary Racket side effects are not rolled back. Do not
use these operations to analyze untrusted or nonterminating callbacks.

@local-table-of-contents[#:style 'immediate-only]

@section{Capability Table}

@defthing[output-backends list?]{
The list @racket['(pdf svg raster)] of output representation backends.
}

@defthing[output-feature-names list?]{
The list of recognized feature symbols accepted by @racket[output-capability-for]. Features
describe operations and retained resource properties, such as @racket['geometry],
@racket['image], @racket['native-text], @racket['runtime-shader], @racket['annotation], and
@racket['projective-transform]. The list is a policy vocabulary, not an inventory of functions
or a claim that all features are supported on every backend.
}

@defproc[(output-capability? [v any/c])
          boolean?]{
Returns @racket[#t] for an immutable capability description and @racket[#f] otherwise.
Descriptions contain no native resources.
}

@defproc[(output-capability-for [backend (or/c 'pdf 'svg 'raster)] [feature symbol?])
          output-capability?]{
Returns the capability entry for the backend and a symbol in @racket[output-feature-names]. An
unknown spelling raises; it does not mean supported. Ordinary raster features are classified as
@racket['rasterized], while annotation loss and unknown provenance remain visible. The operation
does not load native code or draw.
}

@defproc[(output-capability-backend [capability output-capability?])
          (or/c 'pdf 'svg 'raster)]{
Returns the representation backend.
}

@defproc[(output-capability-feature [capability output-capability?])
          symbol?]{
Returns the recognized feature symbol.
}

@defproc[(output-capability-status [capability output-capability?])
          (or/c 'vector 'embedded-raster 'native-expansion 'needs-raster
                  'viewer-dependent 'rasterized 'discarded 'unknown 'unsupported)]{
Returns the policy status for the capability entry.
}

@defproc[(output-capability-reason [capability output-capability?])
          string?]{
Returns the explanatory reason. This is diagnostic text, not a stable machine-readable status
code.
}

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Status} @bold{Meaning})
  (list @racket['vector] "Vector geometry or document metadata; attached features are separate.")
  (list @racket['embedded-raster] "Existing raster samples are embedded, not made into vectors.")
  (list @racket['native-expansion] "Native expansion or rasterization may occur.")
  (list @racket['needs-raster] "Use an explicit raster boundary for the conservative policy.")
  (list @racket['viewer-dependent] "Appearance depends on the document viewer or its fonts.")
  (list @racket['rasterized] "Content is rendered into an explicit raster representation.")
  (list @racket['discarded] "Semantics such as interactivity are lost.")
  (list @racket['unknown] "The operation or resource provenance is not established.")
  (list @racket['unsupported] "Reserved blocking status for an unsupported operation."))]

@examples[#:eval policy-eval
  (eval:check
    (output-capability-status (output-capability-for 'svg 'runtime-shader))
    'needs-raster)
  (eval:check
    (output-capability-status (output-capability-for 'raster 'annotation))
    'discarded)]

@close-eval[policy-eval]

@section{Preflight and Audited Export}

Sources and export settings follow @racket[output->bytes]. A source is one output page or a
nonempty list of pages; SVG accepts only one page. The PDF-only and SVG-only options remain
restricted rather than ignored. The callback receives a real canvas for the selected backend.
Analyzing a page and then exporting it executes the authoring callback twice; an audited export
is the single-execution alternative.

@defproc[(analyze-output-page [source (or/c output-page? (listof output-page?))] [format (or/c
          'pdf 'svg)] [#:title title string? ""] [#:description description string? ""]
          [#:text-mode text-mode (or/c 'auto 'native 'outline) 'auto] [#:raster-dpi raster-dpi
          (real-in 1 9600) 144] [#:id-prefix id-prefix (or/c string? #f) #f] [#:encoding-quality
          quality (or/c (integer-in 0 101) #f) #f] [#:pdfa? pdfa? boolean? #f])
          output-audit-report?]{
Executes each page callback once in preflight mode and returns a report without returning or
publishing document bytes. Native target drawing calls are observed but suppressed. Explicit
raster groups, native allocations, and ordinary callback side effects still run. Invalid
resources, callback exceptions, and document-finalization errors propagate.
}

@defproc[(output->bytes/audit [source (or/c output-page? (listof output-page?))] [format (or/c
          'pdf 'svg)] [#:policy policy (or/c 'report 'error 'vector-only) 'report] [#:title
          title string? ""] [#:description description string? ""] [#:text-mode text-mode (or/c
          'auto 'native 'outline) 'auto] [#:raster-dpi raster-dpi (real-in 1 9600) 144]
          [#:id-prefix id-prefix (or/c string? #f) #f] [#:encoding-quality quality (or/c
          (integer-in 0 101) #f) #f] [#:pdfa? pdfa? boolean? #f])
          (values (and/c bytes? (not/c immutable?)) output-audit-report?)]{
Exports each page once and returns completed mutable document bytes and an immutable report. The
default @racket['report] policy collects observations without repairing unsupported native
behavior. The resulting file can still omit an effect when the caller chooses that policy.

The @racket['error] policy raises before an operation classified as @racket['needs-raster],
@racket['unsupported], @racket['unknown], or @racket['discarded]. Embedded images, native
expansion, and viewer-dependent text are permitted but reported. The @racket['vector-only]
policy rejects every status other than @racket['vector], including ordinary images and explicit
raster groups. These policies do not certify visual or semantic equivalence.
}

@defproc[(save-output/audit [source (or/c output-page? (listof output-page?))] [filename
          path-string?] [format (or/c 'pdf 'svg)] [#:policy policy (or/c 'report 'error
          'vector-only) 'error] [#:exists exists (or/c 'error 'replace) 'error] [#:title title
          string? ""] [#:description description string? ""] [#:text-mode text-mode (or/c 'auto
          'native 'outline) 'auto] [#:raster-dpi raster-dpi (real-in 1 9600) 144] [#:id-prefix
          id-prefix (or/c string? #f) #f] [#:encoding-quality quality (or/c (integer-in 0 101)
          #f) #f] [#:pdfa? pdfa? boolean? #f])
          output-audit-report?]{
Publishes a completed audited document and returns its report. The default policy is
@racket['error], unlike @racket[output->bytes/audit]. The destination is resolved before
callbacks run. Drawing, auditing, and finalization complete before publication through the
normal temporary-file/rename writer. An audit rejection does not truncate or replace the
destination. Callback side effects are not undone.
}

@racketblock[
(define page
  (make-output-page 20 20
    (lambda (canvas)
      (with-skia ([ink (make-paint #:color 'blue)])
        (draw-circle canvas 10 10 6 ink)))))
(define-values (document report)
  (output->bytes/audit page 'svg #:policy 'vector-only))
(list (positive? (bytes-length document))
      (output-audit-report-blocking? report))
]

The result is @racket['(#t #f)]. The report describes observed operations, not a visual comparison.

@section{Labels, Events, and Reports}

@defparam[current-output-audit-event-limit limit exact-positive-integer?]{
Limits the number of collected events. Its initial value is 100000. Exceeding it raises rather
than returning a report that appears complete. This is an event-count bound, not a bound on
callback time or total native memory. An active collector cannot be used from another thread.
}

@defproc[(call-with-output-label [label string?] [thunk (-> any)])
          any]{
Copies a label containing 1 through 200 characters and runs @racket[thunk] with that label in
the audit scope. Labels nest from outer to inner in reported events. The callback's values are
preserved. A label does not create a document annotation or a clipping region.
}

@defform[(with-output-label label-expr body ...+)]{
Like @racket[call-with-output-label], using the nonempty body as the callback. The body may
contain internal definitions and must end with an expression. It can return multiple values.
}

@defproc[(output-audit-event? [v any/c])
          boolean?]{
Returns @racket[#t] for a detached immutable observed event and @racket[#f] otherwise.
}

@defproc[(output-audit-event-page [event output-audit-event?])
          exact-positive-integer?]{
Returns the one-based page index.
}

@defproc[(output-audit-event-operation [event output-audit-event?])
          symbol?]{
Returns the observed underlying operation. One high-level drawing call can produce several
observations.
}

@defproc[(output-audit-event-scope [event output-audit-event?])
          (listof string?)]{
Returns the outer-to-inner scope labels and group identifiers.
}

@defproc[(output-audit-event-feature [event output-audit-event?])
          symbol?]{
Returns the feature assessed by this event. Paint, shader, and filter features can generate
separate events for one draw.
}

@defproc[(output-audit-event-status [event output-audit-event?])
          (or/c 'vector 'embedded-raster 'native-expansion 'needs-raster
                  'viewer-dependent 'rasterized 'discarded 'unknown 'unsupported)]{
Returns the policy classification for the observed feature and its representation scope.
}

@defproc[(output-audit-event-reason [event output-audit-event?])
          string?]{
Returns explanatory diagnostic text, not a separate capability test.
}

@defproc[(output-audit-event-details [event output-audit-event?])
          (and/c hash? immutable?)]{
Returns detached ordinary-value details, such as raster dimensions and execution metadata. The
result holds no native resource or callback.
}

@defproc[(output-audit-report? [v any/c])
          boolean?]{
Returns @racket[#t] for a detached immutable report and @racket[#f] otherwise.
}

@defproc[(output-audit-report-backend [report output-audit-report?])
          (or/c 'pdf 'svg 'raster)]{
Returns the representation backend.
}

@defproc[(output-audit-report-pages [report output-audit-report?])
          exact-positive-integer?]{
Returns the number of pages in the audited source.
}

@defproc[(output-audit-report-events [report output-audit-report?])
          (listof output-audit-event?)]{
Returns the events in observation order. Clipped or overpainted content can still appear in this
conservative record.
}

@defproc[(output-audit-report-mode [report output-audit-report?])
          (or/c 'preflight 'export)]{
Reports whether the callback ran as a preflight or an actual export.
}

@defproc[(output-audit-report-blocking? [report output-audit-report?])
          boolean?]{
Reports whether any event has a blocking status: needs-raster, unsupported, unknown, or
discarded. A false result does not establish visual equivalence.
}

@defproc[(output-audit-report-vector-only? [report output-audit-report?])
          boolean?]{
Reports whether every event has status @racket['vector]. An empty event list satisfies this
test; it is not proof of useful page content.
}

@defproc[(output-audit-report->jsexpr [report output-audit-report?])
          (and/c hash? immutable?)]{
Returns a detached JSON-compatible hash containing the backend, mode, page count, blocking and
vector-only summaries, scope qualification, and event details. Symbolic backend, mode,
operation, feature, and status values are converted to strings. This serialization is a report,
not an executable drawing.
}

@defproc[(exn:fail:output-audit? [v any/c])
          boolean?]{
Returns @racket[#t] for an output-policy rejection exception. Other argument, lifetime, native,
and publication errors retain their ordinary exception types.
}

@defproc[(exn:fail:output-audit-event [exception exn:fail:output-audit?])
          output-audit-event?]{
Returns the event that caused the policy rejection. It does not mean that preceding Racket
callback side effects have been rolled back.
}

Explicit rasterization resolves representation risks, not every semantic risk. It loses
searchable text and annotations, and cannot certify padding, backdrop completeness, or color
fidelity. Unknown provenance stays unknown. Recorded pictures retain conservative feature
summaries; closing a child wrapper does not remove a retained warning. The audit does not
intercept foreign code that bypasses Skia's public wrappers.

#lang racket/base
(require racket/list)
(provide output-capability? output-capability-backend output-capability-feature
         output-capability-status output-capability-reason
         output-capability-for output-feature-names output-backends
         output-audit-event? output-audit-event-page output-audit-event-operation
         output-audit-event-scope output-audit-event-feature output-audit-event-status
         output-audit-event-reason output-audit-event-details
         output-audit-report? output-audit-report-backend output-audit-report-pages
         output-audit-report-events output-audit-report-mode
         output-audit-report-blocking? output-audit-report-vector-only?
         output-audit-report->jsexpr
         exn:fail:output-audit? exn:fail:output-audit-event)

;; A conservative m119 policy table, not runtime driver introspection. The
;; predicates describe *known serialization risks*, not visual equivalence.
(struct output-capability (backend feature status reason) #:transparent)
(struct output-audit-event (page operation scope feature status reason details) #:transparent)
(struct output-audit-report (backend pages events mode) #:transparent)
(struct exn:fail:output-audit exn:fail (event) #:transparent)
(define output-backends '(pdf svg raster))
(define specifications
  ;; feature       PDF                  SVG                  explanation
  '((geometry       vector               vector               "Ordinary path/shape geometry; paint and clip features are reported separately.")
    (point-sprites  vector               needs-raster         "Native isolated-point drawing is not implemented by the pinned SVG device; rasterize point sets explicitly.")
    (recorded-color-fill vector          needs-raster         "An unbounded color fill recorded in a picture depends on the receiving clip/replay matrix. Use finite geometry or explicit rasterization for portable SVG replay.")
    (layer          native-expansion     needs-raster         "A compositing layer can expand/rasterize in PDF and is not generally preserved by SVG. Supply conservative content bounds: m119 may restrict the layer to them. Layer-contained annotations may be lost.")
    (native-text    vector               viewer-dependent     "SVG native glyph-to-text output depends on viewer fonts and may lose shaped glyphs; use outlines for portable geometry.")
    (image          embedded-raster      embedded-raster       "An existing raster image is embedded; this is not vector geometry or an ICC/font fidelity check.")
    (linear-gradient vector              vector               "Native linear-gradient serialization; resource composition is assessed separately.")
    (radial-gradient vector              needs-raster         "The pinned SVG serializer does not generally preserve radial-gradient shaders; rasterize the bounded group.")
    (sweep-gradient vector               needs-raster         "SVG does not preserve this Skia gradient family; use an explicit raster group.")
    (conical-gradient vector             needs-raster         "SVG does not preserve this Skia gradient family; use an explicit raster group.")
    (solid-shader   native-expansion         needs-raster         "A shader resource is not a plain paint color. Use a plain color or an explicit raster group for portable output.")
    (image-shader   native-expansion         needs-raster         "Image shader tiling/sampling is not promised as portable SVG vector output.")
    (shader-composition native-expansion    needs-raster         "Composite shader serialization is backend dependent; SVG requires an explicit raster group.")
    (shader-local-matrix native-expansion   needs-raster         "Local shader transforms are not generally preserved by the pinned SVG writer.")
    (runtime-shader needs-raster         needs-raster         "Arbitrary SkSL has no promised PDF/SVG vector representation. Rasterize explicitly.")
    (color-filter   native-expansion        needs-raster         "Color-filter effects can expand/rasterize in PDF and are not generally preserved by SVG.")
    (runtime-color-filter needs-raster  needs-raster         "Rasterize runtime color filtering explicitly on vector backends.")
    (image-filter   native-expansion        needs-raster         "PDF can expand image filters into pixels; SVG needs an explicit bounded raster group. Text semantics can be lost.")
    (mask-filter    needs-raster         needs-raster         "Mask-filter behavior depends on the drawing primitive. Explicit rasterization is the conservative policy.")
    (dash-effect    vector               vector               "Dash effects have native path/stroke support; other effects are reported separately.")
    (path-effect    native-expansion        needs-raster         "General path effects may expand geometry; the audit does not prove vector preservation for every primitive.")
    (blend-mode     native-expansion        needs-raster         "Non-default blending may expand in PDF and is not generally preserved in SVG; include its backdrop in fallback groups.")
    (runtime-blender needs-raster        needs-raster         "A custom blender needs its destination backdrop inside the same rasterized group.")
    (inverse-path   vector               needs-raster         "Inverse-filled paths require explicit handling on the pinned SVG backend.")
    (clip-intersect vector               vector               "Intersection clip; exact antialiasing and hit-region geometry are not assessed.")
    (clip-difference vector              needs-raster         "Difference/inverse clip behavior is not reliably serialized by the pinned SVG backend.")
    (transform      vector               vector               "The public transform API is affine; individual resource effects are assessed separately.")
    (annotation     vector               vector               "Document links are metadata, not painted geometry; rasterization discards interactivity.")
    (picture        vector               vector               "Recorded drawing is replayed with its stored feature summary, not assumed to be a plain vector path.")
    (raster-group   rasterized           rasterized           "Explicit bounded rasterization; pixel size and padding are recorded. Outer backdrop is not captured.")
    (vertices needs-raster needs-raster "Triangle meshes can use per-vertex colors and shader coordinates; use explicit rasterization for conservative PDF/SVG output.")
    (coons-patch needs-raster needs-raster "Coons patches are tessellated colored/textured meshes, not promised vector paths. Rasterize explicitly.")
    (image-atlas needs-raster needs-raster "Batched, transformed/tinted sprites have no promised vector-backend parity; rasterize explicitly.")
    (image-grid embedded-raster needs-raster "Nine-patch/lattice embeds raster samples in PDF. Use an explicit SVG raster group; this is not vector geometry.")
    (device-region-clip vector needs-raster "Integer region clipping is in device coordinates and ignores the local transform. Use a boundary path for portable local-coordinate clips.")
    (unknown-resource unknown            unknown              "Resource provenance was not recognized. This is not a claim of backend support.")
    (unknown-operation unknown           unknown              "A native canvas operation is outside the audited operation table.")))
(define output-feature-names (map car specifications))
(define (check-backend who b)
  (unless (memq b output-backends) (raise-argument-error who "'pdf, 'svg, or 'raster" b)))
(define (output-capability-for backend feature)
  (check-backend 'output-capability-for backend)
  (define row (assq feature specifications))
  (unless row (raise-argument-error 'output-capability-for "symbol in output-feature-names" feature))
  (define status
    (if (eq? backend 'raster)
        (case feature [(annotation) 'discarded] [(unknown-resource unknown-operation) 'unknown]
              [else 'rasterized])
        (list-ref row (if (eq? backend 'pdf) 1 2))))
  (output-capability
   backend feature status
   (if (eq? backend 'raster)
       (case feature
         [(annotation) "Raster output has no link/destination metadata; annotate the receiving document canvas instead."]
         [(unknown-resource unknown-operation) (list-ref row 3)]
         [else "Rendered as raster content. The enclosing explicit group addresses vector serialization, not backdrop, padding, or color-fidelity questions."])
       (cond
         [(and (eq? backend 'pdf) (eq? feature 'native-text))
          "Native PDF text; embedding, extraction, and glyph fidelity require separate validation."]
         [(and (eq? backend 'pdf) (eq? feature 'point-sprites))
          "Native PDF point geometry; cap and stroke settings determine the point shape."]
         [else (list-ref row 3)]))))
(define blocking-statuses '(needs-raster unsupported unknown discarded))
(define (blocking-status? s) (and (memq s blocking-statuses) #t))
(define (output-audit-report-blocking? r)
  (unless (output-audit-report? r) (raise-argument-error 'output-audit-report-blocking? "output-audit-report?" r))
  (for/or ([e (in-list (output-audit-report-events r))])
    (blocking-status? (output-audit-event-status e))))
(define (output-audit-report-vector-only? r)
  (unless (output-audit-report? r) (raise-argument-error 'output-audit-report-vector-only? "output-audit-report?" r))
  (for/and ([e (in-list (output-audit-report-events r))])
    (eq? (output-audit-event-status e) 'vector)))
(define (output-audit-report->jsexpr r)
  (unless (output-audit-report? r) (raise-argument-error 'output-audit-report->jsexpr "output-audit-report?" r))
  (hasheq 'backend (symbol->string (output-audit-report-backend r))
          'mode (symbol->string (output-audit-report-mode r))
          'pages (output-audit-report-pages r)
          'blocking (output-audit-report-blocking? r)
          'vector_only (output-audit-report-vector-only? r)
          'scope "Observed public-wrapper calls; not a visual, ICC, font-embedding, or PDF/A validator."
          'events
          (for/list ([e (in-list (output-audit-report-events r))])
            (hasheq 'page (output-audit-event-page e)
                    'operation (symbol->string (output-audit-event-operation e))
                    'scope (output-audit-event-scope e)
                    'feature (symbol->string (output-audit-event-feature e))
                    'status (symbol->string (output-audit-event-status e))
                    'reason (output-audit-event-reason e)
                    'details (output-audit-event-details e)))))
(module* internals #f
  (provide output-audit-event output-audit-report exn:fail:output-audit
           blocking-status? check-backend))

# Skia Reference Sources

Start with [reference.scrbl](reference.scrbl), which assembles the Reference
from subject-group files. Those group files include the detailed API chapters.
The chapter sources specify contracts, units, coordinate systems, lifetimes,
backend restrictions, and cross-references rather than a required learning order.

The [images/](images/README.md) directory contains committed rendered examples
and conceptual figures. [support/](support/README.md) validates their use, and
[tests/](tests/README.md) contains cross-reference probes. Normal Reference
builds consume committed figures instead of running native drawing examples.

Shared collection navigation comes from [../support/](../support/README.md).

## Files

- [annotations.scrbl](annotations.scrbl) — API specification for Annotations.
- [canvases.scrbl](canvases.scrbl) — API specification for Canvases.
- [codecs.scrbl](codecs.scrbl) — API specification for Codecs.
- [color-filters.scrbl](color-filters.scrbl) — API specification for Color Filters.
- [color-management.scrbl](color-management.scrbl) — API specification for Color Management.
- [color-paint-effects.scrbl](color-paint-effects.scrbl) — Subject-group assembly for Color Paint Effects.
- [colors.scrbl](colors.scrbl) — API specification for Colors.
- [dc-output.scrbl](dc-output.scrbl) — API specification for DC Output.
- [documents-and-output.scrbl](documents-and-output.scrbl) — Subject-group assembly for Documents And Output.
- [drawables.scrbl](drawables.scrbl) — API specification for Drawables.
- [drawing.scrbl](drawing.scrbl) — API specification for Drawing.
- [encoding.scrbl](encoding.scrbl) — API specification for Encoding.
- [float-colors.scrbl](float-colors.scrbl) — API specification for Float Colors.
- [fonts.scrbl](fonts.scrbl) — API specification for Fonts.
- [foundations.scrbl](foundations.scrbl) — Subject-group assembly for Foundations.
- [geometry-and-drawing.scrbl](geometry-and-drawing.scrbl) — Subject-group assembly for Geometry And Drawing.
- [gpu-context-options.scrbl](gpu-context-options.scrbl) — API specification for GPU Context Options.
- [gpu-contexts.scrbl](gpu-contexts.scrbl) — API specification for GPU Contexts.
- [gpu-dc.scrbl](gpu-dc.scrbl) — API specification for GPU DC.
- [gpu-diagnostics.scrbl](gpu-diagnostics.scrbl) — API specification for GPU Diagnostics.
- [gpu-external-resources.scrbl](gpu-external-resources.scrbl) — API specification for GPU External Resources.
- [gpu-gl-interop.scrbl](gpu-gl-interop.scrbl) — API specification for GPU Gl Interop.
- [gpu-images.scrbl](gpu-images.scrbl) — API specification for GPU Images.
- [gpu-interoperability-output.scrbl](gpu-interoperability-output.scrbl) — Subject-group assembly for GPU Interoperability Output.
- [gpu-native-handoffs.scrbl](gpu-native-handoffs.scrbl) — API specification for GPU Native Handoffs.
- [gpu-opengl-hosts.scrbl](gpu-opengl-hosts.scrbl) — API specification for GPU Opengl Hosts.
- [gpu-output.scrbl](gpu-output.scrbl) — API specification for GPU Output.
- [gpu-presentation.scrbl](gpu-presentation.scrbl) — API specification for GPU Presentation.
- [gpu-providers.scrbl](gpu-providers.scrbl) — API specification for GPU Providers.
- [gpu-rendering.scrbl](gpu-rendering.scrbl) — Subject-group assembly for GPU Rendering.
- [gpu-surfaces.scrbl](gpu-surfaces.scrbl) — API specification for GPU Surfaces.
- [gpu-synchronization.scrbl](gpu-synchronization.scrbl) — API specification for GPU Synchronization.
- [gpu-transfers.scrbl](gpu-transfers.scrbl) — API specification for GPU Transfers.
- [gpu-widgets.scrbl](gpu-widgets.scrbl) — API specification for GPU Widgets.
- [graphics.scrbl](graphics.scrbl) — API specification for Graphics.
- [gui-canvases.scrbl](gui-canvases.scrbl) — API specification for Gui Canvases.
- [image-api.scrbl](image-api.scrbl) — Subject-group assembly for Image Api.
- [image-filters.scrbl](image-filters.scrbl) — API specification for Image Filters.
- [image-operations.scrbl](image-operations.scrbl) — API specification for Image Operations.
- [images.scrbl](images.scrbl) — API specification for Images.
- [incremental-codecs.scrbl](incremental-codecs.scrbl) — API specification for Incremental Codecs.
- [layers.scrbl](layers.scrbl) — API specification for Layers.
- [live-streams.scrbl](live-streams.scrbl) — API specification for Live Streams.
- [matrices.scrbl](matrices.scrbl) — API specification for Matrices.
- [native-libraries.scrbl](native-libraries.scrbl) — API specification for Native Libraries.
- [notation.scrbl](notation.scrbl) — API specification for Notation.
- [output-audit.scrbl](output-audit.scrbl) — API specification for Output Audit.
- [output-groups.scrbl](output-groups.scrbl) — API specification for Output Groups.
- [output-pages.scrbl](output-pages.scrbl) — API specification for Output Pages.
- [paints.scrbl](paints.scrbl) — API specification for Paints.
- [path-effects.scrbl](path-effects.scrbl) — API specification for Path Effects.
- [paths.scrbl](paths.scrbl) — API specification for Paths.
- [pdf-documents.scrbl](pdf-documents.scrbl) — API specification for PDF Documents.
- [pict-bridge.scrbl](pict-bridge.scrbl) — API specification for Pict Bridge.
- [pictures.scrbl](pictures.scrbl) — API specification for Pictures.
- [pixel-descriptions.scrbl](pixel-descriptions.scrbl) — API specification for Pixel Descriptions.
- [portable-drawing.scrbl](portable-drawing.scrbl) — Portable marker and atlas drawing, with links to image-grid drawing and planning.
- [presentation-and-gui.scrbl](presentation-and-gui.scrbl) — Subject-group assembly for Presentation And Gui.
- [projective-matrices.scrbl](projective-matrices.scrbl) — API specification for Projective Matrices.
- [racket-dc.scrbl](racket-dc.scrbl) — API specification for Racket DC.
- [racket-draw.scrbl](racket-draw.scrbl) — API specification for Racket Draw.
- [racket-integration.scrbl](racket-integration.scrbl) — Subject-group assembly for Racket Integration.
- [raster-buffers.scrbl](raster-buffers.scrbl) — API specification for Raster Buffers.
- [recording.scrbl](recording.scrbl) — Subject-group assembly for Recording.
- [reference.scrbl](reference.scrbl) — Reference entry point and chapter assembly.
- [regions.scrbl](regions.scrbl) — API specification for Regions.
- [render-canvases.scrbl](render-canvases.scrbl) — API specification for Render Canvases.
- [resources.scrbl](resources.scrbl) — API specification for Resources.
- [rounded-rectangles.scrbl](rounded-rectangles.scrbl) — API specification for Rounded Rectangles.
- [runtime-effects.scrbl](runtime-effects.scrbl) — API specification for Runtime Effects.
- [scanline-codecs.scrbl](scanline-codecs.scrbl) — API specification for Scanline Codecs.
- [shaders.scrbl](shaders.scrbl) — API specification for Shaders.
- [shaping.scrbl](shaping.scrbl) — API specification for Shaping.
- [specialized-canvases.scrbl](specialized-canvases.scrbl) — API specification for Specialized Canvases.
- [standard-conversion.scrbl](standard-conversion.scrbl) — Shared Racket conversion protocol, supported formats, defaults, and resource requirements.
- [streams-pixels-codecs.scrbl](streams-pixels-codecs.scrbl) — Subject-group assembly for Streams Pixels Codecs.
- [streams.scrbl](streams.scrbl) — API specification for Streams.
- [structured-drawing.scrbl](structured-drawing.scrbl) — Meshes, patches, nine-patch and lattice images, portable image-grid drawing, grid plans, and native atlas drawing.
- [surface-properties.scrbl](surface-properties.scrbl) — API specification for Surface Properties.
- [surfaces-and-canvases.scrbl](surfaces-and-canvases.scrbl) — Subject-group assembly for Surfaces And Canvases.
- [surfaces.scrbl](surfaces.scrbl) — API specification for Surfaces.
- [svg-documents.scrbl](svg-documents.scrbl) — API specification for SVG Documents.
- [text-and-fonts.scrbl](text-and-fonts.scrbl) — Subject-group assembly for Text And Fonts.
- [text-blobs.scrbl](text-blobs.scrbl) — API specification for Text Blobs.
- [text-layout.scrbl](text-layout.scrbl) — API specification for Text Layout.
- [typefaces.scrbl](typefaces.scrbl) — API specification for Typefaces.
- [images/](images/README.md) — Related sources and support assets.
- [support/](support/README.md) — Related sources and support assets.
- [tests/](tests/README.md) — Related sources and support assets.

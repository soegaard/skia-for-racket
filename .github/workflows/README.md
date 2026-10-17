# GitHub Actions workflows

These YAML files connect repository checks in [tools/](../../tools/README.md)
to GitHub runners and retained validation artifacts. Runner/platform requirements
and evidence rules are documented in [CI](../../docs/CI.md).

## Automatic gates and publication

| Workflow | Role |
| --- | --- |
| [ci.yml](ci.yml) | Central source regressions, isolated package installation, CPU checks, and EGL matrix. Runs on pull requests, main pushes, version tags, or explicit invocation. |
| [acceptance.yml](acceptance.yml) | Acceptance artifacts and selected validation profiles; complements, rather than replaces, the central CI gate. |
| [api-inventory.yml](api-inventory.yml) | Checks reviewed native/API inventory and source consistency on pushes, pull requests, or manual dispatch. |
| [release-candidate.yml](release-candidate.yml) | Explicitly dispatched release-candidate matrix and evidence collection. |
| [pages.yml](pages.yml) | Manually builds registered Scribble manuals, collects the static site, and deploys GitHub Pages. |

## Opt-in feature acceptance

The following workflows are manually dispatched. Their names identify the
feature under test; their job definitions specify the actual native, GUI, GPU,
document-inspection, and platform requirements.

- Canvas/DC: [advanced-canvases.yml](advanced-canvases.yml),
  [render-canvas.yml](render-canvas.yml), [gpu-dc.yml](gpu-dc.yml),
  [dc-output.yml](dc-output.yml).
- GPU control and storage: [gpu-context-controls.yml](gpu-context-controls.yml),
  [gpu-formats.yml](gpu-formats.yml).
- Images/codecs/streams: [image-operations.yml](image-operations.yml),
  [integer-pixels.yml](integer-pixels.yml), [float-pixels.yml](float-pixels.yml),
  [codec-queries.yml](codec-queries.yml), [streams.yml](streams.yml).
- Text: [typefaces.yml](typefaces.yml), [font-queries.yml](font-queries.yml),
  [text-blobs.yml](text-blobs.yml).
- Drawing and global state: [geometry-completion.yml](geometry-completion.yml),
  [effects.yml](effects.yml), [global-caches.yml](global-caches.yml).

Keep the existing read-only pull-request trust boundary and pinned action
revisions when maintaining these files. Documentation deployment has separate
write permissions; it is not an automatic pull-request action.

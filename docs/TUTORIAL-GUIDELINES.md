# Tutorial Guidelines

These guidelines describe the conventions used for the Skia tutorials.

They are intended for short, example-driven tutorials such as Moonlight,
Clock, Logo, Images, Poster, Text, and Shaping. They are not a replacement for
the Guide or the API reference.

## 1. Purpose of a Tutorial

A tutorial should teach one main idea by building one concrete result.

Good tutorial subjects have a clear conceptual center, for example:

- **Transforms change how later local coordinates map to the surface.**
- **A path describes geometry. A paint describes how Skia draws that geometry.**
- **An image stores pixels. Drawing an image decides where and how those pixels
  appear on a canvas.**
- **Geometry says where to draw. A paint says how to draw it. A shader can make
  the paint vary across coordinates.**
- **Simple text starts at an origin on a baseline. Advance, bounds, and font
  metrics describe different parts of its geometry.**
- **Shaping turns text into positioned glyphs. Drawing places that shaped run on
  the canvas.**

A tutorial should not try to cover every related function. Advanced options,
edge cases, complete contracts, and exhaustive feature lists belong in the
Guide or Reference.

Each tutorial should end with a useful, finished artifact rather than a
collection of unrelated demonstrations.

## 2. Audience and Assumptions

Assume that the reader knows basic Racket:

- definitions;
- function calls;
- `require`;
- lists;
- keyword arguments;
- simple iteration and local definitions.

Teach Skia, not introductory Racket.

Use `#lang racket` for complete tutorial programs unless there is a specific
reason to use another language.

Explain Racket syntax only when it is important to understanding the Skia
example.

## 3. Tutorial Structure

The normal tutorial structure is:

1. Introduce the finished goal.
2. State the main idea in one short sentence.
3. Introduce one concept at a time.
4. Show runnable code for the concept.
5. Show the resulting image when the concept is visual.
6. Explain what changed and why.
7. Reuse the earlier pieces to build the final result.
8. Show the complete result.
9. Show how to save it.
10. End with a small **Try It** section.
11. End with **Where to Go From Here** and name the concepts deliberately left
    for later.

Prefer a progression in which every section visibly contributes to the final
program.

Do not introduce an API merely because it is adjacent to the current subject.
A tutorial is a path through the API, not an API inventory.

## 4. Prose Style

Use simple English, but do not make the prose simplistic.

Prefer precise technical language when it helps. The reader should learn the
correct concepts and terminology.

Follow the terminology conventions in
[How to Program Racket: a Style Guide](https://docs.racket-lang.org/style/),
especially its
[Scribbling Documentation](https://docs.racket-lang.org/style/reference-style.html)
section.

In particular:

- Prefer **function** to **procedure** in tutorial prose.
- Do not call an identifier a variable or a symbol.
- Use **argument** for function calls, not for arbitrary syntactic sub-forms.
- Distinguish values, expressions, forms, identifiers, lists, and sequences.
- Use meaningful examples instead of `foo`, `bar`, and similar placeholders.
- Capitalize section titles consistently.

Begin every prose sentence with a proper word. Do not begin a sentence with a
lowercase Racket identifier or a parenthesized expression.

For example, prefer:

> The `draw-circle` function draws a circle using the current canvas state.

over:

> `draw-circle` draws a circle using the current canvas state.

Likewise, prefer:

> The point `(0, 0)` is the upper-left corner.

over:

> `(0, 0)` is the upper-left corner.

Avoid vague explanations such as:

> A canvas is where you send drawing commands.

Prefer a description that exposes the useful model:

> A canvas carries drawing state, including the current transform and clip.
> Drawing functions use the canvas to modify the surface.

## 5. Code Style

Follow
[How to Program Racket: a Style Guide](https://docs.racket-lang.org/style/)
for Racket source style.

Important conventions for the tutorials are:

- Use DrRacket-compatible indentation.
- Do not use tab characters.
- Keep Racket source lines at or below 102 characters.
- Prefer meaningful, full-word, dashed names.
- Prefer small local helpers over deeply nested code.
- Use real examples rather than placeholder names.
- Keep code in the order a reader needs it.

### Internal definitions

A function body is already an internal-definition context. Use `define`
directly:

```racket
(define (draw-sky canvas)
  (define paint
    (make-paint #:color "#28476A"))
  (draw-rect canvas 0 0 width height paint))
```

Do not add a redundant `let`:

```racket
(define (draw-sky canvas)
  (let ()
    (define paint
      (make-paint #:color "#28476A"))
    (draw-rect canvas 0 0 width height paint)))
```

The same rule applies to module bodies, `module+` bodies, and lambda bodies
when the definitions come before expressions.

Use `(let () ...)` when it is genuinely needed to create a new
internal-definition context after an expression. For example:

```racket
(with-canvas-state canvas
  (canvas-clip-rect! canvas 0 0 200 100)
  (let ()
    (define paint
      (make-paint #:color 'blue))
    (draw-circle canvas 100 50 30 paint)))
```

Do not introduce `let` merely as a replacement for `with-skia`.

## 6. Resource Lifetime Style

Visible tutorial code should follow the project's normal resource-lifetime
policy.

For ordinary owned CPU resources, use ordinary Racket bindings when exact
release time does not matter:

```racket
(define surface (make-surface 800 500))
(define paint (make-paint #:color 'blue))
```

Use deterministic cleanup with `with-skia`, `call-with-skia-resource`, or
`skia-close!` when prompt release matters.

Borrowed, scoped, stateful, and GPU resources must follow their explicit
lifetime rules.

Hidden Scribble evaluator helpers may use `with-skia` more aggressively because
documentation builds create many temporary native resources repeatedly and
benefit from deterministic cleanup.

See:

- [Resource Lifetimes](RESOURCE-LIFETIMES.md)
- [API Contracts](API-CONTRACTS.md)
- [API Reference Notes](API.md)

A tutorial must not imply that `with-skia` is mandatory for every ordinary
CPU-owned Skia object.

## 7. Runnable Documentation

Tutorial code should be executable documentation.

Use Scribble evaluators so that examples are run while the documentation is
built. A broken API call should fail the documentation build instead of leaving
a stale example in the manual.

Use a persistent evaluator for a tutorial when later examples depend on earlier
definitions.

Use `for-label` imports so identifiers in prose and code are linked to their
documentation.

The existing tutorials use `scribble/eval` helper macros. The current Scribble
documentation recommends `scribble/example` as the newer example interface.
Do not mix an unrelated evaluator migration into a tutorial patch; change the
shared documentation machinery separately if we decide to migrate it.

Useful references:

- [Scribble: The Racket Documentation Tool](https://docs.racket-lang.org/scribble/)
- [Getting Started with Racket Documentation](https://docs.racket-lang.org/scribble/how-to-doc.html)
- [Evaluation and Examples](https://docs.racket-lang.org/scribble/eval.html)

## 8. Images and Visual Examples

A visual tutorial should show the result of each important visual step.

Do not let several sections introduce visual changes without showing those
changes. In particular, if a section teaches an image shader, a blended shader,
or text added to a poster, show the result in that section rather than waiting
for the final image.

Generate figures from actual Skia code at documentation-build time whenever
possible. Avoid hand-maintained screenshots.

A documentation figure should show the actual object or result being explained.
Do not redraw an approximation merely for the figure when the real value is
available.

For example, if a tutorial explains an image returned by `surface-snapshot`,
the figure should display that returned image rather than construct a second,
similar checker pattern.

When a source image is enlarged for documentation, say so. State the natural
size and the displayed scale. Use nearest-neighbor sampling when the purpose is
to expose individual source pixels.

Diagrams are useful when the concept is geometric. Good candidates include:

- coordinate systems;
- transform order;
- control points;
- gradient domains and stops;
- tile domains;
- text origins and baselines;
- advance versus ink bounds;
- ascent and descent;
- glyph positions in a shaped run.

A diagram should explain one idea. Avoid turning it into a second finished
artwork.

## 9. Keep the Figure and the Code Consistent

The figure shown after an example should be produced by that example or by the
same helper definitions.

Avoid subtle duplication such as:

- tutorial code creating one checker image while the evaluator draws another;
- example code using one alpha value while the figure uses another;
- prose describing one sampling mode while the figure uses another;
- a final example drifting from the code developed section by section.

When a figure needs presentation-only scaling, framing, or labels, keep those
operations in the hidden evaluator helper and make the distinction explicit.

## 10. Explain Geometry, Not Just Calls

When an API has a geometric interpretation, explain that model before
enumerating options.

For example:

- A transform changes how later local coordinates map to the surface.
- A path stores geometry independently of its paint.
- A gradient has a domain, and tile modes define behavior outside that domain.
- Text begins at an origin on a baseline.
- Text advance describes placement; text bounds describe visible ink.
- Font metrics describe the font, while text bounds describe a particular
  string.
- Shaping converts text into glyph IDs and positions.

Readers should be able to predict the effect of a code change before running
it.

## 11. Distinguish Related Concepts Explicitly

Tutorials should call out distinctions that are easy to blur.

Examples include:

### Surface, canvas, and image

A surface owns pixels that can be modified. A canvas carries drawing state for
a surface or document. A snapshot captures surface contents as an immutable
image.

### Geometry and appearance

Paths, rectangles, and circles describe geometry. Paints and shaders describe
how that geometry is rendered.

### Advance and bounds

A text advance is primarily a placement measurement. Ink bounds describe the
rectangle occupied by the measured glyph ink. They need not have the same
edges.

### Shaping and layout

`shape-text` shapes one font run. It does not perform paragraph-level bidi,
automatic multi-font fallback, line breaking, wrapping, or justification.

### Direction and placement

Shaping direction does not by itself define a right-alignment policy. Use the
actual shaped positions and advance. Do not assume that every RTL run has a
particular advance sign.

## 12. Platform-Dependent Results

Do not present platform-dependent output as universal.

Fonts are the most common example. The platform default typeface can differ
between Mac OS, Windows, and Unix. Font matching for Arabic, Hebrew, CJK, and
other scripts can also select different families.

When a tutorial deliberately uses the platform default:

- say that the exact family may differ;
- show `typeface-family-name` when useful;
- teach geometry and API behavior that does not depend on one family;
- do not promise an exact glyph count or exact metric unless the tutorial uses
  a controlled fixture.

If exact font output is required for a test, use a controlled fixture in the
test infrastructure rather than pretending that a tutorial's platform font is
portable.

## 13. Verify Subtle Semantics Against the Implementation

Do not infer semantics from a function name when the behavior is subtle.

Before teaching a non-obvious rule, check at least one of:

- the public API documentation;
- the implementation;
- native tests;
- an existing working example.

This is especially important for:

- resource ownership;
- retained native references;
- coordinate transforms;
- gradient domains;
- text metrics;
- shaping direction and advances;
- bidi behavior;
- PDF/SVG vector versus raster behavior;
- GPU lifetime and synchronization.

When an observed rendered result contradicts the tutorial, treat it as evidence
that the tutorial may be wrong. Fix the explanation rather than explaining away
a real discrepancy as platform variation.

## 14. Complete Example Files

Each tutorial should have a standalone `.rkt` file containing the finished
program.

The complete example should:

- use the same helpers developed in the tutorial;
- avoid tutorial-only scaffolding;
- run without network access;
- use deterministic local assets when assets are needed;
- save a useful output file;
- follow the same resource and code style as the visible tutorial.

The final rendered image in the tutorial should be generated from the same
drawing function used by the complete example.

## 15. Keep Tutorials, Guide, and Reference Separate

The three documentation layers have different jobs.

### Tutorials

Tutorials are linear, selective, and result-oriented. They answer:

> How do I learn this by building something?

### Guide

The Guide is concept- and task-oriented. It explains alternatives,
trade-offs, interactions between features, and broader workflows.

### Reference

The Reference gives exact signatures, accepted values, defaults, ownership
rules, errors, and detailed contracts.

Do not overload a tutorial with material that belongs in the other two layers.
Instead, state the boundary and point forward.

## 16. Tutorial Review Checklist

Before considering a tutorial finished, check the following.

### Concept

- Is there one clear main idea?
- Does every section support that idea?
- Is the final artifact useful and visually coherent?
- Have unrelated APIs been left for later?

### Prose

- Is the English simple and precise?
- Does every sentence begin with a proper word?
- Is Racket terminology correct?
- Are platform-dependent claims qualified?
- Are important conceptual distinctions stated explicitly?

### Code

- Does visible code use normal Racket definition contexts?
- Are redundant `let` wrappers absent?
- Are ordinary CPU resources shown with ordinary bindings?
- Are stricter resource rules followed where necessary?
- Are names meaningful?
- Are lines no longer than 102 characters?
- Does `git diff --check` pass?

### Figures

- Is there an image after each important visual step?
- Does each figure come from the code being explained?
- Are enlargements or presentation-only transformations stated?
- Are diagrams focused on one concept?
- Does the final image come from the complete drawing function?

### Execution

- Do the Scribble examples execute?
- Does the complete `.rkt` example run?
- Does the documentation build?
- Are source checksums regenerated?
- Do the relevant tests pass?

## 17. Useful External References

The following documents are useful when writing or reviewing a tutorial:

- [How to Program Racket: a Style Guide](https://docs.racket-lang.org/style/)
- [Scribbling Documentation](https://docs.racket-lang.org/style/reference-style.html)
- [Textual Matters — Racket Style Guide](https://docs.racket-lang.org/style/Textual_Matters.html)
- [Quick: An Introduction to Racket with Pictures](https://docs.racket-lang.org/quick/)
- [The Racket Guide](https://docs.racket-lang.org/guide/)
- [Scribble: The Racket Documentation Tool](https://docs.racket-lang.org/scribble/)
- [Getting Started with Racket Documentation](https://docs.racket-lang.org/scribble/how-to-doc.html)
- [Evaluation and Examples](https://docs.racket-lang.org/scribble/eval.html)

The Racket Quick tutorial is especially useful as a model for pacing:
introduce a small idea, execute it, show the result, and then reuse it in the
next step.

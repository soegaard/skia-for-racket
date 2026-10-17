# Skia House Style

## 1. Scope

These conventions apply to new and substantially revised Racket code, examples,
and documentation.

Preserve existing public names and behavior. Do not combine unrelated formatting
changes with a functional change. Existing files need not be reformatted merely
to adopt this guide.

This document specifies presentation and editorial conventions, not an
architecture.

## 2. Comment Style

Use the following comment conventions, adapted from
[Animate's house style](https://raw.githubusercontent.com/soegaard/animate/refs/heads/main/HOUSE_STYLE.md):

| Prefix | Purpose |
| --- | --- |
| `;;;` | Module titles and section headings. |
| `;;` | Explanatory paragraphs and structure-field descriptions. |
| `;` | Function signatures and constant contracts. |
| `;   ` | A short purpose sentence following a contract comment. |

Place the module description before imports. Use section headings to group
related definitions.

Give each top-level function and constant a contract comment and a brief purpose
sentence. Put a blank line before each contract comment. Keep the contract,
purpose sentence, and definition together, without intervening blank lines.
Use a single semicolon for both the contract and its purpose sentence, including
continuation lines; indent the purpose text by three spaces after the semicolon.

Document structure fields immediately after the definition, including expected
values, meaning, significant ordering, and invariants. These field descriptions
remain double-semicolon explanatory comments.

Explain reasons and constraints rather than narrating obvious operations.
Comment on small local helpers only when their role or accepted values need
explanation.

For example:

```racket
#lang racket/base

;;;
;;; Marker Drawing
;;;

;; Draws circular markers using a caller-supplied canvas and paint.


;;;
;;; Imports and Exports
;;;

(require (only-in skia draw-circle))

(provide draw-marker)


;;;
;;; Drawing Functions
;;;

; marker-radius : exact-positive-integer?
;   Gives the marker radius in local drawing units.
(define marker-radius 4)

; draw-marker : canvas? real? real? paint? -> void?
;   Draws a marker centered at the given local coordinates.
(define (draw-marker canvas x y paint)
  (draw-circle canvas x y marker-radius paint))
```

Contract comments describe intended interfaces; they do not install runtime
checks. Additional restrictions, such as valid native-coordinate ranges, still
apply.

Keep short teaching examples lightweight. Their surrounding explanation can
supply information that would otherwise appear in source comments.

## 3. Racket Code Style

- Use DrRacket-compatible indentation and spaces rather than tabs.
- Keep Racket source lines at or below 102 characters.
- Use meaningful kebab-case names.
- Use `?` for predicates and `->` for conversions.
- Follow the established API family when naming mutating operations. Do not
  rename existing drawing functions merely because they lack `!`.
- Prefer small functions and local helpers to deeply nested expressions.
- Use ordinary internal definitions when the surrounding form already permits
  them. Do not introduce redundant `(let () ...)` wrappers.
- Use explicit exports and focused imports. Qualify imported names when that
  improves clarity.
- Use `#lang racket` for complete tutorial programs unless another language is
  needed.

Names should identify the role of a value: `canvas`, `paint`, `baseline-y`, or
`row-bytes` is usually more informative than `data` or `value`.

# Documentation Sources

This tree contains the reader-facing Scribble manuals, their complete Racket
examples, and the small support modules used to build navigation and figures.
It is distinct from the generated HTML output, which should not be edited here.

- [reference/](reference/README.md) specifies public API contracts, effects,
  units, ownership, and limitations.
- [tutorials/](tutorials/README.md) contains subject-oriented tutorials,
  runnable examples, and shared evaluator/figure support.
- [quick/](quick/README.md) contains the introductory landscape tutorial.
- [support/](support/README.md) supplies collection metadata and navigation
  shared by the documentation collections.

Manual registration lives in [info.rkt](../info.rkt). Editorial conventions are
in [house-style.md](../house-style.md) and the
[Tutorial Guidelines](../docs/TUTORIAL-GUIDELINES.md).

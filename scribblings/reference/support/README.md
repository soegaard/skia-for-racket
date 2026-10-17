# Reference Support

[figures.rkt](figures.rkt) is the small reader-facing bridge between Reference
chapters and [committed images](../images/README.md). Its `reference-figure`
helper checks the image name and alternative text and supplies the intended
display scale. It does not regenerate images or initialize native Skia.

See [tools](../../../tools/README.md) for developer-side generation
and validation tools.

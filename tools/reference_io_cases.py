"""Independent R3f call shapes transcribed from implementation 5a2d7d41.

These are test expectations, not live reflection and not replacement API snapshots.
The production checker still requires the two original hash-pinned inventories.
"""
STREAM_EXPORTS = '''
skia-input-stream? skia-output-stream? make-memory-input-stream make-file-input-stream
make-memory-output-stream input-stream-length input-stream-position input-stream-at-end?
input-stream-read-bytes input-stream-peek-bytes input-stream-skip! input-stream-seek!
input-stream-rewind! input-stream-move! input-stream-duplicate input-stream-fork
input-stream->bytes output-stream-write-bytes! output-stream-bytes-written
output-stream->bytes output-stream-detach-input! buffered-port->input-stream
output-stream-write-port/buffered
'''.split()
FILE_STREAM_EXPORTS = 'make-file-output-stream output-stream-flush!'.split()
STREAM_INPUT_EXPORTS = '''
codec-from-stream typeface-from-stream picture-from-stream codec-from-port/buffered
 typeface-from-port/buffered image-from-port/buffered picture-from-port/buffered
'''.split()
LIVE_STREAM_EXPORTS = '''
live-streams-check! live-streams-available? image-from-port picture-from-port
copy-port/streaming image->port picture->port output->port image-write-stream!
picture-write-stream! output-write-stream!
'''.split()
CODEC_QUERY_EXPORTS = 'codec-scaled-dimensions codec-supported-subset'.split()
SCANLINE_EXPORTS = '''
codec-scanline-session? codec-scanline-from-bytes codec-scanline-from-stream
codec-scanline-from-port/buffered codec-scanline-state codec-scanline-info
codec-scanline-source-info codec-scanline-order codec-scanline-position
codec-scanline-next-row codec-scanline-output-row codec-scanline-read! codec-scanline-skip!
scanline-batch? scanline-batch-info scanline-batch-row-bytes scanline-batch-first-row
scanline-batch-requested-count scanline-batch-decoded-count scanline-batch-bytes
scanline-batch-complete? scanline-batch->raster-buffer exn:fail:codec-scanline?
exn:fail:codec-scanline-result exn:fail:codec-scanline-native-code
'''.split()
INCREMENTAL_EXPORTS = '''
codec-incremental-session? make-codec-incremental codec-incremental-feed!
codec-incremental-step! codec-incremental-cancel! codec-incremental-state
codec-incremental-info codec-incremental-origin codec-incremental-statistics
codec-incremental-snapshot incremental-snapshot->raster-buffer incremental-progress?
incremental-progress-state incremental-progress-result incremental-progress-initialized-rows
incremental-snapshot? incremental-snapshot-info incremental-snapshot-row-bytes
incremental-snapshot-bytes incremental-snapshot-progress
'''.split()
# Prerequisites for describing and using decoded storage. Constants and other
# raster operations remain in R3g; color-space-descriptor? was documented by R3d.
PIXEL_INFO_EXPORTS = '''
image-info? make-image-info image-info-width image-info-height image-info-color-type
image-info-alpha-type image-info-color-space image-info-bytes-per-pixel
image-info-channel-bits image-info-byte-order image-info-min-row-bytes
image-info-storage-layout image-info-with-dimensions image-info-sample-type image-info-supports?
'''.split()
DECODED_BUFFER_EXPORTS = 'raster-buffer? raster-buffer-image-info raster-buffer->image'.split()
IO_MODULES = {
    'streams.rkt': STREAM_EXPORTS,
    'file-streams.rkt': FILE_STREAM_EXPORTS,
    'stream-inputs.rkt': STREAM_INPUT_EXPORTS,
    'live-streams.rkt': LIVE_STREAM_EXPORTS,
    'codec-queries.rkt': CODEC_QUERY_EXPORTS,
    'codec-scanlines.rkt': SCANLINE_EXPORTS,
    'codec-incremental.rkt': INCREMENTAL_EXPORTS,
    'image-info.rkt': PIXEL_INFO_EXPORTS,
    'raster-buffers.rkt': DECODED_BUFFER_EXPORTS,
}
IO_PROCEDURES = {}
for names, arity in (
    ('''skia-input-stream? skia-output-stream? input-stream-length input-stream-position
        input-stream-at-end? input-stream-rewind! input-stream-duplicate input-stream-fork
        input-stream->bytes output-stream-bytes-written output-stream->bytes
        output-stream-detach-input! output-stream-flush! codec-from-stream
        codec? codec-from-bytes codec-from-file codec-info codec-frame-count codec-repetition-count
        codec-color-space encoded-image-info? encoded-image-info-from-bytes
        encoded-image-info-from-file encoded-image-info-width encoded-image-info-height
        encoded-image-info-format encoded-image-info-color-type encoded-image-info-alpha-type
        encoded-image-info-origin encoded-image-info-frame-count encoded-image-info-display-width
        encoded-image-info-display-height codec-frame-info? codec-frame-info-index
        codec-frame-info-required-frame codec-frame-info-duration codec-frame-info-fully-received?
        codec-frame-info-alpha-type codec-frame-info-has-alpha-within-bounds?
        codec-frame-info-disposal-method codec-frame-info-blend codec-frame-info-rect
        codec-scanline-session? codec-scanline-state codec-scanline-info codec-scanline-source-info
        codec-scanline-order codec-scanline-position codec-scanline-next-row scanline-batch?
        scanline-batch-info scanline-batch-row-bytes scanline-batch-first-row
        scanline-batch-requested-count scanline-batch-decoded-count scanline-batch-bytes
        scanline-batch-complete? scanline-batch->raster-buffer exn:fail:codec-scanline?
        exn:fail:codec-scanline-result exn:fail:codec-scanline-native-code
        codec-incremental-session? codec-incremental-cancel! codec-incremental-state
        codec-incremental-info codec-incremental-origin codec-incremental-statistics
        codec-incremental-snapshot incremental-progress? incremental-progress-state
        incremental-progress-result incremental-progress-initialized-rows incremental-snapshot?
        incremental-snapshot-info incremental-snapshot-row-bytes incremental-snapshot-bytes
        incremental-snapshot-progress incremental-snapshot->raster-buffer image-info?
        image-info-width image-info-height image-info-color-type image-info-alpha-type
        image-info-color-space image-info-bytes-per-pixel image-info-channel-bits
        image-info-sample-type image-info-byte-order image-info-min-row-bytes
        raster-buffer? raster-buffer-image-info raster-buffer->image''', 2),
    ('''input-stream-read-bytes input-stream-peek-bytes input-stream-skip! input-stream-seek!
        input-stream-move! codec-frame-info codec-scaled-dimensions codec-scanline-output-row
        codec-scanline-skip! image-info-supports? picture-write-stream!''', 4),
    ('live-streams-check! live-streams-available?', 1),
    ('codec-supported-subset', 32),
    ('image-info-with-dimensions', 8),
    ('output-stream-write-bytes!', 28),
):
    IO_PROCEDURES.update({name: (arity, []) for name in names.split()})
PORT_OPTIONS = ['cancel-evt', 'close?', 'limit']
SCAN_OPTIONS = ['alpha-type', 'color-space', 'color-type', 'scale']
ENCODING_OPTIONS = ['color-space', 'icc-description', 'icc-profile', 'jpeg-alpha',
                    'jpeg-downsample', 'png-compression', 'quality', 'webp-lossless?']
DOCUMENT_OPTIONS = ['description', 'encoding-quality', 'id-prefix', 'pdfa?', 'policy',
                    'raster-dpi', 'text-mode', 'title']
IO_PROCEDURES.update({
    'make-memory-input-stream': (2, ['limit']),
    'make-file-input-stream': (2, ['limit']),
    'make-memory-output-stream': (1, ['limit']),
    'make-file-output-stream': (2, ['exists', 'limit']),
    'buffered-port->input-stream': (2, PORT_OPTIONS),
    'output-stream-write-port/buffered': (4, ['cancel-evt', 'close?']),
    'typeface-from-stream': (2, ['index']),
    'picture-from-stream': (2, ['height', 'trusted?', 'width']),
    'codec-from-port/buffered': (2, PORT_OPTIONS),
    'image-from-port/buffered': (2, PORT_OPTIONS),
    'typeface-from-port/buffered': (2, sorted([*PORT_OPTIONS, 'index'])),
    'picture-from-port/buffered': (2, sorted([*PORT_OPTIONS, 'height', 'trusted?', 'width'])),
    'image-from-port': (2, sorted([*PORT_OPTIONS, 'length', 'normalize-origin?', 'seekable?'])),
    'picture-from-port': (2, sorted([*PORT_OPTIONS, 'height', 'length', 'seekable?',
                                    'trusted?', 'width'])),
    'copy-port/streaming': (4, ['cancel-evt', 'close-input?', 'close-output?', 'limit']),
    'image->port': (8, sorted([*PORT_OPTIONS, *ENCODING_OPTIONS])),
    'picture->port': (4, PORT_OPTIONS),
    'output->port': (8, sorted([*PORT_OPTIONS, *DOCUMENT_OPTIONS])),
    'image-write-stream!': (8, ENCODING_OPTIONS),
    'output-write-stream!': (8, DOCUMENT_OPTIONS),
    'codec->image': (2, ['color-space', 'frame-index', 'normalize-origin?']),
    'image-frame-from-bytes': (6, ['color-space', 'normalize-origin?']),
    'image-frame-from-file': (6, ['color-space', 'normalize-origin?']),
    'codec-scanline-from-bytes': (2, SCAN_OPTIONS),
    'codec-scanline-from-stream': (2, SCAN_OPTIONS),
    'codec-scanline-from-port/buffered': (2, sorted([*SCAN_OPTIONS, *PORT_OPTIONS])),
    'codec-scanline-read!': (6, ['row-bytes']),
    'make-codec-incremental': (1, ['alpha-type', 'color-space', 'color-type', 'limit', 'row-bytes']),
    'codec-incremental-feed!': (4, ['final?']),
    'codec-incremental-step!': (2, ['cancel-evt']),
    'make-image-info': (4, ['alpha-type', 'color-space', 'color-type']),
    'image-info-storage-layout': (2, ['row-bytes']),
})

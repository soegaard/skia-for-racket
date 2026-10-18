#!/usr/bin/env python3
"""Source/HTML regressions with synthetic inventories and HTML, not native rendering."""
import copy
import contextlib
import importlib.util
import io
from types import SimpleNamespace
from unittest.mock import patch
from html import escape
import json
from pathlib import Path
import shutil
import tempfile
import unittest
import hashlib
import re
import zipfile
from urllib.parse import quote

import reference_support as checks
import reference_review as review

ROOT = Path(__file__).resolve().parents[1]
PREDICATES = ('skia-resource?', 'skia-closed?', 'surface?', 'canvas?', 'color-space?',
              'paint?', 'shader?', 'path-effect?', 'color-filter?', 'mask-filter?',
              'image-filter?', 'color?', 'rgba?')
PROCEDURES = {
    **{name: (2, []) for name in PREDICATES},
    'rgba': (16, []), 'rgb': (8, []), 'color->rgba': (2, []),
    **{name: (2, []) for name in ('rgba-red', 'rgba-green', 'rgba-blue', 'rgba-alpha')},
    'skia-close!': (2, []), 'call-with-skia-resource': (4, []),
    'surface-canvas': (2, []), 'color->argb': (2, []), 'draw-rect': (64, []),
    'make-surface': (4, ['background', 'color-space']),
    'make-paint': (1, ['antialias?', 'blend-mode', 'cap', 'color', 'color-filter',
                       'image-filter', 'join', 'mask-filter', 'miter-limit', 'path-effect',
                       'shader', 'stroke-width', 'style']),
    'save-png': (4, ['color-space', 'compression', 'exists', 'icc-description', 'icc-profile']),
}


# Independently specified call shapes for the bounded R2 subset. These synthetic
# fixtures test the checker; they are not evidence of a live Racket API capture.
MATRIX_EXPORTS = (
    'matrix? make-matrix matrix-identity matrix-xx matrix-yx matrix-xy matrix-yy '
    'matrix-x0 matrix-y0 matrix->vector vector->matrix matrix-translate matrix-scale '
    'matrix-rotate matrix-rotate-degrees matrix-skew matrix-compose matrix-invert '
    'matrix-map-point matrix-map-vector matrix-map-rect').split()
GEOMETRY_EXPORTS = (
    'paint-style paint-stroke-width paint-cap paint-join paint-miter-limit '
    'paint-antialias? paint-dither? paint-set-dither! paint-blend-mode-or-src-over '
    'paint-reset! paint->fill-path').split()

for names, arity in (
    ('surface-width surface-height surface-backend surface-color-space surface-snapshot '
     'canvas-execution-backend canvas-save! canvas-save-count canvas-restore! '
     'canvas-reset-transform! canvas-transform', 2),
    ('canvas-clear! canvas-restore-to-count! call-with-canvas-state canvas-rotate! '
     'canvas-rotate-radians! canvas-set-transform! canvas-concat!', 4),
    ('surface-pixel canvas-translate! canvas-skew!', 8),
    ('paint-copy paint-color paint-shader paint-path-effect paint-color-filter '
     'paint-mask-filter paint-image-filter paint-style paint-stroke-width paint-cap '
     'paint-join paint-miter-limit paint-antialias? paint-dither? '
     'paint-blend-mode-or-src-over paint-reset!', 2),
    ('paint-set-color! paint-set-style! paint-set-stroke-width! paint-set-antialias! '
     'paint-set-cap! paint-set-join! paint-set-miter-limit! paint-set-blend-mode! '
     'paint-set-shader! paint-set-path-effect! paint-set-color-filter! '
     'paint-set-mask-filter! paint-set-image-filter! paint-set-dither!', 4),
    ('make-color-shader', 2), ('make-blend-shader', 8), ('shader-with-local-matrix', 4),
    ('draw-paint', 4), ('draw-line draw-oval', 64), ('draw-rounded-rect', 256),
    ('draw-circle', 32), ('draw-path', 8),
    ('skia-path? path-copy path-fill-rule path-reset! path-close! path-point-count '
     'path-points path-last-point path-bounds path-tight-bounds path-convex? '
     'path->svg-path path->commands path-segment? path-segment-verb path-segment-points '
     'path-segment-conic-weight path-segment-closing-line? path-contour? '
     'path-contour-segments path-contour-closed? path-simplify path-as-winding '
     'path-measure? path-measure-length path-measure-closed? path-measure-next-contour!', 2),
    ('path-set-fill-rule! path-add-reversed-path! path-point-ref path-transform '
     'path-transform! path-union path-intersect path-difference path-xor '
     'path-reverse-difference path-measure-position+tangent', 4),
    ('path-move-to! path-rmove-to! path-line-to! path-rline-to! path-contains? path-op', 8),
    ('path-quad-to! path-rquad-to!', 32), ('path-conic-to! path-rconic-to!', 64),
    ('path-cubic-to! path-rcubic-to!', 128),
    ('matrix? matrix-xx matrix-yx matrix-xy matrix-yy matrix-x0 matrix-y0 matrix->vector '
     'vector->matrix matrix-rotate matrix-rotate-degrees matrix-invert', 2),
    ('matrix-translate matrix-skew', 4), ('matrix-map-point matrix-map-vector', 8),
    ('matrix-map-rect', 32), ('make-matrix', 127), ('matrix-scale', 6), ('matrix-compose', -1),
    ('image? image-from-bytes image-from-file image-width image-height image-color-type '
     'image-alpha-type image-color-space image-original-encoded-bytes', 2),
    ('image-subset', 32),
):
    PROCEDURES.update({name: (arity, []) for name in names.split()})

PNG_OPTIONS = ['color-space', 'compression', 'icc-description', 'icc-profile']
ENCODING_OPTIONS = ['color-space', 'icc-description', 'icc-profile', 'jpeg-alpha',
                    'jpeg-downsample', 'png-compression', 'quality', 'webp-lossless?']
PROCEDURES.update({
    'surface->rgba-bytes': (2, ['color-space', 'premultiplied?']),
    'canvas-scale!': (12, []),
    'canvas-clip-rect!': (32, ['antialias?', 'operation']),
    'canvas-clip-path!': (4, ['antialias?', 'operation']),
    'paint->fill-path': (4, ['cull', 'matrix']),
    'make-linear-gradient-shader': (32, ['positions', 'tile-mode']),
    'make-radial-gradient-shader': (16, ['positions', 'tile-mode']),
    'make-sweep-gradient-shader': (8, ['end-angle', 'positions', 'start-angle', 'tile-mode']),
    'make-two-point-conical-gradient-shader': (128, ['positions', 'tile-mode']),
    'make-image-shader': (2, ['sampling', 'tile-x', 'tile-y']),
    'draw-polygon': (8, ['closed?']),
    'make-path': (3, ['fill-rule']),
    'path-add-rect!': (32, ['direction']),
    'path-add-rounded-rect!': (128, ['direction']),
    'path-add-oval!': (32, ['direction']),
    'path-add-circle!': (16, ['direction']),
    'path-add-path!': (4, ['dx', 'dy', 'mode']),
    'svg-path->path': (2, ['fill-rule']),
    'path-segments': (2, ['force-closed?', 'mode']),
    'in-path-segments': (2, ['force-closed?', 'mode']),
    'path-contours': (2, ['force-closed?', 'mode']),
    'make-path-measure': (2, ['force-closed?', 'res-scale']),
    'path-measure-set-path!': (4, ['force-closed?']),
    'path-measure-segment': (8, ['start-with-move-to?']),
    'path-measure-matrix': (4, ['mode']),
    'rgba-bytes->image': (8, ['color-space', 'premultiplied?']),
    'image->rgba-bytes': (2, ['color-space', 'premultiplied?']),
    'draw-image': (16, ['paint', 'sampling']),
    'draw-image-rect': (64, ['paint', 'sampling']),
    'draw-image-subrect': (1024, ['paint', 'sampling']),
    'surface->png-bytes': (2, PNG_OPTIONS),
    'image->png-bytes': (2, PNG_OPTIONS),
    'image->jpeg-bytes': (2, ['alpha', 'color-space', 'downsample', 'icc-description',
                            'icc-profile', 'quality']),
    'image->webp-bytes': (2, ['color-space', 'icc-description', 'icc-profile', 'lossless?',
                            'quality']),
    'image->encoded-bytes': (4, ENCODING_OPTIONS),
    'save-image': (8, sorted([*ENCODING_OPTIONS, 'exists'])),
})

# Standard-space constructors and queries added by R2.1.
PROCEDURES.update({
    'make-srgb-color-space': (1, []), 'make-linear-srgb-color-space': (1, []),
    'color-space=?': (4, []), 'color-space-srgb?': (2, []),
    'color-space-linear-gamma?': (2, []),
})


from reference_text_cases import FONT_EXPORTS, TYPEFACE_EXPORTS, TEXT_PROCEDURES

from reference_blob_cases import ATLAS_EXPORTS, BLOB_EXPORTS, BLOB_PROCEDURES

PROCEDURES.update(TEXT_PROCEDURES)
PROCEDURES.update(BLOB_PROCEDURES)

from reference_effect_cases import (EFFECT_EXPORTS, COLOR_FILTER_EXPORTS,
                                    RUNTIME_EXPORTS, EFFECT_PROCEDURES)
PROCEDURES.update(EFFECT_PROCEDURES)

from reference_color_cases import (COLOR_SPACE_EXPORTS, COLOR4F_EXPORTS, FLOAT_COLOR_EXPORTS,
                                   DESCRIPTOR_EXPORTS, COLOR_PROCEDURES, COLOR_REQUIRED_KEYWORDS)
PROCEDURES.update(COLOR_PROCEDURES)


from reference_output_cases import (PICTURE_EXPORTS, OUTPUT_EXPORTS, ANNOTATION_EXPORTS,
                                    OUTPUT_PROCEDURES, OUTPUT_PARAMETERS, OUTPUT_SYNTAX)
PROCEDURES.update(OUTPUT_PROCEDURES)


from reference_io_cases import IO_MODULES, IO_PROCEDURES, PIXEL_INFO_EXPORTS
PROCEDURES.update(IO_PROCEDURES)


from reference_geometry_cases import (GA_MODULES, GA_PROCEDURES, GA_SYNTAX,
                                      GA_PARAMETERS, GA_CONSTANTS)
PROCEDURES.update(GA_PROCEDURES)

from reference_raster_cases import (GB_MODULES, GB_PROCEDURES, GB_REQUIRED_KEYWORDS,
                                    GB_CONSTANTS, GB_SYNTAX, GB_PARAMETERS)
PROCEDURES.update(GB_PROCEDURES)


from reference_gpu_context_cases import (R4A_MODULES, R4A_PROCEDURES, R4A_REQUIRED_KEYWORDS,
                                         GPU_CONTEXT_EXPORTS, GPU_OPTION_EXPORTS)
PROCEDURES.update(R4A_PROCEDURES)
from reference_gpu_surface_cases import R4B_MODULES, R4B_PROCEDURES, R4B_REQUIRED_KEYWORDS
from reference_gpu_interop_cases import R4C_MODULES, R4C_PROCEDURES, R4C_REQUIRED_KEYWORDS
from reference_gpu_presentation_cases import (R4D_MODULES, R4D_PROCEDURES,
                                              R4D_VALUES, R4D_GUI_MODULES)
from reference_dc_cases import (R4E_MODULES, R4E_PROCEDURES, R4E_VALUES, R4E_PARAMETERS)
from reference_gpu_surface_evidence import COMMON_CASES, ONE_SHOT_CASE, check_gpu_surface_receipt
PROCEDURES.update(R4B_PROCEDURES)
PROCEDURES.update(R4C_PROCEDURES)
PROCEDURES.update(R4D_PROCEDURES)
PROCEDURES.update(R4E_PROCEDURES)


def row(name, arity, keywords, kind='procedure'):
    return dict(name=name, phase='0', kind=kind, export_kind='value', arity_mask=str(arity),
                required_keywords=R4C_REQUIRED_KEYWORDS.get(name, R4B_REQUIRED_KEYWORDS.get(name,
                    R4A_REQUIRED_KEYWORDS.get(name, GB_REQUIRED_KEYWORDS.get(name,
                    COLOR_REQUIRED_KEYWORDS.get(name, []))))),
                allowed_keywords=keywords)


def synthetic_inventory():
    """Independent test snapshots; never stand in for the repository's pinned files."""
    exports = [row(name, arity, keywords) for name, (arity, keywords) in PROCEDURES.items()]
    exports += [row('current-skia-byte-limit', 3, [], 'parameter'),
                dict(name='with-skia', phase='0', kind='syntax', export_kind='syntax'),
                dict(name='with-canvas-state', phase='0', kind='syntax', export_kind='syntax'),
                dict(name='matrix-identity', phase='0', kind='value', export_kind='value'),
                row('synthetic-uncovered-export', 2, []),
                dict(name='struct:rgba', phase='0', kind='value', export_kind='value')]
    exports += [row(name, 3, [], 'parameter') for name in OUTPUT_PARAMETERS]
    exports += [dict(name=name, phase='0', kind='syntax', export_kind='syntax')
                for name in OUTPUT_SYNTAX]
    exports += [row(name, 3, [], 'parameter') for name in GA_PARAMETERS]
    exports += [dict(name=name, phase='0', kind='syntax', export_kind='syntax')
                for name in GA_SYNTAX]
    exports += [dict(name=name, phase='0', kind='value', export_kind='value')
                for name in GA_CONSTANTS]
    exports += [row(name, 3, [], 'parameter') for name in GB_PARAMETERS]
    exports += [dict(name=name, phase='0', kind='syntax', export_kind='syntax')
                for name in GB_SYNTAX]
    exports += [dict(name=name, phase='0', kind='value', export_kind='value')
                for name in GB_CONSTANTS]
    exports += [dict(name=name, phase='0', kind=kind, export_kind='value')
                for name, kind in {**R4D_VALUES, **R4E_VALUES}.items()]
    exports += [row(name, 3, [], 'parameter') for name in R4E_PARAMETERS]
    snapshots = [dict(modules=[dict(path='main.rkt', exports=exports),
                                    dict(path='color.rkt', exports=[
                                        copy.deepcopy(item) for item in exports
                                        if item['name'] in (
                                            'color?', 'color->argb', 'color->rgba',
                                            'rgba', 'rgba?', 'rgba-red', 'rgba-green',
                                            'rgba-blue', 'rgba-alpha', 'struct:rgba', 'rgb')])]),
                      dict(modules=[])]
    snapshots[0]['modules'].append(dict(path='pict.rkt', exports=[
        row('image->pict', 2, ['backing-scale']),
        row('picture->pict', 2, ['bounds', 'raster-scale']),
        row('surface->pict', 2, ['backing-scale'])]))
    snapshots[0]['modules'].append(dict(path='racket-draw.rkt', exports=[
        dict(name='bitmap->image', phase='0', kind='procedure', export_kind='syntax', arity_mask='2',
             required_keywords=[], allowed_keywords=['mask', 'resolution']),
        row('color%->rgba', 2, []),
        dict(name='dc-path->skia-path', phase='0', kind='procedure', export_kind='syntax', arity_mask='2',
             required_keywords=[], allowed_keywords=['fill-style']),
        row('image->bitmap', 2, []),
        row('rgba->color%', 2, []),
        dict(name='skia-path->dc-path', phase='0', kind='procedure', export_kind='syntax', arity_mask='2',
             required_keywords=[], allowed_keywords=['conic-subdivisions']),
        row('surface->bitmap', 2, [])]))
    for path, names in (('matrix.rkt', MATRIX_EXPORTS), ('geometry.rkt', GEOMETRY_EXPORTS),
                        ('typefaces.rkt', TYPEFACE_EXPORTS), ('fonts.rkt', FONT_EXPORTS),
                        ('text-blobs.rkt', BLOB_EXPORTS), ('geometry-primitives.rkt', ATLAS_EXPORTS),
                        ('effects.rkt', EFFECT_EXPORTS), ('color-filters.rkt', COLOR_FILTER_EXPORTS),
                        ('runtime-effects.rkt', RUNTIME_EXPORTS),
                        ('color-space.rkt', COLOR_SPACE_EXPORTS),
                        ('color4f.rkt', COLOR4F_EXPORTS), ('float-colors.rkt', FLOAT_COLOR_EXPORTS),
                        ('image-info.rkt', [*DESCRIPTOR_EXPORTS, *PIXEL_INFO_EXPORTS]),
                        ('pictures.rkt', PICTURE_EXPORTS), ('output.rkt', OUTPUT_EXPORTS),
                        ('annotations.rkt', ANNOTATION_EXPORTS),
                        *[(p, n) for p, n in IO_MODULES.items() if p != 'image-info.rkt']):
        snapshots[0]['modules'].append(dict(
            path=path, exports=[copy.deepcopy(item) for item in exports
                                if item['name'] in names]))
    combined_modules = {}
    for group in (GA_MODULES, GB_MODULES, R4A_MODULES, R4B_MODULES, R4C_MODULES, R4D_MODULES,
                  R4E_MODULES):
        for path, names in group.items():
            combined_modules.setdefault(path, [])
            combined_modules[path].extend(name for name in names
                                          if name not in combined_modules[path])
    for path, names in combined_modules.items():
        new = dict(path=path, exports=[copy.deepcopy(item) for item in exports
                                       if item['name'] in names])
        old = next((m for m in snapshots[0]['modules'] if m['path'] == path), None)
        if old is None:
            snapshots[0]['modules'].append(new)
        else:
            old['exports'] = new['exports']
    non_main = {'image->bitmap', 'surface->bitmap', 'native-abi-catalog', 'native-abi-profiles',
                'skia-native-capabilities', 'skia-native-symbol-inventory'}
    snapshots[0]['modules'][0]['exports'] = [
        e for e in exports if e['name'] not in non_main and e['name'] not in R4A_PROCEDURES
        and e['name'] not in R4B_PROCEDURES
        and e['name'] not in R4C_PROCEDURES
        and e['name'] not in R4D_PROCEDURES and e['name'] not in R4D_VALUES
        and e['name'] not in R4E_PROCEDURES and e['name'] not in R4E_VALUES
        and e['name'] not in R4E_PARAMETERS]
    return snapshots


class Fixtures(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        shutil.copytree(ROOT / checks.REFERENCE, self.root / checks.REFERENCE)
        shutil.copy(ROOT / 'info.rkt', self.root / 'info.rkt')
        (self.root / 'api').mkdir()
        self.manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        # The synthetic inventory already contains the later procedure. Keep the
        # real source supplement separate from these deliberately synthetic fixtures.
        self.manifest.pop('source_verified_additions', None)
        self.manifest['deferred_policy'] = {
            'stage': 'synthetic-fixture',
            'reason': 'The fixture deliberately adds one uncovered export.'}
        self.snapshots = synthetic_inventory()
        self.write_inventory()

    def write_inventory(self):
        for expected, data in zip(self.manifest['snapshots'], self.snapshots):
            raw = (json.dumps(data, indent=2) + '\n').encode()
            (self.root / expected['file']).write_bytes(raw)
            expected['git_blob'] = checks.git_blob(raw)
        self.write_manifest()

    def write_manifest(self):
        (self.root / checks.MANIFEST).write_text(json.dumps(self.manifest) + '\n')

    def change(self, file, before, after):
        path = self.root / checks.REFERENCE / file
        text = path.read_text()
        self.assertIn(before, text)
        path.write_text(text.replace(before, after, 1))

    def check(self, **options):
        return checks.check_source(self.root, **options)

    def test_effect_module_alias_sets_are_complete(self):
        for module, names in [('skia/effects', EFFECT_EXPORTS),
                              ('skia/color-filters', COLOR_FILTER_EXPORTS),
                              ('skia/runtime-effects', RUNTIME_EXPORTS)]:
            actual = {r['name'] for r in self.manifest['definitions'] if module in r['exports']}
            self.assertEqual(actual, set(names))

    def test_missing_runtime_alias_is_rejected(self):
        module = next(m for m in self.snapshots[0]['modules'] if m['path'] == 'runtime-effects.rkt')
        module['exports'] = [r for r in module['exports'] if r['name'] != 'runtime-effect->shader']
        self.write_inventory()
        with self.assertRaisesRegex(checks.CheckError, 'unknown public export'):
            self.check()

    def test_incorrect_runtime_keyword_is_rejected(self):
        self.change('runtime-effects.scrbl', '#:local-matrix local-matrix', '#:matrix local-matrix')
        with self.assertRaisesRegex(checks.CheckError, 'allowed_keywords'):
            self.check()

    def test_effect_alias_arity_must_agree(self):
        module = next(m for m in self.snapshots[0]['modules'] if m['path'] == 'effects.rkt')
        next(r for r in module['exports'] if r['name'] == 'make-1d-path-effect')['arity_mask'] = '4'
        self.write_inventory()
        with self.assertRaisesRegex(checks.CheckError, 'arity_mask'):
            self.check()

    def test_real_authored_source_shape(self):
        result = self.check()
        self.assertEqual(len(result['definitions']), 1263)
        self.assertEqual(result['documented_exports'], 1988)
        self.assertEqual(len(result['deferred']), 1)
        self.assertFalse(result['binding_identity_checked'])

    def test_missing_definition(self):
        self.change('drawing.scrbl', '@defproc[', '@racketblock[')
        with self.assertRaises(checks.CheckError):
            self.check()

    def test_extra_definition(self):
        path = self.root / checks.REFERENCE / 'drawing.scrbl'
        path.write_text(path.read_text() + '\n@defproc[(invented) void?]{No public export.}\n')
        with self.assertRaises(checks.CheckError):
            self.check()

    def test_duplicate_definition(self):
        path = self.root / checks.REFERENCE / 'drawing.scrbl'
        path.write_text(path.read_text() + '\n@defproc[(draw-rect) void?]{Duplicate.}\n')
        with self.assertRaises(checks.CheckError):
            self.check()

    def test_changed_arity(self):
        self.change('drawing.scrbl', '[canvas canvas?]', '[canvas canvas?] [extra any/c]')
        with self.assertRaisesRegex(checks.CheckError, 'arity_mask'):
            self.check()

    def test_changed_keyword(self):
        self.change('surfaces.scrbl', '#:background background', '#:backdrop background')
        with self.assertRaisesRegex(checks.CheckError, 'allowed_keywords'):
            self.check()

    def test_required_keyword(self):
        self.change('surfaces.scrbl', "background color? 'transparent", 'background color?')
        with self.assertRaisesRegex(checks.CheckError, 'required_keywords'):
            self.check()

    def test_defaults_are_not_inferred_by_inventory(self):
        self.change('surfaces.scrbl', "background color? 'transparent", "background color? 'white")
        self.assertEqual(self.check()['status'], 'passed')

    def test_wrong_kind(self):
        self.snapshots[0]['modules'][0]['exports'][0]['kind'] = 'class'
        self.write_inventory()
        with self.assertRaisesRegex(checks.CheckError, 'kind mismatch'):
            self.check()

    def test_export_kind_is_not_callable_kind(self):
        self.snapshots[0]['modules'][0]['exports'][0]['export_kind'] = 'syntax'
        self.write_inventory()
        self.assertEqual(self.check()['status'], 'passed')

    def test_unknown_alias(self):
        self.manifest['definitions'][0]['exports'].append('skia/not-an-exporter')
        self.write_manifest()
        with self.assertRaisesRegex(checks.CheckError, 'unknown public export'):
            self.check()

    def test_same_name_in_another_module_is_not_merged(self):
        self.snapshots[1]['modules'].append(
            dict(path='other.rkt', exports=[row('make-surface', 2, [])]))
        self.write_inventory()
        result = self.check()
        self.assertEqual(len(result['deferred']), 2)
        self.assertTrue(any(r['module'] == 'skia/other' for r in result['deferred']))

    def test_snapshot_change_requires_review(self):
        path = self.root / self.manifest['snapshots'][0]['file']
        path.write_bytes(path.read_bytes() + b'\n')
        with self.assertRaisesRegex(checks.CheckError, 'snapshot changed'):
            self.check()

    def test_missing_snapshot_fails(self):
        (self.root / self.manifest['snapshots'][1]['file']).unlink()
        with self.assertRaises(FileNotFoundError):
            self.check()

    def test_documents_only_discloses_missing_inventory(self):
        (self.root / self.manifest['snapshots'][1]['file']).unlink()
        self.assertFalse(self.check(documents_only=True)['inventory_checked'])

    def test_complete_mode_rejects_deferrals(self):
        with self.assertRaisesRegex(checks.CheckError, 'remain deferred'):
            self.check(require_complete=True)

    def test_documents_only_is_not_complete(self):
        with self.assertRaises(checks.CheckError):
            self.check(documents_only=True, require_complete=True)

    def test_no_duplicate_export_claims(self):
        self.manifest['definitions'][0]['exports'].append('skia')
        self.write_manifest()
        with self.assertRaisesRegex(checks.CheckError, 'claimed twice'):
            self.check()

    def test_no_private_import_paths(self):
        self.manifest['definitions'][0]['exports'].append('skia/private/core')
        self.write_manifest()
        with self.assertRaises(checks.CheckError):
            self.check()

    def test_wrong_chapter(self):
        self.manifest['definitions'][0]['chapter'] = 'scribblings/reference/surfaces.scrbl'
        self.write_manifest()
        with self.assertRaisesRegex(checks.CheckError, 'wrong canonical chapter'):
            self.check()

    def test_unregistered_manual(self):
        (self.root / 'info.rkt').write_text('#lang info\n')
        with self.assertRaisesRegex(checks.CheckError, 'not registered'):
            self.check()

    def test_no_disabled_definition_targets(self):
        self.change('drawing.scrbl', '@defproc[', '@defproc[#:link-target? #f ')
        with self.assertRaises(checks.CheckError):
            self.check()

    def test_no_fake_definition_inside_examples(self):
        path = self.root / checks.REFERENCE / 'drawing.scrbl'
        path.write_text(path.read_text() + '\n@racketblock["@defproc[(fake) any/c]"]\n')
        self.assertEqual(len(self.check()['definitions']), 1263)

    def test_scribble_comments_are_not_definitions(self):
        path = self.root / checks.REFERENCE / 'drawing.scrbl'
        path.write_text(path.read_text() + '\n@;{@defproc[(fake) any/c]{No.}}\n')
        self.assertEqual(len(self.check()['definitions']), 1263)

    def test_cyclic_chapter_include(self):
        path = self.root / checks.REFERENCE / 'drawing.scrbl'
        path.write_text(path.read_text() + '\n@include-section["reference.scrbl"]\n')
        with self.assertRaisesRegex(checks.CheckError, 'cyclic'):
            self.check()

    def test_unsafe_chapter_path(self):
        self.change('geometry-and-drawing.scrbl', '"drawing.scrbl"', '"../../outside.scrbl"')
        with self.assertRaisesRegex(checks.CheckError, 'unsafe'):
            self.check()

    def test_datum_comments_in_signature(self):
        self.change('drawing.scrbl', '[canvas canvas?]', '[canvas #;ignored canvas?]')
        self.assertEqual(self.check()['status'], 'passed')

    def test_unsupported_signature_fails_closed(self):
        self.change('drawing.scrbl', '[canvas canvas?]', '[canvas canvas?] ...')
        with self.assertRaisesRegex(checks.CheckError, 'rest/case'):
            self.check()


    def test_structure_member_inventory(self):
        result = self.check()
        members = [row for row in result['definitions'] if row.get('definition_group') == 'rgba']
        self.assertEqual({row['name'] for row in members},
                         {'rgba', 'struct:rgba', 'rgba?', 'rgba-red', 'rgba-green',
                          'rgba-blue', 'rgba-alpha'})
        self.assertTrue(all(row['form'] == 'defstruct*' for row in members))
        descriptor = next(row for row in members if row['name'] == 'struct:rgba')
        self.assertEqual(descriptor['kind'], 'value')
        self.assertNotIn('arity_mask', descriptor)

    def test_no_separate_duplicate_predicate(self):
        path = self.root / checks.REFERENCE / 'colors.scrbl'
        path.write_text(path.read_text() + '\n@defproc[(rgba? [v any/c]) boolean?]{Duplicate.}\n')
        with self.assertRaisesRegex(checks.CheckError, 'duplicate canonical'):
            self.check()

    def test_missing_accessor_export_rejected(self):
        exports = self.snapshots[0]['modules'][1]['exports']
        exports[:] = [row for row in exports if row['name'] != 'rgba-alpha']
        self.write_inventory()
        with self.assertRaisesRegex(checks.CheckError, 'unknown public export'):
            self.check()

    def test_changed_field_changes_coverage(self):
        self.change('colors.scrbl', '[alpha byte?]', '[opacity byte?]')
        with self.assertRaisesRegex(checks.CheckError, 'coverage mismatch'):
            self.check()

    def test_structure_constructor_arity_is_checked(self):
        exports = self.snapshots[0]['modules'][0]['exports']
        next(row for row in exports if row['name'] == 'rgba')['arity_mask'] = '8'
        self.write_inventory()
        with self.assertRaisesRegex(checks.CheckError, 'arity_mask'):
            self.check()

    def test_structure_descriptor_kind_is_checked(self):
        exports = self.snapshots[0]['modules'][0]['exports']
        next(row for row in exports if row['name'] == 'struct:rgba')['kind'] = 'procedure'
        self.write_inventory()
        with self.assertRaisesRegex(checks.CheckError, 'kind mismatch'):
            self.check()

    def test_unsupported_structure_flags(self):
        for flag in ('#:mutable', '#:prefab', '#:omit-constructor', '#:constructor-name make-rgba'):
            with self.subTest(flag=flag), self.assertRaises(checks.CheckError):
                checks.structure_shapes(checks.Reader('[rgba ([red byte?]) ' + flag + ']').read())

    def test_unsupported_structure_fields(self):
        for fields in ('([(red #:mutable) byte?])', '([red byte? 0])',
                       '([red byte?] [red byte?])'):
            with self.subTest(fields=fields), self.assertRaises(checks.CheckError):
                checks.structure_shapes(checks.Reader('[rgba ' + fields + ' #:transparent]').read())

    def test_tutorial_destination_metadata_matches_source(self):
        self.manifest['tutorial_links'][0]['tag'] = 'nonexistent'
        self.write_manifest()
        with self.assertRaisesRegex(checks.CheckError, 'tutorial link/source'):
            self.check()

    def test_tutorial_link_in_entry_body_is_found(self):
        self.change('paints.scrbl', 'vector-raster/vector-raster.scrbl', 'vector-raster/wrong.scrbl')
        with self.assertRaisesRegex(checks.CheckError, 'tutorial link/source'):
            self.check()

    def test_tutorial_link_in_example_is_not_counted(self):
        path = self.root / checks.REFERENCE / 'drawing.scrbl'
        path.write_text(path.read_text() + '\n@racketblock["@seclink[\\\"top\\\"]"]\n')
        self.assertEqual(self.check()['status'], 'passed')

    def test_color_space_predicate_is_in_color_chapter(self):
        spec = next(row for row in self.check()['definitions'] if row['name'] == 'color-space?')
        self.assertEqual(spec['chapter'], 'scribblings/reference/color-management.scrbl')
        self.assertEqual(spec['exports'], ['skia'])

    def test_no_temporary_edition_language(self):
        text = (self.root / checks.REFERENCE / 'reference.scrbl').read_text()
        self.assertNotIn('first edition', text)


class HtmlTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.site = Path(self.temporary.name)
        self.reference = self.site / 'skia-reference'
        self.reference.mkdir()
        self.names = ('make-surface', 'surface-canvas', 'make-paint', 'draw-rect',
                      'save-png', 'with-skia', 'color?', 'color->argb')
        self.targets = [dict(name=name, relative_path='entry.html', anchor='def-' + name)
                        for name in self.names]
        self.page = self.reference / 'entry.html'
        self.page.write_text(''.join('<a name="' + escape(t['anchor']) + '"></a>'
                                     for t in self.targets))
        self.quick = self.site / 'skia-tutorial-quick/index.html'
        self.quick.parent.mkdir()
        self.quick.write_text(''.join(
            '<a href="../skia-reference/entry.html#' + quote(t['anchor']) + '"><span>'
            + escape(t['name']) + '</span></a>' for t in self.targets))
        self.evidence = dict(targets=self.targets, tutorial_targets=[])

    def check(self):
        return checks.check_targets(self.site, self.evidence, quick=self.quick)

    def test_real_anchor_matching_logic(self):
        self.assertEqual(self.check()['status'], 'passed')

    def test_missing_identifier_link(self):
        self.quick.write_text('No API links.')
        with self.assertRaisesRegex(checks.CheckError, 'missing identifier'):
            self.check()

    def test_wrong_anchor(self):
        self.quick.write_text(self.quick.read_text().replace('#def-draw-rect', '#def-make-paint'))
        with self.assertRaisesRegex(checks.CheckError, 'wrong binding link'):
            self.check()

    def test_missing_target_anchor(self):
        self.page.write_text('No definitions.')
        with self.assertRaisesRegex(checks.CheckError, 'anchor'):
            self.check()

    def test_duplicate_target_anchor(self):
        self.page.write_text(self.page.read_text() * 2)
        with self.assertRaisesRegex(checks.CheckError, 'duplicate'):
            self.check()

    def test_unresolved_reference_markup(self):
        self.page.write_text(self.page.read_text() + '<span class="RktSym badlink">oops</span>')
        with self.assertRaisesRegex(checks.CheckError, 'unresolved'):
            self.check()

    def test_racket_redirect(self):
        url = ('https://download.racket-lang.org/releases/9.3/doc/local-redirect/index.html'
               '?doc=skia-reference&rel=entry.html%23def-draw-rect&version=0.78')
        self.assertEqual(checks.internal_redirect(url),
                         ('skia-reference', 'entry.html', 'def-draw-rect'))

    def test_external_redirect_host_is_not_trusted(self):
        url = ('https://example.org/local-redirect/index.html'
               '?doc=skia-reference&rel=entry.html')
        self.assertIsNone(checks.internal_redirect(url))

    def test_external_manual_is_not_rewritten(self):
        url = ('https://docs.racket-lang.org/local-redirect/index.html'
               '?doc=reference&rel=index.html')
        self.assertIsNone(checks.internal_redirect(url))

    def test_traversal_redirect_rejected(self):
        url = ('https://docs.racket-lang.org/local-redirect/index.html'
               '?doc=skia-reference&rel=..%2Fsecret')
        with self.assertRaises(checks.CheckError):
            checks.internal_redirect(url)

    def test_prepare_reference_and_tutorial_redirects(self):
        for doc in ('skia-reference', 'skia-tutorial-quick'):
            filename = 'entry.html' if doc == 'skia-reference' else 'index.html'
            self.quick.write_text('<a href="https://docs.racket-lang.org/local-redirect/index.html'
                                  f'?doc={doc}&amp;rel={filename}%23here&amp;version=0.78">x</a>')
            self.assertEqual(checks.prepare_site(self.site), 1)
            self.assertNotIn('local-redirect', self.quick.read_text())
            self.assertIn('#here', self.quick.read_text())

    def test_uncopied_destination_rejected(self):
        self.quick.write_text('<a href="https://docs.racket-lang.org/local-redirect/index.html'
                              '?doc=skia-reference&amp;rel=missing.html">x</a>')
        with self.assertRaises(checks.CheckError):
            checks.prepare_site(self.site)

    def test_prepare_local_file_link(self):
        source = self.site / 'original-doc'
        self.quick.write_text('<a href="' + (source / 'skia-reference/entry.html').as_uri()
                              + '#def-draw-rect">x</a>')
        self.assertEqual(checks.prepare_site(self.site, source_root=source), 1)
        self.assertIn('../skia-reference/entry.html#def-draw-rect', self.quick.read_text())

    def test_reference_test_evidence_path_is_confined(self):
        evidence = copy.deepcopy(self.evidence)
        evidence['targets'][0]['relative_path'] = '../index.html'
        with self.assertRaises(checks.CheckError):
            checks.check_targets(self.site, evidence)


    def add_tutorial(self, *, anchor='top'):
        path = self.site / 'skia-tutorials/index.html'
        path.parent.mkdir(exist_ok=True)
        path.write_text('<a name="top"></a>Skia Tutorials')
        row = dict(manual='scribblings/tutorials/index.scrbl', directory='skia-tutorials',
                   tag='top', label='Skia tutorials', relative_path='index.html', anchor=anchor)
        self.evidence['tutorial_targets'] = [row]
        href = '../skia-tutorials/index.html' + ('#' + anchor if anchor else '')
        self.page.write_text(self.page.read_text() + '<a href="' + href + '">Skia tutorials</a>')
        return path

    def test_tutorial_destination_is_checked(self):
        self.add_tutorial()
        self.assertEqual(self.check()['tutorial_links'], {'skia-tutorials': 1})

    def test_tutorial_top_without_fragment(self):
        self.add_tutorial(anchor='')
        self.assertEqual(self.check()['status'], 'passed')

    def test_deleted_tutorial_page(self):
        self.add_tutorial().unlink()
        with self.assertRaisesRegex(checks.CheckError, 'missing HTML'):
            self.check()

    def test_missing_tutorial_anchor(self):
        self.add_tutorial().write_text('No target.')
        with self.assertRaisesRegex(checks.CheckError, 'tutorial target anchor'):
            self.check()

    def test_plain_text_is_not_a_working_tutorial_link(self):
        self.add_tutorial()
        text = self.page.read_text()
        self.page.write_text(text[:text.rindex('<a href=')] + 'Skia tutorials')
        with self.assertRaisesRegex(checks.CheckError, 'missing tutorial link'):
            self.check()

    def test_wrong_tutorial_link_is_not_accepted(self):
        self.add_tutorial()
        self.page.write_text(self.page.read_text().replace('index.html#top', 'index.html#wrong'))
        with self.assertRaisesRegex(checks.CheckError, 'wrong tutorial link'):
            self.check()

    def test_external_substitute_is_not_accepted(self):
        self.add_tutorial()
        self.page.write_text(self.page.read_text().replace('../skia-tutorials/',
                                                           'https://example.org/tutorials/'))
        with self.assertRaisesRegex(checks.CheckError, 'missing tutorial link'):
            self.check()

    def test_tutorial_link_is_checked_after_relocation(self):
        self.add_tutorial()
        self.page.write_text(self.page.read_text().replace(
            '../skia-tutorials/index.html#top',
            'https://docs.racket-lang.org/local-redirect/index.html'
            '?doc=skia-tutorials&amp;rel=index.html%23top'))
        self.assertEqual(checks.prepare_site(self.site), 1)
        self.assertEqual(self.check()['status'], 'passed')

    def test_member_aliases_can_share_a_struct_anchor(self):
        self.evidence['targets'] += [dict(name='rgba-red', module='skia/color',
                                         relative_path='entry.html', anchor='def-color?')]
        self.assertEqual(self.check()['status'], 'passed')


class EvidenceTests(unittest.TestCase):
    def test_evidence_requires_exact_source_coverage(self):
        source = dict(definitions=[dict(name='color?', exports=['skia', 'skia/color'])])
        evidence = dict(status='passed', xref_checked=True, installed_xref=True,
                        targets=[dict(name='color?', module='skia')])
        with self.assertRaises(checks.CheckError):
            checks.check_evidence(source, evidence, installed=True)
        evidence['targets'].append(dict(name='color?', module='skia/color'))
        checks.check_evidence(source, evidence, installed=True)

    def test_fresh_xref_is_not_installed_evidence(self):
        with self.assertRaises(checks.CheckError):
            checks.check_evidence(dict(definitions=[]),
                                  dict(status='passed', xref_checked=True, installed_xref=False),
                                  installed=True)


    def test_missing_tutorial_xref_evidence_fails(self):
        source = dict(definitions=[], tutorial_links=[
            dict(manual='scribblings/tutorials/index.scrbl', directory='skia-tutorials',
                 tag='top', label='Skia tutorials')])
        evidence = dict(status='passed', xref_checked=True, targets=[])
        with self.assertRaisesRegex(checks.CheckError, 'tutorial target inventory'):
            checks.check_evidence(source, evidence)
        evidence['tutorial_targets'] = copy.deepcopy(source['tutorial_links'])
        checks.check_evidence(source, evidence)


class ReaderTests(unittest.TestCase):
    def test_nested_block_comment(self):
        self.assertEqual(checks.Reader('(x #| outer #| inner |# end |# y)').read(), ['x', 'y'])

    def test_bracket_mismatch(self):
        with self.assertRaises(checks.CheckError):
            checks.Reader('(x]').read()

    def test_optional_positionals(self):
        header = checks.Reader('[(f [x any/c] [y any/c #f]) any/c]').read()
        self.assertEqual(checks.procedure_shape(header)['arity_mask'], '6')

    def test_string_does_not_become_identifier(self):
        self.assertIsInstance(checks.Reader('"hello"').read(), checks.String)

    def test_braces_in_embedded_code_are_not_body_delimiters(self):
        text = '@defproc[(f) any/c]{Example: @racket["}"] text.} @defproc[(g) any/c]{Next.}'
        self.assertEqual([name for name, _, _ in checks.commands(text)], ['defproc', 'defproc'])

    def test_unclosed_string(self):
        with self.assertRaises(checks.CheckError):
            checks.Reader('"hello').read()


class BuildPlanTests(unittest.TestCase):
    """Mocked command planning only: these tests do not execute Racket."""
    def setUp(self):
        spec = importlib.util.spec_from_file_location(
            'reference_runner', ROOT / 'tools/check-reference.py')
        self.runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.runner)
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.output = Path(self.temporary.name) / 'evidence'
        links = json.loads((ROOT / checks.MANIFEST).read_text())['tutorial_links']
        self.source = dict(definitions=[], deferred=[], tutorial_links=links)
        self.commands = []

    def run_fake(self, command, **options):
        self.commands.append(command)
        if any(str(arg).endswith('reference-runtime.rkt') for arg in command):
            Path(command[command.index('--output') + 1]).write_text('{}')
        return SimpleNamespace(returncode=0)

    def execute(self, *args):
        with (patch.object(self.runner, 'source_hashes', return_value={}),
              patch.object(self.runner, 'inspect_link_scopes', return_value={}),
              patch.object(self.runner, 'check_review_html', return_value={}),
              patch.object(self.runner, 'check_source', return_value=self.source),
              patch.object(self.runner.shutil, 'which', return_value='/fake/racket'),
              patch.object(self.runner.subprocess, 'run', side_effect=self.run_fake),
              patch.object(self.runner, 'check_evidence'),
              patch.object(self.runner, 'check_targets', return_value=dict(status='passed')),
              contextlib.redirect_stdout(io.StringIO())):
            result = self.runner.main([*args, '--output', str(self.output)])
        self.assertEqual(result, 0)
        return json.loads((self.output / 'validation.json').read_text())

    def test_reference_render_loads_real_tutorial_xrefs(self):
        report = self.execute('--render')
        steps = {row['label']: row['command'] for row in report['commands']}
        labels = [row['label'] for row in report['commands']]
        self.assertLess(labels.index('reference-seed'), labels.index('skia-tutorials'))
        self.assertLess(labels.index('skia-tutorial-color-spaces'), labels.index('reference'))
        self.assertEqual(steps['reference'].count('++info-in'), 3)
        self.assertEqual(steps['xref'].count('--tutorial-xref'), 3)
        self.assertIn('--lib', steps['reference'])
        self.assertTrue(any(arg.endswith('reference-render.rkt') for arg in steps['reference']))
        self.assertIn('render-driver-tests', steps)
        self.assertIn('skia/scribblings/reference/reference.scrbl', steps['reference'])
        for row in self.source['tutorial_links']:
            command = steps[row['directory']]
            self.assertIn('skia/' + row['manual'], command)
            self.assertIn('--info-out', command)
            self.assertIn('++info-in', command)
        self.assertEqual(len(report['tutorial_manuals_rendered']), 3)
        self.assertIn('color-tests', steps)

    def test_all_standalone_documents_use_the_prefix_driver(self):
        report = self.execute('--render', '--quick')
        steps = {row['label']: row['command'] for row in report['commands']}
        for label in ('reference-seed', 'reference', 'link-probe', 'quick',
                      *[row['directory'] for row in self.source['tutorial_links']]):
            self.assertTrue(any(arg.endswith('reference-render.rkt') for arg in steps[label]))
            self.assertIn('--lib', steps[label])
            self.assertIn('--dest-name', steps[label])

    def test_review_zip_requires_a_render_or_installed_check(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                self.runner.main(['--documents-only', '--review-zip',
                                  str(self.output / 'review.zip')])

    def test_failed_html_does_not_call_packager(self):
        archive = self.output.parent / 'review.zip'
        with (patch.object(self.runner, 'source_hashes', return_value={}),
              patch.object(self.runner, 'inspect_link_scopes', return_value={}),
              patch.object(self.runner, 'check_review_html', return_value={}),
              patch.object(self.runner, 'check_source', return_value=self.source),
              patch.object(self.runner.shutil, 'which', return_value='/fake/racket'),
              patch.object(self.runner.subprocess, 'run', side_effect=self.run_fake),
              patch.object(self.runner, 'check_evidence'),
              patch.object(self.runner, 'check_targets', side_effect=checks.CheckError('bad HTML')),
              patch.object(self.runner, 'package_review') as package,
              contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO())):
            result = self.runner.main(['--render', '--review-zip', str(archive),
                                       '--output', str(self.output)])
        self.assertEqual(result, 1)
        package.assert_not_called()
        self.assertFalse(archive.exists())

    def test_review_packaging_follows_native_checks(self):
        archive = self.output.parent / 'review.zip'
        with patch.object(self.runner, 'package_review', return_value={'path': str(archive)}) as pack:
            report = self.execute('--render', '--native', '--review-zip', str(archive))
        pack.assert_called_once()
        self.assertEqual(report['commands'][-1]['label'], 'native-cpu')
        self.assertEqual(report['review_zip']['path'], str(archive))

    def test_installed_check_does_not_rebuild_tutorials(self):
        report = self.execute('--installed', str(self.output.parent / 'installed'))
        steps = {row['label']: row['command'] for row in report['commands']}
        self.assertNotIn('reference-seed', steps)
        self.assertNotIn('reference', steps)
        self.assertIn('--installed', steps['xref'])
        self.assertNotIn('--tutorial-xref', steps['xref'])
        self.assertEqual(report['tutorial_manuals_rendered'], [])

    def test_native_check_remains_separate_from_rendering(self):
        report = self.execute('--native')
        labels = [row['label'] for row in report['commands']]
        self.assertIn('native-cpu', labels)
        self.assertIn('color-tests', labels)
        self.assertNotIn('reference', labels)
        self.assertFalse(report['scribble_rendered'])

    def test_render_does_not_silently_skip_missing_racket(self):
        with (patch.object(self.runner, 'source_hashes', return_value={}),
              patch.object(self.runner, 'inspect_link_scopes', return_value={}),
              patch.object(self.runner, 'check_review_html', return_value={}),
              patch.object(self.runner, 'check_source', return_value=self.source),
              patch.object(self.runner.shutil, 'which', return_value=None),
              contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO())):
            result = self.runner.main(['--render', '--output', str(self.output)])
        self.assertEqual(result, 1)
        report = json.loads((self.output / 'validation.json').read_text())
        self.assertFalse(report['racket_executed'])
        self.assertFalse(report['scribble_rendered'])
        self.assertEqual(report['commands'], [])



    def test_plain_render_rejects_unresolved_identifier_in_secondary_page(self):
        def render(command, **options):
            result = self.run_fake(command, **options)
            directory = self.output / 'skia-reference'
            directory.mkdir(exist_ok=True)
            (directory / 'index.html').write_text('<p>Reference</p>')
            (directory / 'doc-index.html').write_text('<span class="badlink">picture?</span>')
            return result
        with (patch.object(self.runner, 'source_hashes', return_value={}),
              patch.object(self.runner, 'check_source', return_value=self.source),
              patch.object(self.runner.shutil, 'which', return_value='/fake/racket'),
              patch.object(self.runner.subprocess, 'run', side_effect=render),
              patch.object(self.runner, 'check_evidence'),
              patch.object(self.runner, 'check_targets', return_value=dict(status='passed')),
              contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO())):
            result = self.runner.main(['--render', '--output', str(self.output)])
        self.assertEqual(result, 1)
        report = json.loads((self.output / 'validation.json').read_text())
        self.assertTrue(report['scribble_rendered'])
        self.assertFalse(report['reference_html_checked'])
        self.assertIn('doc-index.html', report['error'])
        self.assertEqual(report['html_link_scopes']['reference']['unresolved_references'], 1)

    def test_plain_render_runs_real_html_gate_without_publishing_an_archive(self):
        def render(command, **options):
            result = self.run_fake(command, **options)
            directory = self.output / 'skia-reference'
            directory.mkdir(exist_ok=True)
            (directory / 'index.html').write_text('<p>Reference</p>')
            return result
        with (patch.object(self.runner, 'source_hashes', return_value={}),
              patch.object(self.runner, 'check_source', return_value=self.source),
              patch.object(self.runner.shutil, 'which', return_value='/fake/racket'),
              patch.object(self.runner.subprocess, 'run', side_effect=render),
              patch.object(self.runner, 'check_evidence'),
              patch.object(self.runner, 'check_targets', return_value=dict(status='passed')),
              patch.object(self.runner, 'package_review') as package,
              contextlib.redirect_stdout(io.StringIO())):
            result = self.runner.main(['--render', '--output', str(self.output)])
        self.assertEqual(result, 0)
        report = json.loads((self.output / 'validation.json').read_text())
        self.assertTrue(report['reference_html_checked'])
        self.assertEqual(report['reference_html']['reference_pages'], 1)
        package.assert_not_called()


class EditorialRevisionTests(unittest.TestCase):
    def test_arbitrary_value_predicates_use_v(self):
        definitions, _ = checks.document_definitions(ROOT)
        for spec in definitions:
            if spec['kind'] == 'procedure' and spec['name'] in PREDICATES:
                self.assertEqual(spec['arguments'][0]['name'], 'v', spec['name'])

    def test_coordinate_prose_is_not_an_application(self):
        text = (ROOT / checks.REFERENCE / 'drawing.scrbl').read_text()
        self.assertNotIn('@racket[(x y)]', text)
        self.assertIn('@racket[x] and @racket[y]', text)

    def test_complete_drawing_manages_both_resources(self):
        text = (ROOT / checks.REFERENCE / 'drawing.scrbl').read_text()
        blocks = [header for form, header, _ in checks.commands(text, recursive=True)
                  if form == 'racketblock']
        self.assertEqual(len(blocks), 12)
        self.assertEqual(blocks[0][0][0], 'with-skia')
        self.assertEqual([row[0] for row in blocks[0][0][1]], ['surface', 'paint'])
        self.assertIn("#:exists 'replace", text)

    def test_icc_responsibility_and_validation_are_distinct(self):
        text = (ROOT / checks.REFERENCE / 'encoding.scrbl').read_text()
        self.assertIn('The caller is responsible', text)
        self.assertIn('does not verify that it agrees with those samples', text)
        self.assertIn("checks the profile's format", text)
        self.assertIn('profile does not convert the samples', text)

    def test_supported_color_names_are_indexed_once(self):
        text = (ROOT / checks.REFERENCE / 'colors.scrbl').read_text()
        indexed = re.findall(r"@indexed-racket\['([a-z-]+)\]", text)
        names = ('transparent black white red green blue yellow cyan magenta gray grey orange purple'
                 .split())
        self.assertCountEqual(indexed, names)
        self.assertEqual(len(indexed), len(set(indexed)))

    def test_every_blend_symbol_has_an_authoritative_description(self):
        text = (ROOT / checks.REFERENCE / 'paints.scrbl').read_text()
        signature = next(header for form, header, _ in checks.commands(text)
                         if form == 'defproc' and header[0][0] == 'make-paint')
        blend = next(row for row in signature[0] if isinstance(row, list)
                     and row[0] == '#:blend-mode')
        allowed = [item[1] for item in blend[2][1:]]
        self.assertEqual(len(allowed), 29)
        described = re.findall(r"@indexed-racket\['([a-z-]+)\]", text)
        self.assertCountEqual(described, allowed)
        self.assertIn('@secref["skia-blend-modes"]', text)

    def test_blend_alpha_and_scope_are_explicit(self):
        text = (ROOT / checks.REFERENCE / 'paints.scrbl').read_text()
        for phrase in ('fully covered pixels', 'premultiplied', 'Ralpha = a + b - a b',
                       "@racket['modulate] mode instead gives alpha @math{a b}",
                       'extended-range floating-point storage'):
            self.assertIn(phrase, text)

    def test_source_definitions_and_chapter_count_are_unchanged(self):
        result = checks.check_source(ROOT, documents_only=True)
        self.assertEqual(len(result['definitions']), 1263)
        self.assertEqual(result['documented_exports'], 1988)
        self.assertEqual(len(result['chapters']), 85)  # Root plus eighty-four chapters.


class ReviewArchiveTests(unittest.TestCase):
    """Synthetic HTML/xref evidence exercises packaging, not a Racket build."""
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        base = Path(self.temporary.name)
        self.root, self.site = base / 'sources', base / 'rendered'
        self.root.mkdir()
        shutil.copytree(ROOT / checks.REFERENCE, self.root / checks.REFERENCE)
        for name in ('info.rkt', str(checks.MANIFEST), 'docs/REFERENCE-DEVELOPMENT.md'):
            destination = self.root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / name, destination)
        self.manifest = json.loads((self.root / checks.MANIFEST).read_text())
        # The synthetic inventory already contains the later procedure. Keep the
        # real source supplement separate from these deliberately synthetic fixtures.
        self.manifest.pop('source_verified_additions', None)
        self.manifest['deferred_policy'] = {
            'stage': 'synthetic-fixture',
            'reason': 'The fixture deliberately adds one uncovered export.'}
        self.snapshots = synthetic_inventory()
        for expected, data in zip(self.manifest['snapshots'], self.snapshots):
            raw = (json.dumps(data, indent=2) + '\n').encode()
            (self.root / expected['file']).write_bytes(raw)
            expected['git_blob'] = checks.git_blob(raw)
        (self.root / checks.MANIFEST).write_text(json.dumps(self.manifest) + '\n')
        for row in self.manifest['tutorial_links']:
            path = self.root / row['manual']
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('#lang scribble/manual\n@title{Synthetic companion}\n')
        (self.root / 'tools').mkdir()
        for path in (ROOT / 'tools').glob('*reference*'):
            if path.suffix in {'.py', '.rkt'}:
                shutil.copy(path, self.root / 'tools' / path.name)
        self.source = checks.check_source(self.root)
        self.hashes = review.source_hashes(self.root, review_inputs=True)
        self.archive = base / 'review.zip'
        self.reference = self.site / 'skia-reference'
        self.reference.mkdir(parents=True)
        targets, anchors = [], []
        for index, spec in enumerate(self.source['definitions']):
            anchor = 'definition-' + str(index)
            anchors.append(f'<span id="{anchor}"></span>')
            for module in spec['exports']:
                targets.append(dict(name=spec['name'], module=module, anchor=anchor,
                                    relative_path='entries.html'))
        self.entries = self.reference / 'entries.html'
        self.entries.write_text(''.join(anchors))
        links, tutorial_targets = [], []
        for row in self.source['tutorial_links']:
            target = self.site / row['directory'] / 'index.html'
            target.parent.mkdir()
            target.write_text('<h1 id="top">Tutorial</h1>')
            links.append(f'<a href="../{row["directory"]}/index.html#top">{row["label"]}</a>')
            tutorial_targets.append(dict(row, relative_path='index.html', anchor='top'))
        self.index = self.reference / 'index.html'
        self.index.write_text('<link rel="stylesheet" href="../manual-style.css">' + ''.join(links))
        (self.site / 'manual-style.css').write_text('body { margin: 2em; }')
        (self.site / 'reference-seed.sxref').write_text('Not for publication')
        section_targets = [dict(link, relative_path=link['filename'], anchor=link['tag'])
                           for link in self.source['section_links']]
        for filename in {row['filename'] for row in section_targets}:
            (self.reference / filename).write_text(''.join(
                f'<span id="{row["anchor"]}"></span>' for row in section_targets
                if row['filename'] == filename))
        self.evidence = dict(status='passed', xref_checked=True, targets=targets,
                             tutorial_targets=tutorial_targets, section_targets=section_targets)

    def package(self):
        return review.package_review(self.root, self.site, self.source, self.evidence,
                                     self.archive, self.hashes)

    def test_archive_rechecks_extracted_html_and_source_bytes(self):
        result = self.package()
        self.assertTrue(result['extracted_zip_checked'])
        with zipfile.ZipFile(self.archive) as archive:
            self.assertIsNone(archive.testzip())
            names = archive.namelist()
            self.assertIn('html/skia-reference/index.html', names)
            for row in self.source['tutorial_links']:
                self.assertIn('html/' + row['directory'] + '/index.html', names)
            self.assertIn('sources/scribblings/reference/drawing.scrbl', names)
            self.assertFalse(any('seed' in name or name.endswith('.sxref') for name in names))
            for line in archive.read('SHA256SUMS.txt').decode().splitlines():
                digest, name = line.split('  ', 1)
                self.assertEqual(hashlib.sha256(archive.read(name)).hexdigest(), digest)
            self.assertEqual(result['entries'], len(names))

    def test_existing_archive_is_never_replaced(self):
        self.archive.write_bytes(b'keep')
        with self.assertRaisesRegex(checks.CheckError, 'already exists'):
            self.package()
        self.assertEqual(self.archive.read_bytes(), b'keep')

    def test_sources_changed_after_build_rejected(self):
        path = self.root / checks.REFERENCE / 'drawing.scrbl'
        path.write_text(path.read_text() + '\n')
        with self.assertRaisesRegex(checks.CheckError, 'changed during the build'):
            self.package()
        self.assertFalse(self.archive.exists())

    def test_badlink_prevents_publication(self):
        self.index.write_text(self.index.read_text() + '<span class="badlink">Missing</span>')
        with self.assertRaises(checks.CheckError):
            self.package()
        self.assertFalse(self.archive.exists())

    def test_unresolved_binding_in_identifier_index_blocks_publication(self):
        # The R3d regression occurred in doc-index.html, not only index.html.
        index = self.reference / 'doc-index.html'
        index.write_text('<span class="RktErr badlink">make-rgb-color-space</span>')
        with self.assertRaisesRegex(checks.CheckError,
                                    'unresolved review Reference: doc-index.html'):
            review.check_review_html(self.site)
        with self.assertRaises(checks.CheckError):
            self.package()
        self.assertFalse(self.archive.exists())

    def test_reference_only_badlink_build_is_not_published(self):
        # Reproduce the reported partial review: no companions and unlinked labels.
        self.index.write_text(''.join(
            '<span class="badlink">' + row['label'] + '</span>'
            for row in self.source['tutorial_links']))
        for row in self.source['tutorial_links']:
            shutil.rmtree(self.site / row['directory'])
        with self.assertRaisesRegex(checks.CheckError, 'unresolved review Reference'):
            review.check_review_html(self.site)
        with self.assertRaises(checks.CheckError):
            self.package()
        self.assertFalse(self.archive.exists())

    def test_resolved_links_without_companion_files_are_not_published(self):
        # Even resolved links do not make a Reference-only directory portable.
        for row in self.source['tutorial_links']:
            shutil.rmtree(self.site / row['directory'])
        with self.assertRaises(checks.CheckError):
            self.package()
        self.assertFalse(self.archive.exists())

    def test_unlinked_tutorial_label_prevents_publication(self):
        self.index.write_text('Skia tutorials')
        with self.assertRaisesRegex(checks.CheckError, 'missing tutorial link'):
            self.package()
        self.assertFalse(self.archive.exists())

    def test_wrong_but_existing_tutorial_destination_rejected(self):
        rows = self.source['tutorial_links']
        text = self.index.read_text().replace(
            '../' + rows[0]['directory'] + '/index.html#top',
            '../' + rows[0]['directory'] + '/index.html#wrong')
        self.index.write_text(text)
        with self.assertRaisesRegex(checks.CheckError, 'wrong tutorial link'):
            self.package()
        self.assertFalse(self.archive.exists())

    def test_missing_asset_prevents_publication(self):
        (self.site / 'manual-style.css').unlink()
        with self.assertRaisesRegex(checks.CheckError, 'missing review resource'):
            self.package()
        self.assertFalse(self.archive.exists())

    def test_other_broken_internal_anchor_prevents_publication(self):
        self.index.write_text(self.index.read_text() + '<a href="entries.html#absent">More</a>')
        with self.assertRaisesRegex(checks.CheckError, 'review anchor'):
            self.package()
        self.assertFalse(self.archive.exists())

    def test_machine_local_manual_link_is_relocated(self):
        row = self.source['tutorial_links'][0]
        path = self.site / row['directory'] / 'index.html'
        text = self.index.read_text().replace('../' + row['directory'] + '/index.html', path.as_uri())
        self.index.write_text(text)
        self.package()
        with zipfile.ZipFile(self.archive) as archive:
            text = archive.read('html/skia-reference/index.html').decode()
            self.assertNotIn('file:', text)
            self.assertIn('../' + row['directory'] + '/index.html#top', text)

    def test_failed_runtime_evidence_prevents_publication(self):
        self.evidence['status'] = 'failed'
        with self.assertRaisesRegex(checks.CheckError, 'real-xref evidence'):
            self.package()
        self.assertFalse(self.archive.exists())

    def test_symlink_input_rejected(self):
        (self.reference / 'alias.html').symlink_to(self.entries)
        with self.assertRaisesRegex(checks.CheckError, 'symlink'):
            self.package()
        self.assertFalse(self.archive.exists())

    def test_local_link_cannot_escape_the_archive(self):
        self.index.write_text(self.index.read_text() + '<a href="../../outside.html">Outside</a>')
        with self.assertRaisesRegex(checks.CheckError, 'escapes'):
            self.package()
        self.assertFalse(self.archive.exists())

    def test_font_files_are_not_packaged(self):
        (self.reference / 'font.woff2').write_bytes(b'not-a-real-font')
        with self.assertRaisesRegex(checks.CheckError, 'font files'):
            self.package()
        self.assertFalse(self.archive.exists())

    def test_corrupt_extraction_is_not_published(self):
        original = zipfile.ZipFile.extractall
        def corrupt(archive, directory, *args, **kwargs):
            original(archive, directory, *args, **kwargs)
            (Path(directory) / 'html/skia-reference/index.html').write_text('corrupt')
        with patch.object(zipfile.ZipFile, 'extractall', corrupt):
            with self.assertRaisesRegex(checks.CheckError, 'checksum mismatch'):
                self.package()
        self.assertFalse(self.archive.exists())



class R2SignatureTests(unittest.TestCase):
    def shape(self, text):
        return checks.procedure_shape(checks.Reader(text).read())

    def test_zero_or_more_arguments(self):
        shape = self.shape('[(combine [value any/c] ...) any]')
        self.assertEqual(shape['arity_mask'], '-1')
        self.assertEqual(shape['arguments'][0]['repeat'], 'zero-or-more')

    def test_one_or_more_arguments(self):
        shape = self.shape('[(combine [value any/c] ...+) any]')
        self.assertEqual(shape['arity_mask'], '-2')
        self.assertEqual(shape['arguments'][0]['repeat'], 'one-or-more')

    def test_fixed_prefix_before_rest(self):
        shape = self.shape('[(combine [first any/c] [others any/c] ...) any]')
        self.assertEqual(shape['arity_mask'], '-2')

    def test_fixed_prefix_before_nonempty_rest(self):
        shape = self.shape('[(combine [first any/c] [others any/c] ...+) any]')
        self.assertEqual(shape['arity_mask'], '-4')

    def test_keyword_after_rest(self):
        shape = self.shape('[(combine [values any/c] ... [#:key key procedure?]) any]')
        self.assertEqual(shape['arity_mask'], '-1')
        self.assertEqual(shape['required_keywords'], ['key'])

    def test_optional_keyword_after_rest(self):
        shape = self.shape('[(combine [values any/c] ... [#:key key procedure? values]) any]')
        self.assertEqual(shape['allowed_keywords'], ['key'])
        self.assertEqual(shape['required_keywords'], [])

    def test_ellipsis_without_argument_is_rejected(self):
        with self.assertRaises(checks.CheckError):
            self.shape('[(combine ...) any]')

    def test_positional_after_ellipsis_is_rejected(self):
        with self.assertRaises(checks.CheckError):
            self.shape('[(combine [values any/c] ... [last any/c]) any]')

    def test_second_ellipsis_is_rejected(self):
        with self.assertRaises(checks.CheckError):
            self.shape('[(combine [values any/c] ... ...) any]')

    def test_optional_prefix_is_not_guessed(self):
        with self.assertRaises(checks.CheckError):
            self.shape('[(combine [first any/c #f] [others any/c] ...) any]')

    def test_repeated_keyword_is_rejected(self):
        with self.assertRaises(checks.CheckError):
            self.shape('[(combine [#:values values any/c] ...) any]')

    def test_duplicate_keywords_are_rejected(self):
        with self.assertRaises(checks.CheckError):
            self.shape('[(combine [#:key key any/c] [#:key other any/c]) any]')

    def test_constant_has_predicate_not_a_procedure_signature(self):
        shape = checks.constant_shape(['matrix-identity', 'matrix?'])
        self.assertEqual(shape['kind'], 'value')
        self.assertEqual(shape['value_predicate'], 'matrix?')
        self.assertNotIn('arity_mask', shape)

    def test_constant_composite_contract_requires_reader_extension(self):
        with self.assertRaises(checks.CheckError):
            checks.constant_shape(['example', ['and/c', 'number?', 'positive?']])

    def test_constant_options_require_reader_extension(self):
        with self.assertRaises(checks.CheckError):
            checks.constant_shape(['#:link-target?', '#f', 'example', 'number?'])

    def test_constant_string_is_not_a_binding(self):
        with self.assertRaises(checks.CheckError):
            checks.constant_shape([checks.String('example'), 'number?'])


class R2CoverageTests(unittest.TestCase):
    setUp = Fixtures.setUp
    write_inventory = Fixtures.write_inventory
    write_manifest = Fixtures.write_manifest
    change = Fixtures.change
    check = Fixtures.check

    def test_matrix_reexports_are_all_accounted_for(self):
        specs = {row['name']: row for row in self.check()['definitions']}
        for name in MATRIX_EXPORTS:
            self.assertEqual(set(specs[name]['exports']), {'skia', 'skia/matrix'})
            self.assertEqual(specs[name]['canonical_module'], 'skia/matrix')

    def test_paint_query_reexports_are_all_accounted_for(self):
        specs = {row['name']: row for row in self.check()['definitions']}
        for name in GEOMETRY_EXPORTS:
            self.assertEqual(set(specs[name]['exports']), {'skia', 'skia/geometry'})
            self.assertEqual(specs[name]['canonical_module'], 'skia/geometry')

    def test_disagreeing_alias_signature_fails(self):
        matrix = next(module for module in self.snapshots[0]['modules']
                      if module['path'] == 'matrix.rkt')
        item = next(item for item in matrix['exports'] if item['name'] == 'matrix-compose')
        item['arity_mask'] = '1'
        self.write_inventory()
        with self.assertRaisesRegex(checks.CheckError, 'arity_mask'):
            self.check()

    def test_omitted_constant_fails_coverage(self):
        self.change('matrices.scrbl', '@defthing[matrix-identity matrix?]',
                    '@racket[matrix-identity]')
        with self.assertRaisesRegex(checks.CheckError, 'coverage'):
            self.check()

    def test_constant_callable_kind_mismatch_fails(self):
        for module in self.snapshots[0]['modules']:
            for item in module['exports']:
                if item['name'] == 'matrix-identity':
                    item['kind'] = 'procedure'
        self.write_inventory()
        with self.assertRaisesRegex(checks.CheckError, 'kind mismatch'):
            self.check()

    def test_rest_lower_bound_is_checked(self):
        self.change('matrices.scrbl', '(matrix-compose [matrix matrix?] ...)',
                    '(matrix-compose [matrix matrix?] ...+)')
        with self.assertRaisesRegex(checks.CheckError, 'arity_mask'):
            self.check()

    def test_required_keyword_drift_in_image_drawing_fails(self):
        self.change('images.scrbl', "sampling (or/c 'nearest 'linear) 'nearest",
                    "sampling (or/c 'nearest 'linear)")
        with self.assertRaisesRegex(checks.CheckError, 'required_keywords'):
            self.check()

    def test_unchanged_scope_form_still_syntax(self):
        spec = next(row for row in self.check()['definitions'] if row['name'] == 'with-canvas-state')
        self.assertEqual(spec['kind'], 'syntax')
        self.assertNotIn('arity_mask', spec)

    def test_current_subset_includes_presentation_and_dc_integration(self):
        names = {row['name'] for row in self.check()['definitions']}
        self.assertIn('gpu-presenter-render!', names)
        self.assertIn('skia-render-window%', names)
        self.assertIn('skia-dc%', names)


class R2ProseTests(unittest.TestCase):
    def text(self, name):
        return (ROOT / checks.REFERENCE / name).read_text()

    def test_general_numeric_limits_are_centralized(self):
        notation = self.text('notation.scrbl')
        self.assertIn('@deftech{drawing scalar}', notation)
        for phrase in ('-3.402823e38', '3.402823e38', 'coefficients',
                       'components supplied in lists or vectors', 'padding'):
            self.assertIn(phrase, notation)
        # Projective matrices deliberately use a wider range than the general rule.
        exceptions = {'notation.scrbl', 'projective-matrices.scrbl'}
        for path in (ROOT / checks.REFERENCE).rglob('*.scrbl'):
            if path.name not in exceptions:
                with self.subTest(chapter=path.name):
                    self.assertNotRegex(path.read_text(), r'drawing[\s-]+scalars?')

    def test_operation_specific_numeric_restrictions_remain_explicit(self):
        cases = {
            'shaders.scrbl': ('Radii must be nonnegative', 'endpoints must differ'),
            'codecs.scrbl': ('must remain strictly positive after binary32',
                            'positive value that rounds to zero is rejected'),
            'image-filters.scrbl': ('positive extents', 'distinct after rounding'),
            'text-blobs.scrbl': ('strictly less than @racket[bottom]',),
        }
        for chapter, phrases in cases.items():
            text = ' '.join(self.text(chapter).split())
            for phrase in phrases:
                with self.subTest(chapter=chapter, phrase=phrase):
                    self.assertIn(phrase, text)
        for chapter in ('matrices.scrbl', 'paths.scrbl', 'output-pages.scrbl'):
            self.assertIn('@secref["skia-scalars"]', self.text(chapter))

    def test_matrix_order_and_rounding_are_explicit(self):
        text = self.text('matrices.scrbl')
        self.assertIn('xx, yx, xy, yy, x0, y0', text)
        self.assertIn('last\nmatrix acts on a point first', text)
        self.assertIn('single precision', text)

    def test_inputs_are_described_without_automatic_encoding_or_packing(self):
        fonts = ' '.join(self.text('fonts.scrbl').split())
        self.assertIn('Maps the characters in @racket[text] to glyph IDs', fonts)
        self.assertNotIn('Maps UTF-8 text', fonts)
        structured = ' '.join(self.text('structured-drawing.scrbl').split())
        self.assertIn('Optional colors are @tech{color specification}s, one per sprite',
                      structured)
        for phrase in ('Optional packed colors', 'copied as packed ARGB',
                       'Colors are stored as packed ARGB'):
            self.assertNotIn(phrase, structured)
        self.assertNotIn('normalized to the byte-valued color representation',
                         ' '.join(self.text('shaders.scrbl').split()))
        self.assertNotIn('normalized to an RGBA value',
                         ' '.join(self.text('output-pages.scrbl').split()))

    def test_matrix_entries_omit_routine_native_preparation(self):
        affine = ' '.join(self.text('matrices.scrbl').split())
        projective = ' '.join(self.text('projective-matrices.scrbl').split())
        for phrase in ('same checks and rounding', 'rounded and range-checked',
                       'no native conversion or allocation'):
            self.assertNotIn(phrase, affine)
        for phrase in ('native storage layout is converted',
                       'storage representation used by the native canvas ABI',
                       'applying the binary32 checks'):
            self.assertNotIn(phrase, projective)
        # Precision remains a shared rule; vector ownership and failures remain explicit.
        self.assertIn('Mapping operations round input coordinates and results', affine)
        self.assertIn('later mutation of the vector does not change the matrix', affine)
        self.assertIn('Mapping queries instead return immutable binary64 coordinate vectors',
                      projective)
        self.assertIn('nonfinite native matrix cannot be represented and raises an exception',
                      projective)

    def test_caller_visible_conversion_results_and_restrictions_are_preserved(self):
        cases = {
            'structured-drawing.scrbl': (
                'Returns the immutable packed-ARGB color vector',
                'exactly four entries, in corner order',
                'even when its cell type does not use the color',
                "independent of later changes to the caller's collections"),
            'shaping.scrbl': ('UTF-8 byte offset into @racket[text]',
                             'limitations of @racket[shaped-run->path]'),
            'text-blobs.scrbl': ('malformed byte sequences are rejected',),
            'pdf-documents.scrbl': ('Metadata strings must not contain NUL',),
            'float-colors.scrbl': ('does not round the stored RGB to binary32',
                                  'stores the converted color in extended sRGB'),
            'rounded-rectangles.scrbl': ('must be nonnegative after binary32 rounding',
                                        'Inputs are unchanged'),
            'output-pages.scrbl': ('Returns the background as an RGBA color',),
            'racket-draw.scrbl': ('premultiplied RGB component and alpha',
                                 'exceeds alpha, raise an exception'),
            'raster-buffers.scrbl': ('Floating-point samples can lose range and precision',),
        }
        for chapter, phrases in cases.items():
            text = ' '.join(self.text(chapter).split())
            for phrase in phrases:
                with self.subTest(chapter=chapter, phrase=phrase):
                    self.assertIn(phrase, text)

    def test_surface_snapshot_documents_independent_pixels(self):
        self.assertIn('Later drawing\nto @racket[surface] does not change the image.',
                      self.text('surfaces.scrbl'))

    def test_image_sampling_defaults_differ(self):
        definitions, _ = checks.document_definitions(ROOT)
        names = {spec['name']: spec for spec in definitions}
        for name, arity in (('draw-image', '16'), ('draw-image-rect', '64'),
                            ('draw-image-subrect', '1024')):
            self.assertEqual(names[name]['arity_mask'], arity)
        text = self.text('images.scrbl')
        self.assertIn("'nearest]", text)
        self.assertIn("'linear]", text)
        self.assertIn('coordinates and sizes can be fractional', text)

    def test_path_measure_distance_difference_is_explicit(self):
        text = self.text('paths.scrbl')
        self.assertIn('no greater than the current', text)
        self.assertIn('clamps it to the contour length', text)

    def test_relative_move_after_close_is_not_last_stored_point(self):
        text = self.text('paths.scrbl')
        self.assertIn("preceding contour's start, not its last stored", text)

    def test_nonpositive_conic_weight_reduces_to_line(self):
        text = self.text('paths.scrbl')
        self.assertIn('weight no greater than zero produces a line', text)
        self.assertIn('weight of one produces an ordinary', text)

    def test_native_reset_is_not_constructor_defaults(self):
        text = self.text('paints.scrbl')
        self.assertIn('not exactly the defaults', text)
        self.assertIn('hairline stroke width', text)

    def test_fill_path_false_flag_does_not_discard_owned_result(self):
        self.assertIn('hairline geometry, not allocation', self.text('paints.scrbl'))

    def test_all_native_examples_remain_opt_in(self):
        for chapter in ('canvases.scrbl', 'paths.scrbl', 'images.scrbl', 'shaders.scrbl'):
            forms = {form for form, _, _ in checks.commands(self.text(chapter), recursive=True)}
            self.assertIn('racketblock', forms)
            self.assertNotIn('examples', forms)

    def test_affine_examples_require_only_pure_module(self):
        text = self.text('matrices.scrbl')
        self.assertIn("(matrix-eval '(require skia/matrix))", text)
        self.assertIn('@examples[#:eval matrix-eval', text)

    def test_probe_includes_noncolor_aliases(self):
        text = self.text('tests/links.scrbl')
        for name in ('matrix:matrix-compose', 'matrix:matrix-identity',
                     'geometry:paint->fill-path'):
            self.assertIn('@racket[' + name + ']', text)


class R21SourceTests(unittest.TestCase):
    """Contract declarations and compatibility metadata, not native execution."""
    def setUp(self):
        self.fixture = Fixtures()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)

    def header(self, name):
        text = (self.fixture.root / checks.REFERENCE / 'encoding.scrbl').read_text()
        return next(header for form, header, _ in checks.commands(text)
                    if form == 'defproc' and header[0][0] == name)

    def test_five_new_color_space_entries_have_independent_call_shapes(self):
        result = self.fixture.check()
        entries = {row['name']: row for row in result['definitions']}
        for name, mask in (('make-srgb-color-space', '1'), ('make-linear-srgb-color-space', '1'),
                           ('color-space=?', '4'), ('color-space-srgb?', '2'),
                           ('color-space-linear-gamma?', '2')):
            with self.subTest(name=name):
                self.assertEqual(entries[name]['arity_mask'], mask)
                self.assertEqual(entries[name]['exports'], ['skia'])
                self.assertEqual(entries[name]['chapter'],
                                 'scribblings/reference/color-management.scrbl')

    def test_shader_predicate_has_one_definition_in_shaders(self):
        entries = [row for row in self.fixture.check()['definitions'] if row['name'] == 'shader?']
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]['chapter'], 'scribblings/reference/shaders.scrbl')

    def test_dispatcher_keywords_use_conditional_contracts_and_keep_defaults(self):
        expected = {
            '#:quality': '90', '#:png-compression': '6',
            '#:jpeg-downsample': ['quote', 'yuv-420'], '#:jpeg-alpha': ['quote', 'ignore'],
            '#:webp-lossless?': '#f',
        }
        for name in ('image->encoded-bytes', 'save-image'):
            fields = {field[0]: field for field in self.header(name)[0][1:]}
            for keyword, default in expected.items():
                with self.subTest(name=name, keyword=keyword):
                    self.assertEqual(fields[keyword][2:], ['any/c', default])

    def test_straight_encoder_contracts_are_not_weakened(self):
        expected = {
            'image->png-bytes': {'#:compression': ['integer-in', '0', '9']},
            'image->jpeg-bytes': {
                '#:quality': ['integer-in', '0', '100'],
                '#:downsample': ['or/c', ['quote', 'yuv-420'], ['quote', 'yuv-422'],
                                ['quote', 'yuv-444']],
                '#:alpha': ['or/c', ['quote', 'ignore'], ['quote', 'blend-on-black']]},
            'image->webp-bytes': {'#:quality': ['real-in', '0', '100'], '#:lossless?': 'boolean?'},
        }
        for name, fields in expected.items():
            actual = {field[0]: field[2] for field in self.header(name)[0][1:]
                      if str(field[0]).startswith('#:')}
            for keyword, contract in fields.items():
                with self.subTest(name=name, keyword=keyword):
                    self.assertEqual(actual[keyword], contract)

    def test_common_encoding_contracts_remain_precise(self):
        for name in ('image->encoded-bytes', 'save-image'):
            fields = {field[0]: field for field in self.header(name)[0][1:]}
            for keyword, predicate in (('#:color-space', 'color-space?'),
                                       ('#:icc-profile', 'bytes?'),
                                       ('#:icc-description', 'string?')):
                with self.subTest(name=name, keyword=keyword):
                    self.assertEqual(fields[keyword][2], ['or/c', predicate, '#f'])
        fields = {field[0]: field for field in self.header('save-image')[0][1:]}
        self.assertEqual(fields['#:exists'][2],
                         ['or/c', ['quote', 'error'], ['quote', 'replace']])

    def test_format_options_table_is_shared_not_duplicated(self):
        text = (self.fixture.root / checks.REFERENCE / 'encoding.scrbl').read_text()
        self.assertEqual(text.count('@bold{Keyword} @bold{PNG} @bold{JPEG} @bold{WebP}'), 1)
        self.assertIn('may have any value', text)
        self.assertIn('follow the table in @racket[image->encoded-bytes]', text)
        for keyword in ('quality', 'png-compression', 'jpeg-downsample', 'jpeg-alpha',
                         'webp-lossless?'):
            self.assertIn('(list @racket[#:' + keyword + ']', text)

    def test_paint_module_declaration_from_upstream_is_preserved(self):
        text = (self.fixture.root / checks.REFERENCE / 'paints.scrbl').read_text()
        self.assertIn('@defmodule[skia/geometry #:no-declare]', text)
        self.assertIn('(for-label racket/base racket/contract skia skia/geometry)', text)

    def test_new_color_examples_are_not_evaluated_during_the_build(self):
        text = (self.fixture.root / checks.REFERENCE / 'color-management.scrbl').read_text()
        text = text[:text.index('@section[#:tag "skia-color-gamma"]')]
        forms = [form for form, _, _ in checks.commands(text, recursive=True)]
        self.assertEqual(forms.count('racketblock'), 2)
        self.assertNotIn('examples', forms)
        self.assertIn('does not mean sRGB', text)

    def test_behavioral_examples_are_displayed_at_the_relevant_entries(self):
        for chapter, identifier, expression in (
            ('paints.scrbl', 'paint-reset!', '(paint-reset! paint)'),
            ('paths.scrbl', 'path-segments', "[mode '(normal raw)]"),
            ('paths.scrbl', 'path-measure-segment', '#:start-with-move-to? #f'),
        ):
            text = (self.fixture.root / checks.REFERENCE / chapter).read_text()
            start = text.index('@defproc[(' + identifier + ' ')
            end = text.find('@defproc', start + 1)
            entry = text[start:end if end >= 0 else len(text)]
            with self.subTest(name=identifier):
                self.assertIn('@racketblock[', entry)
                self.assertIn(expression, entry)
                self.assertNotIn('@examples', entry)

    def test_encoding_aliases_keep_legacy_filename(self):
        links = self.fixture.check()['section_links']
        self.assertEqual([row['tag'] for row in links], ['skia-png', 'skia-encoding'])
        self.assertEqual({row['filename'] for row in links}, {'skia-png.html'})

    def test_missing_current_alias_is_rejected(self):
        self.fixture.change('encoding.scrbl', '\'("skia-png" "skia-encoding")', '"skia-png"')
        with self.assertRaisesRegex(checks.CheckError, 'tag is not declared'):
            self.fixture.check()

    def test_reordered_aliases_do_not_silently_change_page_address(self):
        self.fixture.change('encoding.scrbl', '\'("skia-png" "skia-encoding")',
                             '\'("skia-encoding" "skia-png")')
        with self.assertRaisesRegex(checks.CheckError, 'published filename'):
            self.fixture.check()

    def test_alias_manifest_cannot_omit_the_current_tag(self):
        self.fixture.manifest['section_links'].pop()
        self.fixture.write_manifest()
        with self.assertRaisesRegex(checks.CheckError, 'missing from the section-link manifest'):
            self.fixture.check()

    def test_duplicate_section_manifest_entry_is_rejected(self):
        self.fixture.manifest['section_links'].append(self.fixture.manifest['section_links'][0])
        self.fixture.write_manifest()
        with self.assertRaisesRegex(checks.CheckError, 'duplicate section'):
            self.fixture.check()

    def test_section_filename_cannot_escape_the_reference(self):
        self.fixture.manifest['section_links'][0]['filename'] = '../skia-png.html'
        self.fixture.write_manifest()
        with self.assertRaisesRegex(checks.CheckError, 'invalid section filename'):
            self.fixture.check()

    def test_section_cannot_claim_a_tag_in_another_chapter(self):
        self.fixture.manifest['section_links'][0]['chapter'] = 'scribblings/reference/shaders.scrbl'
        self.fixture.write_manifest()
        with self.assertRaisesRegex(checks.CheckError, 'tag is not declared'):
            self.fixture.check()


class R21HtmlTests(unittest.TestCase):
    """Synthetic sections exercise the checker; these are not rendered manuals."""
    def setUp(self):
        self.fixture = HtmlTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.site = self.fixture.site
        self.page = self.fixture.reference / 'skia-png.html'
        self.page.write_text('<a id="legacy"></a><a id="current"></a>')
        self.sections = [
            dict(tag='skia-png', label='Image Encoding (legacy tag)', anchor='legacy',
                 chapter='scribblings/reference/encoding.scrbl',
                 relative_path='skia-png.html', filename='skia-png.html'),
            dict(tag='skia-encoding', label='Image Encoding (current tag)', anchor='current',
                 chapter='scribblings/reference/encoding.scrbl',
                 relative_path='skia-png.html', filename='skia-png.html'),
        ]
        self.evidence = dict(self.fixture.evidence, section_targets=self.sections,
                             status='passed', xref_checked=True)
        self.probe = self.site / 'probe.html'
        bindings = ''.join(
            f'<a href="skia-reference/entry.html#{quote(t["anchor"])}">{escape(t["name"])}</a>'
            for t in self.fixture.targets)
        self.probe.write_text(bindings + ''.join(
            f'<a href="skia-reference/skia-png.html#{row["anchor"]}">{row["label"]}</a>'
            for row in self.sections))

    def check(self):
        return checks.check_targets(self.site, self.evidence, smoke=self.probe)

    def test_both_aliases_are_checked_in_real_destination_shape(self):
        self.assertEqual(set(self.check()['section_links']), {'skia-png', 'skia-encoding'})

    def test_missing_legacy_anchor_is_rejected(self):
        self.page.write_text('<a id="current"></a>')
        with self.assertRaisesRegex(checks.CheckError, 'section anchor'):
            self.check()

    def test_missing_current_anchor_is_rejected(self):
        self.page.write_text('<a id="legacy"></a>')
        with self.assertRaisesRegex(checks.CheckError, 'section anchor'):
            self.check()

    def test_duplicate_alias_anchor_is_rejected(self):
        self.page.write_text(self.page.read_text() + '<a id="current"></a>')
        with self.assertRaisesRegex(checks.CheckError, 'section anchor'):
            self.check()

    def test_plain_text_in_probe_is_not_an_alias_link(self):
        text = self.probe.read_text()
        self.probe.write_text(text.replace(
            '<a href="skia-reference/skia-png.html#current">Image Encoding (current tag)</a>',
            'Image Encoding (current tag)'))
        with self.assertRaisesRegex(checks.CheckError, 'missing section link'):
            self.check()

    def test_wrong_but_existing_alias_target_is_rejected(self):
        self.probe.write_text(self.probe.read_text().replace(
            'skia-png.html#current', 'skia-png.html#legacy'))
        with self.assertRaisesRegex(checks.CheckError, 'wrong section link'):
            self.check()

    def test_two_tags_may_share_the_same_resolved_anchor(self):
        self.sections[1]['anchor'] = 'legacy'
        self.probe.write_text(self.probe.read_text().replace(
            'skia-png.html#current', 'skia-png.html#legacy'))
        self.assertEqual(self.check()['status'], 'passed')

    def test_top_of_page_section_is_valid(self):
        self.sections[0]['anchor'] = ''
        self.probe.write_text(self.probe.read_text().replace('skia-png.html#legacy', 'skia-png.html'))
        self.assertEqual(self.check()['status'], 'passed')

    def test_top_of_page_section_still_requires_a_real_file(self):
        for row in self.sections:
            row['anchor'] = ''
        self.page.unlink()
        with self.assertRaisesRegex(checks.CheckError, 'missing HTML'):
            self.check()

    def test_new_filename_in_runtime_evidence_is_rejected(self):
        self.sections[1]['relative_path'] = 'skia-encoding.html'
        with self.assertRaisesRegex(checks.CheckError, 'section filename changed'):
            self.check()

    def test_alias_evidence_cannot_be_silently_dropped(self):
        source = dict(definitions=[], tutorial_links=[], section_links=[
            {key: row[key] for key in ('chapter', 'tag', 'label', 'filename')}
            for row in self.sections])
        evidence = dict(status='passed', xref_checked=True, targets=[],
                        tutorial_targets=[], section_targets=self.sections[:1])
        with self.assertRaisesRegex(checks.CheckError, 'section target inventory'):
            checks.check_evidence(source, evidence)


class R21ReviewTests(unittest.TestCase):
    def setUp(self):
        self.fixture = ReviewArchiveTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)

    def test_review_zip_includes_the_legacy_named_encoding_page(self):
        self.fixture.package()
        with zipfile.ZipFile(self.fixture.archive) as archive:
            self.assertTrue(any(name.endswith('/skia-png.html') for name in archive.namelist()))

    def test_missing_section_page_prevents_review_publication(self):
        (self.fixture.reference / 'skia-png.html').unlink()
        with self.assertRaises(checks.CheckError):
            self.fixture.package()
        self.assertFalse(self.fixture.archive.exists())



class PreparatorySourceTests(unittest.TestCase):
    def test_all_three_blend_contracts_match_the_complete_supported_set(self):
        expected = ('clear src dst src-over dst-over src-in dst-in src-out dst-out '
                    'src-atop dst-atop xor plus modulate screen overlay darken lighten '
                    'color-dodge color-burn hard-light soft-light difference exclusion '
                    'multiply hue saturation color luminosity').split()
        found = {}
        for chapter in ('paints.scrbl', 'shaders.scrbl'):
            for form, header, _ in checks.commands((ROOT / checks.REFERENCE / chapter).read_text()):
                if form != 'defproc':
                    continue
                name = header[0][0]
                if name not in ('make-paint', 'paint-set-blend-mode!', 'make-blend-shader'):
                    continue
                key = '#:blend-mode' if name == 'make-paint' else 'mode'
                field = next(arg for arg in header[0][1:] if arg[0] == key)
                contract = field[2 if key.startswith('#:') else 1]
                self.assertEqual(contract, ['or/c', *[['quote', symbol] for symbol in expected]])
                found[name] = contract
        self.assertEqual(set(found), {'make-paint', 'paint-set-blend-mode!', 'make-blend-shader'})
        self.assertEqual(len(expected), 29)
        self.assertEqual(len(set(expected)), 29)

    def test_clipping_example_compares_same_initial_clip_in_separate_scopes(self):
        text = (ROOT / checks.REFERENCE / 'canvases.scrbl').read_text()
        start = text.index('@defproc[(canvas-clip-rect!')
        end = text.index('@defproc[(canvas-clip-path!', start)
        example = text[start:end]
        self.assertIn("[operation '(intersect difference)]", example)
        self.assertIn('(canvas-clear! canvas', example)
        self.assertIn('(with-canvas-state canvas', example)
        self.assertIn('(canvas-clip-rect! canvas 0 0 6 6)', example)
        self.assertIn('(canvas-clip-rect! canvas 2 2 2 2 #:operation operation)', example)
        self.assertIn("[x '(3 1 7)]", example)
        self.assertNotIn('@examples', example)

    def test_displayed_native_example_inventory_has_one_addition(self):
        count = sum(form == 'racketblock' for path in (ROOT / checks.REFERENCE).glob('*.scrbl')
                    for form, _, _ in checks.commands(path.read_text(), recursive=True))
        self.assertEqual(count, 316)

    def test_native_acceptance_contains_blend_rejection_and_clip_restoration(self):
        text = (ROOT / 'tools/reference-core-test.rkt').read_text()
        for phrase in ("(make-paint #:blend-mode 'not-a-blend-mode)",
                       "(paint-set-blend-mode! paint 'not-a-blend-mode)",
                       "(make-blend-shader 'not-a-blend-mode destination source)",
                       "(check-equal? samples '((#t #f #f) (#f #t #f)))",
                       '(check-equal? (canvas-save-count canvas) 1)'):
            self.assertIn(phrase, text)


class SourceReviewArchiveTests(unittest.TestCase):
    """Real subprocess/extraction checks against explicitly synthetic test inventories."""
    def setUp(self):
        self.fixture = ReviewArchiveTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        self.archive = self.fixture.archive

    def package(self):
        return review.package_source_review(self.root, self.archive, self.fixture.hashes)

    def test_source_archive_runs_the_full_checker_after_extraction(self):
        result = self.package()
        self.assertTrue(result['extracted_zip_checked'])
        self.assertTrue(result['extracted_source_check']['inventory_checked'])
        self.assertFalse(result['extracted_source_check']['documents_only'])
        with zipfile.ZipFile(self.archive) as archive:
            for item in self.fixture.manifest['snapshots']:
                self.assertEqual(archive.read('sources/' + item['file']),
                                 (self.root / item['file']).read_bytes())
            names = set(archive.namelist())
            for path in ('info.rkt', 'tools/check-reference.py', 'tools/reference_support.py',
                         'tools/reference_review.py', *[item['manual']
                         for item in self.fixture.manifest['tutorial_links']]):
                self.assertIn('sources/' + path, names)
            self.assertFalse(any(path.startswith('html/') for path in names))

    def test_source_copy_checker_uses_an_unrelated_directory_and_no_pythonpath(self):
        original = review.subprocess.run
        observed = []
        def run(command, **options):
            observed.append((command, options))
            return original(command, **options)
        with patch.object(review.subprocess, 'run', side_effect=run):
            self.package()
        self.assertEqual(len(observed), 2)
        for command, options in observed:
            self.assertEqual(command[1:4], ['-E', '-s', '-B'])
            self.assertNotIn('--documents-only', command)
            self.assertNotEqual(Path(options['cwd']), self.root)
            self.assertNotEqual(Path(options['cwd']), Path(command[4]).parent)

    def test_missing_inventory_does_not_publish_a_source_archive(self):
        path = self.root / self.fixture.manifest['snapshots'][0]['file']
        path.unlink()
        with self.assertRaises(FileNotFoundError):
            self.package()
        self.assertFalse(self.archive.exists())

    def test_wrong_inventory_hash_is_rejected_even_with_fresh_source_hashes(self):
        path = self.root / self.fixture.manifest['snapshots'][0]['file']
        path.write_text(path.read_text() + '\n')
        hashes = review.source_hashes(self.root, review_inputs=True)
        with self.assertRaises(checks.CheckError):
            review.package_source_review(self.root, self.archive, hashes)
        self.assertFalse(self.archive.exists())

    def test_missing_tutorial_source_fails_closed(self):
        (self.root / self.fixture.manifest['tutorial_links'][0]['manual']).unlink()
        with self.assertRaises(FileNotFoundError):
            self.package()
        self.assertFalse(self.archive.exists())

    def test_existing_source_archive_is_not_replaced(self):
        self.archive.write_bytes(b'keep')
        with self.assertRaisesRegex(checks.CheckError, 'already exists'):
            self.package()
        self.assertEqual(self.archive.read_bytes(), b'keep')

    def test_copy_without_checker_dependency_cannot_pass(self):
        destination = self.root.parent / 'incomplete-copy'
        review.copy_source_inputs(self.root, destination, self.fixture.hashes)
        (destination / 'tools/reference_support.py').unlink()
        with self.assertRaisesRegex(checks.CheckError, 'copied source checker failed'):
            review.validate_source_copy(
                destination, self.root.parent / 'failure', self.fixture.source)

    def test_copy_cannot_use_a_documents_only_result_as_full_evidence(self):
        destination = self.root.parent / 'copy'
        review.copy_source_inputs(self.root, destination, self.fixture.hashes)
        limited = checks.check_source(self.root, documents_only=True)
        with self.assertRaisesRegex(checks.CheckError, 'differs from the original'):
            review.validate_source_copy(destination, self.root.parent / 'failure', limited)

    def test_corrupt_extracted_source_is_never_published(self):
        original = zipfile.ZipFile.extractall
        def corrupt(archive, directory, *args, **kwargs):
            original(archive, directory, *args, **kwargs)
            (Path(directory) / 'sources/info.rkt').write_text('corrupt')
        with patch.object(zipfile.ZipFile, 'extractall', corrupt):
            with self.assertRaisesRegex(checks.CheckError, 'checksum mismatch'):
                self.package()
        self.assertFalse(self.archive.exists())

    def test_html_review_also_contains_full_source_check_inputs(self):
        result = self.fixture.package()
        self.assertTrue(result['extracted_source_check']['inventory_checked'])
        with zipfile.ZipFile(self.archive) as archive:
            report = json.loads(archive.read('evidence/review.json'))
            self.assertTrue(report['source_validation']['inventory_checked'])
            self.assertFalse(report['link_scopes']['complete_site_checked'])
            for item in self.fixture.manifest['snapshots']:
                self.assertEqual(archive.read('sources/' + item['file']),
                                 (self.root / item['file']).read_bytes())

    def test_source_archive_creation_is_available_without_racket(self):
        command = [review.sys.executable, '-E', '-s', '-B',
                   str(self.root / 'tools/check-reference.py'),
                   '--output', str(self.root.parent / 'cli-evidence'),
                   '--source-zip', str(self.archive), '--racket', '/nonexistent/racket']
        result = review.subprocess.run(command, cwd=self.root.parent, capture_output=True,
                                       text=True, timeout=120, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        evidence = json.loads((self.root.parent / 'cli-evidence/validation.json').read_text())
        self.assertEqual(evidence['commands'], [])
        self.assertFalse(evidence['racket_executed'])
        self.assertTrue(evidence['source_zip']['extracted_source_check']['inventory_checked'])

    def test_source_zip_disallows_partial_validation(self):
        spec = importlib.util.spec_from_file_location(
            'source_runner', ROOT / 'tools/check-reference.py')
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        with contextlib.redirect_stderr(io.StringIO()):
            for option in ('--documents-only', '--render', '--native', '--quick'):
                with self.subTest(option=option), self.assertRaises(SystemExit):
                    runner.main(['--source-zip', str(self.archive), option])


class LinkScopeDiagnosticsTests(unittest.TestCase):
    """Separate unresolved markup, bad destinations, and partial-site scope."""
    def setUp(self):
        self.fixture = ReviewArchiveTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.site = self.fixture.site
        self.reference = self.fixture.index
        directory = self.fixture.source['tutorial_links'][0]['directory']
        self.companion = self.site / directory / 'index.html'

    def diagnose(self):
        return review.inspect_link_scopes(self.site)

    def test_clean_reference_is_not_complete_site_evidence(self):
        result = self.diagnose()
        self.assertEqual(result['reference']['status'], 'passed')
        self.assertEqual(result['companions']['status'], 'passed')
        self.assertFalse(result['complete_site_checked'])
        self.assertEqual(result['reference']['checked_local_links'], 3)

    def test_badlink_tokens_are_separate_from_unlinked_identifiers(self):
        page = checks.Page('<span class="x badlink">A</span><span class="RktErr">B</span>'
                           '<span class="badlink RktErr">C</span>')
        self.assertEqual(page.unresolved_references, 2)
        self.assertEqual(page.unlinked_identifiers, 2)
        self.assertEqual(page.badlinks, 3)

    def test_companion_unresolved_text_is_not_an_existing_hyperlink(self):
        self.companion.write_text('<h1 id="top">Tutorial</h1>'
                                  '<span class="badlink">Other tutorial</span>')
        result = self.diagnose()
        self.assertEqual(result['reference']['status'], 'passed')
        self.assertEqual(result['companions']['status'], 'incomplete')
        self.assertEqual(result['companions']['unresolved_references'], 1)
        self.assertEqual(result['companions']['checked_local_links'], 0)
        self.assertEqual(result['companions']['broken_local_links'], 0)

    def test_existing_hyperlink_with_missing_file_is_counted_separately(self):
        self.companion.write_text('<a href="absent.html">Other tutorial</a>')
        result = self.diagnose()['companions']
        self.assertEqual(result['unresolved_references'], 0)
        self.assertEqual(result['checked_local_links'], 1)
        self.assertEqual(result['broken_local_links'], 1)
        self.assertEqual(result['problems'][0]['reason'], 'missing target file')

    def test_missing_fragment_is_not_a_valid_local_link(self):
        self.companion.write_text('<a href="index.html#absent">Section</a>')
        result = self.diagnose()['companions']
        self.assertEqual(result['broken_local_links'], 1)
        self.assertEqual(result['problems'][0]['reason'], 'missing or duplicate fragment')

    def test_external_links_are_counted_but_not_claimed_verified(self):
        self.companion.write_text('<a href="https://example.invalid/manual">Other manual</a>')
        result = self.diagnose()['companions']
        self.assertEqual(result['external_links_not_checked'], 1)
        self.assertEqual(result['checked_local_links'], 0)

    def test_file_links_are_machine_local_not_portable_acceptance(self):
        self.companion.write_text('<a href="file:///tmp/manual.html">Manual</a>')
        result = self.diagnose()['companions']
        self.assertEqual(result['machine_local_links'], 1)
        self.assertEqual(result['status'], 'incomplete')

    def test_escaping_relative_link_is_reported(self):
        self.companion.write_text('<a href="../../escape.html">Other</a>')
        self.assertEqual(self.diagnose()['companions']['problems'][0]['reason'],
                         'outside the packaged tree')

    def test_partial_companion_diagnostics_survive_review_packaging(self):
        self.companion.write_text('<h1 id="top">Tutorial</h1>'
                                  '<span class="badlink">Undocumented entry</span>')
        result = self.fixture.package()
        self.assertEqual(result['link_scopes']['reference']['unresolved_references'], 0)
        self.assertEqual(result['link_scopes']['companions']['unresolved_references'], 1)
        with zipfile.ZipFile(self.fixture.archive) as archive:
            report = json.loads(archive.read('evidence/review.json'))
            self.assertEqual(report['link_scopes']['companions']['status'], 'incomplete')
            self.assertIn('does not certify', archive.read('README.txt').decode())



class R3TextCoverageTests(unittest.TestCase):
    """Read authored entries against independent test call shapes, not captured exports."""
    setUp = Fixtures.setUp
    write_inventory = Fixtures.write_inventory
    write_manifest = Fixtures.write_manifest
    change = Fixtures.change
    check = Fixtures.check

    def test_text_subset_has_one_definition_per_reviewed_call_shape(self):
        entries = {row['name']: row for row in self.check()['definitions']}
        self.assertEqual(len(TEXT_PROCEDURES), 169)
        for name, (mask, keywords) in TEXT_PROCEDURES.items():
            with self.subTest(name=name):
                self.assertEqual(entries[name]['arity_mask'], str(mask))
                self.assertEqual(entries[name]['allowed_keywords'], sorted(keywords))
                self.assertEqual(entries[name]['required_keywords'], [])

    def test_new_chapters_have_explicit_ownership(self):
        entries = self.check()['definitions']
        for chapter, count in (('typefaces', 48), ('fonts', 58), ('shaping', 14),
                               ('text-blobs', 29), ('text-layout', 43)):
            with self.subTest(chapter=chapter):
                owned = [e for e in entries
                         if e['chapter'] == f'scribblings/reference/{chapter}.scrbl']
                self.assertEqual(len(owned), count)

    def test_all_typeface_and_font_aliases_have_one_canonical_entry(self):
        entries = {row['name']: row for row in self.check()['definitions']}
        for module, names in (('skia/typefaces', TYPEFACE_EXPORTS), ('skia/fonts', FONT_EXPORTS)):
            for name in names:
                with self.subTest(module=module, name=name):
                    self.assertEqual(set(entries[name]['exports']), {'skia', module})
                    self.assertEqual(entries[name]['canonical_module'], module)

    def test_missing_font_alias_is_rejected(self):
        module = next(m for m in self.snapshots[0]['modules'] if m['path'] == 'fonts.rkt')
        module['exports'] = [e for e in module['exports'] if e['name'] != 'font-typeface']
        self.write_inventory()
        with self.assertRaisesRegex(checks.CheckError, 'unknown public export'):
            self.check()

    def test_disagreeing_typeface_alias_arity_is_rejected(self):
        module = next(m for m in self.snapshots[0]['modules'] if m['path'] == 'typefaces.rkt')
        entry = next(e for e in module['exports'] if e['name'] == 'font-table-tag')
        entry['arity_mask'] = '4'
        self.write_inventory()
        with self.assertRaisesRegex(checks.CheckError, 'arity_mask'):
            self.check()

    def test_changing_optional_face_to_required_is_rejected(self):
        self.change('fonts.scrbl', '[face (or/c typeface? #f) #f]', '[face (or/c typeface? #f)]')
        with self.assertRaisesRegex(checks.CheckError, 'arity_mask'):
            self.check()

    def test_new_shaping_keyword_cannot_escape_inventory_check(self):
        self.change('shaping.scrbl', "'btt) 'auto]", "'btt) 'auto] [#:invented option any/c #f]")
        with self.assertRaisesRegex(checks.CheckError, 'allowed_keywords'):
            self.check()

    def test_every_declared_text_alias_appears_in_the_link_probe(self):
        text = (self.root / checks.REFERENCE / 'tests/links.scrbl').read_text()
        for prefix, names in (('typefaces:', TYPEFACE_EXPORTS), ('fonts:', FONT_EXPORTS)):
            for name in names:
                self.assertIn('@racket[' + prefix + name + ']', text)
        for name in TEXT_PROCEDURES:
            self.assertIn('@racket[' + name + ']', text)

    def test_later_documentation_batches_are_reflected_in_current_source(self):
        names = {e['name'] for e in self.check()['definitions']}
        self.assertIn('gpu-presenter-render!', names)
        self.assertIn('skia-render-window%', names)
        self.assertIn('skia-dc%', names)


class R3TextSemanticsTests(unittest.TestCase):
    """Check specification details and test wiring; no Racket execution is implied."""
    chapters = ('typefaces', 'fonts', 'shaping', 'text-blobs', 'text-layout')

    def text(self, chapter):
        return (ROOT / checks.REFERENCE / (chapter + '.scrbl')).read_text()

    def header(self, chapter, name):
        return next(header for form, header, _ in checks.commands(self.text(chapter))
                    if form == 'defproc' and header[0][0] == name)

    def test_font_defaults_are_complete_and_match_the_reviewed_constructor(self):
        fields = self.header('fonts', 'make-font')[0][1:]
        self.assertEqual(fields[0], ['face', ['or/c', 'typeface?', '#f'], '#f'])
        actual = {field[0]: field[-1] for field in fields[1:]}
        self.assertEqual(actual, {
            '#:size': '12', '#:scale-x': '1', '#:skew-x': '0',
            '#:edging': ['quote', 'antialias'], '#:hinting': ['quote', 'normal'],
            '#:subpixel?': '#f', '#:linear-metrics?': '#f', '#:embolden?': '#f',
            '#:embedded-bitmaps?': '#f', '#:force-auto-hinting?': '#f', '#:baseline-snap?': '#t'})

    def test_table_tag_conversions_have_different_domains(self):
        forward = self.header('typefaces', 'font-table-tag')[0][1][1]
        reverse = self.header('typefaces', 'font-table-tag->bytes')[0][1][1]
        self.assertEqual(forward, ['or/c', ['integer-in', '0', '#xffffffff'], 'bytes?', 'string?'])
        self.assertEqual(reverse, ['integer-in', '0', '#xffffffff'])
        self.assertIn('symbols are not accepted', self.text('typefaces'))

    def test_unicode_scalar_contract_excludes_surrogates(self):
        for chapter, name in (('typefaces', 'font-manager-match-character'),
                              ('fonts', 'font-char->glyph')):
            header = self.header(chapter, name)
            field = next(f for f in header[0][1:] if f[0] == 'character')
            self.assertEqual(field[1], ['or/c', 'char?', ['integer-in', '0', '#xd7ff'],
                                       ['integer-in', '#xe000', '#x10ffff']])

    def test_nullable_metrics_do_not_claim_zero_means_false(self):
        for name in ('underline-thickness', 'underline-position',
                     'strikeout-thickness', 'strikeout-position'):
            self.assertEqual(self.header('fonts', 'font-metrics-' + name)[1],
                             ['or/c', 'real?', '#f'])
        self.assertEqual(self.header('fonts', 'font-metrics-ascent')[1], 'real?')

    def test_positioned_blob_positions_accept_lists_and_vectors(self):
        header = self.header('text-blobs', 'make-positioned-text-blob')
        field = next(f for f in header[0][1:] if f[0] == 'positions')
        point = ['or/c', ['list/c', 'real?', 'real?'], ['vector/c', 'real?', 'real?']]
        self.assertEqual(field[1], ['or/c', ['listof', point], ['vectorof', point]])
        self.assertIn('copies glyphs and positions', self.text('text-blobs'))

    def test_character_counts_and_cluster_bytes_are_distinguished(self):
        self.assertIn('The count is not a UTF-8 byte offset.',
                      ' '.join(self.text('fonts').split()))
        self.assertIn('A @deftech{cluster offset} is a UTF-8 byte offset',
                      self.text('shaping'))
        self.assertIn('not a Racket character', self.text('shaping'))
        self.assertIn('paragraph-relative Racket character index', self.text('text-layout'))

    def test_layout_requires_live_dependencies_without_claiming_owned_resource(self):
        text = self.text('text-layout')
        self.assertIn('ordinary Racket values, not resources', text)
        self.assertIn('Both the shaper and manager must remain open', text)
        self.assertIn('does not own a permanent native', text)
        self.assertIn('Drawing is not transactional', text)

    def test_shape_and_layout_directions_are_not_conflated(self):
        shaped = self.header('shaping', 'shape-text')[0]
        layout = self.header('text-layout', 'layout-text')[0]
        shape_dir = next(f[2] for f in shaped[1:] if f[0] == '#:direction')
        layout_dir = next(f[2] for f in layout[1:] if f[0] == '#:direction')
        self.assertEqual(shape_dir, ['or/c'] + [['quote', s] for s in ('auto', 'ltr', 'rtl',
                                                                 'ttb', 'btt')])
        self.assertEqual(layout_dir, ['or/c'] + [['quote', s] for s in ('auto', 'ltr', 'rtl')])
        self.assertIn('signed y advances', self.text('shaping'))

    def test_explicit_script_justification_limit_is_not_hidden(self):
        self.assertIn('does not enable these script-specific justification opportunities',
                      self.text('text-layout'))
        self.assertIn('A break provider is not invoked when wrapping is disabled',
                      self.text('text-layout'))

    def test_no_native_evaluation_added_to_documentation_build(self):
        total = 0
        for chapter in self.chapters:
            forms = list(checks.commands(self.text(chapter), recursive=True))
            self.assertFalse(any(form in ('examples', 'interaction', 'interaction-eval')
                                 for form, _, _ in forms))
            total += sum(form == 'racketblock' for form, _, _ in forms)
        self.assertEqual(total, 60)

    def test_new_complete_file_examples_explicitly_allow_replacement(self):
        for chapter in self.chapters:
            for form, header, _ in checks.commands(self.text(chapter), recursive=True):
                if form == 'racketblock' and 'save-png' in str(header):
                    self.assertIn('with-skia', str(header))
                    self.assertIn("['quote', 'replace']", str(header))

    def test_native_and_pure_acceptance_are_wired_separately(self):
        source = (ROOT / 'tools/check-reference.py').read_text()
        self.assertIn("run('text-pure-tests'", source)
        native = source[source.index('if args.native:'):]
        self.assertIn("ROOT / 'tools/reference-text-test.rkt'", native)
        self.assertNotIn("ROOT / 'tools/reference-text-pure-test.rkt'", native)

    def test_racket_cases_are_independent_and_inside_test_submodules(self):
        # Delimiter/structure check only; this small reader does not compile Racket.
        for filename, expected in (('reference-text-pure-test.rkt', 3),
                                   ('reference-text-test.rkt', 12)):
            text = (ROOT / 'tools' / filename).read_text().split('\n', 1)[1]
            reader, forms = checks.Reader(text), []
            while True:
                reader.skip()
                if reader.position == len(text):
                    break
                forms.append(reader.read())
            modules = [f for f in forms if isinstance(f, list) and f[0] == 'module+']
            self.assertEqual(len(modules), 1)
            cases = [f for f in modules[0][2:] if isinstance(f, list) and f[0] == 'test-case']
            self.assertEqual(len(cases), expected)
            def count_cases(form):
                if not isinstance(form, list):
                    return 0
                return int(bool(form) and form[0] == 'test-case') + sum(map(count_cases, form))
            self.assertEqual(count_cases(modules[0]), expected)

class R3aEditorialCleanupTests(unittest.TestCase):
    """Check local wording and discoverability, not native implementation behavior."""

    def text(self, chapter):
        return (ROOT / checks.REFERENCE / (chapter + '.scrbl')).read_text()

    def entry(self, chapter, name):
        text = self.text(chapter)
        offset = next(at for form, header, at in checks.commands(text)
                      if form == 'defproc' and header[0][0] == name)
        reader = checks.Reader(text, offset + len('@defproc'))
        reader.read()
        reader.skip()
        start = reader.position
        self.assertEqual(text[start], '{')
        return text[start + 1:checks.brace_end(text, start) - 1]

    def test_layout_keyword_caveat_is_in_the_entry_before_its_example(self):
        entry = self.entry('text-layout', 'layout-text').split('@racketblock[', 1)[0]
        prose = ' '.join(entry.split())
        self.assertIn('explicit @racket[#:script] affects shaping but does not enable', prose)
        self.assertIn('CJK or Arabic expansion opportunities', prose)
        self.assertIn('script inference when @racket[#:script] is @racket[#f]', prose)
        self.assertIn('does not enable the script-specific CJK or Arabic expansion opportunities',
                      prose)

    def test_break_text_describes_results_and_keeps_boundary_caveats(self):
        prose = ' '.join(self.entry('fonts', 'font-break-text').split())
        self.assertIn('longest leading unshaped prefix', prose)
        self.assertIn('The count is not a UTF-8 byte offset.', prose)
        self.assertIn('boundary need not be a word or grapheme boundary', prose)
        self.assertIn('An empty input returns 0 and 0.0.', prose)
        self.assertNotIn('implementation converts', prose)
        self.assertIn('(substring text 0 count)', prose)

    def test_typeface_bytes_describes_member_selection_not_loader_steps(self):
        prose = ' '.join(self.entry('typefaces', 'typeface-from-bytes').split())
        self.assertIn('@racket[index] selects the requested member, including on macOS', prose)
        self.assertIn('does not silently substitute a different face', prose)
        self.assertIn('Invalid or unsupported font data and native failures raise exceptions', prose)
        self.assertNotIn('rewrapped', prose)
        self.assertNotIn('Other platforms', prose)
        notes = (ROOT / 'docs/REFERENCE-DEVELOPMENT.md').read_text()
        self.assertIn('rewraps the requested TrueType collection member', notes)

    def test_shaping_term_is_lowercase_in_an_ordinary_sentence(self):
        source = self.text('shaping')
        self.assertEqual(source.count('@deftech{shaping}'), 1)
        self.assertNotIn('@deftech{Shaping}', source)
        self.assertIn('The process of @deftech{shaping} maps text to glyphs and positions', source)




class R3BlobCoverageTests(unittest.TestCase):
    """Static call shapes and alias coverage; no native execution is implied."""
    setUp = Fixtures.setUp
    write_inventory = Fixtures.write_inventory
    write_manifest = Fixtures.write_manifest
    change = Fixtures.change
    check = Fixtures.check

    def test_complete_public_text_blob_family_and_transform_dependencies(self):
        entries = {row['name']: row for row in self.check()['definitions']}
        self.assertEqual(len(BLOB_EXPORTS), 23)
        self.assertEqual(len(ATLAS_EXPORTS), 3)
        self.assertEqual(set(BLOB_EXPORTS + ATLAS_EXPORTS), set(BLOB_PROCEDURES))
        for name, (arity, keywords) in BLOB_PROCEDURES.items():
            with self.subTest(name=name):
                self.assertEqual(entries[name]['arity_mask'], str(arity))
                self.assertEqual(entries[name]['allowed_keywords'], sorted(keywords))
                self.assertEqual(entries[name]['required_keywords'], [])

    def test_new_exports_have_canonical_chapters_and_real_public_aliases(self):
        entries = {row['name']: row for row in self.check()['definitions']}
        for module, chapter, names in (('skia/text-blobs', 'text-blobs', BLOB_EXPORTS),
                                       ('skia/geometry-primitives', 'matrices', ATLAS_EXPORTS)):
            for name in names:
                with self.subTest(name=name):
                    self.assertEqual(entries[name]['canonical_module'], module)
                    self.assertEqual(entries[name]['exports'], ['skia', module])
                    self.assertEqual(entries[name]['chapter'],
                                     f'scribblings/reference/{chapter}.scrbl')

    def test_each_new_public_import_path_is_exercised_by_link_probe(self):
        text = (self.root / checks.REFERENCE / 'tests/links.scrbl').read_text()
        for prefix, names in (('text-blobs:', BLOB_EXPORTS), ('geometry-primitives:', ATLAS_EXPORTS)):
            for name in names:
                self.assertEqual(text.count('@racket[' + name + ']'), 1)
                self.assertEqual(text.count('@racket[' + prefix + name + ']'), 1)
        self.assertIn('(prefix-in text-blobs: skia/text-blobs)', text)
        self.assertIn('(prefix-in geometry-primitives: skia/geometry-primitives)', text)

    def test_missing_text_blob_reexport_is_rejected(self):
        module = next(m for m in self.snapshots[0]['modules'] if m['path'] == 'text-blobs.rkt')
        module['exports'] = [r for r in module['exports'] if r['name'] != 'text-blob-runs']
        self.write_inventory()
        with self.assertRaisesRegex(checks.CheckError, 'unknown public export'):
            self.check()

    def test_disagreeing_builder_alias_arity_is_rejected(self):
        module = next(m for m in self.snapshots[0]['modules'] if m['path'] == 'text-blobs.rkt')
        row = next(r for r in module['exports'] if r['name'] == 'text-blob-builder-add-run!')
        row['arity_mask'] = '16'
        self.write_inventory()
        with self.assertRaisesRegex(checks.CheckError, 'arity_mask'):
            self.check()

    def test_unrecognized_placement_keyword_is_rejected(self):
        self.change('text-blobs.scrbl', '[#:start-offset start real? 0]',
                    '[#:start-offset start real? 0] [#:invented option any/c #f]')
        with self.assertRaisesRegex(checks.CheckError, 'allowed_keywords'):
            self.check()

    def test_unsupported_transform_alias_is_rejected(self):
        row = next(r for r in self.manifest['definitions'] if r['name'] == 'make-atlas-transform')
        row['exports'].append('skia/matrix')
        self.write_manifest()
        with self.assertRaisesRegex(checks.CheckError, 'unknown public export'):
            self.check()


class R3BlobSemanticsTests(unittest.TestCase):
    """Inspect authored contracts and focused regression wiring, not simulated Skia."""
    def text(self, chapter='text-blobs'):
        return (ROOT / checks.REFERENCE / (chapter + '.scrbl')).read_text()

    def header(self, name, chapter='text-blobs'):
        return next(header for form, header, _ in checks.commands(self.text(chapter))
                    if form == 'defproc' and header[0][0] == name)

    def test_nullable_finishing_and_path_results_are_explicit(self):
        for name in ('text-blob-builder-finish!', 'shaped-run->text-blob/on-path'):
            self.assertEqual(self.header(name)[1], ['or/c', 'text-blob?', '#f'])
        self.assertEqual(self.header('positioned-glyphs->path')[1], 'skia-path?')
        self.assertEqual(self.header('draw-shaped-run/on-path')[1], 'void?')

    def test_glyph_append_keywords_preserve_defaults_and_precise_metadata_domains(self):
        names = ('text-blob-builder-add-run!', 'text-blob-builder-add-horizontal-run!',
                 'text-blob-builder-add-positioned-run!', 'text-blob-builder-add-transformed-run!')
        for name in names:
            fields = {f[0]: f for f in self.header(name)[0][1:]}
            self.assertEqual(fields['#:text'], ['#:text', 'text',
                                                ['or/c', 'string?', 'bytes?', '#f'], '#f'])
            self.assertEqual(fields['#:clusters'][2],
                             ['or/c', ['listof', 'exact-nonnegative-integer?'],
                              ['vectorof', 'exact-nonnegative-integer?'], '#f'])
            self.assertEqual(fields['#:clusters'][-1], '#f')
            self.assertEqual(self.header(name)[1], 'void?')
        self.assertEqual(self.header(names[0])[0][4][-1], ['quote', ['0', '0']])

    def test_four_coefficient_transforms_include_atlas_values_lists_and_vectors(self):
        fields = {f[0]: f for f in self.header('text-blob-builder-add-transformed-run!')[0][1:]}
        transform = ['or/c', 'atlas-transform?', ['list/c'] + ['real?'] * 4,
                     ['vector/c'] + ['real?'] * 4]
        self.assertEqual(fields['transforms'][1],
                         ['or/c', ['listof', transform], ['vectorof', transform]])
        self.assertIn('not an affine matrix\'s six coefficients', self.text())

    def test_shaped_append_does_not_offer_caller_supplied_cluster_offsets(self):
        fields = {f[0]: f for f in self.header('text-blob-builder-add-shaped-run!')[0][1:]}
        self.assertIn('#:text', fields)
        self.assertNotIn('#:clusters', fields)
        self.assertIn("The original string cannot be reconstructed", self.text())
        self.assertIn('no automatic\nfont-provenance check', self.text())

    def test_input_byte_offsets_are_distinguished_from_character_indices(self):
        prose = ' '.join(self.text().split())
        self.assertIn('not a Racket character index or necessarily a grapheme boundary', prose)
        self.assertIn('Repeated and descending offsets are permitted', prose)
        self.assertIn('not that semantic correspondence', prose)
        self.assertIn('malformed byte sequences are rejected', prose)

    def test_builder_lifetime_and_error_boundary_are_local_and_explicit(self):
        prose = ' '.join(self.text().split())
        self.assertIn('Finishing consumes the builder', prose)
        self.assertIn('An empty append still validates its options and resources', prose)
        self.assertIn('before native run allocation leave the builder available', prose)
        self.assertIn('failure after native run allocation begins closes the builder', prose)
        self.assertIn('Both outcomes close the builder', prose)
        self.assertIn('counts logical appends', prose)

    def test_run_description_contracts_preserve_absence_and_coordinate_representations(self):
        self.assertEqual(self.header('text-run-info-positioning')[1],
                         ['or/c'] + [['quote', n] for n in
                                     ('default', 'horizontal', 'positioned', 'transformed')])
        self.assertEqual(self.header('text-run-info-positions')[1],
                         ['vectorof', ['list/c', 'real?', 'real?']])
        self.assertEqual(self.header('text-run-info-transforms')[1],
                         ['or/c', ['vectorof', ['list/c'] + ['real?'] * 4], '#f'])
        self.assertEqual(self.header('text-run-info-utf8')[1], ['or/c', 'bytes?', '#f'])
        self.assertEqual(self.header('text-run-info-clusters')[1],
                         ['or/c', ['vectorof', 'exact-nonnegative-integer?'], '#f'])

    def test_run_font_is_owned_and_independent_not_a_borrow(self):
        prose = ' '.join(self.text().split())
        self.assertIn('new owned mutable font copied', prose)
        self.assertIn('Closing the blob does not close the returned font', prose)
        self.assertIn('remains usable after the blob closes', prose)
        self.assertIn('A transformed run returns an empty vector here', prose)

    def test_intercepts_reject_partial_answers_for_transformed_runs(self):
        prose = ' '.join(self.text().split())
        self.assertIn('native backend omits transformed runs when computing intercepts', prose)
        self.assertIn('rejects any blob containing a transformed run', prose)
        self.assertIn('result is subject to @racket[current-skia-byte-limit]', prose)
        self.assertIn('not as a promised sorted, merged union', prose)
        self.assertIn('not a pixel coverage readback', prose)
        self.assertEqual(self.header('text-blob-intercepts')[1],
                         ['vectorof', ['list/c', 'real?', 'real?']])

    def test_text_on_path_uses_origin_distances_and_signed_normal_offsets(self):
        prose = ' '.join(self.text().split())
        self.assertIn('@math{start + gx}', prose)
        self.assertIn('@math{normal + gy}', prose)
        self.assertIn('@math{(-ty, tx)}', prose)
        self.assertIn('no fitting, clipping, or wraparound', prose)
        self.assertIn('origins, not the full visible glyph extents', prose)
        self.assertIn('Glyphs may extend beyond an endpoint', prose)
        self.assertIn('empty run returns @racket[#f], but still validates', prose)

    def test_direct_path_drawing_has_no_metadata_keyword_and_validates_empty_input(self):
        fields = {f[0]: f for f in self.header('draw-shaped-run/on-path')[0][1:]}
        self.assertNotIn('#:text', fields)
        self.assertIn('#:text', {f[0]: f for f in
                                self.header('shaped-run->text-blob/on-path')[0][1:]})
        self.assertIn('canvas and paint are validated even for an empty run', self.text())
        self.assertIn('then released, including when drawing raises an', self.text())

    def test_atlas_helpers_have_detached_value_contracts_and_correct_defaults(self):
        header = self.header('make-atlas-transform', 'matrices')[0]
        fields = {f[0]: f for f in header[1:]}
        self.assertEqual(fields['#:scale'][2:], [['and/c', 'real?', ['>=/c', '0']], '1'])
        self.assertEqual(fields['#:rotation'][2:], ['real?', '0'])
        self.assertEqual(fields['#:anchor'][-1], ['quote', ['0', '0']])
        self.assertEqual(self.header('atlas-transform-coefficients', 'matrices')[1],
                         ['vector/c'] + ['real?'] * 4)
        self.assertIn('Zero scale is accepted', self.text('matrices'))
        self.assertIn('anchor is copied', self.text('matrices'))

    def test_six_focused_blob_examples_are_added_without_native_doc_evaluation(self):
        forms = list(checks.commands(self.text(), recursive=True))
        self.assertEqual(sum(form == 'racketblock' for form, _, _ in forms), 19)
        self.assertFalse(any(form in ('examples', 'interaction', 'interaction-eval')
                             for form, _, _ in forms))
        # The seventh block is the original R3a positioned-blob example.
        self.assertIn('(text-blob-builder-finish! builder)', self.text())
        self.assertIn('#:text text #:clusters', self.text())
        self.assertIn('(text-blob-intercepts blob 20 25)', self.text())

    def test_new_cases_are_included_in_review_sources(self):
        paths = review.source_hashes(ROOT)
        for name in ('reference_blob_cases.py', 'reference-blob-values-test.rkt',
                     'reference-blobs-test.rkt'):
            self.assertIn('tools/' + name, paths)

    def test_pure_and_native_acceptance_are_wired_separately(self):
        source = (ROOT / 'tools/check-reference.py').read_text()
        self.assertIn("run('blob-value-tests'", source)
        native = source[source.index('if args.native:'):]
        self.assertIn("ROOT / 'tools/reference-blobs-test.rkt'", native)
        self.assertNotIn("ROOT / 'tools/reference-blob-values-test.rkt'", native)

    def test_new_racket_tests_have_valid_delimiters_and_top_level_cases(self):
        # This is a delimiter/structure check, not Racket reading or evaluation.
        for name, count in (('reference-blob-values-test.rkt', 4), ('reference-blobs-test.rkt', 17)):
            text = (ROOT / 'tools' / name).read_text().split('\n', 1)[1]
            reader, forms = checks.Reader(text), []
            while True:
                reader.skip()
                if reader.position == len(text):
                    break
                forms.append(reader.read())
            modules = [f for f in forms if isinstance(f, list) and f and f[0] == 'module+']
            self.assertEqual(len(modules), 1)
            cases = [f for f in modules[0][2:] if isinstance(f, list) and f and f[0] == 'test-case']
            self.assertEqual(len(cases), count)
            def nested_cases(form):
                if not isinstance(form, list):
                    return 0
                return int(bool(form) and form[0] == 'test-case') + sum(map(nested_cases, form))
            self.assertEqual(nested_cases(modules[0]), count)


class R3b1EditorialTests(unittest.TestCase):
    """Inspect the actual Scribble example; these tests do not evaluate Racket."""
    def text(self):
        return (ROOT / checks.REFERENCE / 'matrices.scrbl').read_text()

    def test_atlas_heading_keeps_its_existing_link_target(self):
        text = self.text()
        self.assertIn('@section[#:tag "skia-atlas-transforms"]{Atlas Transforms}', text)
        self.assertNotIn('Scaled Rotations and Translations', text)
        self.assertIn('@title[#:tag "skia-matrices"]{Affine Matrices}', text)

    def test_anchor_example_checks_computed_coefficients_in_the_constructor_entry(self):
        text = self.text()
        start = text.index('@defproc[(make-atlas-transform')
        stop = text.index('@defproc[(atlas-transform-coefficients', start)
        entry = text[start:stop]
        examples = [header for form, header, _ in checks.commands(entry, recursive=True)
                    if form == 'examples']
        self.assertEqual(examples, [[
            '#:eval', 'atlas-eval',
            ['define', 'transform', ['make-atlas-transform', '10', '20',
                                     '#:scale', '2', '#:anchor', ['quote', ['3', '4']]]],
            ['eval:check', ['atlas-transform-coefficients', 'transform'],
             ['vector-immutable', '2.0', '0.0', '4.0', '12.0']]]])
        self.assertIn('translation compensates for the scaled anchor', entry)
        self.assertNotIn('eval:result', entry)
        self.assertNotIn('eval:alts', entry)

    def test_atlas_example_has_its_own_closed_public_api_evaluator(self):
        text = self.text()
        normalized = ' '.join(text.split())
        self.assertIn("(atlas-eval '(require (only-in skia/geometry-primitives "
                      "make-atlas-transform atlas-transform-coefficients)))", normalized)
        self.assertEqual(text.count('@(define atlas-eval (make-base-eval))'), 1)
        self.assertEqual(text.count('@close-eval[atlas-eval]'), 1)
        self.assertGreater(text.index('@close-eval[atlas-eval]'),
                           text.index('@examples[#:eval atlas-eval'))
        self.assertLess(text.index('@close-eval[matrix-eval]'),
                        text.index('@(define atlas-eval'))



class R3EffectsSemanticsTests(unittest.TestCase):
    """Inspect independently authored contracts and test wiring, not simulated native behavior."""
    def text(self, chapter):
        return (ROOT / checks.REFERENCE / (chapter + '.scrbl')).read_text()

    def header(self, name, chapter):
        return next(h for form, h, _ in checks.commands(self.text(chapter))
                    if form == 'defproc' and h[0][0] == name)

    def entry(self, name, chapter):
        text = self.text(chapter)
        start = next(at for form, h, at in checks.commands(text)
                     if form == 'defproc' and h[0][0] == name)
        end = text.find('@defproc[', start + 1)
        return ' '.join(text[start:end if end >= 0 else None].split())

    def test_four_existing_predicates_have_one_new_authoritative_location(self):
        mapping = {'path-effect?': 'path-effects', 'mask-filter?': 'path-effects',
                   'color-filter?': 'color-filters', 'image-filter?': 'image-filters'}
        specs, _ = checks.document_definitions(ROOT)
        for name, chapter in mapping.items():
            rows = [r for r in specs if r['name'] == name]
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]['chapter'], 'scribblings/reference/' + chapter + '.scrbl')
            self.assertNotIn('@defproc[(' + name, self.text('paints'))

    def test_new_public_module_targets_are_not_duplicated(self):
        text = '\n'.join(p.read_text() for p in (ROOT / checks.REFERENCE).glob('*.scrbl'))
        for module in ('effects', 'color-filters', 'runtime-effects'):
            self.assertEqual(text.count('@defmodule[skia/' + module + ' #:no-declare]'), 1)

    def test_color_blend_contract_excludes_only_dst(self):
        ordinary = self.header('make-blend-mode-blender', 'runtime-effects')[0][1][1]
        restricted = self.header('make-blend-color-filter', 'color-filters')[0][2][1]
        expected = [x for x in ordinary if x != ['quote', 'dst']]
        self.assertEqual(restricted, expected)
        self.assertEqual(len(ordinary) - 1, 29)

    def test_blend_graph_uses_the_complete_blend_mode_set(self):
        ordinary = self.header('make-blend-mode-blender', 'runtime-effects')[0][1][1]
        self.assertEqual(self.header('make-blend-image-filter', 'image-filters')[0][1][1],
                         ordinary)

    def test_mask_tables_and_color_tables_have_different_domains(self):
        self.assertEqual(self.header('make-table-mask-filter', 'path-effects')[0][1][1], 'bytes?')
        self.assertEqual(self.header('make-table-color-filter', 'color-filters')[0][1][1],
                         ['or/c', 'bytes?', ['listof', 'byte?'], ['vectorof', 'byte?']])

    def test_no_op_trim_and_dash_restrictions_are_visible(self):
        text = ' '.join(self.text('path-effects').split())
        self.assertIn('an all-zero pattern is rejected', text)
        self.assertIn('Normal mode rejects the full interval from 0 to 1', text)
        self.assertIn('must exceed 1/4096', text)

    def test_path_composition_and_sum_are_distinguished(self):
        text = ' '.join(self.text('path-effects').split())
        self.assertIn('applies @racket[inner] first, then @racket[outer]', text)
        self.assertIn("neither effect receives the other's output", text)

    def test_image_input_is_dynamic_source_not_transparent(self):
        text = ' '.join(self.text('image-filters').split())
        self.assertIn('not a transparent image and not a disabled branch', text)
        self.assertIn('not everything already present on the canvas', text)
        self.assertIn('two false inputs to a blend node refer to the same source', text)

    def test_crop_and_canvas_clip_are_not_conflated(self):
        self.assertIn('not a\ncanvas @tech{clip}', self.text('image-filters'))
        self.assertIn('collapse after native rounding are rejected', self.text('image-filters'))

    def test_blur_and_convolution_reject_mirror(self):
        for name in ('make-blur-image-filter', 'make-matrix-convolution-image-filter'):
            fields = {f[0]: f for f in self.header(name, 'image-filters')[0][1:]}
            self.assertEqual(fields['#:tile-mode'][2],
                             ['or/c', ['quote', 'decal'], ['quote', 'clamp'], ['quote', 'repeat']])
        self.assertIn('requires an explicit crop', self.text('image-filters'))

    def test_image_samplers_do_not_claim_unsupported_cubic_modes(self):
        for name in ('make-matrix-transform-image-filter', 'make-image-source-filter',
                     'make-magnifier-image-filter'):
            fields = {f[0]: f for f in self.header(name, 'image-filters')[0][1:]}
            self.assertEqual(fields['#:sampling'][2],
                             ['or/c', ['quote', 'nearest'], ['quote', 'linear']])

    def test_rounding_dependent_domains_are_not_unconditional_real_in_contracts(self):
        fields = {f[0]: f for f in self.header('make-magnifier-image-filter', 'image-filters')[0][1:]}
        self.assertEqual(fields['zoom'][1], 'real?')
        fields = {f[0]: f for f in self.header('make-spot-lit-specular-image-filter',
                                              'image-filters')[0][1:]}
        for keyword in ('#:shininess', '#:exponent', '#:cutoff-angle'):
            self.assertEqual(fields[keyword][2], 'real?')
        self.assertIn('apply after single-precision rounding', self.text('image-filters'))
        for name in ('make-fractal-noise-shader', 'make-turbulence-shader'):
            fields = {f[0]: f for f in self.header(name, 'shaders')[0][1:]}
            for argument in ('frequency-x', 'frequency-y'):
                self.assertEqual(fields[argument][1], 'real?')

    def test_image_source_default_destination_keeps_source_coordinates(self):
        text = self.entry('make-image-source-filter', 'image-filters')
        self.assertIn('preserving its coordinates and scale', text)
        self.assertIn('does not automatically relocate a subset', text)

    def test_runtime_effect_metadata_remains_available_after_closure(self):
        for name in ('runtime-effect-kind', 'runtime-effect-source',
                     'runtime-effect-uniform-byte-size', 'runtime-effect-uniforms',
                     'runtime-effect-children'):
            self.assertRegex(self.entry(name, 'runtime-effects'), r'closed|closure')

    def test_runtime_packing_returns_bytes_not_a_native_resource(self):
        self.assertEqual(self.header('runtime-effect-uniform-bytes', 'runtime-effects')[1],
                         ['and/c', 'bytes?', 'immutable?'])
        self.assertIn('new immutable byte string', self.text('runtime-effects'))
        self.assertIn('not a portable serialization', self.text('runtime-effects'))

    def test_runtime_binding_hashes_are_complete_and_normalized(self):
        text = ' '.join(self.text('runtime-effects').split())
        for phrase in ('Missing names, unknown names', 'same normalized spelling',
                       'Every reflected uniform and child must be supplied',
                       'no implicit zero uniforms or null-child fallbacks'):
            self.assertIn(phrase, text)

    def test_scalar_array_and_half_uniform_packing_rules_are_explicit(self):
        text = ' '.join(self.text('runtime-effects').split())
        self.assertIn('A scalar array of length one still requires a sequence', text)
        self.assertIn("column-major component order", text)
        self.assertIn('four bytes per supplied component', text)

    def test_runtime_stage_specific_factory_shapes(self):
        for name, result in [('runtime-effect->shader', 'shader?'),
                             ('runtime-effect->color-filter', 'color-filter?'),
                             ('runtime-effect->blender', 'blender?')]:
            h = self.header(name, 'runtime-effects')
            self.assertEqual(h[1], result)
            fields = {f[0]: f for f in h[0][1:]}
            for keyword in ('#:uniforms', '#:children'):
                self.assertEqual(fields[keyword][2:], ['hash?', ['hash']])
            self.assertEqual('#:local-matrix' in fields, result == 'shader?')

    def test_paint_blender_has_an_owned_nullable_result(self):
        self.assertEqual(self.header('paint-blender', 'runtime-effects')[1],
                         ['or/c', 'blender?', '#f'])
        text = self.entry('paint-blender', 'runtime-effects')
        self.assertIn('independently owned', text)
        self.assertIn('implicit source-over', text)

    def test_runtime_alpha_and_color_uniform_conventions_are_visible(self):
        text = self.text('runtime-effects')
        self.assertIn('premultiplied RGBA', text)
        self.assertIn('unpremultiplied sRGB', text)
        self.assertIn('does not automatically premultiply', text)

    def test_seven_new_examples_remain_native_opt_in(self):
        count = 0
        for chapter in ('path-effects', 'color-filters', 'image-filters', 'runtime-effects'):
            forms = list(checks.commands(self.text(chapter), recursive=True))
            self.assertFalse(any(form == 'examples' for form, _, _ in forms))
            count += sum(form == 'racketblock' for form, _, _ in forms)
        self.assertEqual(count, 53)

    def test_effect_acceptance_is_wired_into_the_existing_runner(self):
        text = (ROOT / 'tools/check-reference.py').read_text()
        self.assertIn('tools/reference-effects-pure-test.rkt', text)
        self.assertIn('tools/reference-effects-test.rkt', text)
        for file, count in [('reference-effects-pure-test.rkt', 6),
                            ('reference-effects-test.rkt', 17)]:
            source = (ROOT / 'tools' / file).read_text()
            checks.Reader('(' + source.split('\n', 1)[1] + ')').read()
            self.assertEqual(source.count('(test-case '), count)

    def test_picture_filter_is_documented_with_the_picture_batch(self):
        manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        self.assertIn('make-picture-image-filter', {r['name'] for r in manifest['definitions']})
        notes = (ROOT / 'docs/REFERENCE-DEVELOPMENT.md').read_text()
        self.assertIn('make-picture-image-filter', notes)



class R3dColorSemanticsTests(unittest.TestCase):
    """Source and call-shape checks; native outcomes are tested separately in Racket."""
    def text(self, chapter):
        return (ROOT / checks.REFERENCE / (chapter + '.scrbl')).read_text()


    def test_every_alias_in_the_actual_probe_matches_the_html_validator(self):
        manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        probe = (ROOT / checks.REFERENCE / 'tests/links.scrbl').read_text()
        for row in manifest['definitions']:
            for module in row['exports']:
                if module == 'skia':
                    continue
                prefix = module.removeprefix('skia/').replace('/', '-')
                with self.subTest(module=module, name=row['name']):
                    self.assertIn('(prefix-in ' + prefix + ': ' + module + ')', probe)
                    self.assertEqual(probe.count('@racket[' + prefix + ':' + row['name'] + ']'), 1)

    def header(self, name, chapter):
        return next(h for form, h, _ in checks.commands(self.text(chapter))
                    if form == 'defproc' and h[0][0] == name)

    def test_all_new_call_shapes_match_independent_expectations(self):
        definitions, _ = checks.document_definitions(ROOT)
        specs = {row['name']: row for row in definitions}
        for name, (arity, keywords) in COLOR_PROCEDURES.items():
            with self.subTest(name=name):
                self.assertEqual(specs[name]['arity_mask'], str(arity))
                self.assertEqual(specs[name]['allowed_keywords'], keywords)
                self.assertEqual(specs[name]['required_keywords'],
                                 COLOR_REQUIRED_KEYWORDS.get(name, []))

    def test_new_public_modules_have_one_canonical_definition_for_each_export(self):
        manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        for module, names in (('color-space', COLOR_SPACE_EXPORTS), ('color4f', COLOR4F_EXPORTS),
                              ('float-colors', FLOAT_COLOR_EXPORTS),
                              ('image-info', GB_MODULES['image-info.rkt'])):
            actual = [row['name'] for row in manifest['definitions']
                      if 'skia/' + module in row['exports']]
            self.assertEqual(sorted(actual), sorted(names))
            self.assertEqual(len(actual), len(set(actual)))
        self.assertEqual(len(manifest['definitions']), 1263)
        self.assertEqual(sum(len(r['exports']) for r in manifest['definitions']), 1988)

    def test_real_inventory_pins_are_not_replaced_by_test_snapshots(self):
        manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        self.assertEqual({row['file']: row['git_blob'] for row in manifest['snapshots']}, {
            'api/public-api-headless.json': 'bd5bb2a178dacf491b9c5e2b045592c69f0f2a1d',
            'api/public-api-gui.json': '1221794e26e099b8ca38110f4a42564f6b38f8f6'})

    def test_standard_space_definitions_move_without_removing_the_legacy_section(self):
        old = self.text('colors')
        new = self.text('color-management')
        self.assertIn('@section[#:tag "skia-color-spaces"]{Color Spaces}', old)
        self.assertIn('@secref["skia-color-management"]', old)
        for name in ('color-space?', 'make-srgb-color-space', 'make-linear-srgb-color-space',
                     'color-space=?', 'color-space-srgb?', 'color-space-linear-gamma?'):
            self.assertNotIn('@defproc[(' + name, old)
            self.assertEqual(new.count('@defproc[(' + name + ' ')
                             + new.count('@defproc[(' + name + ')'), 1)

    def test_float_constructor_descriptors_are_required_and_accept_mutable_bytes(self):
        expected = ['or/c', ['quote', 'srgb'], ['quote', 'linear-srgb'], 'bytes?']
        for name in COLOR_REQUIRED_KEYWORDS:
            fields = {f[0]: f for f in self.header(name, 'float-colors')[0][1:]}
            self.assertEqual(fields['#:color-space'], ['#:color-space', 'space', expected])
        self.assertIn('Mutable ICC bytes are accepted by', self.text('float-colors'))

    def test_make_paint_color4f_does_not_advertise_all_make_paint_keywords(self):
        fields = {f[0] for f in self.header('make-paint/color4f', 'float-colors')[0][1:]}
        self.assertEqual(fields, {'color', '#:color-space', '#:style', '#:stroke-width',
                                  '#:antialias?'})
        self.assertIn("does not accept its complete keyword set", self.text('float-colors'))

    def test_float_gradient_stop_keyword_and_strict_rounding_rule(self):
        text = ' '.join(self.text('float-colors').split())
        self.assertIn('strictly increasing after binary32 conversion', text)
        self.assertIn('two distinct Racket numbers that round to the same stop are rejected', text)
        for name in FLOAT_COLOR_EXPORTS:
            if 'gradient' not in name:
                continue
            fields = {f[0] for f in self.header(name, 'float-colors')[0][1:]}
            self.assertIn('#:stops', fields)
            self.assertNotIn('#:positions', fields)

    def test_extended_RGB_is_not_accidentally_narrowed_to_drawing_scalars(self):
        h = self.header('make-color4f', 'float-colors')
        self.assertEqual(h[0][1:], [['red', 'real?'], ['green', 'real?'],
                                  ['blue', 'real?'], ['alpha', 'real?', '1']])
        text = ' '.join(self.text('float-colors').split())
        self.assertIn('does not round the stored RGB to binary32', text)
        self.assertIn('After conversion to an inexact Racket number, alpha', text)
        self.assertIn('not multiplied by alpha', text)

    def test_byte_quantization_is_not_color_conversion(self):
        text = ' '.join(self.text('float-colors').split())
        self.assertIn('floor(255 v + 0.5)', text)
        self.assertIn('not a color-space conversion', text)
        h = self.header('color4f->rgba', 'float-colors')
        self.assertEqual(h[0][2], ['#:out-of-range', 'policy',
                                  ['or/c', ['quote', 'error'], ['quote', 'clip']],
                                  ['quote', 'error']])

    def test_transfer_constructor_and_evaluation_have_distinct_rounding(self):
        text = ' '.join(self.text('color-management').split())
        self.assertIn('does not require the two branches to meet continuously', text)
        self.assertIn('without first rounding @racket[x] to binary32', text)
        self.assertEqual(self.header('transfer-function-evaluate', 'color-management')[0][2],
                         ['x', ['real-in', '0', '3.402823e38']])

    def test_named_transfer_and_gamut_domains_are_distinct_finite_sets(self):
        transfer = self.header('named-transfer-function', 'color-management')[0][1][1]
        gamut = self.header('named-xyz-d50', 'color-management')[0][1][1]
        self.assertEqual(transfer, ['or/c', *[['quote', x] for x in
                                            ('srgb', 'linear', 'gamma-2.2', 'rec2020')]])
        self.assertEqual(gamut, ['or/c', *[['quote', x] for x in
                                         ('srgb', 'adobe-rgb', 'display-p3', 'rec2020', 'xyz')]])

    def test_XYZ_is_row_major_and_native_even_for_detached_values(self):
        text = ' '.join(self.text('color-management').split())
        self.assertIn('row-major three-by-three', text)
        self.assertIn('not by an affine drawing matrix', text)
        self.assertIn('@racket[b] acts first', text)
        self.assertIn('Singular inputs are permitted for multiplication', text)
        self.assertIn('Native Skia is required', text)

    def test_chromaticity_tolerance_is_not_hidden_by_a_stricter_header(self):
        text = self.text('color-management')
        self.assertIn('x + y <= 1.000001', text)
        h = self.header('primaries->xyz-d50', 'color-management')
        for field in h[0][1:]:
            self.assertEqual(field[1], ['or/c', ['list/c', 'real?', 'real?'],
                                       ['vector/c', 'real?', 'real?']])

    def test_ICC_export_is_mutable_and_not_a_byte_preserving_round_trip(self):
        self.assertEqual(self.header('color-space->icc-bytes', 'color-management')[1], 'bytes?')
        text = ' '.join(self.text('color-management').split())
        self.assertIn('new mutable byte string containing an ICC v4', text)
        self.assertIn('not the original imported profile', text)
        self.assertIn('need not give bit-identical coefficients', text)
        self.assertIn('additional matrix/TRC restrictions', text)

    def test_descriptor_recognition_is_not_native_ICC_validation(self):
        text = ' '.join(self.text('color-management').split())
        self.assertIn('including for mutable ICC bytes and live color-space resources', text)
        self.assertIn('does not parse tag contents, load native Skia', text)
        self.assertEqual(self.header('color-space-descriptor?', 'color-management')[0][1],
                         ['v', 'any/c'])

    def test_image_conversion_documents_source_and_precision_restrictions(self):
        text = ' '.join(self.text('color-management').split())
        self.assertIn('untagged input requires an explicit open source color space', text)
        self.assertIn('Floating-point images are rejected', text)
        self.assertIn('stages eight-bit unpremultiplied RGBA samples', text)
        self.assertIn('GPU-dependent input is rejected', text)
        self.assertEqual(self.header('image-convert-color-space', 'color-management')[0][3],
                         ['#:source-color-space', 'source', ['or/c', 'color-space?', '#f'], '#f'])

    def test_crop_description_only_promises_an_output_region(self):
        text = ' '.join(self.text('image-filters').split())
        self.assertIn("crop constrains the filter node's output region", text)
        self.assertNotIn("bounds the filter node's processing", text)
        self.assertIn("Cropping a child before a blur", text)

    def test_lighting_constraints_are_shared_but_each_entry_links_to_them(self):
        text = self.text('image-filters')
        self.assertIn('@section[#:tag "skia-lighting-from-alpha"]{Lighting from Alpha}', text)
        self.assertEqual(text.count('Coefficient must be nonnegative'), 1)
        self.assertEqual(text.count('@secref["skia-lighting-from-alpha"]'), 6)
        self.assertIn('ranges apply after single-precision rounding', ' '.join(text.split()))

    def test_two_runtime_result_contracts_express_immutability(self):
        for name, kind in (('runtime-effect-source', 'string?'),
                           ('runtime-effect-uniform-bytes', 'bytes?')):
            self.assertEqual(self.header(name, 'runtime-effects')[1], ['and/c', kind, 'immutable?'])

    def test_pure_examples_use_real_evaluation_and_a_closed_public_module_evaluator(self):
        text = self.text('float-colors')
        blocks = [h for form, h, _ in checks.commands(text, recursive=True) if form == 'examples']
        self.assertEqual(len(blocks), 3)
        self.assertEqual(text.count('@close-eval[float-color-eval]'), 1)
        self.assertIn("(float-color-eval '(require skia/color4f skia/color))", text)
        self.assertNotIn('eval:alts', text)
        self.assertNotIn('eval:result', text)
        self.assertFalse(any(form == 'examples' for form, _, _ in
                             checks.commands(self.text('color-management'), recursive=True)))

    def test_native_acceptance_is_separate_and_wired_into_the_existing_runner(self):
        runner = (ROOT / 'tools/check-reference.py').read_text()
        for name, cases in (('reference-color-management-pure-test.rkt', 7),
                            ('reference-color-management-test.rkt', 11)):
            self.assertIn(name, runner)
            text = (ROOT / 'tools' / name).read_text()
            checks.Reader('(' + text.split('\n', 1)[1] + ')').read()
            self.assertEqual(text.count('(test-case '), cases)


class R3d1BindingScopeTests(unittest.TestCase):
    """Guard the two sibling-section source identities that produced 40 badlinks.

    These are source regressions, not an actual Scribble hyperlink-resolution test.
    The live --render probe and extracted-archive check remain publication gates.
    """

    affected = (
        ('color-management.scrbl', 'skia-xyz-d50', 'skia/color-space',
         ('named-xyz-d50', 'primaries->xyz-d50', 'make-rgb-color-space',
          'color-space-transfer-function', 'color-space-xyz-d50',
          'xyz-d50-concat', 'xyz-d50-invert')),
        ('float-colors.scrbl', 'skia-float-shaders', 'skia/float-colors',
         ('make-color4f-shader', 'make-linear-gradient-color4f-shader',
          'make-radial-gradient-color4f-shader', 'make-sweep-gradient-color4f-shader',
          'make-two-point-conical-gradient-color4f-shader')),
    )

    def section(self, filename, tag):
        text = (ROOT / checks.REFERENCE / filename).read_text()
        start = text.index('@section[#:tag "' + tag + '"]')
        following = re.search(r'(?m)^@section(?:\[|\{)', text[start + 1:])
        stop = start + 1 + following.start() if following else len(text)
        return text[start:stop]

    def test_every_affected_section_selects_the_public_source_binding(self):
        for filename, tag, module, names in self.affected:
            with self.subTest(section=tag):
                section = self.section(filename, tag)
                declaration = ('@(declare-exporting skia ' + module +
                               ' #:use-sources (' + module + '))')
                self.assertEqual(section.count(declaration), 1)
                self.assertEqual(section.count('@(declare-exporting'), 1)
                self.assertLess(section.index(declaration), section.index('@defproc['))
                defined = re.findall(r'(?m)^@defproc\[\(([^\s)]+)', section)
                self.assertEqual(set(defined), set(names))
                self.assertEqual(len(defined), len(names))

    def test_affected_source_modules_remain_in_for_label(self):
        for filename, _tag, module, _names in self.affected:
            with self.subTest(module=module):
                text = (ROOT / checks.REFERENCE / filename).read_text()
                require = text.split('@title', 1)[0]
                self.assertIn(module, require)
                self.assertIn('for-label', require)
                self.assertIn(' skia ', require)

    def test_canonical_export_manifest_and_probe_cover_the_twelve_names(self):
        manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        definitions = {row['name']: row for row in manifest['definitions']}
        probe = (ROOT / checks.REFERENCE / 'tests/links.scrbl').read_text()
        affected_count = 0
        for filename, tag, module, names in self.affected:
            for name in names:
                with self.subTest(name=name):
                    row = definitions[name]
                    self.assertEqual(row['canonical_module'], 'skia')
                    self.assertEqual(row['chapter'],
                                     'scribblings/reference/' + filename)
                    self.assertIn(module, row['exports'])
                    self.assertEqual(probe.count('@racket[' + name + ']'), 1)
                    prefix = module.removeprefix('skia/').replace('/', '-')
                    self.assertEqual(probe.count('@racket[' + prefix + ':' + name + ']'), 1)
                    affected_count += 1
        self.assertEqual(affected_count, 12)

    def test_rendered_review_uses_full_companion_and_binding_checks(self):
        driver = (ROOT / 'tools/check-reference.py').read_text()
        review_src = (ROOT / 'tools/reference_review.py').read_text()
        self.assertIn("run('reference-seed'", driver)
        self.assertIn('tutorial_xrefs.append(saved)', driver)
        self.assertIn("run('reference',", driver)
        self.assertIn("run('link-probe'", driver)
        self.assertIn("report['links'] = check_targets(", driver)
        self.assertIn('site, targets, smoke=probe / \'links.html\'', driver)
        self.assertIn('check_review_html(html,', review_src)
        self.assertIn('check_review_html(extracted_html,', review_src)



class R3eOutputSourceTests(unittest.TestCase):
    """Inspect authored output semantics; no native or rendered success is implied."""
    def text(self, name):
        return (ROOT / checks.REFERENCE / (name + '.scrbl')).read_text()

    def normalized(self, name):
        return ' '.join(self.text(name).split())

    def header(self, name):
        for file in (ROOT / checks.REFERENCE).glob('*.scrbl'):
            for form, header, _ in checks.commands(file.read_text(), recursive=True):
                if form == 'defproc' and header[0][0] == name:
                    return header
        self.fail('missing definition: ' + name)

    def test_added_output_call_shapes_match_independent_expectations(self):
        specs, _ = checks.document_definitions(ROOT)
        by_name = {s['name']: s for s in specs}
        self.assertEqual(len(OUTPUT_PROCEDURES), 70)
        for name, (mask, keywords) in OUTPUT_PROCEDURES.items():
            with self.subTest(name=name):
                self.assertEqual(by_name[name]['arity_mask'], str(mask))
                self.assertEqual(by_name[name]['allowed_keywords'], sorted(keywords))
                self.assertEqual(by_name[name]['required_keywords'], [])
        for name in OUTPUT_PARAMETERS:
            self.assertEqual(by_name[name]['kind'], 'parameter')
        self.assertEqual(by_name['with-document-page']['kind'], 'syntax')

    def test_public_module_families_are_complete_and_not_private_paths(self):
        manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        for module, names in [('skia/pictures', PICTURE_EXPORTS),
                              ('skia/output', OUTPUT_EXPORTS),
                              ('skia/annotations', ANNOTATION_EXPORTS)]:
            actual = {r['name'] for r in manifest['definitions'] if module in r['exports']}
            self.assertEqual(actual, set(names))
        self.assertFalse(any('private/' in mod for row in manifest['definitions']
                             for mod in row['exports']))

    def test_new_source_declarations_cover_whole_chapters_not_only_siblings(self):
        for chapter, module in [('pictures', 'pictures'), ('output-pages', 'output'),
                                ('annotations', 'annotations')]:
            text = self.text(chapter)
            declaration = ('@(declare-exporting skia skia/' + module +
                           ' #:use-sources (skia/' + module + '))')
            self.assertIn(declaration, text)
            self.assertLess(text.index(declaration), text.index('@section'))
            self.assertIn('skia/' + module, text.split('@title')[0])
            self.assertEqual(text.count('@(declare-exporting'), 1)

    def test_output_alias_probe_matches_actual_import_prefixes(self):
        text = (ROOT / checks.REFERENCE / 'tests/links.scrbl').read_text()
        for module, names in [('pictures', PICTURE_EXPORTS), ('output', OUTPUT_EXPORTS),
                              ('annotations', ANNOTATION_EXPORTS)]:
            self.assertIn('(prefix-in ' + module + ': skia/' + module + ')', text)
            for name in names:
                self.assertIn('@racket[' + module + ':' + name + ']', text)
                self.assertIn('@racket[' + name + ']', text)

    def test_picture_trust_is_explicit_and_not_a_sandbox_claim(self):
        text = self.normalized('pictures')
        self.assertIn('Do not load untrusted SKP data', text)
        self.assertIn('not a sandbox', text)
        self.assertIn('executable SkSL', text)
        for name in ('picture-from-bytes', 'picture-from-file'):
            field = next(f for f in self.header(name)[0][1:] if f[0] == '#:trusted?')
            self.assertEqual(field, ['#:trusted?', 'trusted?', 'boolean?', '#f'])

    def test_recording_metadata_is_not_ink_bounds_or_raster_allocation(self):
        text = self.normalized('pictures')
        self.assertIn('not an exact visible-ink bound', text)
        self.assertIn('origin is not translated to zero', text)
        self.assertIn('@racket[(* 4 width height)] byte-limit', text)
        self.assertIn('not a test that the native resource remains open', text)

    def test_skp_size_overrides_do_not_recenter_commands(self):
        text = self.normalized('pictures')
        self.assertIn('Both overrides must be given together', text)
        self.assertIn('not the recorded commands, cull rectangle, or coordinate origin', text)
        self.assertIn('R-tree recording', text)

    def test_picture_source_closes_the_previous_explicit_deferral(self):
        text = self.normalized('image-filters')
        self.assertIn('make-picture-image-filter', text)
        self.assertIn('not a fit-to-size transform', text)
        self.assertIn('ignores the dynamic source', text)
        self.assertEqual(self.header('make-picture-image-filter')[1], 'image-filter?')

    def test_pdf_page_macro_grammar_and_callback_values(self):
        text = self.text('pdf-documents')
        forms = [h for f, h, _ in checks.commands(text, recursive=True) if f == 'defform']
        self.assertEqual(forms, [[['with-document-page',
                                 ['canvas-id', 'document-expr', 'width-expr', 'height-expr'],
                                 'body', '...+']]])
        self.assertEqual(self.header('call-with-document-page')[1], 'any')
        self.assertIn('returns all of the callback', text)
        self.assertIn('whole document is aborted', self.normalized('pdf-documents'))

    def test_pdf_dimensions_quality_and_literal_metadata_defaults(self):
        header = self.header('make-pdf-document')
        fields = {f[0]: f for f in header[0][1:]}
        self.assertEqual(fields['#:creator'][-1], 'skia-for-racket')
        self.assertEqual(fields['#:producer'][-1], 'Skia/PDF m119; skia-for-racket')
        self.assertEqual(fields['#:encoding-quality'][-2:], [['integer-in', '0', '101'], '101'])
        self.assertEqual(fields['#:creation-date'][-1], '#f')
        self.assertEqual(self.header('document-begin-page!')[0][2][1],
                          ['real-in', '1/1000', '14400'])

    def test_pdfa_is_not_an_arbitrary_profile_or_conformance_certificate(self):
        text = self.normalized('pdf-documents')
        self.assertIn('sRGB output intent', text)
        self.assertIn('not a caller-selected ICC profile', text)
        self.assertIn('not a PDF/A conformance validation', text)
        self.assertIn('UUID prevents a promise of byte-identical', text)

    def test_pdf_and_svg_finalize_and_release_are_distinct(self):
        pdf = self.normalized('pdf-documents')
        svg = self.normalized('svg-documents')
        self.assertIn('beginning another page does not revive an old canvas', pdf)
        self.assertIn('without releasing the document', pdf)
        self.assertIn('requires the native resource to remain open', pdf)
        self.assertIn('an SVG with no drawing commands may be finished', svg)
        self.assertIn('does not finalize it implicitly', svg)

    def test_document_byte_results_are_independent_mutable_copies(self):
        for name in ('picture->bytes', 'document->pdf-bytes', 'svg-document->bytes',
                     'call-with-pdf-bytes', 'call-with-svg-bytes', 'output->bytes'):
            self.assertEqual(self.header(name)[1], ['and/c', 'bytes?', ['not/c', 'immutable?']])

    def test_file_helpers_freeze_destinations_and_publish_completed_files(self):
        for chapter in ('pictures', 'pdf-documents', 'svg-documents'):
            text = self.normalized(chapter)
            self.assertIn('parent', text)
            self.assertRegex(text, r'rename(?:d only after|s it only after)')
        for chapter in ('pdf-documents', 'svg-documents'):
            self.assertIn('current-directory', self.text(chapter))
            self.assertIn('before', self.text(chapter))

    def test_page_unit_and_margin_examples_check_actual_results(self):
        text = self.normalized('output-pages')
        self.assertIn('left, top, right, bottom order', text)
        self.assertIn('not CSS order', text)
        self.assertIn('96 pixels per inch', text)
        self.assertIn('(eval:check (unit->points 127/5 \'mm) 72)', text)
        self.assertIn('without subtracting margins', text)
        self.assertIn("not points", text)

    def test_output_format_restrictions_are_not_ignored_options(self):
        text = self.normalized('output-pages')
        self.assertIn('These are rejected options, not ignored', text)
        self.assertIn('SVG requires exactly one page', text)
        self.assertIn('not inferred from the filename suffix', text)
        self.assertIn('Automatic text mode selects', text)

    def test_page_callbacks_differ_from_picture_playback(self):
        self.assertIn('Exporting it invokes the callback again', self.normalized('output-pages'))
        self.assertIn('does not call the Racket function that originally recorded them',
                      self.normalized('pictures'))
        self.assertIn('temporary translation and scale are restored', self.normalized('pictures'))

    def test_fallback_has_explicit_bounds_scope_and_gpu_exclusion(self):
        text = self.normalized('output-pages')
        for phrase in ('does not inherit', 'ceilings of the padded extents',
                       'GPU-surface target is rejected', 'callback canvas must not be retained',
                       'failed callback does not draw the final snapshot'):
            self.assertIn(phrase, text)
        field = next(f for f in self.header('draw-rasterized')[0][1:] if f[0] == '#:scale')
        self.assertEqual(field[-1], ['current-raster-output-scale'])

    def test_annotation_names_are_document_scoped_and_checked_when_invisible(self):
        text = self.normalized('annotations')
        self.assertIn('scoped to the whole PDF document', text)
        self.assertIn('Zero-size and fully clipped references are still checked', text)
        self.assertIn('case-sensitive', text)
        self.assertIn('Picture recording rejects named links', text)

    def test_annotation_urls_and_identifier_encoding_have_distinct_roles(self):
        text = self.normalized('annotations')
        self.assertIn('Validation does not access the network', text)
        self.assertIn('valid percent escapes', text)
        self.assertIn('not a registered destination', text)
        self.assertIn('(eval:check (destination-id "A") "dest-41")', text)

    def test_native_tests_are_separate_and_wired_into_acceptance(self):
        runner = (ROOT / 'tools/check-reference.py').read_text()
        for name, count in [('reference-output-pure-test.rkt', 13),
                            ('reference-output-test.rkt', 18)]:
            source = (ROOT / 'tools' / name).read_text()
            self.assertIn('tools/' + name, runner)
            self.assertEqual(source.count('(test-case '), count)
            checks.Reader('(' + source.split('\n', 1)[1] + ')').read()
        for chapter in ('pictures', 'pdf-documents', 'svg-documents'):
            self.assertNotIn('@examples', self.text(chapter))

    def test_render_gate_is_required_even_without_archive_publication(self):
        runner = (ROOT / 'tools/check-reference.py').read_text()
        gate = "report['reference_html'] = check_review_html("
        self.assertIn(gate, runner)
        self.assertLess(runner.index(gate), runner.index("report['status'] = 'passed'"))
        self.assertLess(runner.index(gate), runner.index('if args.review_zip:',
                                                        runner.index(gate)))
        self.assertIn('reference_html_checked=False', runner)


class R3e1EditorialTests(unittest.TestCase):
    """Check the revised specification and real-macro test setup, not Racket execution."""

    def test_page_form_prose_uses_the_documented_binding_identifier(self):
        text = (ROOT / checks.REFERENCE / 'pdf-documents.scrbl').read_text()
        start = text.index('@defform[(with-document-page')
        end = text.index('@defproc[', start)
        entry = ' '.join(text[start:end].split())
        self.assertIn("@racket[canvas-id] bound to the page's canvas in @racket[body]", entry)
        self.assertNotIn('@racket[canvas]', entry)
        self.assertIn('body must be nonempty and end with an expression', entry)
        self.assertIn('internal definitions and return multiple values', entry)
        self.assertIn('page protection, abort-on-escape, and lifetime rules', entry)

    def test_gpu_annotation_classification_links_to_the_execution_query(self):
        text = (ROOT / checks.REFERENCE / 'annotations.scrbl').read_text()
        start = text.index('@defproc[(canvas-annotation-backend')
        end = text.index('@defproc[', start + 1)
        entry = ' '.join(text[start:end].split())
        self.assertIn("GPU-surface canvases are also classified as @racket['raster]", entry)
        self.assertIn('do not produce document annotations', entry)
        self.assertIn("independent of the surface's rendering backend", entry)
        self.assertIn('@racket[canvas-execution-backend]', entry)
        self.assertIn('Unsupported specialized canvases raise an exception', entry)

    def test_expansion_helper_uses_the_public_macro_without_a_substitute_transformer(self):
        text = (ROOT / 'tools/reference-output-pure-test.rkt').read_text()
        forms = checks.Reader('(' + text.split('\n', 1)[1] + ')').read()
        imports = [form for form in forms if form and form[0] == 'require']
        self.assertTrue(any('skia' in form for form in imports))
        self.assertIn(['define-namespace-anchor', 'expansion-anchor'], forms)
        helper = next(form for form in forms if form[:2] ==
                      ['define', ['expand-page-form', 'form']])
        self.assertEqual(helper[2], [
            'parameterize', [['current-namespace',
                              ['namespace-anchor->namespace', 'expansion-anchor']]],
            ['expand', ['datum->syntax', '#f', 'form']]])
        self.assertNotIn('(define-syntax', text)
        self.assertNotIn('(eval ', text)
        runner = (ROOT / 'tools/check-reference.py').read_text()
        self.assertIn("run('output-pure-tests'", runner)
        self.assertIn("ROOT / 'tools/reference-output-pure-test.rkt'", runner)

    def test_expansion_cases_cover_valid_bodies_empty_bodies_and_binding_errors(self):
        text = (ROOT / 'tools/reference-output-pure-test.rkt').read_text()
        forms = checks.Reader('(' + text.split('\n', 1)[1] + ')').read()
        module = next(form for form in forms if form[:2] == ['module+', 'test'])
        cases = [form for form in module[2:] if form and form[0] == 'test-case'
                 and str(form[1]).startswith('page macro ')]
        self.assertEqual(len(cases), 4)

        def nodes(form):
            if isinstance(form, list):
                yield form
                for child in form:
                    yield from nodes(child)

        self.assertEqual(sum(node[:1] == ['check-not-exn']
                             for case in cases for node in nodes(case)), 2)
        errors = [node for case in cases for node in nodes(case)
                  if node[:1] == ['check-exn']]
        self.assertEqual(len(errors), 3)
        self.assertTrue(all(node[1] == 'exn:fail:syntax?' for node in errors))
        calls = [node for case in cases for node in nodes(case)
                 if node[:1] == ['expand-page-form']]
        self.assertEqual(len(calls), 5)
        self.assertTrue(all(call[1][0] == 'quote' for call in calls))
        quoted_forms = [call[1][1] for call in calls]
        self.assertIn(['with-document-page', ['canvas', '#f', '20', '10']], quoted_forms)
        self.assertIn(['with-document-page', ['canvas', '#f', '20', '10'],
                       ['define', 'saved', 'canvas']], quoted_forms)
        self.assertIn(['with-document-page', ['42', '#f', '20', '10'], ['void']], quoted_forms)
        self.assertIn('body expression ran', text)
        self.assertIn('document expression ran', text)
        self.assertIn('width expression ran', text)
        self.assertIn('height expression ran', text)



class R3fStreamCodecTests(unittest.TestCase):
    """Authored semantics and call shapes; no native/render execution is implied."""
    chapters = ('streams', 'live-streams', 'codecs', 'pixel-descriptions',
                'scanline-codecs', 'incremental-codecs')

    def text(self, chapter):
        return (ROOT / checks.REFERENCE / (chapter + '.scrbl')).read_text()

    def prose(self, chapter):
        return ' '.join(self.text(chapter).split())

    def header(self, name):
        for path in (ROOT / checks.REFERENCE).glob('*.scrbl'):
            for form, header, _ in checks.commands(path.read_text(), recursive=True):
                if form == 'defproc' and header[0][0] == name:
                    return header
        self.fail('missing R3f procedure: ' + name)

    def option(self, name, keyword):
        args = self.header(name)[0][1:]
        return next(arg for arg in args if isinstance(arg, list) and arg[0] == keyword)

    def test_all_added_call_shapes_match_independently_transcribed_expectations(self):
        definitions, _ = checks.document_definitions(ROOT)
        by_name = {row['name']: row for row in definitions}
        self.assertEqual(len(IO_PROCEDURES), 141)
        for name, (arity, keywords) in IO_PROCEDURES.items():
            with self.subTest(name=name):
                self.assertEqual(by_name[name]['arity_mask'], str(arity))
                self.assertEqual(by_name[name]['allowed_keywords'], sorted(keywords))
                self.assertEqual(by_name[name]['required_keywords'], [])

    def test_module_families_have_one_canonical_entry_per_binding(self):
        manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        for path, names in IO_MODULES.items():
            module = checks.public_module(path)
            rows = [row for row in manifest['definitions'] if module in row['exports']]
            expected = set(GB_MODULES.get(path, names))
            if path == 'image-info.rkt':
                expected.add('color-space-descriptor?')
            self.assertEqual({row['name'] for row in rows}, expected)
            self.assertEqual(len(rows), len(expected))
            self.assertTrue(all(row['canonical_module'] == 'skia' for row in rows))
        self.assertFalse(any('private/' in module for row in manifest['definitions']
                             for module in row['exports']))

    def test_new_canonical_and_alias_probes_are_present_exactly_once(self):
        probe = (ROOT / checks.REFERENCE / 'tests/links.scrbl').read_text()
        for name in IO_PROCEDURES:
            self.assertEqual(probe.count('@racket[' + name + ']'), 1, name)
        for path, names in IO_MODULES.items():
            module = checks.public_module(path)
            prefix = module.removeprefix('skia/').replace('/', '-')
            self.assertEqual(probe.count('(prefix-in ' + prefix + ': ' + module + ')'), 1)
            for name in names:
                self.assertEqual(probe.count('@racket[' + prefix + ':' + name + ']'), 1)

    def test_each_new_chapter_has_export_scope_and_public_for_label_imports(self):
        primary = {'streams': 'streams', 'live-streams': 'live-streams',
                   'codecs': None, 'pixel-descriptions': 'image-info',
                   'scanline-codecs': 'codec-scanlines',
                   'incremental-codecs': 'codec-incremental'}
        for chapter, module in primary.items():
            text = self.text(chapter)
            self.assertIn('for-label racket/base racket/contract skia', text)
            if module:
                declaration = ('@(declare-exporting skia skia/' + module +
                               ' #:use-sources (skia/' + module + '))')
                self.assertIn(declaration, text)
                self.assertLess(text.index(declaration), text.index('@defproc['))
                self.assertIn('skia/' + module, text.split('@title', 1)[0])

    def test_nested_source_modules_do_not_change_later_sibling_ownership(self):
        text = self.text('streams')
        start = text.index('@section[#:tag "skia-buffered-ports"]')
        stop = text.index('@section[#:tag "skia-stream-consumers"]')
        self.assertIn('@(declare-exporting skia skia/streams', text[start:stop])
        self.assertIn('@(declare-exporting skia skia/stream-inputs', text[stop:])
        codecs = self.text('codecs')
        start = codecs.index('@defmodule[skia/codec-queries')
        self.assertIn('#:use-sources (skia/codec-queries)', codecs[start:])
        pixels = self.text('pixel-descriptions')
        buffers = self.text('raster-buffers')
        self.assertNotIn('skia/raster-buffers', pixels)
        self.assertIn('#:use-sources (skia/raster-buffers)', buffers)

    def test_stream_zero_reads_and_positive_eof_are_distinguished(self):
        self.assertEqual(self.header('input-stream-read-bytes')[1],
                         ['or/c', 'bytes?', 'eof-object?'])
        text = self.prose('streams')
        self.assertIn('zero request returns an empty byte string', text)
        self.assertIn('positive request at end-of-input returns @racket[eof]', text)
        self.assertIn('requested count itself must fit the effective stream limit', text)

    def test_duplicate_and_fork_have_independent_cursors_and_native_owners(self):
        text = self.prose('streams')
        self.assertIn('independently owned input stream at position zero', text)
        self.assertIn("starts at the original stream's current position", text)
        self.assertIn('a fork is not a suffix-only stream', text)
        self.assertIn('not a promise of copied file contents', text)

    def test_detach_is_memory_only_resets_count_and_does_not_close_writer(self):
        text = self.prose('streams')
        self.assertIn('output remains open, empty, and reusable', text)
        self.assertIn('File output streams are rejected', text)
        self.assertIn('not a lifetime total across detach operations', text)
        self.assertEqual(self.header('output-stream->bytes')[1],
                         ['and/c', 'bytes?', ['not/c', 'immutable?']])

    def test_stream_limits_and_native_long_are_not_conflated(self):
        text = self.prose('streams')
        self.assertIn('smaller of the captured limit and the current byte limit', text)
        self.assertIn('whole stream length, not only the unread suffix', text)
        self.assertIn("platform's signed C @tt{long}", text)
        self.assertIn('not necessarily the same as the pointer-sized integer range', text)

    def test_file_writer_documents_immediate_truncation_and_nonatomic_failure(self):
        text = self.prose('streams')
        self.assertIn('create or truncate the destination immediately', text)
        self.assertIn('not atomic exclusive creation', text)
        self.assertIn('no durability guarantee is implied', text)
        self.assertIn('failed native write may have written a prefix', text)

    def test_buffered_ports_document_over_limit_probe_and_close_ownership(self):
        text = self.prose('streams')
        self.assertIn('one-byte probe', text)
        self.assertIn('@racket[(add1 limit)] bytes', text)
        self.assertIn('before entering that scope does not take ownership', text)
        self.assertIn('do not retain live port callbacks', text)

    def test_resource_stream_constructors_use_byte_zero_not_callers_cursor(self):
        text = self.prose('streams')
        self.assertIn("not from the caller's current cursor", text)
        self.assertIn('cursor unchanged, including on construction failure', text)
        self.assertIn('file-backed duplicate still requires a stable backing file', text)
        self.assertIn('@racket[#:trusted? #t]', text)

    def test_live_encoding_contracts_validate_inactive_options_and_integer_webp(self):
        for name in ('image->port', 'image-write-stream!'):
            self.assertEqual(self.option(name, '#:quality')[2], ['integer-in', '0', '100'])
            self.assertEqual(self.option(name, '#:png-compression')[2], ['integer-in', '0', '9'])
        text = self.prose('live-streams')
        self.assertIn('validate @emph{all} encoding options', text)
        self.assertIn('whose inactive options are ignored', text)
        self.assertIn('WebP quality accepts noninteger real values', text)

    def test_live_input_length_seekability_and_callback_constraints_are_explicit(self):
        text = self.prose('live-streams')
        self.assertIn('Seekable input requires an explicit length', text)
        self.assertIn('relative to the starting position', text)
        self.assertIn('Port callbacks must not re-enter live operations', text)
        self.assertIn('No persistent port-backed image or codec is returned', text)
        self.assertEqual(self.option('image-from-port', '#:normalize-origin?')[-1], '#t')

    def test_live_document_writers_record_once_and_do_not_promise_constant_memory(self):
        text = self.prose('live-streams')
        self.assertIn('callback runs once to record its page', text)
        self.assertIn('preflight failure writes no bytes', text)
        self.assertIn('not a constant-memory authoring guarantee', text)
        self.assertIn('There is no format argument', text)
        self.assertEqual(self.option('output->port', '#:policy')[2],
                         ['or/c', ['quote', 'report'], ['quote', 'error'], ['quote', 'vector-only']])

    def test_live_stream_failure_poisoning_is_not_successful_rollback(self):
        text = self.prose('live-streams')
        self.assertIn('make further use fail; close that stream instead of retrying', text)
        self.assertIn('partial', text)
        self.assertIn('exclusive', text)
        self.assertEqual(self.header('output-write-stream!')[1], 'exact-nonnegative-integer?')

    def test_still_frame_count_is_not_the_animation_metadata_count(self):
        text = self.prose('codecs')
        self.assertIn('one selectable frame', text)
        self.assertIn('still image commonly reports zero', text)
        self.assertEqual(self.header('codec-frame-info')[1], ['or/c', 'codec-frame-info?', '#f'])
        self.assertIn('invalid index', text)

    def test_frame_decode_uses_fresh_storage_and_does_not_return_partial_pixels(self):
        text = self.prose('codecs')
        self.assertIn('fresh buffer', text)
        self.assertIn('Calls need not be made in frame order', text)
        self.assertIn('premultiplied', text)
        self.assertIn('incomplete', text)
        self.assertIn('No scaling or subset negotiation is applied', text)

    def test_negotiation_and_orientation_are_not_resampling_or_subset_decoding(self):
        text = self.prose('codecs')
        self.assertIn('without resampling', text)
        self.assertIn('encoded coordinates', text)
        self.assertIn('contain', text)
        self.assertIn('strictly positive after binary32 rounding', text)
        self.assertEqual(self.header('codec-supported-subset')[1][0], 'or/c')

    def test_pixel_descriptions_have_zero_size_and_format_constraints(self):
        text = self.prose('pixel-descriptions')
        self.assertIn('Zero extents are accepted as descriptions', text)
        self.assertIn('RGBX, grayscale, and RGB565 require', text)
        self.assertIn('not full native profile support', text)
        self.assertIn('Mutable ICC bytes are accepted and copied', text)
        self.assertEqual(self.option('make-image-info', '#:color-space')[-1], '#f')

    def test_row_stride_example_is_evaluated_and_checks_final_padding(self):
        text = self.text('pixel-descriptions')
        examples = [header for form, header, _ in checks.commands(text, recursive=True)
                    if form == 'examples']
        self.assertEqual(len(examples), 1)
        self.assertIn('eval:check', str(examples))
        self.assertIn("'(16 28 32)", text)
        self.assertIn('@close-eval[pixel-eval]', text)
        self.assertIn("(pixel-eval '(require skia/image-info))", text)

    def test_decoded_buffers_are_not_views_of_native_decoder_storage(self):
        text = self.prose('raster-buffers')
        self.assertIn('independently owned image containing copied pixels', text)
        self.assertIn('no active canvas or pixmap scope', text)
        self.assertIn('does not change the image', text)
        self.assertIn('certify that incremental decoding was complete', text)

    def test_scanline_state_and_requested_vs_decoded_count_are_separate(self):
        text = self.prose('scanline-codecs')
        self.assertIn('requested', text)
        self.assertIn('decoded', text)
        self.assertIn('incomplete', text)
        self.assertIn('fill', text)
        self.assertEqual(self.header('scanline-batch-first-row')[1],
                         ['or/c', 'exact-nonnegative-integer?', '#f'])
        self.assertEqual(self.header('scanline-batch-bytes')[1], ['and/c', 'bytes?', 'immutable?'])

    def test_scanline_options_and_native_support_do_not_promise_fallback(self):
        text = self.prose('scanline-codecs')
        self.assertIn('bottom-up', text)
        self.assertIn('fallback', text)
        self.assertIn('first frame', text)
        self.assertEqual(self.option('codec-scanline-from-bytes', '#:alpha-type')[-1],
                         ['quote', 'unpremul'])
        self.assertEqual(self.option('codec-scanline-from-bytes', '#:color-space')[-1],
                         ['quote', 'srgb'])

    def test_incremental_destinations_are_restricted_without_port_callbacks(self):
        text = self.prose('incremental-codecs')
        self.assertIn('does not read a Racket port', text)
        self.assertIn('Floating-point destinations are not accepted', text)
        self.assertEqual(self.option('make-codec-incremental', '#:color-type')[2],
                         ['or/c', ['quote', 'rgba-8888'], ['quote', 'bgra-8888']])
        self.assertEqual(self.option('make-codec-incremental', '#:alpha-type')[2],
                         ['or/c', ['quote', 'premul'], ['quote', 'unpremul']])

    def test_incremental_png_visibility_is_not_accepted_byte_count(self):
        text = self.prose('incremental-codecs')
        self.assertIn('complete chunk boundaries', text)
        self.assertIn('Other formats are exposed only once', text)
        self.assertIn('visible input size nor final flag has changed', text)
        self.assertIn('not their combined heap budget', text)
        self.assertIn('not current allocation sizes', text)

    def test_incremental_final_input_and_completion_are_different(self):
        text = self.prose('incremental-codecs')
        self.assertIn('declaring final means no more input will arrive', text)
        self.assertIn('terminal @racket[\'incomplete] afterward', text)
        self.assertIn('A quota rejection leaves the retained prefix and final flag unchanged', text)
        self.assertIn('cancellation between steps', text)
        self.assertEqual(self.header('codec-incremental-feed!')[1], 'exact-nonnegative-integer?')

    def test_incremental_snapshot_progress_does_not_certify_complete_image(self):
        text = self.prose('incremental-codecs')
        self.assertIn('row report of @racket[#f] means unknown, not zero', text)
        self.assertIn('Interlaced decoding may revisit pixels', text)
        self.assertIn('snapshot can describe incomplete output', text)
        self.assertIn('remains valid after the session closes', text)
        self.assertEqual(self.header('incremental-snapshot-bytes')[1],
                         ['and/c', 'bytes?', 'immutable?'])

    def test_all_new_displayed_examples_are_native_tests_not_documentation_evaluation(self):
        native = []
        evaluated = []
        for chapter in self.chapters:
            for form, header, _ in checks.commands(self.text(chapter), recursive=True):
                if form == 'racketblock':
                    native.append(header)
                if form == 'examples':
                    evaluated.append(header)
        self.assertEqual(len(native), 10)
        self.assertEqual(len(evaluated), 1)
        for example in native:
            self.assertNotIn('eval:alts', str(example))
            self.assertNotIn('eval:result', str(example))

    def test_new_racket_suites_have_expected_cases_and_are_in_the_acceptance_runner(self):
        runner = (ROOT / 'tools/check-reference.py').read_text()
        for filename, expected in [('reference-io-pure-test.rkt', 14),
                                   ('reference-io-test.rkt', 21)]:
            text = (ROOT / 'tools' / filename).read_text()
            self.assertEqual(text.count('(test-case '), expected)
            self.assertIn("ROOT / 'tools/" + filename + "'", runner)
            self.assertNotIn('skip-test', text)
        self.assertIn("run('io-pure-tests'", runner)

    def test_no_new_tests_use_packaged_fonts_or_native_replacements(self):
        text = (ROOT / 'tools/reference-io-test.rkt').read_text()
        self.assertIn('(codec-scanline-from-bytes (bottom-up-bmp))', text)
        self.assertIn('(make-codec-incremental)', text)
        self.assertIn('(copy-port/streaming input output', text)
        self.assertIn('(output->port page output', text)
        for suffix in ('.ttf', '.otf', '.woff'):
            self.assertNotIn(suffix, text)
        self.assertNotIn('(define (codec-', text)
        self.assertNotIn('(define (input-stream-', text)

    def test_integer_range_contracts_use_exact_bounds_or_false(self):
        # Racket integer-in uses #f for an unbounded end, not +inf.0.
        def visit(form):
            if isinstance(form, list):
                if form[:1] == ['integer-in']:
                    yield form
                for child in form:
                    yield from visit(child)
        for name in IO_PROCEDURES:
            for contract in visit(self.header(name)):
                self.assertEqual(len(contract), 3)
                for bound in contract[1:]:
                    self.assertTrue(bound == '#f' or re.fullmatch(r'-?\d+', str(bound)), name)
        self.assertEqual(self.header('codec-repetition-count')[1], ['integer-in', '-1', '#f'])

    def test_required_review_gate_and_companions_remain_in_the_existing_path(self):
        runner = (ROOT / 'tools/check-reference.py').read_text()
        self.assertIn("report['reference_html'] = check_review_html(", runner)
        self.assertIn("run('reference-seed'", runner)
        self.assertIn('tutorial_xrefs.append(saved)', runner)
        self.assertIn("run('reference',", runner)
        self.assertIn('report[\'status\'] = \'passed\'', runner)
        self.assertIn('check_review_html(extracted_html,',
                      (ROOT / 'tools/reference_review.py').read_text())


class R3f1EditorialTests(unittest.TestCase):
    """Inspect actual source forms; native decoder assertions run separately in Racket."""

    def text(self, chapter):
        return (ROOT / checks.REFERENCE / (chapter + '.scrbl')).read_text()

    def header(self, name):
        return next(header for form, header, _ in checks.commands(self.text('codecs'))
                    if form == 'defproc' and header[0][0] == name)

    def test_frame_rectangle_result_contract_promises_immutability(self):
        self.assertEqual(self.header('codec-frame-info-rect'), [
            ['codec-frame-info-rect', ['info', 'codec-frame-info?']],
            ['and/c', ['vector/c', *(['exact-integer?'] * 4)], 'immutable?']])

    def test_subset_keeps_false_alternative_and_positive_immutable_extents(self):
        self.assertEqual(self.header('codec-supported-subset')[-1], [
            'or/c', '#f',
            ['and/c', ['vector/c', 'exact-integer?', 'exact-integer?',
                       'exact-positive-integer?', 'exact-positive-integer?'], 'immutable?']])

    def test_authored_channel_vectors_do_not_add_redundant_quotes(self):
        text = self.text('pixel-descriptions')
        for fields in ('8 8 8 8', '8 8 8', '8', '5 6 5', '10 10 10 2'):
            self.assertIn('@racket[#(' + fields + ')]', text)
        self.assertNotIn("@racket['#(", text)
        # This change does not rewrite evaluated output or change its expressions.
        examples = [header for form, header, _ in checks.commands(text, recursive=True)
                    if form == 'examples']
        self.assertEqual(len(examples), 1)
        self.assertIn('eval:check', str(examples[0]))

    def test_introduction_is_short_and_preserves_module_and_navigation(self):
        text = self.text('reference')
        intro = text[:text.index('@local-table-of-contents[]')]
        self.assertEqual(intro.count('@defmodule[skia]'), 1)
        self.assertIn("@(documentation-navigation-band 'reference #:index? #t)", intro)
        self.assertIn('The Skia package for Racket is an independent interface', intro)
        self.assertNotIn('docs/API.md', intro)
        self.assertIn('@seclink["top" #:doc', intro)
        self.assertIn('skia/scribblings/tutorials/index.scrbl', intro)
        self.assertEqual(text.count('@include-reference-section['), 13)
        self.assertIn('@(decorate-reference-index (index-section))', text)

    def test_bottom_up_example_is_self_contained_and_uses_the_native_test_fixture(self):
        text = self.text('scanline-codecs')
        at = text.index('@defproc[(scanline-batch-first-row')
        end = text.index('@defproc[(scanline-batch-requested-count', at)
        entry = text[at:end]
        blocks = [header for form, header, _ in checks.commands(entry, recursive=True)
                  if form == 'racketblock']
        self.assertEqual(len(blocks), 1)
        native = (ROOT / 'tools/reference-io-test.rkt').read_text()
        fixture = checks.Reader(native, native.index('(define (bottom-up-bmp)')).read()
        self.assertEqual(blocks[0][0], fixture)
        example = str(blocks[0][1])
        for fragment in ('codec-scanline-from-bytes', 'bottom-up-bmp',
                         'define', 'lower-batch', 'upper-batch',
                         'scanline-batch->raster-buffer', 'raster-buffer->image',
                         'scanline-batch-first-row'):
            self.assertIn(fragment, example)
        self.assertIn("@racket['(1 0)]", entry)
        self.assertIn('rows 1, 2, 0', entry)
        self.assertNotIn('@examples', entry)

    def test_native_regressions_check_immutable_metadata_and_pixel_placement(self):
        text = (ROOT / 'tools/reference-io-test.rkt').read_text()
        self.assertIn('(check-true (immutable? rectangle))', text)
        self.assertIn('(codec-frame-info codec 1)', text)
        self.assertIn('(vector-set! rectangle 0 7)', text)
        self.assertIn('(when subset', text)
        self.assertIn('(check-true (immutable? subset))', text)
        self.assertIn('(check-equal? assembled expected)', text)
        self.assertIn('(* 8 (scanline-batch-first-row batch))', text)
        self.assertIn('(check-not-equal? (bytes-append (scanline-batch-bytes lower-batch)', text)
        self.assertEqual(text.count('(test-case '), 21)

    def test_tutorial_references_are_preserved_for_integrated_publication(self):
        manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        references = {}
        for chapter in ('reference', 'paints', 'encoding'):
            for form, header, _ in checks.commands(self.text(chapter), recursive=True):
                if form == 'seclink' and '#:doc' in header:
                    document = header[header.index('#:doc') + 1]
                    references[document[1][1]] = header[0]
        for row in manifest['tutorial_links']:
            self.assertEqual(references['skia/' + row['manual']], row['tag'])
        notes = (ROOT / 'docs/REFERENCE-DEVELOPMENT.md').read_text()
        self.assertIn('## Reference-only editing previews', notes)
        self.assertIn('tools/reference-render.rkt +m --htmls', notes)
        self.assertIn('No export paths are\ndeferred.', notes)



class R3gaGeometryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        cls.definitions, cls.chapters = checks.document_definitions(ROOT)
        cls.by_name = {d['name']: d for d in cls.definitions}

    def text(self, name):
        return (ROOT / checks.REFERENCE / name).read_text()

    def header(self, name):
        chapter = ROOT / self.by_name[name]['chapter']
        for form, header, _ in checks.commands(chapter.read_text()):
            if form == 'defproc' and header[0][0] == name:
                return header
        self.fail('missing procedure: ' + name)

    def test_ten_selected_modules_have_complete_documented_export_sets(self):
        for path, names in GA_MODULES.items():
            module = checks.public_module(path)
            found = {d['name'] for d in self.manifest['definitions'] if module in d['exports']}
            with self.subTest(module=module):
                self.assertEqual(found, set(names))

    def test_fixture_call_boundaries_match_authored_declarations(self):
        self.assertEqual(len(GA_PROCEDURES), 188)
        for name, (arity, keywords) in GA_PROCEDURES.items():
            with self.subTest(name=name):
                spec = self.by_name[name]
                self.assertEqual(spec['arity_mask'], str(arity))
                self.assertEqual(spec['allowed_keywords'], keywords)
                self.assertEqual(spec['required_keywords'], [])
        self.assertEqual(set(GA_CONSTANTS), {'matrix3-identity', 'matrix4-identity'})
        self.assertEqual(set(GA_PARAMETERS), {'current-path-operation-limit'})
        self.assertEqual(set(GA_SYNTAX), {'with-canvas-layer', 'with-canvas-matrix'})

    def test_new_chapters_and_aggregate_counts_are_explicit(self):
        self.assertEqual(len(self.definitions), 1263)
        self.assertEqual(sum(len(d['exports']) for d in self.manifest['definitions']), 1988)
        self.assertEqual(len(self.chapters) - 1, 84)
        self.assertEqual(self.manifest['stage'], 'R4g')
        for chapter in ('rounded-rectangles', 'regions', 'projective-matrices',
                        'structured-drawing', 'portable-drawing', 'layers',
                        'drawables', 'specialized-canvases'):
            self.assertIn(f'scribblings/reference/{chapter}.scrbl', self.chapters)

    def test_r4_presentation_and_dc_integration_are_both_present(self):
        self.assertIn('gpu-presenter-render!', self.by_name)
        self.assertIn('skia-canvas%', self.by_name)
        self.assertIn('skia-dc%', self.by_name)
        self.assertNotIn('deferred_policy', self.manifest)

    def test_projective_conversion_does_not_promise_lossless_projection(self):
        text = self.text('projective-matrices.scrbl')
        for phrase in ('row-major', 'rightmost', 'binary32', 'lossless', 'lossy',
                       'strict sign', 'No depth buffer', 'negative divisor'):
            self.assertIn(phrase, text)
        self.assertEqual(self.header('matrix4->matrix3')[1], ['or/c', 'matrix3?', '#f'])
        self.assertEqual(self.header('matrix4-project-xy')[1], 'matrix3?')

    def test_matrix_result_vectors_and_failure_alternatives_are_explicit(self):
        for name in ('matrix3-map-point', 'matrix3-map-rect', 'matrix4-map-point',
                     'matrix4-map-homogeneous', 'matrix4-map-rect'):
            result = self.header(name)[1]
            self.assertEqual(result[:2], ['or/c', '#f'])
            self.assertEqual(result[2][0], 'and/c')
            self.assertIn('immutable?', result[2])
        self.assertEqual(self.header('matrix3->vector')[1], ['and/c', 'vector?', 'immutable?'])

    def test_macro_grammars_use_expression_metavariables_and_nonempty_bodies(self):
        for chapter, name in (('layers.scrbl', 'with-canvas-layer'),
                              ('projective-matrices.scrbl', 'with-canvas-matrix')):
            found = [h[0] for f, h, _ in checks.commands(self.text(chapter))
                     if f == 'defform' and h[0][0] == name]
            self.assertEqual(len(found), 1)
            self.assertEqual(found[0][-2:], ['body', '...+'])
            self.assertIn('canvas-expr', found[0])
        pure = (ROOT / 'tools/reference-geometry-pure-test.rkt').read_text()
        self.assertIn('expand-geometry-form', pure)
        self.assertIn('exn:fail:syntax?', pure)

    def test_layer_options_do_not_turn_bounds_into_clips_or_cleanup_into_rollback(self):
        text = self.text('layers.scrbl')
        for phrase in ('not a canvas @tech{clip}',
                       'Use an explicit clip to restrict drawing to an exact region.',
                       'The clip, rather than the layer bound, excludes',
                       'An exception does not undo drawing in the layer',
                       'does not clear the target to transparent pixels'):
            self.assertIn(phrase, text)
        self.assertEqual(self.header('layer-options-flags')[1],
                         ['or/c', '0', '2', '4', '6', '16', '18', '20', '22'])

    def test_region_queries_distinguish_half_open_snapshots_and_quick_rejection(self):
        text = self.text('regions.scrbl')
        for phrase in ('Right and bottom edges are excluded', 'not proven disjoint',
                       'not when', 'device coordinates', 'Empty results are valid resources'):
            self.assertIn(phrase, text)
        self.assertEqual(self.header('region-spans')[1][-1][-1], 'immutable?')

    def test_vertex_metadata_has_an_explicit_post_closure_exception(self):
        text = self.text('structured-drawing.scrbl')
        for phrase in ('after explicit closure', 'without requiring its creating thread',
                       'not a readback', '65536', 'unsigned 16-bit', 'not the number of indices'):
            self.assertIn(phrase, text)

    def test_lattice_cells_and_portable_atlas_restrictions_are_separate(self):
        text = self.text('structured-drawing.scrbl')
        portable = self.text('portable-drawing.scrbl')
        self.assertIn('fractional source', text)
        self.assertIn('must have\ninteger coordinates', portable)
        self.assertIn('Colors require explicit cell types', text)
        self.assertEqual(self.header('image-grid-cell-color')[1], ['or/c', 'rgba?', '#f'])
        self.assertNotIn('#:paint', str(self.header('draw-atlas/portable')[0]))
        self.assertNotIn('#:blend-mode', str(self.header('draw-atlas/portable')[0]))

    def test_drawable_generation_is_not_an_editing_or_callback_api(self):
        text = self.text('drawables.scrbl')
        for phrase in ('callback count is 1', 'does not edit', 'process-local',
                       'independently owned', 'not a projective matrix'):
            self.assertIn(phrase, text)

    def test_specialized_canvases_preserve_borrowing_and_target_requirements(self):
        text = ' '.join(self.text('specialized-canvases.scrbl').split())
        for phrase in ('@tech{save count} 1', '1 and 64', 'distinct surfaces', 'alpha-8',
                       'cannot be used after the function returns or exits early', 'do not undo drawing',
                       'GPU surfaces must belong to the same GPU context',
                       'does not clear it automatically'):
            self.assertIn(phrase, text)

    def test_rewind_documentation_resets_fill_instead_of_inventing_preservation(self):
        text = self.text('paths.scrbl')
        self.assertIn('Native rewind resets the fill type to winding', text)
        native = (ROOT / 'tools/reference-geometry-test.rkt').read_text()
        self.assertIn("(check-equal? (path-fill-rule path) 'winding)", native)

    def test_each_new_chapter_declares_sources_at_the_required_scope(self):
        for chapter in ('rounded-rectangles', 'regions', 'structured-drawing',
                        'portable-drawing', 'layers', 'drawables', 'specialized-canvases'):
            text = self.text(chapter + '.scrbl')
            self.assertLess(text.index('declare-exporting'), text.index('@defproc'))
            if chapter == 'rounded-rectangles':
                self.assertNotIn('#:use-sources', text)
            else:
                self.assertIn('#:use-sources', text)
        text = self.text('projective-matrices.scrbl')
        at = text.index('{Canvas Matrix State}')
        end = text.index('@defproc[(canvas-matrix4', at)
        self.assertIn('#:use-sources (skia/canvas-matrix)', text[at:end])

    def test_pure_examples_use_public_modules_and_checked_results(self):
        for chapter, evaluator, module in (
            ('projective-matrices.scrbl', 'projective-eval', 'skia/projective-matrix'),
            ('portable-drawing.scrbl', 'grid-eval', 'skia/portable-drawing')):
            text = self.text(chapter)
            self.assertIn(f"({evaluator} '(require {module}))", text)
            self.assertIn(f'@examples[#:eval {evaluator}', text)
            self.assertIn('eval:check', text)
            self.assertIn(f'@close-eval[{evaluator}]', text)
            self.assertLess(text.index(f'@(define {evaluator}'), text.index('@title'))

    def test_displayed_examples_are_preserved_as_opt_in_native_execution(self):
        forms = [(f, h) for p in (ROOT / checks.REFERENCE).glob('*.scrbl')
                 for f, h, _ in checks.commands(p.read_text(), recursive=True)]
        self.assertEqual(sum(f == 'racketblock' for f, _ in forms), 316)
        self.assertEqual(sum(f == 'examples' for f, _ in forms), 25)
        text = (ROOT / 'tools/reference-native-test.rkt').read_text()
        self.assertIn('(in-range 2)', text)
        self.assertIn('run-displayed-examples', text)

    def test_native_and_pure_geometry_suites_are_connected_to_acceptance(self):
        runner = (ROOT / 'tools/check-reference.py').read_text()
        self.assertIn("run('geometry-pure-tests'", runner)
        for name in ('reference-geometry-pure-test.rkt', 'reference-geometry-test.rkt'):
            self.assertIn(name, runner)
            text = (ROOT / 'tools' / name).read_text()
            reader = checks.Reader(text, text.index('\n') + 1)
            while reader.position < len(text):
                reader.skip()
                if reader.position < len(text):
                    reader.read()

    def test_bottom_up_example_retains_the_two_batch_native_case(self):
        native = (ROOT / 'tools/reference-io-test.rkt').read_text()
        for call in ('(codec-scanline-read! session 2)', '(codec-scanline-read! session 1)',
                     '(scanline-batch-first-row lower-batch)', '(1 0)',
                     'check-not-equal? (bytes-append'):
            self.assertIn(call, native)

    def test_new_scope_keeps_actual_pinned_inventory_hashes(self):
        expected = {row['file']: row['git_blob'] for row in self.manifest['snapshots']}
        self.assertEqual(expected, {
            'api/public-api-headless.json': 'bd5bb2a178dacf491b9c5e2b045592c69f0f2a1d',
            'api/public-api-gui.json': '1221794e26e099b8ca38110f4a42564f6b38f8f6'})


class R3gbRasterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        cls.definitions, cls.chapters = checks.document_definitions(ROOT)
        cls.by_name = {d['name']: d for d in cls.definitions}

    def text(self, name):
        return (ROOT / checks.REFERENCE / (name + '.scrbl')).read_text()

    def header(self, name):
        text = (ROOT / self.by_name[name]['chapter']).read_text()
        return next(h for f, h, _ in checks.commands(text)
                    if f == 'defproc' and h[0][0] == name)

    def test_selected_modules_have_complete_documented_exports(self):
        for path, names in GB_MODULES.items():
            module = checks.public_module(path)
            actual = {d['name'] for d in self.manifest['definitions'] if module in d['exports']}
            with self.subTest(module=module):
                self.assertEqual(actual, set(names))

    def test_new_call_boundaries_match_pinned_fixtures(self):
        self.assertEqual(len(GB_PROCEDURES), 157)
        for name, (arity, keywords) in GB_PROCEDURES.items():
            with self.subTest(name=name):
                entry = self.by_name[name]
                self.assertEqual(entry['arity_mask'], str(arity))
                self.assertEqual(entry['allowed_keywords'], keywords)
                self.assertEqual(entry['required_keywords'], GB_REQUIRED_KEYWORDS.get(name, []))
        self.assertEqual(GB_REQUIRED_KEYWORDS, {'image-apply-filter': ['clip']})

    def test_scope_counts_and_r4_completion_are_explicit(self):
        self.assertEqual(len(self.definitions), 1263)
        self.assertEqual(sum(len(d['exports']) for d in self.manifest['definitions']), 1988)
        self.assertEqual(len(self.chapters) - 1, 84)
        self.assertEqual(self.manifest['stage'], 'R4g')
        self.assertNotIn('deferred_policy', self.manifest)
        self.assertIn('gpu-presenter-render!', self.by_name)
        self.assertIn('skia-dc%', self.by_name)

    def test_every_main_export_is_accounted_for(self):
        # This is a pinned inventory check, not live reflection.
        exports = checks.load_exports(ROOT, self.manifest)
        actual = {name for module, phase, space, name in exports if module == 'skia'}
        documented = {d['name'] for d in self.manifest['definitions'] if 'skia' in d['exports']}
        self.assertEqual(actual, documented)

    def test_layer_grammar_has_five_options_and_no_repetition(self):
        h = next(h for f, h, _ in checks.commands(self.text('layers'))
                 if f == 'defform' and h[0][0] == 'with-canvas-layer')
        self.assertEqual(h[0], ['with-canvas-layer', 'canvas-expr', 'options', 'body', '...+'])
        grammar = h[h.index('#:grammar') + 1]
        self.assertEqual(grammar, [['options', 'code:blank',
            ['code:line', '#:bounds', 'bounds-expr'],
            ['code:line', '#:paint', 'paint-expr'],
            ['code:line', '#:bounds', 'bounds-expr', '#:paint', 'paint-expr'],
            ['code:line', '#:paint', 'paint-expr', '#:bounds', 'bounds-expr']]])

    def test_layer_grammar_has_real_expansion_tests(self):
        pure = (ROOT / 'tools/reference-raster-pure-test.rkt').read_text()
        for phrase in ('expand-layer', 'all five documented', 'duplicated layer options',
                       '#:paint #f #:paint #f', 'exn:fail:syntax?'):
            self.assertIn(phrase, pure)

    def test_source_review_inputs_include_every_reachable_chapter(self):
        hashes = review.source_hashes(ROOT, review_inputs=True)
        self.assertTrue(self.chapters <= set(hashes))
        for path in ('api/public-api-headless.json', 'api/public-api-gui.json',
                     'tools/check-reference.py', 'tools/reference_review.py',
                     'tools/reference_raster_cases.py', 'tools/reference-raster-test.rkt'):
            self.assertIn(path, hashes)
        for name in ('layers', 'specialized-canvases', 'rounded-rectangles', 'regions',
                     'structured-drawing', 'portable-drawing', 'projective-matrices', 'drawables'):
            self.assertIn('scribblings/reference/' + name + '.scrbl', hashes)

    def test_missing_old_or_new_include_target_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copytree(ROOT / checks.REFERENCE, root / checks.REFERENCE)
            for name in ('layers', 'raster-buffers'):
                path = root / checks.REFERENCE / (name + '.scrbl')
                before = path.read_bytes()
                path.unlink()
                with self.subTest(chapter=name):
                    with self.assertRaises((checks.CheckError, FileNotFoundError)):
                        checks.document_definitions(root)
                path.write_bytes(before)

    def test_real_inventory_files_remain_byte_pinned(self):
        for row in self.manifest['snapshots']:
            self.assertEqual(checks.git_blob((ROOT / row['file']).read_bytes()), row['git_blob'])

    def test_buffer_and_pixmap_storage_lengths_are_not_conflated(self):
        text = ' '.join(self.text('raster-buffers').split())
        for phrase in ('full allocation, including all row padding', 'Rows are tightly packed',
                       'input length must equal', 'at least the minimum byte length',
                       'new row padding stays zero'):
            self.assertIn(phrase, text)

    def test_borrowed_views_expire_without_changing_wrapper_predicates(self):
        text = ' '.join(self.text('raster-buffers').split())
        for phrase in ('including an expired wrapper', 'subsets expire on exit',
                       'creating thread', 'not pixel rollback', 'second canvas or pixmap scope'):
            self.assertIn(phrase, text)
        self.assertEqual(self.header('call-with-raster-buffer-pixmap')[1], 'any')

    def test_raw_samples_and_srgb_color_fills_are_distinguished(self):
        text = ' '.join(self.text('raster-buffers').split())
        for phrase in ('logical RGBA channel order', 'Premultiplied zero alpha requires zero RGB',
                       'including after storage rounding', 'unpremultiplied sRGB color',
                       'does not convert to sRGB'):
            self.assertIn(phrase, text)
        self.assertEqual(self.header('pixmap-sample')[1], ['and/c', 'vector?', 'immutable?'])

    def test_staged_conversion_and_direct_scaling_have_different_failure_guarantees(self):
        text = ' '.join(self.text('raster-buffers').split())
        self.assertIn('staged and validated before committing pixels', text)
        self.assertIn('writes through the native scaler directly', text)
        self.assertIn('does not promise that a failed native call', text)

    def test_image_materialization_does_not_hide_a_gpu_transfer(self):
        text = ' '.join(self.text('image-operations').split())
        self.assertIn('reject GPU-owned or texture-backed inputs', text)
        self.assertIn('F32 must remain F32', text)
        self.assertIn('16 bytes per pixel', text)
        self.assertIn('is not a content hash', text)

    def test_filtered_image_results_preserve_three_values_and_required_clip(self):
        result = self.header('image-apply-filter')[1]
        self.assertEqual(result[0], 'values')
        self.assertEqual(len(result), 4)
        self.assertIn('immutable?', result[2])
        self.assertIn('immutable?', result[3])
        self.assertEqual(self.by_name['image-apply-filter']['required_keywords'], ['clip'])
        text = ' '.join(self.text('image-operations').split())
        self.assertIn('not converted into an apparently successful empty image', text)

    def test_raw_shader_contract_does_not_advertise_cubic_sampling(self):
        header = self.header('make-raw-image-shader')
        fields = {x[0]: x for x in header[0][1:] if x[0].startswith('#:')}
        self.assertEqual(fields['#:sampling'][2], ['or/c', ['quote', 'nearest'], ['quote', 'linear']])
        self.assertEqual(fields['#:sampling'][3], ['quote', 'nearest'])
        self.assertIn('raw numeric samples', self.text('shaders'))

    def test_surface_property_flags_are_requests_not_hardware_evidence(self):
        text = ' '.join(self.text('surface-properties').split())
        for phrase in ('The flags record requests',
                       'reports the request, not whether it took effect',
                       'copy remains usable after the surface is released'):
            self.assertIn(phrase, text)
        self.assertEqual(self.header('surface-properties-flags')[1], ['integer-in', '0', '7'])

    def test_surface_properties_live_with_gpu_surfaces_but_remain_findable_for_raster(self):
        include = '@include-section["surface-properties.scrbl"]'
        gpu = self.text('gpu-rendering')
        self.assertEqual(gpu.count(include), 1)
        self.assertLess(gpu.index('@include-section["gpu-surfaces.scrbl"]'),
                        gpu.index(include))
        self.assertNotIn(include, self.text('surfaces-and-canvases'))
        self.assertIn('@secref["skia-surface-properties"]', self.text('surfaces'))
        self.assertIn('@racket[surface-properties-of]', self.text('surfaces'))
        self.assertIn('Accepts both raster surfaces and GPU surfaces',
                      ' '.join(self.text('surface-properties').split()))

    def test_audit_policies_distinguish_preflight_and_single_pass_publication(self):
        text = ' '.join(self.text('output-audit').split())
        for phrase in ('@deftech{output preflight} executes the callback', 'twice',
                       'side effects are not rolled back',
                       'default @racket[\'report]', 'does not truncate or replace'):
            self.assertIn(phrase, text)
        for name, value in [('output->bytes/audit', 'report'), ('save-output/audit', 'error')]:
            field = next(x for x in self.header(name)[0][1:] if x[0] == '#:policy')
            self.assertEqual(field[-1], ['quote', value])

    def test_group_policies_do_not_erase_unknowns_or_capture_receiver_backdrops(self):
        text = ' '.join(self.text('output-groups').split())
        for phrase in ('never reruns the Racket authoring code', 'isolated against transparency',
                       'unknown provenance', 'does not trigger a second authoring pass',
                       'device-coordinate region clips'):
            self.assertIn(phrase, text)
        field = next(x for x in self.header('draw-output-group')[0][1:]
                     if x[0] == '#:raster-executor')
        self.assertEqual(field[-1], '#f')

    def test_cache_setters_return_old_settings_and_have_process_scope(self):
        text = ' '.join(self.text('graphics').split())
        for phrase in ('previous setting', 'not bytes freed', 'not an atomic joint snapshot',
                       'while a live stream operation is active', 'not a hard cap'):
            self.assertIn(phrase, text)
        self.assertEqual(self.header('skia-set-font-cache-count-limit!')[1],
                         ['integer-in', '0', '2147483647'])

    def test_memory_report_fields_are_detached_and_bounded(self):
        text = ' '.join(self.text('graphics').split())
        for phrase in ('UTF-8 bytes', 'omitted and counted', 'second module instance or place',
                       'No application callback runs'):
            self.assertIn(phrase, text)
        for name in ('memory-statistic-name', 'memory-statistic-value-name'):
            self.assertEqual(self.header(name)[1], ['and/c', 'string?', 'immutable?'])

    def test_native_capability_queries_do_not_certify_acceleration(self):
        text = ' '.join(self.text('native-libraries').split())
        for phrase in ('active load/preflight attempt', 'flags for optional GPU symbol probing',
                       'hardware acceleration remain false', 'they are not invoked',
                       'not a runtime observation'):
            self.assertIn(phrase, text)

    def test_native_library_source_declarations_do_not_leak_into_sibling_sections(self):
        text = self.text('native-libraries')
        harfbuzz = text.split('@section{HarfBuzz Preflight}', 1)[1]
        harfbuzz = harfbuzz.split('@section{Installed ABI Catalogue}', 1)[0]
        self.assertIn('@(declare-exporting skia)', harfbuzz)
        self.assertNotIn('#:use-sources', harfbuzz)
        default = text.split('@subsection{Default Package}', 1)[1]
        default, queries = default.split('@subsection{Catalogue Queries}', 1)
        self.assertIn('@(declare-exporting skia)', default)
        self.assertIn('@defthing[native-package-version', default)
        self.assertIn('@(declare-exporting skia/native-capabilities', queries)
        self.assertIn('@defproc[(native-abi-catalog)', queries)

    def test_bitmap_results_are_racket_objects_with_a_separate_import_path(self):
        for name in ('image->bitmap', 'surface->bitmap'):
            self.assertEqual(self.header(name)[1], ['is-a?/c', 'bitmap%'])
            row = next(d for d in self.manifest['definitions'] if d['name'] == name)
            self.assertEqual(row['exports'], ['skia/bitmap', 'skia/racket-draw'])
        self.assertIn('not @racket[skia-close!]', ' '.join(self.text('image-operations').split()))

    def test_all_new_aliases_have_imports_and_link_probes(self):
        text = (ROOT / checks.REFERENCE / 'tests/links.scrbl').read_text()
        imports = dict(re.findall(r'\(prefix-in ([^\s]+) (skia/[^\s)]+)\)', text))
        modules = set(imports.values())
        for row in self.manifest['definitions']:
            if row['name'] not in {*GB_PROCEDURES, *GB_CONSTANTS, *GB_PARAMETERS, *GB_SYNTAX}:
                continue
            for module in row['exports']:
                prefix = '' if module == 'skia' else module[5:] + ':'
                self.assertIn('@racket[' + prefix + row['name'] + ']', text)
                if module != 'skia':
                    self.assertIn(module, modules)
                    self.assertEqual(imports[prefix], module)

    def test_new_pure_examples_have_closed_public_evaluators(self):
        for chapter, evaluator, module in (
            ('surface-properties', 'properties-eval', 'skia/surface-properties'),
            ('output-audit', 'policy-eval', 'skia/output-policy'),
            ('native-libraries', 'abi-eval', 'skia/native-capabilities')):
            text = self.text(chapter)
            self.assertIn(f"({evaluator} '(require {module}))", text)
            self.assertIn(f'@close-eval[{evaluator}]', text)
            self.assertIn('eval:check', text)
            self.assertLess(text.index('@(define ' + evaluator), text.index('@title'))

    def test_displayed_examples_remain_opt_in_native_code(self):
        forms = [f for p in (ROOT / checks.REFERENCE).glob('*.scrbl')
                 for f, _, _ in checks.commands(p.read_text(), recursive=True)]
        self.assertEqual(forms.count('racketblock'), 316)
        self.assertEqual(forms.count('examples'), 25)
        for name in ('raster-buffers', 'image-operations', 'graphics', 'output-groups'):
            self.assertNotIn('@examples', self.text(name))

    def test_racket_suites_are_balanced_and_connected_to_acceptance(self):
        runner = (ROOT / 'tools/check-reference.py').read_text()
        for name, expected in [('reference-raster-pure-test.rkt', 14),
                               ('reference-raster-test.rkt', 28)]:
            self.assertIn(name, runner)
            text = (ROOT / 'tools' / name).read_text()
            self.assertEqual(text.count('(test-case '), expected)
            reader = checks.Reader(text, text.index('\n') + 1)
            while reader.position < len(text):
                reader.skip()
                if reader.position < len(text):
                    reader.read()
        self.assertIn("run('raster-pure-tests'", runner)

    def test_native_tests_cover_transaction_lifetimes_and_group_single_execution(self):
        text = (ROOT / 'tools/reference-raster-test.rkt').read_text()
        for phrase in ('pixmap-width saved', 'failed full-rectangle image reads',
                       'pixmap-set-sample! view 0 0', 'exn:fail:output-audit?',
                       'output-group-report-pixel-size', 'readback_count',
                       'memory-statistics-scope',
                       'skia-native-symbol-inventory'):
            self.assertIn(phrase, text)

    def test_bottom_up_two_batch_acceptance_is_preserved(self):
        text = (ROOT / 'tools/reference-io-test.rkt').read_text()
        for phrase in ('codec-scanline-read! session 2', 'codec-scanline-read! session 1',
                       '(check-equal? assembled expected)', "'(1 0)"):
            self.assertIn(phrase, text)
        self.assertEqual(text.count('(test-case '), 21)


class R3gb1EditorialTests(unittest.TestCase):
    def text(self, name):
        return (ROOT / checks.REFERENCE / (name + '.scrbl')).read_text()

    def entry(self, name):
        text = self.text('graphics')
        header, start = next((h, at) for f, h, at in checks.commands(text)
                             if f == 'defproc' and h[0][0] == name)
        reader = checks.Reader(text, text.index('[', start))
        reader.read()
        end = checks.brace_end(text, reader.position)
        body = ' '.join(text[reader.position + 1:end - 1].split())
        return header, body

    def test_format_inventory_contracts_require_immutable_symbol_vectors(self):
        things = {h[0]: h[1] for f, h, _ in checks.commands(self.text('pixel-descriptions'))
                  if f == 'defthing'}
        for name in ('integer-pixel-formats', 'float-pixel-formats', 'pixel-formats'):
            with self.subTest(name=name):
                self.assertEqual(things[name], ['and/c', ['vectorof', 'symbol?'], 'immutable?'])

    def test_constant_reader_preserves_the_compound_contract_in_its_specification(self):
        contract = ['and/c', ['vectorof', 'symbol?'], 'immutable?']
        shape = checks.constant_shape(['pixel-formats', contract])
        self.assertEqual(shape, dict(name='pixel-formats', kind='value', arguments=[],
                                     value_kind='constant', value_contract=contract))
        self.assertNotIn('value_predicate', shape)
        self.assertNotIn('arity_mask', shape)

    def test_constant_reader_rejects_unreviewed_or_quoted_compound_forms(self):
        for contract in (['and/c', 'vector?', 'immutable?'],
                         ['and/c', ['vectorof', 'string?'], 'immutable?'],
                         ['and/c', ['vectorof', checks.String('symbol?')], 'immutable?'],
                         [checks.String('and/c'), ['vectorof', 'symbol?'], 'immutable?'],
                         ['quote', ['and/c', ['vectorof', 'symbol?'], 'immutable?']],
                         [], checks.String('vector?')):
            with self.subTest(contract=contract), self.assertRaises(checks.CheckError):
                checks.constant_shape(['pixel-formats', contract])

    def test_full_source_report_carries_all_three_compound_constant_contracts(self):
        report = checks.check_source(ROOT)
        for name in ('integer-pixel-formats', 'float-pixel-formats', 'pixel-formats'):
            entry = next(e for e in report['definitions'] if e['name'] == name)
            self.assertEqual(entry['value_contract'],
                             ['and/c', ['vectorof', 'symbol?'], 'immutable?'])
            self.assertEqual(entry['kind'], 'value')
            self.assertEqual(entry['exports'], ['skia', 'skia/image-info'])

    def test_runtime_reader_and_value_checker_share_the_tested_pure_submodule(self):
        text = (ROOT / 'tools/reference-runtime.rkt').read_text()
        self.assertIn('(module constant-contracts racket/base', text)
        self.assertIn('(record! (cadr datum) (constant-shape (caddr datum)))', text)
        self.assertIn('(constant-value-valid? spec (string->symbol module) value)', text)
        self.assertIn('(for/and ([element (in-vector value)]) (symbol? element))', text)
        for fragment in ('[(list?) list?]', '[(string?) string?]', '[(vector?) vector?]'):
            self.assertIn(fragment, text)
        pure = (ROOT / 'tools/reference-raster-pure-test.rkt').read_text()
        self.assertIn('(submod "reference-runtime.rkt" constant-contracts)', pure)
        self.assertIn('(constant-value-valid? spec \'skia/image-info formats)', pure)

    def test_count_queries_describe_entries_not_bytes(self):
        for name in ('skia-font-cache-count-used', 'skia-font-cache-count-limit'):
            with self.subTest(name=name):
                header, body = self.entry(name)
                self.assertEqual(header[1], ['integer-in', '0', '2147483647'])
                self.assertIn('number of font-cache entries', body)
                self.assertIn('does not purge', body)
                self.assertNotIn('byte', body.lower())
                self.assertNotIn('unsigned size type', body)

    def test_count_setter_returns_previous_count_limit_and_keeps_global_scope(self):
        header, body = self.entry('skia-set-font-cache-count-limit!')
        self.assertEqual(header, [
            ['skia-set-font-cache-count-limit!', ['limit', ['integer-in', '0', '2147483647']]],
            ['integer-in', '0', '2147483647']])
        for phrase in ('number of font-cache entries', 'previous count limit',
                       'not the current entry count', 'loaded library globally',
                       'restore a temporary change explicitly'):
            self.assertIn(phrase, body)
        self.assertNotIn('byte', body.lower())
        self.assertNotIn('unsigned size type', body)

    def test_byte_accessors_and_setters_keep_their_distinct_units(self):
        for name in ('skia-font-cache-used', 'skia-font-cache-limit',
                     'skia-resource-cache-used', 'skia-resource-cache-limit',
                     'skia-resource-cache-single-allocation-limit'):
            with self.subTest(name=name):
                header, body = self.entry(name)
                self.assertEqual(header[1], 'exact-nonnegative-integer?')
                self.assertIn('byte', body.lower())
                self.assertIn('unsigned size type', body)
        for name in ('skia-set-font-cache-limit!', 'skia-set-resource-cache-limit!',
                     'skia-set-resource-cache-single-allocation-limit!'):
            with self.subTest(name=name):
                _, body = self.entry(name)
                self.assertIn('previous setting', body)
                self.assertIn('bytes freed', body)
                self.assertIn('Byte limits must fit', body)

    def test_no_op_cache_example_is_removed_without_replacing_it(self):
        text = self.text('graphics')
        forms = [f for f, _, _ in checks.commands(text, recursive=True)]
        self.assertNotIn('racketblock', forms)
        self.assertNotIn('examples', forms)
        self.assertNotIn('(define before (skia-font-cache-limit))', text)
        self.assertNotIn('The setter returns the previous limit.', text)
        self.assertIn('@section[#:tag "skia-memory-statistics"]', text)

    def test_pure_suite_checks_real_constants_and_both_rejection_cases(self):
        text = (ROOT / 'tools/reference-raster-pure-test.rkt').read_text()
        for phrase in ('racket/contract', '(and/c (vectorof symbol?) immutable?)',
                       '(list integer-pixel-formats float-pixel-formats pixel-formats)',
                       '(contract formats/c formats', '(vector \'rgba-8888)',
                       '(vector-immutable 8)', '(check-pred symbol? format)'):
            self.assertIn(phrase, text)
        self.assertEqual(text.count('(test-case '), 14)
        runner = (ROOT / 'tools/check-reference.py').read_text()
        self.assertIn("run('raster-pure-tests'", runner)
        self.assertIn('reference-raster-pure-test.rkt', runner)




class R4aContextTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        cls.definitions, cls.chapters = checks.document_definitions(ROOT)
        cls.by_name = {row['name']: row for row in cls.definitions}

    def text(self, chapter):
        return (ROOT / checks.REFERENCE / (chapter + '.scrbl')).read_text()

    def header(self, name):
        path = ROOT / self.by_name[name]['chapter']
        return next(h for f, h, _ in checks.commands(path.read_text())
                    if f == 'defproc' and h[0][0] == name)

    def test_bounded_scope_counts_real_public_aliases_not_only_names(self):
        self.assertEqual(len(self.definitions), 1263)
        self.assertEqual(sum(len(d['exports']) for d in self.manifest['definitions']), 1988)
        self.assertEqual(len(self.chapters) - 1, 84)
        self.assertEqual(self.manifest['stage'], 'R4g')
        self.assertEqual(self.manifest['reviewed_repository_commit'],
                         '4dbbdcc3ab46d896ddd5f2c1de535ea2bab01cb1')
        self.assertEqual(len(R4A_PROCEDURES), 31)

    def test_gpu_chapters_precede_the_identifier_index(self):
        text = self.text('reference')
        group = self.text('gpu-rendering')
        self.assertTrue(text.rstrip().endswith('@(decorate-reference-index (index-section))'))
        self.assertIn('@include-reference-section["gpu-rendering.scrbl"]', text)
        for chapter in ('gpu-providers', 'gpu-context-options', 'gpu-contexts'):
            self.assertIn('@include-section["' + chapter + '.scrbl"]', group)

    def test_selected_gpu_exports_have_one_definition_and_no_main_alias(self):
        rows = [d for d in self.manifest['definitions'] if d['name'] in R4A_PROCEDURES]
        self.assertEqual(len(rows), 31)
        self.assertEqual(sum(len(d['exports']) for d in rows), 40)
        for row in rows:
            self.assertEqual(row['canonical_module'], 'skia/gpu')
            self.assertNotIn('skia', row['exports'])
            self.assertIn('skia/gpu', row['exports'])

    def test_context_options_module_is_completely_documented(self):
        found = {d['name'] for d in self.manifest['definitions']
                 if 'skia/gpu-context-options' in d['exports']}
        self.assertEqual(found, set(GPU_OPTION_EXPORTS))
        self.assertEqual(len(found), 9)

    def test_call_shapes_agree_with_independent_test_specifications(self):
        for name, (arity, keywords) in R4A_PROCEDURES.items():
            with self.subTest(name=name):
                spec = self.by_name[name]
                self.assertEqual(spec['arity_mask'], str(arity))
                self.assertEqual(spec['allowed_keywords'], keywords)
                self.assertEqual(spec['required_keywords'], R4A_REQUIRED_KEYWORDS.get(name, []))

    def test_backend_inventory_is_a_procedure_not_a_constant(self):
        self.assertEqual(self.header('gpu-backends')[0], ['gpu-backends'])
        self.assertEqual(self.by_name['gpu-backends']['kind'], 'procedure')
        self.assertEqual(self.by_name['gpu-backends']['arity_mask'], '1')

    def test_provider_requires_all_five_keywords(self):
        required = self.by_name['make-gpu-provider']['required_keywords']
        self.assertEqual(required, ['backend', 'call-as-current', 'current?', 'key', 'name'])
        header = self.header('make-gpu-provider')[0]
        key = next(row for row in header[1:] if row[0] == '#:key')
        self.assertEqual(key[2], ['or/c', 'symbol?', 'exact-positive-integer?'])

    def test_option_defaults_and_range_units_are_explicit(self):
        header = self.header('make-gpu-context-options')[0]
        args = {row[0]: row for row in header[1:]}
        self.assertEqual(args['#:runtime-program-cache-size'][2:],
                         [['integer-in', '1', '2147483647'], '256'])
        self.assertEqual(args['#:glyph-cache-texture-maximum-bytes'][2:],
                         [['integer-in', '1', '18446744073709551615'], '8388608'])
        self.assertEqual(args['#:buffer-map-threshold'][2:],
                         [['integer-in', '-1', '2147483647'], '-1'])
        self.assertEqual(args['#:allow-path-mask-caching?'][-1], '#t')
        self.assertEqual(args['#:manual-mipmapping?'][-1], '#f')
        self.assertEqual(args['#:avoid-stencil-buffers?'][-1], '#f')

    def test_context_signature_preserves_false_defaults_and_adapter_limit(self):
        header = self.header('make-gpu-context')[0]
        self.assertEqual(header[1], ['provider', ['or/c', 'gpu-provider?', '#f'], '#f'])
        args = {row[0]: row for row in header[2:]}
        self.assertEqual(args['#:adapter-index'][2:],
                         [['or/c', ['integer-in', '0', '4294967294'], '#f'], '#f'])
        self.assertEqual(args['#:backend'][-1], '#f')
        self.assertEqual(args['#:options'][-1], '#f')
        self.assertEqual(args['#:gl-interface'][-1], ['quote', 'default'])

    def test_all_interface_choices_and_no_different_standard_fallback_are_documented(self):
        text = ' '.join(self.text('gpu-contexts').split())
        for phrase in ('does not fall back to GLES or WebGL',
                       'They do not create a different kind of host',
                       'No failed hardware request silently falls back to WARP'):
            self.assertIn(phrase, text)
        args = self.header('make-gpu-context')[0]
        interface = next(row for row in args if isinstance(row, list) and row[0] == '#:gl-interface')
        self.assertEqual(interface[2], ['or/c', *[['quote', x] for x in
                                               ('default', 'auto', 'desktop', 'gles', 'webgl')]])

    def test_declarations_and_options_do_not_claim_runtime_probes(self):
        text = self.text('gpu-providers')
        for field in ('runtime_availability', 'native_probe_performed',
                      'hardware_acceleration_verified', 'performance_measured'):
            self.assertIn(field, text)
        self.assertIn('not-probed', text)
        self.assertIn('native-default factory', self.text('gpu-context-options'))
        self.assertIn('Neither route provides native readback of the effective options',
                      ' '.join(self.text('gpu-context-options').split()))

    def test_provider_contract_distinguishes_host_ownership_and_callback_obligations(self):
        text = ' '.join(self.text('gpu-providers').split())
        for phrase in ('exactly once, synchronously', 'creating thread',
                       'does not acquire or destroy the host',
                       'own return values do not replace them',
                       'Intercepting a callback failure', 'string and returns'):
            self.assertIn(phrase, text)
        self.assertIn('same key for the same host', text)
        self.assertIn('Other failures', self.text('gpu-contexts').replace('Other\nfailures',
                                                                       'Other failures'))

    def test_provider_diagnostics_exclude_symbols_vectors_and_native_pointers(self):
        text = ' '.join(self.text('gpu-providers').split())
        self.assertIn('Symbols as values, vectors, native pointers, and functions are not accepted',
                      text)
        self.assertIn('symbol keys', text)

    def test_same_context_nesting_and_expired_canvas_leases_are_explicit(self):
        text = ' '.join(self.text('gpu-contexts').split())
        for phrase in ('without reactivating the provider', 'Nesting a different context is rejected',
                       'inner scope expires', 'does not revive old canvases',
                       'does not restore the host', 'not pixel rollback'):
            self.assertIn(phrase, text)

    def test_shutdown_is_separate_from_state_and_allows_other_thread_requests(self):
        text = ' '.join(self.text('gpu-contexts').split())
        self.assertIn('request flag is separate', text)
        self.assertIn('called from another Racket thread', text)
        self.assertIn('GC and custodian', text)
        self.assertIn('dead owner', text)
        result = self.header('gpu-context-state')[1]
        self.assertNotIn(['quote', 'shutdown-requested'], result)
        self.assertIn(['quote', 'release-failed'], result)

    def test_healthy_teardown_and_lost_host_abandonment_are_not_conflated(self):
        text = ' '.join(self.text('gpu-contexts').split())
        for phrase in ('lost-host route', 'does not activate the provider',
                       'healthy-host release operation', 'Success leaves the context abandoned',
                       'neither this function, lost-host abandonment, nor normal closure'):
            self.assertIn(phrase, text)
        self.assertEqual(self.header('gpu-context-close!')[1], 'void?')
        self.assertEqual(self.header('gpu-drain-releases!')[1], 'exact-nonnegative-integer?')
        self.assertEqual(self.header('gpu-drain-pending-contexts!')[1],
                         ['listof', ['and/c', 'hash?', 'immutable?']])

    def test_context_information_is_detached_but_not_refreshed_native_state(self):
        self.assertEqual(self.header('gpu-context-info')[1], ['and/c', 'hash?', 'immutable?'])
        text = ' '.join(self.text('gpu-contexts').split())
        for phrase in ('construction-time diagnostics', 'requires no active scope or owning thread',
                       'does not activate the provider or refresh',
                       'not a count of every native allocation',
                       'initial cache measurements', 'shutdown_error'):
            self.assertIn(phrase, text)

    def test_gpu_examples_are_native_free_until_explicitly_called(self):
        examples, blocks = [], []
        for chapter in ('gpu-providers', 'gpu-context-options', 'gpu-contexts'):
            for form, header, _ in checks.commands(self.text(chapter), recursive=True):
                if form == 'examples':
                    examples.append(header)
                elif form == 'racketblock':
                    blocks.append(header)
        self.assertEqual(len(examples), 2)
        self.assertEqual(len(blocks), 1)
        self.assertEqual(blocks[0][0], ['require', 'skia/gpu'])
        self.assertEqual(blocks[0][1][0], 'define')
        self.assertEqual(blocks[0][1][1][0], 'call-with-new-gpu-context')
        self.assertEqual(len(blocks[0]), 2)  # No unguarded constructor invocation.
        for example in examples:
            def calls(value):
                if not isinstance(value, list):
                    return False
                return (bool(value) and value[0] == 'make-gpu-context'
                        or any(calls(child) for child in value))
            self.assertFalse(calls(example))
            self.assertNotIn('eval:alts', str(example))
            self.assertIn('eval:check', str(example))

    def test_export_declarations_match_canonical_modules_and_reexport_sources(self):
        self.assertIn('@defmodule[skia/gpu #:no-declare]', self.text('gpu-providers'))
        self.assertNotIn('@defmodule[skia/gpu', self.text('gpu-contexts'))
        self.assertIn('@(declare-exporting skia/gpu)', self.text('gpu-contexts'))
        self.assertIn('#:use-sources (skia/gpu-context-options)', self.text('gpu-context-options'))
        for chapter, evaluator in (('gpu-providers', 'backend-eval'),
                                   ('gpu-context-options', 'options-eval')):
            text = self.text(chapter)
            self.assertIn('@close-eval[' + evaluator + ']', text)
            self.assertLess(text.index('@(define ' + evaluator), text.index('@title'))

    def test_all_40_new_public_paths_appear_in_the_binding_probe(self):
        text = (ROOT / checks.REFERENCE / 'tests/links.scrbl').read_text()
        for module, names in R4A_MODULES.items():
            prefix = module.removesuffix('.rkt') + ':'
            self.assertIn('(prefix-in ' + prefix + ' skia/' + module.removesuffix('.rkt') + ')',
                          text)
            for name in names:
                self.assertIn('@racket[' + prefix + name + ']', text)

    def test_r4e_topics_are_now_documented_not_stubbed(self):
        self.assertIn('gpu-presenter-render!', self.by_name)
        self.assertIn('skia-render-window%', self.by_name)
        self.assertIn('skia-dc%', self.by_name)
        self.assertNotIn('deferred_policy', self.manifest)

    def test_racket_test_sources_parse_and_native_cases_belong_to_a_single_suite(self):
        for filename in ('reference-gpu-context-pure-test.rkt', 'reference-gpu-context-test.rkt'):
            text = (ROOT / 'tools' / filename).read_text()
            reader, forms = checks.Reader(text, text.index('\n') + 1), []
            while True:
                reader.skip()
                if reader.position == len(text):
                    break
                forms.append(reader.read())
            if filename.endswith('-pure-test.rkt'):
                tests = next(f[2:] for f in forms if f[:2] == ['module+', 'test'])
                self.assertEqual(len(tests), 22)
                self.assertTrue(all(f[0] == 'test-case' for f in tests))
            else:
                suite = next(f[2] for f in forms if f[:2] == ['define', 'suite'])
                self.assertEqual(len(suite[2:]), 10)
                self.assertTrue(all(f[0] == 'test-case' for f in suite[2:]))
                self.assertTrue(any(f[:2] == ['module+', 'main'] for f in forms))

    def test_state_machine_doubles_are_separate_from_native_acceptance(self):
        pure = (ROOT / 'tools/reference-gpu-context-pure-test.rkt').read_text()
        native = (ROOT / 'tools/reference-gpu-context-test.rkt').read_text()
        self.assertIn('fake-context-pointer', pure)
        self.assertIn('wrap-gpu-domain', pure)
        self.assertIn('release-failed', pure)
        self.assertNotIn('fake-context-pointer', native)
        self.assertNotIn('wrap-gpu-domain', native)
        self.assertIn('make-gpu-context #:backend', native)
        self.assertIn("'tests_run 10", native)
        self.assertIn("'pixel_validation_performed #f", native)
        self.assertIn("'hardware_acceleration_verified #f", native)

    def test_source_review_contains_every_new_checker_dependency(self):
        files = review.source_hashes(ROOT, review_inputs=True)
        for name in ('reference_gpu_context_cases.py', 'reference-gpu-context-pure-test.rkt',
                     'reference-gpu-context-test.rkt'):
            self.assertIn('tools/' + name, files)
        for name in ('gpu-providers', 'gpu-contexts', 'gpu-context-options'):
            self.assertIn('scribblings/reference/' + name + '.scrbl', files)
        self.assertIn('api/public-api-headless.json', files)
        self.assertIn('api/public-api-gui.json', files)


class R4aBuildPlanTests(unittest.TestCase):
    """Mocked subprocess/receipt tests. No real GPU or Racket is used here."""
    setUp = BuildPlanTests.setUp
    execute = BuildPlanTests.execute

    def run_fake(self, command, **options):
        result = BuildPlanTests.run_fake(self, command, **options)
        if any(str(arg).endswith('reference-gpu-context-test.rkt') for arg in command):
            backend = command[command.index('--backend') + 1]
            adapter = command[command.index('--adapter') + 1]
            receipt = dict(schema=1, status='passed', backend=backend,
                           adapter=adapter if backend == 'direct3d' else False,
                           tests_run=10, failures=0, native_contexts_created=11,
                           contexts_closed=11, context_states=['closed'] * 11,
                           pixel_validation_performed=False, hardware_acceleration_verified=False)
            Path(command[command.index('--output') + 1]).write_text(json.dumps(receipt))
        return result

    def test_cpu_native_mode_runs_pure_context_tests_but_no_gpu_constructor_suite(self):
        report = self.execute('--native')
        labels = [row['label'] for row in report['commands']]
        self.assertIn('gpu-context-pure-tests', labels)
        self.assertNotIn('gpu-context-native', labels)
        self.assertFalse(report['gpu_executed'])
        self.assertFalse(report['gpu_context_tests_executed'])

    def test_explicit_backend_runs_after_source_binding_and_pure_checks(self):
        report = self.execute('--gpu-context-backend', 'metal')
        labels = [row['label'] for row in report['commands']]
        self.assertEqual(labels[-1], 'gpu-context-native')
        self.assertIn('bindings', labels)
        self.assertIn('gpu-context-pure-tests', labels)
        self.assertNotIn('native-cpu', labels)
        self.assertNotIn('reference', labels)
        self.assertTrue(report['gpu_context_tests_passed'])
        self.assertEqual(report['gpu_context_acceptance']['backend'], 'metal')

    def test_direct3d_warp_is_explicit_and_forwarded(self):
        report = self.execute('--gpu-context-backend', 'direct3d', '--gpu-context-adapter', 'warp')
        command = report['commands'][-1]['command']
        self.assertEqual(command[command.index('--adapter') + 1], 'warp')
        self.assertTrue(report['gpu_context_tests_passed'])

    def test_gpu_execution_cannot_be_requested_in_source_archive_or_documents_only_modes(self):
        for args in (['--source-zip', str(self.output.parent / 'source.zip')],
                     ['--documents-only'], ['--gpu-context-adapter', 'warp']):
            with self.subTest(args=args), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    self.runner.main([*args, '--gpu-context-backend', 'metal'])

    def test_a_success_exit_without_context_creation_evidence_is_rejected(self):
        def no_contexts(command, **options):
            result = self.run_fake(command, **options)
            if any(str(arg).endswith('reference-gpu-context-test.rkt') for arg in command):
                path = Path(command[command.index('--output') + 1])
                receipt = json.loads(path.read_text())
                receipt.update(native_contexts_created=0, contexts_closed=0, context_states=[])
                path.write_text(json.dumps(receipt))
            return result
        with (patch.object(self.runner, 'source_hashes', return_value={}),
              patch.object(self.runner, 'check_source', return_value=self.source),
              patch.object(self.runner.shutil, 'which', return_value='/fake/racket'),
              patch.object(self.runner.subprocess, 'run', side_effect=no_contexts),
              contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO())):
            result = self.runner.main(['--gpu-context-backend', 'metal',
                                       '--output', str(self.output)])
        self.assertEqual(result, 1)
        report = json.loads((self.output / 'validation.json').read_text())
        self.assertTrue(report['gpu_context_tests_executed'])
        self.assertFalse(report['gpu_executed'])
        self.assertFalse(report['gpu_context_tests_passed'])

    def test_requested_gpu_failure_prevents_review_archive_publication(self):
        def unavailable(command, **options):
            result = self.run_fake(command, **options)
            if any(str(arg).endswith('reference-gpu-context-test.rkt') for arg in command):
                return SimpleNamespace(returncode=1)
            return result
        with (patch.object(self.runner, 'source_hashes', return_value={}),
              patch.object(self.runner, 'check_source', return_value=self.source),
              patch.object(self.runner.shutil, 'which', return_value='/fake/racket'),
              patch.object(self.runner.subprocess, 'run', side_effect=unavailable),
              patch.object(self.runner, 'check_evidence'),
              patch.object(self.runner, 'check_targets', return_value={}),
              patch.object(self.runner, 'package_review') as package,
              contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO())):
            result = self.runner.main(['--render', '--gpu-context-backend', 'metal',
                                       '--output', str(self.output), '--review-zip',
                                       str(self.output.parent / 'review.zip')])
        self.assertEqual(result, 1)
        package.assert_not_called()
        report = json.loads((self.output / 'validation.json').read_text())
        self.assertFalse(report['gpu_context_tests_passed'])



class R4bDocumentationTests(unittest.TestCase):
    setUpClass = classmethod(R4aContextTests.setUpClass.__func__)
    text = R4aContextTests.text
    header = R4aContextTests.header

    def test_two_editorial_corrections_identify_the_wrapper_and_qualify_metal(self):
        providers = ' '.join(self.text('gpu-providers').split())
        contexts = ' '.join(self.text('gpu-contexts').split())
        self.assertIn('The wrapper rejects simultaneous GPU contexts', providers)
        self.assertIn('Different keys must not be used to disguise concurrent access', providers)
        self.assertIn('On macOS, when a Metal context can be created', contexts)
        self.assertIn('closes the context before returning:', contexts)

    def test_bounded_batch_adds_36_bindings_and_37_export_paths(self):
        rows = [d for d in self.manifest['definitions'] if d['name'] in R4B_PROCEDURES]
        self.assertEqual(len(rows), 36)
        self.assertEqual(sum(len(d['exports']) for d in rows), 37)
        self.assertEqual(len(self.definitions), 1263)
        self.assertEqual(len(self.chapters) - 1, 84)
        self.assertTrue(all(d['canonical_module'] == 'skia/gpu' for d in rows))
        self.assertTrue(all('skia' not in d['exports'] for d in rows))

    def test_call_shapes_match_independent_inventory_and_source_signature_evidence(self):
        for name, (arity, keywords) in R4B_PROCEDURES.items():
            with self.subTest(name=name):
                shape = self.by_name[name]
                self.assertEqual(shape['arity_mask'], str(arity))
                self.assertEqual(shape['allowed_keywords'], keywords)
                self.assertEqual(shape['required_keywords'], R4B_REQUIRED_KEYWORDS.get(name, []))

    def test_new_chapters_and_diagnostic_sibling_declare_binding_sources(self):
        for name in ('gpu-surfaces', 'gpu-images', 'gpu-transfers', 'gpu-synchronization'):
            text = self.text(name)
            self.assertLess(text.index('declare-exporting'), text.index('@defproc'))
            self.assertIn('#:use-sources (skia/gpu)', text)
        text = self.text('gpu-synchronization')
        self.assertIn('#:use-sources (skia/gpu-diagnostics)', text)
        links = (ROOT / checks.REFERENCE / 'tests/links.scrbl').read_text()
        for name in R4B_PROCEDURES:
            self.assertIn('@racket[gpu:' + name + ']', links)
        self.assertIn('@racket[gpu-diagnostics:gpu-memory-statistics]', links)

    def test_surface_request_does_not_claim_actual_msaa_or_unlimited_unbudgeted_memory(self):
        text = ' '.join(self.text('gpu-surfaces').split())
        for phrase in ('actual count is not exposed', 'format-aware storage estimate',
                       'does not bypass', 'Unpremultiplied alpha is not',
                       'no separate GPU canvas drawing language'):
            self.assertIn(phrase, text)
        args = self.header('make-gpu-surface')[0]
        self.assertIn(['#:sample-count', 'samples', ['integer-in', '0', '64'], '0'], args)

    def test_image_residency_is_not_a_cached_texture_probe(self):
        text = ' '.join(self.text('gpu-images').split())
        self.assertIn('ownership classification', text)
        self.assertIn('caches a texture', text)
        self.assertIn('does not require a GPU activation', text)
        self.assertEqual(self.header('image-residency')[1], ['or/c', ['quote', 'cpu'],
                                                           ['quote', 'gpu']])

    def test_transfers_distinguish_staged_commit_from_direct_partial_writes(self):
        text = ' '.join(self.text('gpu-transfers').split())
        for phrase in ('leaves the destination unchanged', 'can leave partial writes',
                       'rollback is not promised', 'Row padding is initialized',
                       'This is conversion, not scaling', 'temporary GPU surface in the same context'):
            self.assertIn(phrase, text)

    def test_filter_placement_returns_owned_image_and_two_immutable_vectors(self):
        result = self.header('gpu-image-apply-filter')[1]
        self.assertEqual(result[:2], ['values', 'gpu-image?'])
        for vector in result[2:]:
            self.assertEqual(vector[0], 'and/c')
            self.assertIn('immutable?', vector)
        text = ' '.join(self.text('gpu-images').split())
        self.assertIn('sixteen-byte-per-pixel', text)
        self.assertIn('must not narrow', text)
        self.assertIn('extract the valid rectangle', text)

    def test_flush_submit_wait_and_cache_setter_have_distinct_results(self):
        text = ' '.join(self.text('gpu-synchronization').split())
        self.assertIn('does not first flush', text)
        self.assertIn('neither submission nor CPU completion', text)
        self.assertIn('returns void, not the previous', text)
        for name in ('gpu-flush!', 'gpu-submit!', 'gpu-wait!', 'gpu-set-cache-limit!'):
            self.assertEqual(self.header(name)[1], 'void?')

    def test_gpu_memory_report_has_a_context_scope_and_explicit_limits(self):
        text = self.text('gpu-synchronization')
        self.assertIn('gpu-context-skia-resources', text)
        self.assertIn('128 bytes per entry', text)
        self.assertIn('live-stream operation', text)
        self.assertEqual(self.header('gpu-memory-statistics')[1], 'memory-statistics?')

    def test_one_shot_returns_only_after_cleanup_and_requires_an_explicit_backend(self):
        text = ' '.join(self.text('gpu-transfers').split())
        for phrase in ('backend is required', 'closes its surface and context before returning',
                       'closes that image instead', 'not silently replaced by abandonment',
                       'zero, one, or multiple results are ignored'):
            self.assertIn(phrase, text)
        self.assertEqual(self.by_name['render-gpu->raster-image']['required_keywords'], ['backend'])

    def test_examples_are_helper_definitions_and_do_not_create_gpu_contexts_at_build_time(self):
        blocks = []
        for name in ('gpu-surfaces', 'gpu-images', 'gpu-transfers', 'gpu-synchronization'):
            for form, header, _ in checks.commands(self.text(name), recursive=True):
                self.assertNotEqual(form, 'examples')
                if form == 'racketblock':
                    blocks.append(header)
        self.assertEqual(len(blocks), 4)
        for block in blocks:
            self.assertEqual(block[0], ['require', 'skia', 'skia/gpu'])
            self.assertEqual(block[1][0], 'define')
            self.assertEqual(len(block), 2)

    def test_native_sources_parse_and_have_separate_common_and_owned_backend_cases(self):
        sources = {}
        for name in ('reference-gpu-surface-pure-test.rkt', 'reference-gpu-surface-test.rkt'):
            text = (ROOT / 'tools' / name).read_text()
            reader, forms = checks.Reader(text, text.index('\n') + 1), []
            while True:
                reader.skip()
                if reader.position == len(text):
                    break
                forms.append(reader.read())
            sources[name] = forms
        pure = next(f for f in sources['reference-gpu-surface-pure-test.rkt']
                    if f[:2] == ['module+', 'test'])
        self.assertEqual(len(pure[2:]), 19)
        self.assertTrue(all(f[0] == 'test-case' for f in pure[2:]))
        suite = next(f for f in sources['reference-gpu-surface-test.rkt']
                     if f[:2] == ['define', ['suite']])[2]
        common = suite[2:-1]
        self.assertEqual([f[1] for f in common], list(COMMON_CASES))
        self.assertEqual(suite[-1][0], 'if')
        self.assertEqual(suite[-1][-1][1], ONE_SHOT_CASE)

    def test_native_suite_uses_actual_displayed_helpers_and_immutable_snapshot_checks(self):
        text = (ROOT / 'tools/reference-gpu-surface-test.rkt').read_text()
        for fragment in ('read-syntax path in', 'load-displayed-helpers', "helper 'gpu-red-tile",
                         "helper 'draw-shifted-gpu-image", "helper 'copy-gpu-surface-to-buffer",
                         '(skia-close! surface)', '(gpu-upload-image second owned)',
                         '(subbytes data 20 24)', '(gpu-flush-image! context image)'):
            self.assertIn(fragment, text)

    def test_source_inventory_is_fully_reflected(self):
        result = checks.check_source(ROOT)
        self.assertEqual(result['inventory_exports'], 1988)
        self.assertEqual(result['reflected_inventory_exports'], 1988)
        self.assertEqual(result['source_verified_export_additions'], 0)
        self.assertFalse(result['binding_identity_checked'])
        self.assertEqual(result['documented_exports'], 1988)
        self.assertEqual(len(result['deferred']), 0)

    def test_archive_hash_inventory_includes_all_new_chapters(self):
        from reference_review import source_hashes
        files = source_hashes(ROOT, review_inputs=True)
        for chapter in ('gpu-surfaces', 'gpu-images', 'gpu-transfers', 'gpu-synchronization'):
            self.assertIn('scribblings/reference/' + chapter + '.scrbl', files)
        self.assertNotIn('api/reference-source/gpu.rkt.b64', files)
        self.assertIn('api/public-api-headless.json', files)
        self.assertIn('tools/reference_gpu_surface_evidence.py', files)


class R4bSourceAdditionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        # This archived source signature tests the validator itself. It is no
        # longer part of the current inventory, because the refreshed public
        # API snapshot now reflects this export directly.
        item = {
            'evidence': 'source-signature',
            'module': 'skia/gpu',
            'name': 'render-gpu->raster-image',
            'source_path': 'gpu.rkt',
            'source_commit': '6b474cc2cca76377fa220cb054eb5b8d7d6e5ced',
            'source_git_blob': 'd12815c3e504a1d056a66e08e85d550446884a3a',
            'source_copy': 'api/reference-source/gpu.rkt.b64',
        }
        self.manifest['source_verified_additions'] = [item]
        self.path = self.root / item['source_copy']
        self.path.parent.mkdir(parents=True)
        shutil.copyfile(ROOT / item['source_copy'], self.path)

    def check(self):
        return checks.source_addition_exports(self.root, self.manifest)

    def test_exact_source_has_a_direct_export_and_correct_keyword_signature(self):
        shape = self.check()[checks.export_key('skia/gpu', 'render-gpu->raster-image')]
        self.assertEqual(shape['arity_mask'], '8')
        self.assertEqual(shape['required_keywords'], ['backend'])
        self.assertEqual(shape['evidence'], 'source-signature')

    def test_missing_archived_source_is_rejected(self):
        self.path.unlink()
        with self.assertRaises(OSError):
            self.check()

    def test_corrupt_source_copy_is_rejected(self):
        self.path.write_bytes(b'invalid?')
        with self.assertRaises(ValueError):
            self.check()

    def test_changed_source_blob_hash_is_rejected(self):
        self.manifest['source_verified_additions'][0]['source_git_blob'] = '0' * 40
        with self.assertRaises(checks.CheckError):
            self.check()

    def test_source_provenance_cannot_be_relabelled_as_runtime_reflection(self):
        self.manifest['source_verified_additions'][0]['evidence'] = 'runtime-reflection'
        with self.assertRaises(checks.CheckError):
            self.check()

    def test_wrong_public_module_is_rejected(self):
        self.manifest['source_verified_additions'][0]['module'] = 'skia'
        with self.assertRaises(checks.CheckError):
            self.check()

    def test_undocumented_or_private_name_cannot_be_invented(self):
        self.manifest['source_verified_additions'][0]['name'] = 'fabricated-renderer'
        with self.assertRaises(checks.CheckError):
            self.check()

    def test_source_copy_must_match_an_available_checkout(self):
        (self.root / 'gpu.rkt').write_text('#lang racket/base\n')
        with self.assertRaises(checks.CheckError):
            self.check()

    def test_duplicate_addition_is_rejected(self):
        self.manifest['source_verified_additions'] *= 2
        with self.assertRaises(checks.CheckError):
            self.check()


def synthetic_surface_receipt(backend='metal', adapter='hardware'):
    """Only for validator/build-plan tests; never delivered as native evidence."""
    names = list(COMMON_CASES) + ([] if backend == 'opengl' else [ONE_SHOT_CASE])
    return dict(schema=1, status='passed', backend=backend,
                adapter=adapter if backend == 'direct3d' else False,
                tests_run=len(names), case_names=names, failures=0,
                managed_contexts_created=20, managed_contexts_closed=20,
                context_states=['closed'] * 20, pixel_probes_checked=12, readbacks_completed=10,
                one_shot_successes=0 if backend == 'opengl' else 1,
                one_shot_native_status=('not-run-external-host-required'
                                        if backend == 'opengl' else 'passed'),
                float_allocation_tested=False, presentation_tested=False,
                hardware_acceleration_verified=False)


class R4bReceiptTests(unittest.TestCase):
    def test_both_selected_backend_suite_shapes_are_accepted(self):
        for backend in ('opengl', 'metal', 'direct3d'):
            check_gpu_surface_receipt(synthetic_surface_receipt(backend), backend, 'hardware')

    def test_wrong_backend_or_adapter_is_rejected(self):
        for backend, adapter in (('opengl', 'hardware'), ('direct3d', 'warp')):
            with self.assertRaises(checks.CheckError):
                check_gpu_surface_receipt(synthetic_surface_receipt(), backend, adapter)

    def test_no_contexts_or_incomplete_closure_is_rejected(self):
        for changes in (dict(managed_contexts_created=0), dict(managed_contexts_closed=19),
                        dict(context_states=['ready'] * 20)):
            with self.subTest(changes=changes), self.assertRaises(checks.CheckError):
                check_gpu_surface_receipt(dict(synthetic_surface_receipt(), **changes),
                                          'metal', 'hardware')

    def test_duplicate_or_missing_cases_are_rejected(self):
        receipt = synthetic_surface_receipt()
        receipt['case_names'][-1] = receipt['case_names'][0]
        with self.assertRaises(checks.CheckError):
            check_gpu_surface_receipt(receipt, 'metal', 'hardware')

    def test_zero_pixel_work_or_boolean_counts_cannot_pass(self):
        for key in ('pixel_probes_checked', 'readbacks_completed', 'tests_run'):
            for value in (0, True):
                with self.subTest(key=key, value=value), self.assertRaises(checks.CheckError):
                    check_gpu_surface_receipt(dict(synthetic_surface_receipt(), **{key: value}),
                                              'metal', 'hardware')

    def test_failure_status_or_nonzero_failures_cannot_pass(self):
        for changes in (dict(status='failed'), dict(failures=1), dict(failures=False)):
            with self.subTest(changes=changes), self.assertRaises(checks.CheckError):
                check_gpu_surface_receipt(dict(synthetic_surface_receipt(), **changes),
                                          'metal', 'hardware')

    def test_unexecuted_scope_cannot_be_advertised_as_tested(self):
        for key in ('presentation_tested', 'float_allocation_tested',
                    'hardware_acceleration_verified'):
            with self.subTest(key=key), self.assertRaises(checks.CheckError):
                check_gpu_surface_receipt(dict(synthetic_surface_receipt(), **{key: True}),
                                          'metal', 'hardware')

    def test_opengl_does_not_claim_the_separate_external_host_one_shot_test(self):
        receipt = synthetic_surface_receipt('opengl')
        receipt['one_shot_native_status'] = 'passed'
        with self.assertRaises(checks.CheckError):
            check_gpu_surface_receipt(receipt, 'opengl', 'hardware')


class R4bBuildPlanTests(unittest.TestCase):
    """Mocked command execution, not Racket or GPU acceptance."""
    setUp = BuildPlanTests.setUp
    execute = BuildPlanTests.execute

    def run_fake(self, command, **options):
        result = BuildPlanTests.run_fake(self, command, **options)
        if any(str(arg).endswith('reference-gpu-surface-test.rkt') for arg in command):
            backend = command[command.index('--backend') + 1]
            adapter = command[command.index('--adapter') + 1]
            Path(command[command.index('--output') + 1]).write_text(
                json.dumps(synthetic_surface_receipt(backend, adapter)))
        return result

    def test_cpu_acceptance_does_not_run_gpu_rendering(self):
        report = self.execute('--native')
        labels = [row['label'] for row in report['commands']]
        self.assertIn('gpu-surface-pure-tests', labels)
        self.assertNotIn('gpu-surface-native', labels)
        self.assertFalse(report['gpu_surface_tests_executed'])

    def test_explicit_surface_backend_requires_pixel_receipt(self):
        report = self.execute('--gpu-surface-backend', 'metal')
        self.assertTrue(report['gpu_surface_tests_passed'])
        self.assertTrue(report['gpu_surface_tests_executed'])
        self.assertEqual(report['commands'][-1]['label'], 'gpu-surface-native')
        self.assertFalse(report['scribble_rendered'])

    def test_direct3d_adapter_is_forwarded(self):
        report = self.execute('--gpu-surface-backend', 'direct3d', '--gpu-surface-adapter', 'warp')
        self.assertEqual(report['gpu_surface_acceptance']['adapter'], 'warp')

    def test_source_only_modes_reject_gpu_requests(self):
        for mode in ('--documents-only', '--source-zip'):
            args = [mode] + ([str(self.output.parent / 'source.zip')] if mode == '--source-zip'
                             else [])
            with self.subTest(mode=mode), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    self.runner.main([*args, '--gpu-surface-backend', 'metal'])

    def test_requested_gpu_failure_prevents_archive_publication(self):
        def fail(command, **options):
            result = self.run_fake(command, **options)
            if any(str(arg).endswith('reference-gpu-surface-test.rkt') for arg in command):
                return SimpleNamespace(returncode=1)
            return result
        with (patch.object(self.runner, 'source_hashes', return_value={}),
              patch.object(self.runner, 'check_source', return_value=self.source),
              patch.object(self.runner.shutil, 'which', return_value='/fake/racket'),
              patch.object(self.runner.subprocess, 'run', side_effect=fail),
              patch.object(self.runner, 'check_evidence'),
              patch.object(self.runner, 'check_targets', return_value={}),
              patch.object(self.runner, 'package_review') as package,
              contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO())):
            rc = self.runner.main(['--render', '--gpu-surface-backend', 'metal', '--output',
                                   str(self.output), '--review-zip',
                                   str(self.output.parent / 'r.zip')])
        self.assertEqual(rc, 1)
        package.assert_not_called()



class R4cInteropTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        cls.definitions, cls.chapters = checks.document_definitions(ROOT)
        cls.by_name = {d['name']: d for d in cls.definitions}

    def text(self, name):
        return (ROOT / checks.REFERENCE / (name + '.scrbl')).read_text()

    def header(self, name):
        chapter = ROOT / self.by_name[name]['chapter']
        for form, header, _ in checks.commands(chapter.read_text()):
            if form == 'defproc' and header[0][0] == name:
                return header
        self.fail('missing procedure: ' + name)

    def test_coverage_totals_and_stage_are_explicit(self):
        result = checks.check_source(ROOT)
        self.assertEqual(len(result['definitions']), 1263)
        self.assertEqual(result['documented_exports'], 1988)
        self.assertEqual(result['inventory_exports'], 1988)
        self.assertEqual(len(result['deferred']), 0)
        self.assertEqual(self.manifest['stage'], 'R4g')
        self.assertEqual(self.manifest['reviewed_repository_commit'],
                         '4dbbdcc3ab46d896ddd5f2c1de535ea2bab01cb1')

    def test_selected_modules_have_complete_documented_export_sets(self):
        for path, names in R4C_MODULES.items():
            module = checks.public_module(path)
            found = {d['name'] for d in self.manifest['definitions'] if module in d['exports']}
            with self.subTest(module=module):
                self.assertTrue(set(names) <= found)
                self.assertEqual({d['name'] for d in self.manifest['definitions']
                                  if module in d['exports'] and d['name'] in R4C_PROCEDURES},
                                 set(names))

    def test_call_boundaries_match_fixture_inventory(self):
        for name, (arity, keywords) in R4C_PROCEDURES.items():
            with self.subTest(name=name):
                spec = self.by_name[name]
                self.assertEqual(spec['arity_mask'], str(arity))
                self.assertEqual(spec['allowed_keywords'], keywords)
                self.assertEqual(spec['required_keywords'], R4C_REQUIRED_KEYWORDS.get(name, []))

    def test_new_chapters_are_included_and_declare_real_sources(self):
        root = self.text('reference')
        groups = {
            'gpu-rendering': ('gpu-opengl-hosts', 'gpu-diagnostics'),
            'gpu-interoperability-output': ('gpu-gl-interop',
                                            'gpu-external-resources',
                                            'gpu-native-handoffs'),
        }
        for group, chapters in groups.items():
            group_text = self.text(group)
            self.assertIn('@include-reference-section["' + group + '.scrbl"]', root)
            for chapter in chapters:
                self.assertIn('@include-section["' + chapter + '.scrbl"]', group_text)
                text = self.text(chapter)
                self.assertIn('declare-exporting', text)
                self.assertIn('#:use-sources', text)
        self.assertEqual(root.count('@include-reference-section['), 13)

    def test_r4b_examples_show_complete_imports_and_isolated_compile_test(self):
        for chapter in ('gpu-surfaces', 'gpu-images', 'gpu-transfers'):
            for form, block, _ in checks.commands(self.text(chapter), recursive=True):
                if form == 'racketblock':
                    self.assertEqual(block[0], ['require', 'skia', 'skia/gpu'])
        pure = (ROOT / 'tools/reference-gpu-surface-pure-test.rkt').read_text()
        self.assertIn('(make-base-namespace)', pure)
        self.assertIn('(module displayed-gpu-example racket/base', pure)
        self.assertIn("(dynamic-require ''displayed-gpu-example #f)", pure)
        self.assertIn('only their shown imports', pure)

    def test_gpu_image_introduction_separates_drawing_from_cpu_operations(self):
        text = self.text('gpu-images')
        self.assertIn('ordinary canvas image-drawing', text)
        self.assertIn('@racket[draw-image]', text)
        self.assertIn('@racket[draw-image-rect]', text)
        self.assertIn('CPU-only image operations require an explicit transfer', text)
        self.assertNotIn('Draw it with the ordinary image operations', text)

    def test_safe_external_tokens_are_single_use_and_hide_raw_handles(self):
        text = self.text('gpu-external-resources')
        for phrase in ('single-use', 'ready to active to', 'raw_handles_exposed',
                       'borrowed Skia canvas', 'not rolled back'):
            self.assertIn(phrase, text)
        self.assertEqual(self.header('gpu-import-image')[1], 'gpu-image?')

    def test_external_token_lifetime_and_native_platform_rules_are_local(self):
        external = self.text('gpu-external-resources')
        for phrase in ('active', '@tech{GPU activation}', 'creating thread',
                       'does not satisfy @racket[skia-resource?]',
                       'not\nmanaged by @racket[with-skia]',
                       '@racket[gpu-external-texture-close!]'):
            self.assertIn(phrase, external)
        native = ' '.join(self.text('gpu-native-handoffs').split())
        self.assertIn('64-bit macOS and an active Metal GPU context', native)
        self.assertIn('64-bit Windows on x86-64 and an active Direct3D 12 GPU context', native)

    def test_gl_handoff_distinguishes_ordering_wait_and_state_restoration(self):
        text = ' '.join(self.text('gpu-gl-interop').split())
        for phrase in ('same command stream', 'does not save or restore',
                       'eight-bit stencil', 'does not alias', 'No CPU readback'):
            self.assertIn(phrase, text)
        self.assertEqual(self.header('gpu-copy-gl-texture')[1], 'gpu-image?')

    def test_native_handoffs_are_explicitly_unsafe_and_bounded(self):
        text = self.text('gpu-native-handoffs')
        for phrase in ('explicitly unsafe', 'crash the process', '1 through 60000',
                       'all-ones uint64', 'caller declarations', 'quarantine'):
            self.assertIn(phrase, text)
        self.assertIn('cpointer?', str(self.header('make-metal-external-texture')))
        self.assertIn('cpointer?', str(self.header('make-d3d12-external-texture')))

    def test_egl_and_racket_gl_document_ownership_not_presentation(self):
        text = self.text('gpu-opengl-hosts')
        for phrase in ('do not create a presentation window', 'desktop OpenGL',
                       'does not own', 'does not close'):
            self.assertIn(phrase, text)

    def test_diagnostics_do_not_claim_hardware_or_implicit_synchronization(self):
        text = ' '.join(self.text('gpu-diagnostics').split())
        for phrase in ('not hardware attestations', 'No flush, submission, wait, or pixel readback',
                       'fixed synchronous 8 by 8', 'not a general drawing API'):
            self.assertIn(phrase, text)

    def test_link_probe_mentions_every_new_public_alias(self):
        text = (ROOT / checks.REFERENCE / 'tests/links.scrbl').read_text()
        prefixes = {
            'skia/gpu': 'gpu:', 'skia/gpu-diagnostics': 'gpu-diagnostics:',
            'skia/gpu-egl': 'gpu-egl:', 'skia/gpu-racket-gl': 'gpu-racket-gl:',
            'skia/gpu-gl-interop': 'gpu-gl-interop:', 'skia/gpu-interop': 'gpu-interop:',
            'skia/unsafe/gpu-metal': 'unsafe-gpu-metal:',
            'skia/unsafe/gpu-d3d12': 'unsafe-gpu-d3d12:'}
        for d in self.manifest['definitions']:
            if d['name'] not in R4C_PROCEDURES:
                continue
            for module in d['exports']:
                self.assertIn('@racket[' + prefixes[module] + d['name'] + ']', text)

    def test_native_free_interop_suite_is_connected_to_acceptance(self):
        runner = (ROOT / 'tools/check-reference.py').read_text()
        self.assertIn("run('gpu-interop-pure-tests'", runner)
        path = ROOT / 'tools/reference-gpu-interop-pure-test.rkt'
        text = path.read_text()
        self.assertEqual(text.count('(test-case '), 13)
        reader = checks.Reader(text, text.index('\n') + 1)
        while reader.position < len(text):
            reader.skip()
            if reader.position < len(text):
                reader.read()

    def test_platform_specific_native_evidence_is_not_synthesized(self):
        notes = (ROOT / 'docs/REFERENCE-DEVELOPMENT.md').read_text()
        self.assertIn('R4c', notes)
        self.assertIn('platform-specific', notes)
        self.assertIn('not native interop acceptance', notes)
        self.assertNotIn('--gpu-interop-backend', (ROOT / 'tools/check-reference.py').read_text())

    def test_source_review_contains_new_chapters_and_checker_inputs(self):
        from reference_review import source_hashes
        files = source_hashes(ROOT, review_inputs=True)
        for chapter in ('gpu-opengl-hosts', 'gpu-diagnostics', 'gpu-gl-interop',
                        'gpu-external-resources', 'gpu-native-handoffs'):
            self.assertIn('scribblings/reference/' + chapter + '.scrbl', files)
        self.assertIn('tools/reference_gpu_interop_cases.py', files)
        self.assertIn('tools/reference-gpu-interop-pure-test.rkt', files)
        self.assertIn('api/public-api-headless.json', files)
        self.assertIn('api/public-api-gui.json', files)


class R4dPresentationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        cls.definitions, cls.chapters = checks.document_definitions(ROOT)
        cls.by_name = {d['name']: d for d in cls.definitions}

    def text(self, chapter):
        return (ROOT / checks.REFERENCE / (chapter + '.scrbl')).read_text()

    def header(self, name):
        path = ROOT / self.by_name[name]['chapter']
        for form, header, _ in checks.commands(path.read_text()):
            if form == 'defproc' and header[0][0] == name:
                return header
        self.fail('missing procedure: ' + name)

    def test_r4d_coverage_remains_present_in_complete_r4e_manual(self):
        result = checks.check_source(ROOT)
        self.assertEqual(len(result['definitions']), 1263)
        self.assertEqual(result['documented_exports'], 1988)
        self.assertEqual(result['inventory_exports'], 1988)
        self.assertEqual(len(result['deferred']), 0)
        self.assertEqual(self.manifest['stage'], 'R4g')
        self.assertEqual(self.manifest['reviewed_repository_commit'],
                         '4dbbdcc3ab46d896ddd5f2c1de535ea2bab01cb1')
        self.assertEqual(set(result['runtime_deferred_modules']), set(R4D_GUI_MODULES))

    def test_exact_r4d_module_exports_are_documented(self):
        for path, names in R4D_MODULES.items():
            module = checks.public_module(path)
            found = {d['name'] for d in self.manifest['definitions'] if module in d['exports']}
            with self.subTest(module=module):
                self.assertTrue(set(names) <= found)
        rows = [d for d in self.manifest['definitions']
                if d['name'] in set(R4D_PROCEDURES) | set(R4D_VALUES)]
        self.assertEqual(len(rows), 36)
        self.assertEqual(sum(len(d['exports']) for d in rows), 36)

    def test_procedure_call_shapes_match_pinned_inventory(self):
        for name, (arity, keywords) in R4D_PROCEDURES.items():
            with self.subTest(name=name):
                spec = self.by_name[name]
                self.assertEqual(spec['kind'], 'procedure')
                self.assertEqual(spec['arity_mask'], str(arity))
                self.assertEqual(spec['allowed_keywords'], keywords)
                self.assertEqual(spec['required_keywords'], [])

    def test_class_and_interface_forms_keep_inventory_kinds(self):
        for name, kind in R4D_VALUES.items():
            with self.subTest(name=name):
                spec = self.by_name[name]
                self.assertEqual(spec['kind'], kind)
                self.assertEqual(spec['form'], 'defclass' if kind == 'class' else 'definterface')
                self.assertEqual(spec['arguments'], [])

    def test_gui_runtime_deferral_is_explicit_and_limited(self):
        self.assertEqual(set(self.manifest['runtime_deferred_modules']), set(R4D_GUI_MODULES))
        result = checks.check_source(ROOT)
        deferred = {d['name'] for d in result['definitions']
                    if d['runtime_check'] == 'deferred-gui'}
        expected = set().union(*(set(R4D_MODULES[path]) for path in
                                 ('canvas.rkt', 'gpu-canvas.rkt', 'gpu-gui.rkt',
                                  'render-canvas.rkt')))
        self.assertEqual(deferred, expected)
        presenter = {d['name'] for d in result['definitions']
                     if d['name'] in R4D_MODULES['gpu.rkt']}
        self.assertTrue(all(self.by_name[name]['kind'] == 'procedure' for name in presenter))

    def test_runtime_reader_discloses_deferred_gui_identity(self):
        runtime = (ROOT / 'tools/reference-runtime.rkt').read_text()
        self.assertIn('deferred-runtime-specifications', runtime)
        self.assertIn("'binding_identity_deferred_definitions", runtime)
        self.assertIn('(in-list live-specifications)', runtime)

    def test_new_chapters_are_included_before_index(self):
        root = self.text('reference')
        presentation = self.text('presentation-and-gui')
        output = self.text('documents-and-output')
        self.assertIn('@include-reference-section["presentation-and-gui.scrbl"]', root)
        self.assertIn('@include-reference-section["documents-and-output.scrbl"]', root)
        for chapter, group in (
                ('gpu-output', output),
                ('gpu-presentation', presentation),
                ('gpu-widgets', presentation),
                ('gui-canvases', presentation),
                ('render-canvases', presentation)):
            include = '@include-section["' + chapter + '.scrbl"]'
            self.assertIn(include, group)
        self.assertEqual(root.count('@include-reference-section['), 13)

    def test_frame_lifetime_and_presentation_claims_are_precise(self):
        text = ' '.join(self.text('gpu-presentation').split())
        for phrase in ('short-lived value', 'presentation were requested',
                       'does not certify physical display pixels',
                       'Expiration is permanent', 'Cancelled acquired frames'):
            self.assertIn(phrase, text)
        self.assertEqual(self.header('gpu-presenter-render!')[1],
                         ['or/c', ['quote', 'present-requested'], ['quote', 'skipped'],
                          ['quote', 'cancelled']])

    def test_widget_and_unified_selection_rules_are_not_silent_fallbacks(self):
        widget = ' '.join(self.text('gpu-widgets').split())
        unified = ' '.join(self.text('render-canvases').split())
        self.assertIn('the widget selects Metal on macOS and OpenGL elsewhere', widget)
        self.assertIn('not a failure fallback', widget)
        self.assertIn('Direct3D on Windows x86-64', unified)
        self.assertIn('not driver probes or fallback rules', unified)

    def test_unified_factory_contracts_match_gui_and_selection_policy(self):
        text = self.text('render-canvases')
        self.assertIn('(prefix-in draw: racket/draw)', text)
        self.assertEqual(text.count('(or/c string? (is-a?/c draw:color%))'), 2)
        self.assertEqual(text.count('(or/c #f (integer-in 0 2147483647))'), 2)
        self.assertNotIn('[#:background background any/c', text)
        self.assertNotIn('[background any/c', text)

    def test_gpu_output_connects_executor_to_output_group_and_callback_contract(self):
        text = ' '.join(self.text('gpu-output').split())
        for phrase in ('Pass the executor to @racket[draw-output-group]',
                       '@racket[#:raster-executor] argument',
                       "used only when the group's output policy selects rasterization",
                       'one positional argument and no required keywords'):
            self.assertIn(phrase, text)
        header = self.header('call-with-gpu-raster-executor')
        proc = next(arg for arg in header[0] if isinstance(arg, list) and arg[0] == 'proc')
        self.assertEqual(proc[1], ['->', 'output-raster-executor?', 'any'])

    def test_automatic_backend_policies_cross_reference_the_windows_difference(self):
        widget = ' '.join(self.text('gpu-widgets').split())
        unified = ' '.join(self.text('render-canvases').split())
        self.assertIn('@secref["skia-render-canvases"]', widget)
        self.assertIn('@secref["skia-gpu-widgets"]', unified)
        for text in (widget, unified):
            self.assertIn('Windows x86-64', text)
            self.assertIn('Direct3D', text)
            self.assertIn('OpenGL', text)
            self.assertIn('package-wide backend choice', text)

    def test_raster_and_gpu_dc_lifetimes_are_not_conflated(self):
        text = ' '.join(self.text('gui-canvases').split())
        self.assertIn('persistent CPU-raster Skia drawing context', text)
        self.assertIn('drawing context exists only during one frame callback', text)
        self.assertIn('there is no persistent unpresented frame', text)

    def test_unified_interface_exposes_callback_only_common_dc(self):
        text = ' '.join(self.text('render-canvases').split())
        for phrase in ('Returns the exact drawing context only while a paint callback is live',
                       'Returns the persistent raster drawing context',
                       'saved GPU callback DC expires permanently'):
            self.assertIn(phrase, text)

    def test_gpu_output_documents_explicit_readback_and_bounded_fallback(self):
        text = ' '.join(self.text('gpu-output').split())
        for phrase in ('explicit synchronous @tech{GPU readback}', 'CPU-owned @tech{image}',
                       'does not close', 'not a general runtime renderer fallback'):
            self.assertIn(phrase, text)

    def test_link_probe_covers_all_r4d_exports(self):
        links = (ROOT / checks.REFERENCE / 'tests/links.scrbl').read_text()
        prefixes = {'skia/gpu': 'gpu:', 'skia/canvas': 'canvas:',
                    'skia/gpu-gui': 'gpu-gui:', 'skia/gpu-canvas': 'gpu-canvas:',
                    'skia/render-canvas': 'render-canvas:', 'skia/gpu-output': 'gpu-output:'}
        for row in self.manifest['definitions']:
            if row['name'] not in set(R4D_PROCEDURES) | set(R4D_VALUES):
                continue
            for module in row['exports']:
                self.assertIn('@racket[' + prefixes[module] + row['name'] + ']', links)

    def test_pure_presenter_suite_is_connected_but_gui_is_not_implicit(self):
        runner = (ROOT / 'tools/check-reference.py').read_text()
        self.assertIn("run('gpu-presentation-pure-tests'", runner)
        self.assertNotIn('--gpu-presentation-gui', runner)
        pure = (ROOT / 'tools/reference-gpu-presentation-pure-test.rkt').read_text()
        self.assertEqual(pure.count('(test-case '), 12)
        self.assertIn('No GUI, native GPU', pure)

    def test_examples_are_unchanged_by_r4d(self):
        forms = [(form, header) for path in (ROOT / checks.REFERENCE).glob('*.scrbl')
                 for form, header, _ in checks.commands(path.read_text(), recursive=True)]
        self.assertEqual(sum(form == 'racketblock' for form, _ in forms), 316)
        self.assertEqual(sum(form == 'examples' for form, _ in forms), 25)

    def test_gpu_output_remains_in_r4d_after_r4e_completion(self):
        result = checks.check_source(ROOT, require_complete=True)
        self.assertEqual(result['deferred'], [])
        self.assertEqual(self.by_name['make-gpu-raster-executor']['chapter'],
                         'scribblings/reference/gpu-output.scrbl')
        self.assertEqual(self.by_name['call-with-gpu-raster-executor']['allowed_keywords'],
                         ['on-unavailable'])


class R4eDcIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        cls.definitions, cls.chapters = checks.document_definitions(ROOT)
        cls.by_name = {d['name']: d for d in cls.definitions}

    def text(self, chapter):
        return (ROOT / checks.REFERENCE / (chapter + '.scrbl')).read_text()

    def header(self, name):
        path = ROOT / self.by_name[name]['chapter']
        return next(h for f, h, _ in checks.commands(path.read_text())
                    if f == 'defproc' and h[0][0] == name)

    def test_r4e_closes_the_pinned_and_source_verified_inventory(self):
        result = checks.check_source(ROOT, require_complete=True)
        self.assertEqual(len(result['definitions']), 1263)
        self.assertEqual(result['documented_exports'], 1988)
        self.assertEqual(result['inventory_exports'], 1988)
        self.assertEqual(result['reflected_inventory_exports'], 1988)
        self.assertEqual(result['source_verified_export_additions'], 0)
        self.assertEqual(result['deferred'], [])
        self.assertEqual(len(result['chapters']) - 1, 84)
        self.assertEqual(self.manifest['stage'], 'R4g')
        self.assertEqual(self.manifest['reviewed_repository_commit'],
                         '4dbbdcc3ab46d896ddd5f2c1de535ea2bab01cb1')
        self.assertNotIn('deferred_policy', self.manifest)

    def test_exact_r4e_module_exports_are_documented(self):
        expected_names = set(R4E_PROCEDURES) | set(R4E_VALUES) | set(R4E_PARAMETERS)
        rows = [d for d in self.manifest['definitions'] if d['name'] in expected_names]
        self.assertEqual(len(rows), 23)
        self.assertEqual(sum(len(d['exports']) for d in rows), 23)
        for path, names in R4E_MODULES.items():
            module = checks.public_module(path)
            found = {d['name'] for d in self.manifest['definitions'] if module in d['exports']}
            with self.subTest(module=module):
                self.assertEqual(found, set(names))

    def test_r4e_procedure_and_parameter_shapes_match_pinned_inventory(self):
        for name, (arity, keywords) in R4E_PROCEDURES.items():
            with self.subTest(name=name):
                spec = self.by_name[name]
                self.assertEqual(spec['kind'], 'procedure')
                self.assertEqual(spec['arity_mask'], str(arity))
                self.assertEqual(spec['allowed_keywords'], keywords)
                self.assertEqual(spec['required_keywords'], [])
        parameter = self.by_name['current-output-dc-command-limit']
        self.assertEqual(parameter['kind'], 'parameter')
        self.assertEqual(parameter['arity_mask'], '3')
        self.assertEqual(parameter['allowed_keywords'], [])

    def test_dc_class_and_exception_structure_use_native_scribble_forms(self):
        dc = self.by_name['skia-dc%']
        self.assertEqual(dc['kind'], 'class')
        self.assertEqual(dc['form'], 'defclass')
        constructor = self.by_name['exn:fail:skia-dc:unsupported']
        self.assertEqual(constructor['form'], 'defstruct*')
        self.assertEqual(constructor['arity_mask'], '32')
        self.assertEqual([a['name'] for a in constructor['arguments']],
                         ['message', 'continuation-marks', 'method', 'feature', 'stage'])
        descriptor = self.by_name['struct:exn:fail:skia-dc:unsupported']
        self.assertEqual(descriptor['kind'], 'value')
        self.assertEqual(descriptor['value_kind'], 'struct-type')
        for suffix in ('method', 'feature', 'stage'):
            self.assertEqual(self.by_name['exn:fail:skia-dc:unsupported-' + suffix]
                             ['definition_group'], 'exn:fail:skia-dc:unsupported')

    def test_structure_readers_support_only_the_reviewed_exception_supertype(self):
        support = (ROOT / 'tools/reference_support.py').read_text()
        runtime = (ROOT / 'tools/reference-runtime.rkt').read_text()
        for text in (support, runtime):
            self.assertIn('exn:fail:skia-dc:unsupported', text)
            self.assertIn('exn:fail:contract', text)
            self.assertIn('continuation-marks', text)
        self.assertIn('unsupported structure name/supertype', support)
        self.assertIn('unsupported structure name/supertype', runtime)

    def test_complete_manifest_does_not_need_a_dummy_deferral_policy(self):
        self.assertNotIn('deferred_policy', self.manifest)
        support = (ROOT / 'tools/reference_support.py').read_text()
        self.assertIn('if remaining:', support)
        self.assertIn('require_complete or not deferred', support)
        self.assertEqual(checks.check_source(ROOT, require_complete=True)['deferred'], [])

    def test_r4e_chapters_are_included_before_the_index(self):
        root = self.text('reference')
        group = self.text('racket-integration')
        self.assertIn('@include-reference-section["racket-integration.scrbl"]', root)
        for chapter in ('racket-dc', 'dc-output', 'gpu-dc'):
            include = '@include-section["' + chapter + '.scrbl"]'
            self.assertIn(include, group)
            text = self.text(chapter)
            self.assertIn('declare-exporting', text)
            self.assertIn('#:use-sources', text)
        self.assertEqual(root.count('@include-reference-section['), 13)

    def test_reference_introduction_no_longer_points_to_incomplete_api_notes(self):
        intro = self.text('reference').split('@local-table-of-contents[]', 1)[0]
        self.assertNotIn('Interfaces not yet covered', intro)
        self.assertNotIn('docs/API.md', intro)

    def test_three_dc_lifetimes_are_explicitly_distinct(self):
        raster = ' '.join(self.text('racket-dc').split())
        output = ' '.join(self.text('dc-output').split())
        gpu = ' '.join(self.text('gpu-dc').split())
        self.assertIn('persistent CPU-raster backing', raster)
        self.assertIn('idempotent on the owner thread', raster)
        self.assertIn('callback-scoped DC', output)
        self.assertIn('capture DC expires', output)
        self.assertIn('fresh GPU drawing context', gpu)
        self.assertIn('invalid on normal return, exception, or escape', gpu)
        self.assertIn('Pixel persistence does not imply DC-state persistence', gpu)

    def test_output_callbacks_and_explicit_raster_boundary_are_local(self):
        text = ' '.join(self.text('dc-output').split())
        for phrase in ('one positional DC argument with no required keyword arguments',
                       'capture DC expires',
                       'explicitly audited bounded raster group',
                       'require-vector', 'invisible no-op'):
            self.assertIn(phrase, text)
        self.assertEqual(self.header('draw-dc-raster-group')[1], 'void?')
        self.assertEqual(self.header('call-with-output-dc')[1], ['and/c', 'hash?', 'immutable?'])

    def test_bitmap_smooth_style_contract_matches_the_bitmap_bridge(self):
        text = self.text('racket-dc')
        header = next(h for f, h, _ in checks.commands(text, recursive=True)
                      if f == 'defmethod' and h and h[0][0] == 'draw-bitmap-section-smooth')
        style = next(arg for arg in header[0]
                     if isinstance(arg, list) and arg[0] == 'style')
        self.assertEqual(style[1], ['or/c', ['quote', 'solid'], ['quote', 'opaque'],
                                    ['quote', 'xor']])
        prose = ' '.join(text.split())
        self.assertIn("legacy @racket['xor] bitmap style", prose)
        self.assertIn('not a bitwise XOR operation', prose)

    def test_output_page_margin_contract_has_exact_four_side_shape(self):
        header = self.header('make-dc-output-page')[0]
        margins = next(arg for arg in header
                       if isinstance(arg, list) and arg[0] == '#:margins')
        nonnegative = ['and/c', 'real?', ['>=/c', '0']]
        self.assertEqual(margins[2],
                         ['or/c', nonnegative, ['list/c', nonnegative, nonnegative,
                                                nonnegative, nonnegative]])
        prose = ' '.join(self.text('dc-output').split())
        self.assertIn('left, top, right, bottom order', prose)
        self.assertIn('positive content width and height', prose)

    def test_gpu_dc_staging_and_borrowed_surface_semantics_are_explicit(self):
        text = ' '.join(self.text('gpu-dc').split())
        for phrase in ('RGBA/BGRA/F16/F32', 'GPU-to-GPU', 'No automatic CPU readback',
                       'exact owning @racket[call-with-gpu-context] activation',
                       'not a pixel transaction', 'explicit synchronous CPU transfers'):
            self.assertIn(phrase, text)
        frame = self.header('call-with-gpu-frame-dc')[0]
        color = next(arg for arg in frame if isinstance(arg, list) and arg[0] == '#:color-type')
        self.assertEqual(color[2], ['or/c', ['quote', 'rgba-8888'], ['quote', 'bgra-8888'],
                                    ['quote', 'rgba-f16'], ['quote', 'rgba-f32']])
        sample = next(arg for arg in frame if isinstance(arg, list) and arg[0] == '#:sample-count')
        self.assertEqual(sample[2], ['integer-in', '0', '64'])

    def test_r4e_bindings_remain_live_checked_while_gui_deferrals_stay_bounded(self):
        result = checks.check_source(ROOT)
        self.assertEqual(set(result['runtime_deferred_modules']), set(R4D_GUI_MODULES))
        for name in set(R4E_PROCEDURES) | set(R4E_VALUES) | set(R4E_PARAMETERS):
            with self.subTest(name=name):
                self.assertEqual(next(d for d in result['definitions'] if d['name'] == name)
                                 ['runtime_check'], 'live')

    def test_link_probe_covers_every_r4e_export(self):
        links = (ROOT / checks.REFERENCE / 'tests/links.scrbl').read_text()
        prefixes = {'skia/dc': 'dc:', 'skia/dc-output': 'dc-output:', 'skia/gpu-dc': 'gpu-dc:'}
        for path, names in R4E_MODULES.items():
            module = checks.public_module(path)
            for name in names:
                self.assertIn('@racket[' + prefixes[module] + name + ']', links)

    def test_native_free_dc_integration_suite_is_connected_to_acceptance(self):
        runner = (ROOT / 'tools/check-reference.py').read_text()
        self.assertIn("run('dc-integration-pure-tests'", runner)
        path = ROOT / 'tools/reference-dc-integration-pure-test.rkt'
        text = path.read_text()
        self.assertEqual(text.count('(test-case '), 12)
        for phrase in ('not allocate a Skia surface', 'create a GPU context',
                       'render a document', 'a GUI'):
            self.assertIn(phrase, text)
        reader = checks.Reader(text, text.index('\n') + 1)
        while True:
            reader.skip()
            if reader.position == len(text):
                break
            reader.read()

    def test_examples_remain_unchanged_by_r4e(self):
        forms = [(form, header) for path in (ROOT / checks.REFERENCE).glob('*.scrbl')
                 for form, header, _ in checks.commands(path.read_text(), recursive=True)]
        self.assertEqual(sum(form == 'racketblock' for form, _ in forms), 316)
        self.assertEqual(sum(form == 'examples' for form, _ in forms), 25)

    def test_source_review_contains_r4e_chapters_cases_and_pinned_inventories(self):
        files = review.source_hashes(ROOT, review_inputs=True)
        for chapter in ('racket-dc', 'dc-output', 'gpu-dc'):
            self.assertIn('scribblings/reference/' + chapter + '.scrbl', files)
        self.assertIn('tools/reference_dc_cases.py', files)
        self.assertIn('tools/reference-dc-integration-pure-test.rkt', files)
        self.assertIn('api/public-api-headless.json', files)
        self.assertIn('api/public-api-gui.json', files)


class R4fPictBridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        cls.definitions, cls.chapters = checks.document_definitions(ROOT)
        cls.by_name = {row['name']: row for row in cls.definitions}

    def text(self, chapter):
        return (ROOT / checks.REFERENCE / (chapter + '.scrbl')).read_text()

    def test_pict_bridge_closes_the_fresh_inventory(self):
        result = checks.check_source(ROOT, require_complete=True)
        self.assertEqual(len(result['definitions']), 1263)
        self.assertEqual(result['documented_exports'], 1988)
        self.assertEqual(result['inventory_exports'], 1988)
        self.assertEqual(result['reflected_inventory_exports'], 1988)
        self.assertEqual(result['source_verified_export_additions'], 0)
        self.assertEqual(result['deferred'], [])
        self.assertEqual(len(result['chapters']) - 1, 84)
        self.assertEqual(self.manifest['stage'], 'R4g')
        self.assertEqual(self.manifest['reviewed_repository_commit'],
                         '4dbbdcc3ab46d896ddd5f2c1de535ea2bab01cb1')

    def test_pict_module_has_exactly_three_canonical_definitions(self):
        rows = [row for row in self.manifest['definitions']
                if 'skia/pict' in row['exports']]
        self.assertEqual({row['name'] for row in rows},
                         {'image->pict', 'surface->pict', 'picture->pict'})
        self.assertTrue(all(row['canonical_module'] == 'skia/pict' for row in rows))
        self.assertTrue(all(row['chapter'] == 'scribblings/reference/pict-bridge.scrbl'
                            for row in rows))

    def test_pict_call_boundaries_match_the_reflected_inventory(self):
        expected = {
            'image->pict': ['backing-scale'],
            'surface->pict': ['backing-scale'],
            'picture->pict': ['bounds', 'raster-scale'],
        }
        for name, keywords in expected.items():
            with self.subTest(name=name):
                spec = self.by_name[name]
                self.assertEqual(spec['arity_mask'], '2')
                self.assertEqual(spec['allowed_keywords'], keywords)
                self.assertEqual(spec['required_keywords'], [])

    def test_pict_chapter_is_next_to_recorded_picture_material(self):
        root = self.text('reference')
        group = self.text('racket-integration')
        bridge = group.index('@include-section["pict-bridge.scrbl"]')
        racket_draw = group.index('@include-section["racket-draw.scrbl"]')
        self.assertLess(bridge, racket_draw)
        self.assertIn('@include-reference-section["racket-integration.scrbl"]', root)
        self.assertEqual(root.count('@include-reference-section['), 13)

    def test_bridge_semantics_are_explicit(self):
        prose = ' '.join(self.text('pict-bridge').split())
        for phrase in ('The conversions are explicit',
                       'without encoding and decoding PNG',
                       'GPU-dependent image is rejected',
                       'Tagged images are read into sRGB',
                       'twice the physical RGBA byte count',
                       'Ceiling can make the actual x and y pixel scales differ slightly'):
            self.assertIn(phrase, prose)
        self.assertIn('@racketmodname[skia/bitmap]', prose)
        self.assertIn('@racketmodname[file/convertible]', prose)

    def test_link_probe_covers_all_pict_exports(self):
        links = (ROOT / checks.REFERENCE / 'tests/links.scrbl').read_text()
        for name in ('image->pict', 'surface->pict', 'picture->pict'):
            self.assertIn('@racket[pict:' + name + ']', links)

    def test_reference_validation_runs_existing_pict_suites(self):
        runner = (ROOT / 'tools/check-reference.py').read_text()
        self.assertIn("run('pict-pure-tests'", runner)
        self.assertIn("ROOT / 'tests/pict-pure-test.rkt'", runner)
        self.assertIn("ROOT / 'tests/pict-native-test.rkt'", runner)


class R4gRacketDrawBridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        cls.definitions, cls.chapters = checks.document_definitions(ROOT)
        cls.by_name = {row['name']: row for row in cls.definitions}
        cls.manifest_by_name = {row['name']: row for row in cls.manifest['definitions']}

    def text(self, chapter):
        return (ROOT / checks.REFERENCE / (chapter + '.scrbl')).read_text()

    def test_racket_draw_bridge_closes_the_current_inventory(self):
        result = checks.check_source(ROOT, require_complete=True)
        self.assertEqual(len(result['definitions']), 1263)
        self.assertEqual(result['documented_exports'], 1988)
        self.assertEqual(result['inventory_exports'], 1988)
        self.assertEqual(result['reflected_inventory_exports'], 1988)
        self.assertEqual(result['source_verified_export_additions'], 0)
        self.assertEqual(result['deferred'], [])
        self.assertEqual(len(result['chapters']) - 1, 84)
        self.assertEqual(self.manifest['stage'], 'R4g')
        self.assertEqual(self.manifest['reviewed_repository_commit'],
                         '4dbbdcc3ab46d896ddd5f2c1de535ea2bab01cb1')

    def test_racket_draw_module_exports_exactly_the_reviewed_boundary(self):
        rows = [row for row in self.manifest['definitions']
                if 'skia/racket-draw' in row['exports']]
        self.assertEqual({row['name'] for row in rows}, {
            'bitmap->image', 'image->bitmap', 'surface->bitmap',
            'color%->rgba', 'rgba->color%',
            'dc-path->skia-path', 'skia-path->dc-path'})
        for name in ('bitmap->image', 'color%->rgba', 'rgba->color%',
                     'dc-path->skia-path', 'skia-path->dc-path'):
            self.assertEqual(self.manifest_by_name[name]['canonical_module'], 'skia/racket-draw')
        for name in ('image->bitmap', 'surface->bitmap'):
            self.assertEqual(self.manifest_by_name[name]['canonical_module'], 'skia/bitmap')

    def test_racket_draw_call_boundaries_match_the_reflected_inventory(self):
        expected = {
            'bitmap->image': ['mask', 'resolution'],
            'color%->rgba': [],
            'rgba->color%': [],
            'dc-path->skia-path': ['fill-style'],
            'skia-path->dc-path': ['conic-subdivisions'],
        }
        for name, keywords in expected.items():
            with self.subTest(name=name):
                spec = self.by_name[name]
                self.assertEqual(spec['arity_mask'], '2')
                self.assertEqual(spec['allowed_keywords'], keywords)
                self.assertEqual(spec['required_keywords'], [])

    def test_racket_draw_reference_is_discoverable_and_explicit(self):
        root = self.text('reference')
        group = self.text('racket-integration')
        pict = group.index('@include-section["pict-bridge.scrbl"]')
        bridge = group.index('@include-section["racket-draw.scrbl"]')
        self.assertLess(pict, bridge)
        self.assertIn('@include-reference-section["racket-integration.scrbl"]', root)
        self.assertEqual(root.count('@include-reference-section['), 13)
        prose = ' '.join(self.text('racket-draw').split())
        for phrase in ('provides explicit conversions', 'eagerly copies',
                       'not re-exported', 'loaded-mask identity',
                       'Fully transparent output has zero RGB',
                       'at most one final open subpath', 'zero through five'):
            self.assertIn(phrase, prose)
        links = (ROOT / checks.REFERENCE / 'tests/links.scrbl').read_text()
        for name in ('bitmap->image', 'image->bitmap', 'surface->bitmap',
                     'color%->rgba', 'rgba->color%',
                     'dc-path->skia-path', 'skia-path->dc-path'):
            self.assertIn('@racket[racket-draw:' + name + ']', links)

    def test_reference_validation_runs_racket_draw_suites(self):
        runner = (ROOT / 'tools/check-reference.py').read_text()
        self.assertIn("run('racket-draw-pure-tests'", runner)
        for source in ('racket-draw-pure-test.rkt', 'racket-draw-native-test.rkt',
                       'racket-draw-consumer-test.rkt'):
            self.assertIn("ROOT / 'tests/" + source + "'", runner)


if __name__ == '__main__':
    unittest.main()

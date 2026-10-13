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


def row(name, arity, keywords, kind='procedure'):
    return dict(name=name, phase='0', kind=kind, export_kind='value', arity_mask=str(arity),
                required_keywords=COLOR_REQUIRED_KEYWORDS.get(name, []), allowed_keywords=keywords)


def synthetic_inventory():
    """Independent test snapshots; never stand in for the repository's pinned files."""
    exports = [row(name, arity, keywords) for name, (arity, keywords) in PROCEDURES.items()]
    exports += [row('current-skia-byte-limit', 3, [], 'parameter'),
                dict(name='with-skia', phase='0', kind='syntax', export_kind='syntax'),
                dict(name='with-canvas-state', phase='0', kind='syntax', export_kind='syntax'),
                dict(name='matrix-identity', phase='0', kind='value', export_kind='value'),
                row('surface-properties-of', 2, []),
                dict(name='struct:rgba', phase='0', kind='value', export_kind='value')]
    snapshots = [dict(modules=[dict(path='main.rkt', exports=exports),
                                    dict(path='color.rkt', exports=[
                                        copy.deepcopy(item) for item in exports
                                        if item['name'] in (
                                            'color?', 'color->argb', 'color->rgba',
                                            'rgba', 'rgba?', 'rgba-red', 'rgba-green',
                                            'rgba-blue', 'rgba-alpha', 'struct:rgba', 'rgb')])]),
                      dict(modules=[])]
    for path, names in (('matrix.rkt', MATRIX_EXPORTS), ('geometry.rkt', GEOMETRY_EXPORTS),
                        ('typefaces.rkt', TYPEFACE_EXPORTS), ('fonts.rkt', FONT_EXPORTS),
                        ('text-blobs.rkt', BLOB_EXPORTS), ('geometry-primitives.rkt', ATLAS_EXPORTS),
                        ('effects.rkt', EFFECT_EXPORTS), ('color-filters.rkt', COLOR_FILTER_EXPORTS),
                        ('runtime-effects.rkt', RUNTIME_EXPORTS),
                        ('color-space.rkt', COLOR_SPACE_EXPORTS),
                        ('color4f.rkt', COLOR4F_EXPORTS), ('float-colors.rkt', FLOAT_COLOR_EXPORTS),
                        ('image-info.rkt', DESCRIPTOR_EXPORTS)):
        snapshots[0]['modules'].append(dict(
            path=path, exports=[copy.deepcopy(item) for item in exports
                                if item['name'] in names]))
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
        self.assertEqual(len(result['definitions']), 538)
        self.assertEqual(result['documented_exports'], 742)
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
        self.assertEqual(len(self.check()['definitions']), 538)

    def test_scribble_comments_are_not_definitions(self):
        path = self.root / checks.REFERENCE / 'drawing.scrbl'
        path.write_text(path.read_text() + '\n@;{@defproc[(fake) any/c]{No.}}\n')
        self.assertEqual(len(self.check()['definitions']), 538)

    def test_cyclic_chapter_include(self):
        path = self.root / checks.REFERENCE / 'drawing.scrbl'
        path.write_text(path.read_text() + '\n@include-section["reference.scrbl"]\n')
        with self.assertRaisesRegex(checks.CheckError, 'cyclic'):
            self.check()

    def test_unsafe_chapter_path(self):
        self.change('reference.scrbl', '"drawing.scrbl"', '"../../outside.scrbl"')
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
        with self.assertRaisesRegex(checks.CheckError, 'wrong tutorial link'):
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
              patch.object(self.runner, 'check_source', return_value=self.source),
              patch.object(self.runner.shutil, 'which', return_value=None),
              contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO())):
            result = self.runner.main(['--render', '--output', str(self.output)])
        self.assertEqual(result, 1)
        report = json.loads((self.output / 'validation.json').read_text())
        self.assertFalse(report['racket_executed'])
        self.assertFalse(report['scribble_rendered'])
        self.assertEqual(report['commands'], [])



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
        self.assertEqual(len(blocks), 2)
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
        self.assertEqual(len(result['definitions']), 538)
        self.assertEqual(result['documented_exports'], 742)
        self.assertEqual(len(result['chapters']), 24)  # Root plus twenty-three chapters.


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
        text = self.index.read_text().replace(rows[0]['directory'], rows[1]['directory'])
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
        matrix = self.snapshots[0]['modules'][2]
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

    def test_public_subset_does_not_claim_extended_geometry(self):
        names = {row['name'] for row in self.check()['definitions']}
        self.assertNotIn('path-arc-to!', names)
        self.assertNotIn('make-gpu-context', names)
        self.assertNotIn('make-raster-buffer', names)


class R2ProseTests(unittest.TestCase):
    def text(self, name):
        return (ROOT / checks.REFERENCE / name).read_text()

    def test_matrix_order_and_rounding_are_explicit(self):
        text = self.text('matrices.scrbl')
        self.assertIn('xx, yx, xy, yy, x0, y0', text)
        self.assertIn('last\nmatrix acts on a point first', text)
        self.assertIn('single precision', text)

    def test_surface_snapshot_does_not_promise_eager_copy(self):
        self.assertIn('does not promise an immediate copy', self.text('surfaces.scrbl'))

    def test_image_sampling_defaults_differ(self):
        definitions, _ = checks.document_definitions(ROOT)
        names = {spec['name']: spec for spec in definitions}
        for name, arity in (('draw-image', '16'), ('draw-image-rect', '64'),
                            ('draw-image-subrect', '1024')):
            self.assertEqual(names[name]['arity_mask'], arity)
        text = self.text('images.scrbl')
        self.assertIn("'nearest]", text)
        self.assertIn("'linear]", text)
        self.assertIn('fractional drawing scalars', text)

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
        self.assertEqual(count, 63)

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

    def test_later_batches_are_not_counted_as_documented(self):
        names = {e['name'] for e in self.check()['definitions']}
        for name in ('make-region', 'make-pdf-document', 'make-gpu-context',
                     'make-picture-image-filter', 'make-raster-buffer'):
            self.assertNotIn(name, names)


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
        self.assertIn('The count is not a UTF-8 byte offset.', ' '.join(self.text('fonts').split()))
        self.assertIn('A cluster is a UTF-8 byte offset', self.text('shaping'))
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
        self.assertEqual(total, 24)

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
        shared = self.text('text-layout').split('@defproc[(layout-text', 1)[0]
        self.assertIn('does not enable these script-specific justification opportunities', shared)

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
        self.assertEqual(sum(form == 'racketblock' for form, _, _ in forms), 7)
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
        self.assertIn('not a\ncanvas clip', self.text('image-filters'))
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
        self.assertEqual(count, 7)

    def test_effect_acceptance_is_wired_into_the_existing_runner(self):
        text = (ROOT / 'tools/check-reference.py').read_text()
        self.assertIn('tools/reference-effects-pure-test.rkt', text)
        self.assertIn('tools/reference-effects-test.rkt', text)
        for file, count in [('reference-effects-pure-test.rkt', 6),
                            ('reference-effects-test.rkt', 17)]:
            source = (ROOT / 'tools' / file).read_text()
            checks.Reader('(' + source.split('\n', 1)[1] + ')').read()
            self.assertEqual(source.count('(test-case '), count)

    def test_picture_filter_is_explicitly_reserved_for_the_picture_batch(self):
        manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        self.assertNotIn('make-picture-image-filter', {r['name'] for r in manifest['definitions']})
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
                              ('image-info', DESCRIPTOR_EXPORTS)):
            actual = [row['name'] for row in manifest['definitions']
                      if 'skia/' + module in row['exports']]
            self.assertEqual(sorted(actual), sorted(names))
            self.assertEqual(len(actual), len(set(actual)))
        self.assertEqual(len(manifest['definitions']), 538)
        self.assertEqual(sum(len(r['exports']) for r in manifest['definitions']), 742)

    def test_real_inventory_pins_are_not_replaced_by_test_snapshots(self):
        manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        self.assertEqual({row['file']: row['git_blob'] for row in manifest['snapshots']}, {
            'api/public-api-headless.json': '2cadbe3212b62c3becfb0e184a1adc119639b750',
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
        self.assertIn('check_targets(site, targets', driver)
        self.assertIn('check_review_html(html)', review_src)
        self.assertIn('check_review_html(extracted_html)', review_src)



if __name__ == '__main__':
    unittest.main()

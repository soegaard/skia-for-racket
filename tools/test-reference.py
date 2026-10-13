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


def row(name, arity, keywords, kind='procedure'):
    return dict(name=name, phase='0', kind=kind, export_kind='value', arity_mask=str(arity),
                required_keywords=[], allowed_keywords=keywords)


class Fixtures(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        shutil.copytree(ROOT / checks.REFERENCE, self.root / checks.REFERENCE)
        shutil.copy(ROOT / 'info.rkt', self.root / 'info.rkt')
        (self.root / 'api').mkdir()
        self.manifest = json.loads((ROOT / checks.MANIFEST).read_text())
        exports = [row(name, arity, keywords) for name, (arity, keywords) in PROCEDURES.items()]
        exports += [row('current-skia-byte-limit', 3, [], 'parameter'),
                    dict(name='with-skia', phase='0', kind='syntax', export_kind='syntax'),
                    dict(name='with-canvas-state', phase='0', kind='syntax', export_kind='syntax'),
                    dict(name='matrix-identity', phase='0', kind='value', export_kind='value'),
                    row('surface-properties-of', 2, []),
                    dict(name='struct:rgba', phase='0', kind='value', export_kind='value')]
        self.snapshots = [dict(modules=[dict(path='main.rkt', exports=exports),
                                        dict(path='color.rkt', exports=[
                                            copy.deepcopy(item) for item in exports
                                            if item['name'] in (
                                                'color?', 'color->argb', 'color->rgba',
                                                'rgba', 'rgba?', 'rgba-red', 'rgba-green',
                                                'rgba-blue', 'rgba-alpha', 'struct:rgba', 'rgb')])]),
                          dict(modules=[])]
        for path, names in (('matrix.rkt', MATRIX_EXPORTS), ('geometry.rkt', GEOMETRY_EXPORTS)):
            self.snapshots[0]['modules'].append(dict(
                path=path, exports=[copy.deepcopy(item) for item in exports
                                    if item['name'] in names]))
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

    def test_real_authored_source_shape(self):
        result = self.check()
        self.assertEqual(len(result['definitions']), 209)
        self.assertEqual(result['documented_exports'], 252)
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
        self.assertEqual(len(self.check()['definitions']), 209)

    def test_scribble_comments_are_not_definitions(self):
        path = self.root / checks.REFERENCE / 'drawing.scrbl'
        path.write_text(path.read_text() + '\n@;{@defproc[(fake) any/c]{No.}}\n')
        self.assertEqual(len(self.check()['definitions']), 209)

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
        self.assertEqual(spec['chapter'], 'scribblings/reference/colors.scrbl')
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
        with (patch.object(self.runner, 'check_source', return_value=self.source),
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
        with (patch.object(self.runner, 'check_source', return_value=self.source),
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
        with (patch.object(self.runner, 'check_source', return_value=self.source),
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
        self.assertEqual(len(result['definitions']), 209)
        self.assertEqual(result['documented_exports'], 252)
        self.assertEqual(len(result['chapters']), 13)  # Root plus seven chapters.


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
        self.source = checks.check_source(self.root, documents_only=True)
        self.hashes = review.source_hashes(self.root)
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
        self.evidence = dict(status='passed', xref_checked=True, targets=targets,
                             tutorial_targets=tutorial_targets)

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


if __name__ == '__main__':
    unittest.main()

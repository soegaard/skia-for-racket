"""Resolve repository source ownership without changing logical public API paths.

Historical API inventories use collection-relative names. The concrete library
and documentation roots are explicit here; standalone installed helpers and old
unit-test fixtures already have a collection root and need no translation.
"""
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
SOURCE_PACKAGES = ('skia', 'skia-lib', 'skia-doc')
NATIVE_PACKAGES = ('skia-native-macos-1', 'skia-native-x86_64-linux-1',
                   'skia-native-win32-x86_64-1')
CATALOG_PACKAGES = SOURCE_PACKAGES + NATIVE_PACKAGES
INSTALLED_TOOLS = frozenset((
    'doctor.rkt', 'ci-import-smoke.rkt', 'ci-package-smoke.rkt', 'catalog-smoke.rkt',
    'install-windows-natives.rkt', 'check-package-version.rkt',
    'native-abi-reject.rkt', 'native-abi-doctor.rkt',
    'annotation-doctor.rkt',
    'canvas-doctor.rkt',
    'codec-doctor.rkt',
    'color-output-doctor.rkt',
    'filter-graph-doctor.rkt',
    'geometry-doctor.rkt',
    'output-audit-doctor.rkt',
    'output-doctor.rkt',
    'path-matrix-doctor.rkt',
    'pdf-doctor.rkt',
    'picture-doctor.rkt',
    'projective-doctor.rkt',
    'runtime-doctor.rkt',
    'svg-doctor.rkt',

))


def library_root(root=ROOT):
    root = Path(root)
    return root / 'skia-lib' if (root / 'skia-lib/info.rkt').is_file() else root


def documentation_root(root=ROOT):
    root = Path(root)
    return root / 'skia-doc' if (root / 'skia-doc/info.rkt').is_file() else root


def source_path(root, relative):
    """Map validated legacy collection-relative source names to their owner."""
    root = Path(root)
    parts = PurePosixPath(relative).parts
    if not parts:
        return root
    if parts[0] == 'scribblings':
        return documentation_root(root).joinpath(*parts)
    if parts[0] in ('private', 'unsafe', 'tests', 'examples', 'native') or (
            len(parts) == 1 and parts[0].endswith('.rkt')):
        return library_root(root).joinpath(*parts)
    if len(parts) > 1 and parts[0] == 'tools':
        if parts[1] == 'copy-tutorial-examples.rkt':
            return documentation_root(root).joinpath(*parts)
        if parts[1] in INSTALLED_TOOLS:
            return library_root(root).joinpath(*parts)
    return root.joinpath(*parts)

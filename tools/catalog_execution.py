"""Shared relocatable runtime checks and Windows network-denial coverage."""
import os
from pathlib import Path

from native_packages import need, read_json, sha256

PKG_BUILD_PROFILE = dict(schema=1, machine_independent=True,
                         upstream_commit='23cacfcedaead1021dff6bf97ae4a5852af2acfc')
PROFILE_FILE = 'etc/skia-catalog-runtime.json'


RUNTIME_ENVIRONMENTS = (
    'source installation', 'scope lifecycle', 'foreign target data',
    'reinstalled source', 'reinstalled built', 'reinstalled binary-lib',
)


def relocatable_runtime(directory: Path) -> Path:
    """Reject system prefixes before any disposable runtime is copied."""
    directory = directory.resolve()
    executable = any((directory / name).is_file()
                     for name in ('bin/racket', 'Racket.exe', 'racket.exe'))
    need(executable and (directory / 'collects/racket/base.rkt').is_file(),
         'catalog validation requires a self-contained relocatable Racket directory, '
         'not a system prefix: ' + str(directory) + '; configure setup-racket with its dest input')
    return directory


def preserved_package_files(directory: Path) -> dict[str, str]:
    """Identify data and notices using ZIP names, independently of host separators."""
    return {path.relative_to(directory).as_posix(): sha256(path.read_bytes())
            for path in directory.rglob('*')
            if path.is_file() and not path.is_symlink() and path.name != 'info.rkt'
            and path.suffix not in ('.zo', '.dep')}


def runtime_root(executable: Path):
    return executable.parent.parent if executable.parent.name == 'bin' else executable.parent


def runtime_profile(executable: Path):
    """Read only the explicit profile installed in an owned qualification runtime."""
    path = runtime_root(executable) / PROFILE_FILE
    if not path.exists() and not path.is_symlink():
        return None
    profile = read_json(path)
    need(profile == PKG_BUILD_PROFILE, 'unreviewed catalog runtime execution profile')
    return profile


def racket_command(executable: Path, *, profile=None):
    """Match pkg-build's machine-independent flags and per-runtime compiled cache."""
    command = [str(executable)]
    if profile is None:
        profile = runtime_profile(executable)
    if profile is not None:
        need(profile == PKG_BUILD_PROFILE, 'unreviewed catalog runtime execution profile')
        command.extend(['-MCR', str(runtime_root(executable) / 'zo') + os.pathsep])
    return command


def windows_network_programs(output: Path, python: Path):
    """Cover the validator and every Racket copy it is allowed to create."""
    return [python, *(output / 'execution' / name / 'Racket runtime' / executable
                      for name in RUNTIME_ENVIRONMENTS
                      for executable in ('Racket.exe', 'racket.exe'))]

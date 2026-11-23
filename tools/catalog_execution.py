"""Shared relocatable runtime checks and Windows network-denial coverage."""
import os
from pathlib import Path, PurePosixPath

from native_packages import need, read_json, sha256

PKG_BUILD_PROFILE = dict(schema=1, machine_independent=True,
                         upstream_commit='23cacfcedaead1021dff6bf97ae4a5852af2acfc')
PROFILE_FILE = 'etc/skia-catalog-runtime.json'


RUNTIME_ENVIRONMENTS = (
    'source installation', 'library-only installation', 'scope lifecycle', 'foreign target data',
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


def runtime_child_environment(executable: Path, *, profile=None):
    """Match pkg-build's inherited cache path for Racket-created subprocesses."""
    if profile is None:
        profile = runtime_profile(executable)
    if profile is None:
        return {}
    need(profile == PKG_BUILD_PROFILE, 'unreviewed catalog runtime execution profile')
    return dict(PLTCOMPILEDROOTS=str(runtime_root(executable) / 'zo') + os.pathsep)


def verify_drdr_child(child, runtime, *, version, target):
    """Require observed subprocess cache reuse, not just parent command flags."""
    runtime = PurePosixPath(runtime)
    cache = str(runtime / 'zo')
    need(type(child) is dict and child.get('version') == version and child.get('target') == target
         and type(child.get('running_machine')) is str and bool(child['running_machine'])
         and child.get('compile_target_machine') == child['running_machine']
         and child.get('compiled_roots') == [cache, 'same']
         and child.get('compiled_roots_environment') == cache + ':'
         and type(child.get('executable')) is str and runtime.is_absolute()
         and '..' not in PurePosixPath(child['executable']).parts
         and PurePosixPath(child['executable']).is_relative_to(runtime),
         'natipkg DrDr subprocess did not inherit the reviewed compiled cache and native execution mode')


def relocate_runtime_cache(source: Path, copied: Path):
    """Rekey the copied pkg-build cache for Racket's absolute-source-path layout."""
    source, copied = source.resolve(), copied.resolve()
    if runtime_profile(source / 'bin/racket') is None:
        return None
    cache = copied / 'zo'
    old = cache / source.relative_to(source.anchor)
    new = cache / copied.relative_to(copied.anchor)
    need(cache.is_dir() and not cache.is_symlink() and old.is_dir() and not old.is_symlink(),
         'prepared runtime lacks its bootstrapped absolute-path cache')
    need(old.resolve().is_relative_to(cache.resolve()) and new.resolve().is_relative_to(cache.resolve())
         and not old.is_relative_to(new) and not new.is_relative_to(old),
         'runtime cache relocation escapes or overlaps its owned cache')
    need(not new.exists() and not new.is_symlink(), 'runtime cache relocation destination already exists')
    bytecode_files = 0
    for path in old.rglob('*'):
        need(not path.is_symlink(), 'symlink in bootstrapped runtime cache')
        bytecode_files += path.is_file() and path.suffix == '.zo'
    need(bytecode_files > 0, 'prepared runtime cache has no compiled modules')
    new.parent.mkdir(parents=True, exist_ok=True)
    old.rename(new)
    return dict(source_runtime=str(source), copied_runtime=str(copied),
                old_cache=str(old), new_cache=str(new), bytecode_files=bytecode_files)


def windows_network_programs(output: Path, python: Path):
    """Cover the validator and every Racket copy it is allowed to create."""
    return [python, *(output / 'execution' / name / 'Racket runtime' / executable
                      for name in RUNTIME_ENVIRONMENTS
                      for executable in ('Racket.exe', 'racket.exe'))]

"""Shared relocatable runtime checks and Windows network-denial coverage."""
from pathlib import Path

from native_packages import need


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


def windows_network_programs(output: Path, python: Path):
    """Cover the validator and every Racket copy it is allowed to create."""
    return [python, *(output / 'execution' / name / 'Racket runtime' / executable
                      for name in RUNTIME_ENVIRONMENTS
                      for executable in ('Racket.exe', 'racket.exe'))]

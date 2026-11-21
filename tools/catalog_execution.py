"""Shared disposable runtime names and Windows network-denial coverage."""
from pathlib import Path


RUNTIME_ENVIRONMENTS = (
    'source installation', 'scope lifecycle', 'foreign target data',
    'reinstalled source', 'reinstalled built', 'reinstalled binary-lib',
)


def windows_network_programs(output: Path, python: Path):
    """Cover the validator and every Racket copy it is allowed to create."""
    return [python, *(output / 'execution' / name / 'Racket runtime' / executable
                      for name in RUNTIME_ENVIRONMENTS
                      for executable in ('Racket.exe', 'racket.exe'))]

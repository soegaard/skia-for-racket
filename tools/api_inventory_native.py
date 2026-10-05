"""Isolated symbol-resolution observer for the pinned m119 library.

The parent never dlopens a native library. The child calls only two scalar
version functions; all other observations are address resolution, not execution.
An exported platform stub can resolve successfully. No backend is created.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile
import uuid

MAX_LIBRARY = 256 * 1024 * 1024
SYMBOL = re.compile(r"(?:sk|gr)_[A-Za-z0-9_]+\Z")


def _check(ok, message):
    if not ok: raise ValueError(message)


def _json(path):
    def pairs(items):
        out = {}
        for k, v in items:
            _check(k not in out, "duplicate probe key")
            out[k] = v
        return out
    p = Path(path)
    _check(p.is_file() and not p.is_symlink() and p.stat().st_size <= 2 * 1024 * 1024, "invalid probe file")
    data = json.loads(p.read_text(encoding="utf-8"), object_pairs_hook=pairs,
                      parse_constant=lambda _x: (_ for _ in ()).throw(ValueError("nonfinite probe JSON")))
    _check(type(data) is dict, "probe object required")
    return data


def _sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _worker(input_path, output_path):
    spec = _json(input_path)
    _check(set(spec) == {"library", "sha256", "symbols", "token"}, "invalid worker specification")
    path = Path(spec["library"])
    _check(path.is_absolute() and path.is_file() and not path.is_symlink(), "expected absolute regular library")
    _check(0 < path.stat().st_size <= MAX_LIBRARY, "invalid library size")
    _check(_sha(path) == spec["sha256"], "library changed before probe")
    symbols = spec["symbols"]
    _check(type(symbols) is list and bool(symbols) and len(symbols) == len(set(symbols)) and
           all(type(n) is str and SYMBOL.fullmatch(n) for n in symbols), "invalid symbol list")
    _check(re.fullmatch(r"[0-9a-f]{32}", spec["token"]) is not None, "invalid invocation token")
    _check(not Path(output_path).exists(), "worker result already exists")
    import ctypes
    library = ctypes.CDLL(str(path))
    def scalar(name):
        f = getattr(library, name)
        f.argtypes, f.restype = [], ctypes.c_int
        return f()
    version = (scalar("sk_version_get_milestone"), scalar("sk_version_get_increment"))
    _check(version == (119, 0), f"expected pinned ABI 119.0, observed {version}")
    observed = {}
    for name in symbols:
        try:
            getattr(library, name)
            observed[name] = True
        except AttributeError:
            observed[name] = False
    _check(_sha(path) == spec["sha256"], "library changed during probe")
    result = {"schema": 1, "stage": "0.67", "status": "observed", "token": spec["token"],
              "library": str(path), "library_sha256": spec["sha256"], "library_bytes": path.stat().st_size,
              "abi": "119.0", "system": platform.system(), "machine": platform.machine(),
              "pointer_bytes": ctypes.sizeof(ctypes.c_void_p), "symbols": observed,
              "native_calls": ["sk_version_get_milestone", "sk_version_get_increment"],
              "scope": "symbol resolution, not enumeration of direct exports or proof that a platform stub works",
              "backend_created": False, "rendering_executed": False, "hardware_verified": False,
              "package_version_verified": False, "signature_compatibility_verified": False}
    Path(output_path).write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def validate_observation(result, *, token, library, sha256, symbols, required=()):
    _check(type(result.get("schema")) is int and result["schema"] == 1 and result.get("stage") == "0.67", "invalid observation schema")
    _check(result.get("status") == "observed" and result.get("token") == token, "stale/incomplete native observation")
    _check(result.get("library") == str(library) and result.get("library_sha256") == sha256, "foreign native observation")
    _check(result.get("abi") == "119.0" and result.get("pointer_bytes") == 8, "wrong native ABI/platform")
    _check(result.get("native_calls") == ["sk_version_get_milestone", "sk_version_get_increment"], "unexpected native execution")
    for flag in ("backend_created", "rendering_executed", "hardware_verified", "package_version_verified", "signature_compatibility_verified"):
        _check(result.get(flag) is False, "invalid native evidence claim: " + flag)
    values = result.get("symbols")
    _check(type(values) is dict and set(values) == set(symbols) and all(type(v) is bool for v in values.values()), "incomplete symbol inventory")
    _check(all(values.get(s) is True for s in required), "required CPU binding did not resolve")
    return result


def observe(library: Path, symbols: list[str], *, required=(), directory: Path, timeout=120.0):
    library = library.resolve()
    _check(library.is_file() and 0 < library.stat().st_size <= MAX_LIBRARY, "native library missing or oversized")
    _check(not directory.exists(), "native evidence directory must be fresh")
    directory.mkdir(parents=True)
    token, sha = uuid.uuid4().hex, _sha(library)
    spec = {"library": str(library), "sha256": sha, "symbols": sorted(symbols), "token": token}
    input_path, output_path = directory / "input.json", directory / "observation.json"
    input_path.write_text(json.dumps(spec, sort_keys=True) + "\n", encoding="utf-8")
    command = [sys.executable, "-I", str(Path(__file__).resolve()), "--worker", str(input_path), str(output_path)]
    (directory / "command.json").write_text(json.dumps(command) + "\n", encoding="utf-8")
    try:
        with (directory / "stdout.log").open("wb") as stdout, (directory / "stderr.log").open("wb") as stderr:
            proc = subprocess.run(command, stdout=stdout, stderr=stderr, timeout=timeout, check=False)
        _check(proc.returncode == 0, f"native observer exited {proc.returncode}; see {directory / 'stderr.log'}")
        _check(library.is_file() and _sha(library) == sha, "library changed during observation")
        return validate_observation(_json(output_path), token=token, library=library, sha256=sha,
                                    symbols=symbols, required=required)
    except BaseException:
        # Partial files remain diagnostic evidence, never a parent success.
        raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", nargs=2, required=True, metavar=("INPUT", "OUTPUT"))
    args = parser.parse_args()
    try:
        _worker(*args.worker)
    except Exception as error:
        print(type(error).__name__ + ": " + str(error), file=sys.stderr)
        raise SystemExit(1)

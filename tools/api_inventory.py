"""0.75 capability inventory: offline declarations, source drift and explicit evidence.

No native library, GUI, or repository network access on import. Managed coverage
is source/capability-family coverage, NOT a reflection-based C# overload inventory.
"""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = 1
STAGE = "0.77b"
BASELINE = "242a1b71081e6e76d3209c115ab11ff4c09a3eb2"
HISTORICAL_BASELINE = "9d832d3ec9a8fe6b93298d6ac03783ee57ab7f36"
SKIA_COMMIT = "40f75dc0051d141913c07c20d4c19590c7da0cb7"
SHARP_COMMIT = "cc78b5933d23e6383db5d246e70db915770d55d6"
SYMBOL = re.compile(r"(?:sk|gr)_[A-Za-z0-9_]+\Z")
IDENTIFIER = re.compile(r"[a-z][a-z0-9.-]*\Z")
STATUSES = frozenset(("supported", "supported-with-limits", "racket-equivalent",
                      "bound-not-public", "missing-available-abi",
                      "unavailable-pinned-abi", "intentionally-excluded"))
STAGES = frozenset(f"0.{n}" for n in range(66, 79)) | {"0.68a", "0.68b", "0.75a", "0.75b", "0.76a", "0.76b", "0.76c", "0.77a", "0.77b", "0.77c", "G1", "G2", "U1", "U2", "U3", "H1", "X1"}
ORIGINS = frozenset(("m119", "c-shim-only", "future-extension"))
EVIDENCE_SCOPE = "not-asserted; test-source references and baseline CI evidence are separate"
CATALOG_FILES = ("api/upstream-m119.json", "api/bindings-baseline.json",
                 "api/capabilities.json", "api/baseline-evidence.json")
REPORT = "docs/SKIASHARP-GAPS.md"
MAX_JSON = 8 * 1024 * 1024
# Native-name argument positions, counting the form's operator as position 0.
# Metal's define-interop-native is deliberately NOT the GL macro's signature.
REGISTRIES = (
    ("private/native.rkt", "define-native", 1, "cpu"),
    ("private/gpu-native.rkt", "define-gpu-native", 2, "gpu-context"),
    ("private/gpu-surface-native.rkt", "define-surface-native", 3, "gpu-surface"),
    ("private/gpu-image-native.rkt", "define-image-native", 2, "gpu-image"),
    ("private/gpu-cache-native.rkt", "define-cache-native", 2, "gpu-cache"),
    ("private/gpu-gl-interop-native.rkt", "define-interop-native", 2, "gpu-interop-gl"),
    ("private/gpu-presentation-native.rkt", "define-call", 2, "gpu-presentation"),
    ("private/gpu-metal-interop-native.rkt", "define-interop-native", 1, "gpu-interop-metal"),
    ("private/gpu-d3d12-interop-native.rkt", "bind", 1, "gpu-interop-d3d12"),
)


def require(value: bool, message: str) -> None:
    if not value:
        raise ValueError(message)


def safe_file(root: Path, relative: str, *, must_exist: bool = True) -> Path:
    require(isinstance(relative, str) and bool(relative), "empty/non-string source path")
    pieces = relative.split("/")
    require(not relative.startswith("/") and "\\" not in relative and ":" not in relative
            and all(p not in ("", ".", "..") for p in pieces)
            and not any(ord(c) < 32 for c in relative), f"unsafe path: {relative!r}")
    # Use the canonical root only for containment. Preserve the caller's
    # lexical root in the returned path; on macOS /var resolves to /private/var.
    root_resolved = root.resolve()
    path = root.joinpath(*pieces)
    cursor = path
    while cursor != root:
        require(not cursor.is_symlink(), f"symlink in source path: {relative}")
        cursor = cursor.parent
    require(path.resolve().is_relative_to(root_resolved), f"path escapes root: {relative}")
    if must_exist:
        require(path.is_file(), f"missing file: {relative}")
    return path


def unique_object(pairs: list[tuple[str, Any]]) -> dict:
    out: dict = {}
    for key, value in pairs:
        require(key not in out, f"duplicate JSON key: {key}")
        out[key] = value
    return out


def read_json(path: Path) -> dict:
    require(not path.is_symlink() and path.is_file(), f"missing/symlink JSON: {path}")
    require(path.stat().st_size <= MAX_JSON, f"oversized JSON: {path}")
    def bad_constant(value: str):
        raise ValueError("nonfinite JSON value: " + value)
    value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object,
                       parse_constant=bad_constant)
    require(type(value) is dict, f"JSON object required: {path}")
    return value


def json_text(value: Any) -> str:
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=False) + "\n"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def strings(value: Any, context: str, *, nonempty: bool = False) -> list[str]:
    require(type(value) is list and all(type(x) is str and x for x in value), f"bad {context}")
    require(len(value) == len(set(value)), f"duplicate {context}")
    require(not nonempty or bool(value), f"empty {context}")
    return value


def load_catalog(root: Path = ROOT) -> dict:
    upstream, bindings, features, evidence = [read_json(safe_file(root, p)) for p in CATALOG_FILES]
    return {"upstream": upstream, "bindings": bindings, "features": features, "evidence": evidence}


def validate_catalog(catalog: dict) -> dict:
    u, b, d, e = (catalog[n] for n in ("upstream", "bindings", "features", "evidence"))
    for value in (u, b, d, e):
        require(type(value.get("schema")) is int and value["schema"] == SCHEMA, "wrong schema")
    require(d.get("stage") == STAGE and d.get("baseline_commit") == BASELINE, "wrong inventory stage/baseline")
    require(b.get("source_commit") == BASELINE, "wrong binding baseline")
    comparison = d.get("comparison", {})
    require(type(comparison) is dict and type(comparison.get("milestone")) is int and type(comparison.get("increment")) is int, "non-integer ABI identity")
    require(d.get("comparison") == dict(package="3.119.1", milestone=119, increment=0,
                                        minimum_racket="8.18", minimum_draw_lib="1.22"), "changed comparison/minimum")
    require(u.get("package_version") == "3.119.1" and u.get("skia_revision") == SKIA_COMMIT and u.get("skiasharp_revision") == SHARP_COMMIT, "wrong upstream comparison pin")
    require(type(u.get("headers")) is dict and bool(u["headers"]), "missing upstream headers")
    symbols: set[str] = set()
    for path, names in u["headers"].items():
        require(re.fullmatch(r"include/c/(sk|gr)_[a-z0-9_]+\.h", path) is not None, "bad header path")
        strings(names, "header symbols", nonempty=True)
        require(names == sorted(names) and all(SYMBOL.fullmatch(s) for s in names), "invalid/unsorted C declarations")
        require(not symbols.intersection(names), "duplicate C declaration across headers")
        symbols.update(names)
    expected = set(strings(b.get("symbols"), "binding symbols", nonempty=True))
    require(expected <= symbols, "binding outside pinned C inventory")
    cpu = set(strings(b.get("cpu_symbols"), "CPU symbols", nonempty=True))
    require(cpu <= expected, "CPU symbols outside binding inventory")
    managed = set(strings(u.get("managed_files"), "managed source files", nonempty=True))
    require(all(re.fullmatch(r"binding/SkiaSharp/[A-Za-z0-9_./]+\.cs", s) for s in managed), "bad managed file path")
    modules = set(strings(d.get("public_modules"), "public modules", nonempty=True))
    require(all(s.endswith(".rkt") and not s.startswith(("private/", "tests/", "tools/", "plans/")) for s in modules), "bad public module")
    assigned: set[str] = set()
    seen: set[str] = set()
    crosswalk = {path: [] for path in sorted(managed)}
    rows = d.get("capabilities")
    require(type(rows) is list and bool(rows), "missing capabilities")
    allowed = {"id", "title", "status", "planned_stage", "native_symbols", "public_equivalents", "implementation_files", "test_sources", "limitations", "document_behavior", "backend_scope", "managed_sources", "origin", "execution_evidence", "bindings_expected", "unbound_declarations"}
    for f in rows:
        require(type(f) is dict and set(f) == allowed, "unknown/missing capability fields")
        ident = f["id"]
        require(type(ident) is str and IDENTIFIER.fullmatch(ident) is not None and ident not in seen, "invalid/duplicate capability ID")
        seen.add(ident)
        require(f["status"] in STATUSES and f["origin"] in ORIGINS, f"unknown disposition: {ident}")
        require(f["planned_stage"] is None or f["planned_stage"] in STAGES, f"bad planned stage: {ident}")
        for field in ("title", "limitations", "document_behavior", "backend_scope"):
            require(type(f[field]) is str and bool(f[field].strip()), f"missing {field}: {ident}")
        require(f["execution_evidence"] == EVIDENCE_SCOPE, f"unreviewed execution claim: {ident}")
        syms = set(strings(f["native_symbols"], "capability symbols"))
        require(syms <= symbols and not syms & assigned, f"unknown/duplicate symbol disposition: {ident}")
        assigned.update(syms)
        require(f["bindings_expected"] == sorted(syms & expected), f"wrong binding classification: {ident}")
        require(f["unbound_declarations"] == sorted(syms - expected), f"wrong unbound classification: {ident}")
        if f["status"] in {"missing-available-abi", "unavailable-pinned-abi"}:
            require(f["planned_stage"] is not None, f"unplanned missing capability: {ident}")
        if f["status"] == "missing-available-abi":
            require(bool(syms) and not syms & expected, f"missing feature already bound: {ident}")
        if f["status"] == "unavailable-pinned-abi":
            require(not syms and f["origin"] == "future-extension", f"not an ABI-unavailable extension: {ident}")
        if f["status"] == "bound-not-public":
            require(bool(syms) and syms <= expected and not f["public_equivalents"], f"bad binding-only classification: {ident}")
        for field in ("implementation_files", "test_sources", "managed_sources"):
            strings(f[field], field)
        for path in f["managed_sources"]:
            require(path in managed, f"unknown managed source: {path}")
            crosswalk[path].append(ident)
        require(type(f["public_equivalents"]) is list, "bad public-equivalents list")
        for ref in f["public_equivalents"]:
            require(type(ref) is dict and set(ref) == {"module", "name"}, "bad public source anchor")
            require(ref["module"] in modules and type(ref["name"]) is str and ref["name"], "unknown public module/identifier")
        if f["status"] in {"supported", "supported-with-limits", "racket-equivalent"}:
            require(bool(f["public_equivalents"]) and bool(f["implementation_files"]) and bool(f["test_sources"]), f"supported capability needs source/test anchors: {ident}")
    require(assigned == symbols, "unclassified C declarations: " + repr(sorted(symbols - assigned)))
    require(all(crosswalk.values()), "unclassified managed source family")
    require(d.get("managed_source_crosswalk") == crosswalk, "managed crosswalk drift")
    # Important reconciliations from the review: keep them explicit and tested.
    indexed = {f["id"]: f for f in rows}
    require(indexed["paths.iteration"]["status"] == "supported-with-limits", "existing path iteration falsely missing")
    require(indexed["images.gpu-transfers"]["status"] == "supported-with-limits", "existing GPU transfer falsely missing")
    require(indexed["future.variable-fonts"]["status"] == "unavailable-pinned-abi", "variable fonts falsely attributed to m119")
    validate_historical_evidence(e)
    return {"capabilities": len(rows), "c_function_declarations": len(symbols), "managed_source_files": len(managed),
            "distinct_bound_symbols": len(expected), "cpu_bound_symbols": len(cpu),
            "public_modules": len(modules), "dispositions": dict(sorted(Counter(f["status"] for f in rows).items())),
            "next_stages": dict(sorted(Counter(f["planned_stage"] for f in rows if f["planned_stage"]).items()))}


def validate_historical_evidence(e: dict) -> None:
    # Historical evidence is deliberately aggregate-only. Never promote an
    # exported-symbol count or an m153 candidate probe to m119 per-symbol proof.
    require(e.get("source_commit") == HISTORICAL_BASELINE, "foreign historical evidence")
    require(e.get("per_symbol_export_list_retained") is False, "historical evidence cannot acquire an invented symbol list")
    require(e.get("scope") == "historical baseline CPU job; not 0.65 feature execution", "historical scope changed")
    require(e.get("rendering_claim_for_inventory_features") is False, "source inventory cannot claim historical feature execution")
    for key in ("artifact_sha256", "source_manifest_sha256"):
        require(type(e.get(key)) is str and re.fullmatch(r"[0-9a-f]{64}", e[key]), "bad historical digest")
    require(e.get("native_version") == "119.0", "historical ABI mismatch")


# A bounded declaration reader adapted from the existing native_abi.py approach.
# It is not a Racket expander. Unknown binding registries fail for review.
@dataclass(frozen=True)
class String:
    value: str


def forms(text: str) -> list:
    text = re.sub(r"\A(?:\ufeff)?#lang[^\n]*", "", text)
    tokens: list = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c.isspace(): i += 1; continue
        if c == ";":
            j = text.find("\n", i); i = n if j < 0 else j; continue
        if text.startswith("#|", i):
            depth, i = 1, i + 2
            while depth and i < n:
                if text.startswith("#|", i): depth += 1; i += 2
                elif text.startswith("|#", i): depth -= 1; i += 2
                else: i += 1
            require(depth == 0, "unterminated block comment"); continue
        if text.startswith("#;", i): tokens.append("#;"); i += 2; continue
        if text.startswith("#\\", i):
            i += 2; require(i < n, "incomplete character")
            i += 1
            while i < n and not text[i].isspace() and text[i] not in "()[]{}": i += 1
            tokens.append(String("<character>")); continue
        # Ordinary, byte and regexp strings all remain data, not identifiers.
        prefix = re.match(r'#(?:rx|px)?#?(?=")', text[i:]) if c == "#" else None
        if prefix:
            i += prefix.end(); c = text[i]
        if c == '"':
            i += 1; chars = []
            while i < n and text[i] != '"':
                if text[i] == "\\":
                    i += 1; require(i < n, "unterminated string escape")
                    esc = text[i]; chars.append({"n": "\n", "r": "\r", "t": "\t"}.get(esc, esc)); i += 1
                else: chars.append(text[i]); i += 1
            require(i < n, "unterminated string"); i += 1
            tokens.append(String("".join(chars))); continue
        if c in "()[]{}'`,":
            tokens.append(c); i += 1
            if c == "," and i < n and text[i] == "@": i += 1
            continue
        j = i
        while i < n and not text[i].isspace() and text[i] not in '()[]{};"': i += 1
        require(i > j, "unrecognized reader syntax")
        tokens.append(text[j:i])
    pos, skip = 0, object()
    closes = {"(": ")", "[": "]", "{": "}"}
    def read():
        nonlocal pos
        require(pos < len(tokens), "incomplete datum")
        t = tokens[pos]; pos += 1
        if isinstance(t, str) and t in closes:
            out = []
            while pos < len(tokens) and tokens[pos] != closes[t]:
                x = read()
                if x is not skip: out.append(x)
            require(pos < len(tokens), "unclosed datum"); pos += 1
            return out
        require(t not in (")", "]", "}"), "mismatched brackets")
        if t == "#;":
            x = read()
            while x is skip: x = read()
            return skip
        if t in ("'", "`", ","): return ["quote", read()]
        return t
    out = []
    while pos < len(tokens):
        x = read()
        if x is not skip: out.append(x)
    return out


def flat_atoms(value):
    if type(value) is str: yield value
    elif type(value) is list:
        for x in value: yield from flat_atoms(x)


def production_files(root: Path) -> list[str]:
    files = {p.name for p in root.glob("*.rkt") if p.name not in ("info.rkt", "run-tests.rkt")}
    for directory in ("private", "unsafe"):
        require((root / directory).is_dir() and not (root / directory).is_symlink(), f"missing/symlink {directory} directory")
        files.update(p.relative_to(root).as_posix() for p in (root / directory).rglob("*.rkt"))
    return sorted(files)


def scan_bindings(root: Path) -> dict:
    locations: dict[str, list[dict]] = {}
    registries = {p: (macro, index, group) for p, macro, index, group in REGISTRIES}
    seen_files: set[str] = set()
    source_hashes = {}
    for rel in production_files(root):
        path = safe_file(root, rel)
        source = path.read_text(encoding="utf-8")
        source_hashes[rel] = digest(path)
        nodes = forms(source)
        if rel == "private/graphics-trace-native.rkt":
            from global_cache_ffi import checked_imports as checked_trace_imports
            checked_trace_imports(root, forms, String)
            # These three Xamarin declarations are outside include/c. They are
            # validated exactly, not silently counted as additional C coverage.
            continue
        if rel == "private/live-port-native.rkt":
            from live_stream_ffi import checked_imports
            standard, extensions = checked_imports(root, forms, String)
            for name in standard:
                locations.setdefault(name, []).append(dict(file=rel, registry="live-stream-worker", macro="define-raw"))
            continue
        spec = registries.get(rel)
        found: set[str] = set()
        for form in nodes:
            if not isinstance(form, list) or not form: continue
            if spec and form[0] == spec[0]:
                macro, index, group = spec
                require(len(form) > index and type(form[index]) is str and SYMBOL.fullmatch(form[index]), f"unrecognized {macro} in {rel}")
                name = form[index]
                require(name not in found, f"duplicate native declaration: {rel}:{name}")
                found.add(name)
                locations.setdefault(name, []).append(dict(file=rel, registry=group, macro=macro))
            elif (type(form[0]) is str and form[0] not in
                  {"provide", "require", "quote", "define-syntax", "define-syntax-rule", "module", "module*", "module+", "define"}
                  and any(SYMBOL.fullmatch(x) for x in form[1:] if type(x) is str)):
                raise ValueError(f"unregistered native declaration in {rel}: {form[0]}")
        if spec:
            require(bool(found), f"empty native registry: {rel}"); seen_files.add(rel)
        # A new raw FFI binder in a production file is never silently ignored.
        # Existing OS/Pango/HarfBuzz libraries are excluded by their library
        # handle and prefix, not counted as Skia C ABI coverage.
        if not spec and "skia-native-library-handle" in set(flat_atoms(nodes)):
            calls = set(flat_atoms(nodes))
            if "get-ffi-obj" in calls and rel != "private/native-loader.rkt":
                raise ValueError(f"unregistered Skia FFI binding file: {rel}")
    require(seen_files == set(registries), "missing registered native files")
    return {"symbols": dict(sorted(locations.items())), "source_hashes": source_hashes, "registry_count": len(registries)}


def source_exports(root: Path, module: str, cache: dict | None = None, visiting: set | None = None) -> set[str]:
    """Resolve plain provide/all-from-out/rename-out/combine-out forms only.

    A declaration check, not macro expansion. An unsupported form cannot establish
    an anchor; it is recorded as absent and must be reviewed rather than guessed.
    """
    cache = {} if cache is None else cache
    visiting = set() if visiting is None else visiting
    if module in cache: return cache[module]
    require(module not in visiting, f"cyclic export source: {module}")
    visiting.add(module)
    out: set[str] = set()
    def relpath(value: str) -> str:
        # Source-authored ../ imports are normalized but still checked against root.
        path = (root / module).parent.joinpath(value).resolve()
        require(path.is_relative_to(root.resolve()), "reexport escapes source root")
        return path.relative_to(root.resolve()).as_posix()
    def spec(x):
        if type(x) is str:
            out.add(x)
        elif type(x) is list and x:
            if x[0] == "all-from-out":
                for y in x[1:]:
                    if isinstance(y, String): out.update(source_exports(root, relpath(y.value), cache, visiting))
            elif x[0] in ("combine-out", "protect-out"):
                for y in x[1:]: spec(y)
            elif x[0] == "rename-out":
                for y in x[1:]:
                    if type(y) is list and len(y) == 2 and type(y[1]) is str: out.add(y[1])
            elif x[0] == "struct-out" and len(x) == 2 and type(x[1]) is str:
                # Only constructor/predicate here. Accessor anchors must be explicit.
                out.update((x[1], x[1] + "?"))
            elif x[0] in ("except-out", "prefix-out"):
                # Intentionally unsupported for public anchors in this catalog.
                pass
    for f in forms(safe_file(root, module).read_text(encoding="utf-8")):
        if type(f) is list and f and f[0] == "provide":
            for x in f[1:]: spec(x)
    visiting.remove(module)
    cache[module] = out
    return out


def validate_sources(root: Path, catalog: dict) -> dict:
    validate_catalog(catalog)
    b, d = catalog["bindings"], catalog["features"]
    scan = scan_bindings(root)
    actual, expected = set(scan["symbols"]), set(b["symbols"])
    require(actual == expected, "binding drift: added=" + repr(sorted(actual - expected)) + " removed=" + repr(sorted(expected - actual)))
    cpu = {s for s, rows in scan["symbols"].items() if any(r["registry"] == "cpu" for r in rows)}
    require(cpu == set(b["cpu_symbols"]), "CPU registry drift")
    public = {p for p in production_files(root) if not p.startswith("private/")}
    require(public == set(d["public_modules"]), "public module inventory drift: " + repr(sorted(public ^ set(d["public_modules"]))))
    exports: dict = {}
    required = set(CATALOG_FILES)
    required.update(("api/global-cache-ffi.json", "tools/global_cache_ffi.py"))
    anchors = []
    for f in d["capabilities"]:
        for field in ("implementation_files", "test_sources"):
            for p in f[field]:
                safe_file(root, p); required.add(p)
        for ref in f["public_equivalents"]:
            names = source_exports(root, ref["module"], exports)
            require(ref["name"] in names, f"public declaration not found: {ref['module']}:{ref['name']} ({f['id']})")
            anchors.append(ref)
    info = safe_file(root, "info.rkt").read_text()
    for term in ('(define version "0.77")', '("base" #:version "8.18")', '("draw-lib" #:version "1.22")'):
        require(term in info, "package version/minimum mismatch: " + term)
    require(safe_file(root, "private/native-default-version.txt").read_text().strip() == "3.119.1", "native pin changed without inventory review")
    required.update(("info.rkt", "private/native-default-version.txt"))
    hashes = dict(scan["source_hashes"])
    hashes.update({p: digest(safe_file(root, p)) for p in sorted(required)})
    return {"registry_count": scan["registry_count"], "binding_locations": scan["symbols"],
            "source_hashes": hashes, "public_anchor_count": len({(x['module'], x['name']) for x in anchors}),
            "source_check": "complete production Racket file discovery plus declaration/anchor checks; not macro expansion",
            "rendering_executed": False}


def upstream_check(root: Path, commit: str, prefix: str, suffix: str) -> tuple[list[str], dict]:
    require(root.is_dir(), "upstream checkout is missing")
    def git(*args):
        result = subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True, timeout=120)
        return result.stdout
    require(git("rev-parse", "HEAD").decode().strip() == commit, "wrong upstream commit")
    paths = sorted(p for p in git("ls-tree", "-r", "--name-only", commit, "--", prefix).decode().splitlines() if p.endswith(suffix))
    hashes = {}
    for p in paths:
        file = safe_file(root, p)
        data = file.read_bytes()
        expected = git("rev-parse", commit + ":" + p).decode().strip()
        actual = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        require(actual == expected, "dirty/truncated upstream source: " + p)
        hashes[p] = {"git_blob": actual, "sha256": hashlib.sha256(data).hexdigest()}
    return paths, hashes


def c_functions(text: str) -> list[str]:
    clean = re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)
    names = re.findall(r"\bSK_C_API\s+(?:[^;{}]*?\s)?\b((?:sk|gr)_[A-Za-z0-9_]+)\s*\([^;{}]*\)\s*;", clean, re.S)
    require(len(names) == len(set(names)), "duplicate upstream C declarations")
    return sorted(names)


def verify_upstream(catalog: dict, skia: Path, sharp: Path) -> dict:
    u = catalog["upstream"]
    hpaths, hhashes = upstream_check(skia, SKIA_COMMIT, "include/c", ".h")
    cpaths, chashes = upstream_check(sharp, SHARP_COMMIT, "binding/SkiaSharp", ".cs")
    expected_h = set(u["headers"]) | set(u["non_function_headers"]) | set(u["excluded_headers"])
    require(set(hpaths) == expected_h, "upstream C header tree drift")
    require(cpaths == u["managed_files"], "upstream managed source tree drift")
    for path, names in u["headers"].items():
        observed = c_functions(safe_file(skia, path).read_text(encoding="utf-8-sig"))
        require(observed == names, f"upstream C declaration drift: {path}; added={sorted(set(observed)-set(names))}; missing={sorted(set(names)-set(observed))}")
    return {"skia_commit": SKIA_COMMIT, "skiasharp_commit": SHARP_COMMIT, "header_hashes": hhashes,
            "managed_source_hashes": chashes, "managed_scope": "exact source tree/hash verification; not overload reflection",
            "rendering_executed": False}


def generated_report(catalog: dict) -> str:
    summary = validate_catalog(catalog)
    u, d = catalog["upstream"], catalog["features"]
    lines = ["# SkiaSharp capability inventory — 0.75", "", "<!-- Generated by tools/api-inventory.py --write. Edit api/*.json, not this report. -->", "",
             f"Baseline: `{BASELINE}`. Comparison: SkiaSharp **3.119.1**, Skia m119 at `{SKIA_COMMIT}`.", "",
             "## Scope and evidence", "",
             f"**{summary['capabilities']} capability families; {summary['c_function_declarations']} core C function declarations; {summary['managed_source_files']} managed source files; {summary['public_modules']} public Racket modules.**",
             f"The baseline expects **{summary['distinct_bound_symbols']} distinct bindings** across **nine registries**, including **{summary['cpu_bound_symbols']} CPU bindings**. These are not feature-completion percentages.", "",
             "Each scoped C declaration has exactly one primary disposition. Managed files map to one or more capability families; this does **not** classify every C# overload, property, enum value, platform UI package, or Skia add-on. Normalized C declarations are pinned inputs; the explicit upstream-checkout gate verifies their source bytes and names.", "",
             "`missing-available-abi` means a declaration exists in the pinned C interface, not that a particular native binary exports or implements it. `supported-with-limits` and `racket-equivalent` are reviewed source declarations. They do not certify every overload, backend, format, or pixel result.", "",
             "Historical baseline evidence retains a Linux aggregate symbol audit, **not** a per-symbol exported list. A fresh optional child-process probe records resolution for all scoped functions with exact library hash, ABI and invocation identity. Resolution of a stub still does not prove execution. No native/rendering result is invented by generating this report.", "",
             "See [API decisions](API-DESIGN-DECISIONS.md) for the additive image-info/color/lease design and [maintenance](../api/README.md) for scope, drift checks and validation commands.", "",
             "## Dispositions", "", "| Disposition | Capability families |", "|---|---:|"]
    lines += [f"| {k} | {v} |" for k, v in summary["dispositions"].items()]
    lines += ["", "## Capability map", "", "| ID / capability | Disposition | Planned stage | Public equivalent |", "|---|---|---|---|"]
    for f in d["capabilities"]:
        refs = "; ".join("`" + r["module"].removesuffix(".rkt") + ":" + r["name"] + "`" for r in f["public_equivalents"]) or "—"
        lines.append(f"| [{f['id']}](#{f['id'].replace('.', '-')}) — {f['title']} | {f['status']} | {f['planned_stage'] or '—'} | {refs} |")
    lines += ["", "## Detailed dispositions", ""]
    for f in d["capabilities"]:
        lines += [f"<a id=\"{f['id'].replace('.', '-')}\"></a>", f"### {f['id']} — {f['title']}", "",
                  f"**{f['status']}**; next stage: **{f['planned_stage'] or 'none scheduled'}**; origin: `{f['origin']}`.", "",
                  f["limitations"], "", "**Document behavior:** " + f["document_behavior"], "", "**Backend declaration:** " + f["backend_scope"], ""]
        if f["public_equivalents"]:
            lines.append("**Public source anchors:** " + ", ".join(f"`{r['module']}:{r['name']}`" for r in f["public_equivalents"]) + ".")
        if f["implementation_files"]: lines.append("**Implementation:** " + ", ".join(f"[{p}](../{p})" for p in f["implementation_files"]) + ".")
        if f["test_sources"]: lines.append("**Test sources, not execution receipts:** " + ", ".join(f"[{p}](../{p})" for p in f["test_sources"]) + ".")
        if f["native_symbols"]:
            lines += ["", "| C entry point | Binding declaration |", "|---|---|"]
            lines += [f"| `{s}` | {'Bound' if s in f['bindings_expected'] else 'Not bound'} |" for s in f["native_symbols"]]
        if f["managed_sources"]:
            lines += ["", "**Pinned managed source families:** " + ", ".join(f"[{PurePosixPath(p).name}](https://github.com/mono/SkiaSharp/blob/{SHARP_COMMIT}/{p})" for p in f["managed_sources"]) + "."]
        lines.append("")
    lines += ["## Explicit scope exclusions", "", "Skottie/resources/invalidation add-on headers and platform Views/UI packages are outside this core comparison. Native type/layout signatures still require the existing ABI validators. Runtime execution remains the responsibility of focused and cross-backend acceptance suites.", "",
              "## Upstream sources", "", f"- SkiaSharp source: https://github.com/mono/SkiaSharp/tree/{SHARP_COMMIT}/binding/SkiaSharp", f"- C headers: https://github.com/mono/skia/tree/{SKIA_COMMIT}/include/c", ""]
    return "\n".join(lines)


def check_report(root: Path, catalog: dict, *, write: bool = False) -> None:
    path = safe_file(root, REPORT, must_exist=not write)
    expected = generated_report(catalog)
    if write:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(expected, encoding="utf-8", newline="\n")
    else:
        require(path.read_text(encoding="utf-8") == expected, "generated report drift; review catalog then run --write")


def main(argv: list[str] | None = None, *, root: Path = ROOT) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--check", action="store_true", help="check catalog, complete checkout anchors and generated report (default)")
    modes.add_argument("--write", action="store_true", help="regenerate report only after catalog and full-source checks")
    parser.add_argument("--skia-source", type=Path)
    parser.add_argument("--skiasharp-source", type=Path)
    args = parser.parse_args(argv)
    if bool(args.skia_source) != bool(args.skiasharp_source): parser.error("supply both pinned upstream checkouts")
    try:
        catalog = load_catalog(root)
        summary = validate_catalog(catalog)
        source = validate_sources(root, catalog)
        if args.skia_source: verify_upstream(catalog, args.skia_source.resolve(), args.skiasharp_source.resolve())
        check_report(root, catalog, write=args.write)
        print(json_text({"schema": 1, "stage": STAGE, "status": "passed", "summary": summary,
                         "source_verified": True, "upstream_verified": bool(args.skia_source),
                         "registry_count": source["registry_count"], "native_symbols_probed": False,
                         "rendering_executed": False}), end="")
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print("API inventory FAILED: " + str(exc), file=sys.stderr)
        return 1

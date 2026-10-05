#!/usr/bin/env python3
"""0.68a fail-closed inventory gate with optional pinned sources/native observation.

Default gate checks the complete project checkout and generated report, without
native initialization. --native-library probes the explicitly selected binary in
a disposable process. --skia-source/--skiasharp-source verify exact upstream pins.
Existing native/rendering suites remain independent acceptance requirements.
"""
from __future__ import annotations
import argparse
import importlib.util
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid

import api_inventory as inventory
from api_inventory_native import observe


def source_manifest(root: Path):
    name = root / "tools/update-source-sums.py"
    spec = importlib.util.spec_from_file_location("source_sums_for_inventory", name)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    # A normal source checkout is mandatory here. Installed-copy validation is
    # already covered by the existing CI harness; never silently downgrade.
    count = module.check(root, manifest_only=False)
    return {"files": count, "sha256": inventory.digest(root / "SOURCE-SHA256SUMS.txt")}


def main(argv=None, *, root=inventory.ROOT):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path)
    parser.add_argument("--skia-source", type=Path)
    parser.add_argument("--skiasharp-source", type=Path)
    parser.add_argument("--native-library", type=Path)
    parser.add_argument("--timeout", type=float, default=120)
    args = parser.parse_args(argv)
    if bool(args.skia_source) != bool(args.skiasharp_source): parser.error("supply both pinned upstream checkouts")
    if not math.isfinite(args.timeout) or args.timeout <= 0: parser.error("positive finite timeout required")
    if args.directory:
        if args.directory.exists(): raise FileExistsError("evidence directory already exists")
        args.directory.mkdir(parents=True)
        out = args.directory.resolve()
    else:
        (root / "output").mkdir(exist_ok=True)
        out = Path(tempfile.mkdtemp(prefix="api-inventory-0.68a-", dir=root / "output"))
    report = {"schema": 1, "stage": "0.68a", "status": "failed", "run_token": uuid.uuid4().hex,
              "catalog_passed": False, "source_passed": False, "upstream_required": bool(args.skia_source),
              "upstream_passed": False, "native_required": bool(args.native_library), "native_observed": False,
              "rendering_executed": False, "backend_created": False, "hardware_verified": False}
    try:
        before = source_manifest(root)
        report["manifest_before"] = before
        catalog = inventory.load_catalog(root)
        report["summary"] = inventory.validate_catalog(catalog)
        report["catalog_passed"] = True
        source = inventory.validate_sources(root, catalog)
        inventory.check_report(root, catalog)
        report["source_passed"] = True
        (out / "source.json").write_text(inventory.json_text(source), encoding="utf-8")
        if args.skia_source:
            upstream = inventory.verify_upstream(catalog, args.skia_source.resolve(), args.skiasharp_source.resolve())
            (out / "upstream.json").write_text(inventory.json_text(upstream), encoding="utf-8")
            report["upstream_passed"] = True
        if args.native_library:
            symbols = sorted(s for names in catalog["upstream"]["headers"].values() for s in names)
            native = observe(args.native_library, symbols, required=catalog["bindings"]["cpu_symbols"],
                             directory=out / "native", timeout=args.timeout)
            report["native_observed"] = True
            report["native_resolution_counts"] = {"resolved": sum(native["symbols"].values()),
                                                    "missing": len(symbols) - sum(native["symbols"].values())}
            report["native_library_sha256"] = native["library_sha256"]
        # Hash every audited project source again: a changed checkout cannot get
        # a green receipt even when the manifest was regenerated during the run.
        after_source = inventory.validate_sources(root, catalog)
        inventory.require(after_source == source, "audited source changed during validation")
        inventory.check_report(root, inventory.load_catalog(root))
        after = source_manifest(root)
        inventory.require(before == after, "source manifest changed during validation")
        report["manifest_after"] = after
        report["status"] = "passed"
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        report["error"] = type(error).__name__ + ": " + str(error)
        print("API inventory FAILED: " + report["error"], file=sys.stderr)
    finally:
        (out / "validation.json").write_text(inventory.json_text(report), encoding="utf-8")
        print("Evidence: " + str(out))
    if report["status"] == "passed":
        print("API inventory selected gates passed; rendering NOT RUN.")
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

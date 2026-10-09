"""0.78b focused acceptance helpers; source support is not runtime evidence."""
from __future__ import annotations

import re
from pathlib import Path

PURE_CASES = 20
NATIVE_CASES = 24
STAGE = "0.78b"
BASELINE = "4a6082274e06456aa385fa9337c31528f2f44a4a"
NATIVE_SYMBOLS = frozenset(("sk_colorspace_xyz_concat", "sk_colorspace_xyz_invert"))
PUBLIC_NAMES = frozenset(("xyz-d50-concat", "xyz-d50-invert"))


def need(value: bool, message: str) -> None:
    if not value:
        raise ValueError(message)


def suite_output(text: str, label: str, count: int) -> None:
    """Reject empty, duplicate, partial, or error-containing RackUnit output."""
    need(re.findall(rf"^{re.escape(label)}: (\d+) cases, (\d+) failures\s*$", text, re.M)
         == [(str(count), "0")], "missing/duplicate/failed suite completion: " + label)
    need(re.findall(r"(\d+) success\(es\) (\d+) failure\(s\) (\d+) error\(s\) (\d+) test\(s\) run", text)
         == [(str(count), "0", "0", str(count))], "wrong or incomplete RackUnit result: " + label)
    need(not re.search(r"\b(?:ERROR|FAILURE)\b", text), "suite reported an error: " + label)


def source_contracts(root: Path) -> dict:
    # Imports are delayed so receipt tests do not need a complete checkout.
    import api_inventory as inv
    import release_scope as scope
    catalog = inv.load_catalog(root)
    summary = scope.audit(root)
    caps = {c["id"]: c for c in catalog["features"]["capabilities"]}
    xyz, null = caps["colors.xyz-ops"], caps["surfaces.null"]
    need(scope.STAGE == STAGE and scope.BASELINE == BASELINE, "wrong 0.78b review identity")
    need(summary["in_scope_gaps_closed"] and not summary["open_in_scope"], "0.78b still has open in-scope gaps")
    need(summary["release_ready"] is False, "scope closure must not imply release readiness")
    need(xyz["status"] == "supported-with-limits" and xyz["planned_stage"] is None,
         "XYZ arithmetic contract is not classified correctly")
    need(set(xyz["bindings_expected"]) == NATIVE_SYMBOLS and xyz["unbound_declarations"] == [],
         "XYZ native bindings are not fully inventoried")
    need(null["status"] == "intentionally-excluded" and null["planned_stage"] is None,
         "null surface exclusion must stay explicit, not masquerade as an equivalent")
    need(null["bindings_expected"] == [] and "sk_surface_new_null" in null["unbound_declarations"],
         "null-surface native factory must remain unbound")
    need(null["public_equivalents"] == [], "no-draw is an alternative, not null-surface equivalence")
    for module in ("color-space.rkt", "main.rkt"):
        names = inv.source_exports(root, module)
        need(PUBLIC_NAMES <= names, "missing public XYZ exports: " + module)
        need("sk_colorspace_xyz_concat" not in names and "sk_colorspace_xyz_invert" not in names,
             "raw XYZ pointers leaked through public exports")
    for kind, count in (("pure", PURE_CASES), ("native", NATIVE_CASES)):
        text = (root / f"tests/small-gap-{kind}-test.rkt").read_text(encoding="utf-8")
        need(text.count("(test-case ") == count, "test source count drift: " + kind)
        need(f"(define small-gap-{kind}-test-count {count})" in text, "test completion count drift")
        inv.forms(text)
    runner = (root / "run-tests.rkt").read_text(encoding="utf-8")
    need('"tests/small-gap-pure-test.rkt"' in runner and "(run-tests small-gap-pure-tests)" in runner,
         "pure suite missing from aggregate tests")
    need('"tests/small-gap-native-test.rkt"' in runner and
         "(dynamic-require small-gap-native-tests-file 'small-gap-native-tests)" in runner,
         "native suite missing from aggregate tests")
    ci = (root / "tools/ci.py").read_text(encoding="utf-8")
    need("'test-small-gaps.py'" in ci, "source CI must run the 0.78b contracts")
    example = (root / "examples/small-gaps.rkt").read_text(encoding="utf-8")
    need('"../main.rkt"' in example and "private/" not in example, "example must use public APIs")
    need('"0.78"' in (root / "info.rkt").read_text(encoding="utf-8"), "wrong package version")
    return summary

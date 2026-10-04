"""0.61 report checks, reusing the independently tested 0.60 pixel oracles.

The captured pixels belong to the drawing backing, not the displayed screen.
"""
from __future__ import annotations
import hashlib
import html
import itertools
import json
from pathlib import Path
import re

import gpu_dc_consumer_validation as pixels

PURE_CASES = 33
GUI_CASES = 20
SIZES = ("small", "large")
CAPTURES = len(pixels.SCENES) * len(pixels.MODES) * len(SIZES)


def expected_ids() -> set[str]:
    return {f"{s}-{m}-{z}" for s, m, z in itertools.product(pixels.SCENES, pixels.MODES, SIZES)}


def validate_suite(output: str, name: str, count: int) -> None:
    summaries = re.findall(r"^(\d+) success\(es\) (\d+) failure\(s\) (\d+) error\(s\) (\d+) test\(s\) run$", output, re.M)
    markers = re.findall(rf"^{re.escape(name)}: (\d+) cases, (\d+) failures; .+$", output, re.M)
    pixels.require(summaries == [(str(count), "0", "0", str(count))]
                   and markers == [(str(count), "0")], "missing, partial, duplicate or failed suite completion")
    pixels.require(not re.search(r"^(?:ERROR|FAILURE|FAIL:.*)$", output, re.M), "suite printed a failure")


def validate_report(report: object, request: str, backend: str, token: str, identity: dict,
                    adapter: str | None = None) -> list[dict]:
    check = pixels.require
    check(type(report) is dict, "worker report is not an object")
    check(type(report.get("schema")) is int and report["schema"] == 1, "wrong schema")
    check(report.get("stage") == "0.61" and report.get("status") == "passed", "worker did not pass this stage")
    check(report.get("run_token") == token, "stale or foreign run token")
    check(report.get("identity") == identity, "foreign Racket identity")
    check(report.get("requested_renderer") == request, "wrong requested renderer")
    check(report.get("physical_display_verified") is False, "unsupported screen claim")
    check(type(report.get("cases")) is int and report["cases"] == GUI_CASES, "incomplete GUI cases")
    check(type(report.get("failures")) is int and report["failures"] == 0, "failed GUI cases")
    selection = report.get("selection")
    check(type(selection) is dict, "missing backend selection")
    gpu = request != "raster"
    check(selection.get("requested_renderer") == request, "selection request mismatch")
    check(selection.get("requested_backend") == (backend if request == "gpu" else "auto"),
          "wrong requested backend; automatic selection must not be overridden")
    check(selection.get("renderer") == ("gpu" if gpu else "raster"), "implicit renderer fallback")
    check(selection.get("backend") == backend, "wrong actual backend")
    check(selection.get("runtime_fallback") is False, "automatic fallback is forbidden")
    if backend == "direct3d":
        check(selection.get("adapter") == (adapter or "hardware"), "wrong Direct3D adapter")
        check(type(selection.get("adapter_index")) is int and selection["adapter_index"] == 0, "wrong adapter index")
        check(type(selection.get("sync_interval")) is int and selection["sync_interval"] == 1, "wrong sync interval")
    else:
        check(all(selection.get(k) is False for k in ("adapter", "adapter_index", "sync_interval")),
              "unexpected adapter or presentation option")
    rows = report.get("captures")
    check(type(rows) is list and len(rows) == CAPTURES, "incomplete consumer capture matrix")
    seen = set()
    dimensions = {}
    for row in rows:
        check(type(row) is dict, "invalid capture")
        key = row.get("id")
        check(type(key) is str and key in expected_ids() and key not in seen, "duplicate or unknown capture")
        seen.add(key)
        e = row.get("extent")
        check(type(e) is dict and e.get("name") in SIZES, "invalid size")
        check(row.get("scene") in pixels.SCENES and row.get("mode") in pixels.MODES, "invalid workload")
        check(key == f'{row["scene"]}-{row["mode"]}-{e["name"]}', "inconsistent capture identity")
        check(row.get("file") == key + ".rgba", "unsafe capture filename")
        for field in ("pixel_width", "pixel_height"):
            check(type(e.get(field)) is int and 0 < e[field] <= 8192, "invalid physical dimension")
        check(e["pixel_width"] * e["pixel_height"] * 4 <= 256 * 1024 * 1024, "capture allocation exceeds bound")
        for field, minimum in (("logical_width", 320), ("logical_height", 240)):
            check(pixels.finite(e.get(field)) and e[field] >= minimum, "invalid logical dimension")
        shape = tuple(e[k] for k in ("pixel_width", "pixel_height", "logical_width", "logical_height"))
        check(shape == dimensions.setdefault(e["name"], shape), "inconsistent size within a capture group")
        layout = row.get("layout")
        check(type(layout) is dict, "missing layout")
        if row["scene"] == "plot":
            lo, hi = layout.get("lower_left"), layout.get("upper_right")
            check(type(lo) is list and type(hi) is list and len(lo) == len(hi) == 2
                  and all(pixels.finite(v) for v in lo + hi), "invalid plot layout")
            check(hi[0] > lo[0] and hi[1] < lo[1], "reversed plot layout")
        normal = pixels.io_kinds(row.get("draw_io"))
        capture = pixels.io_kinds(row.get("capture_io"))
        check("readback" not in normal, "implicit readback in an ordinary frame")
        if gpu:
            check(normal.count("present-request") == 1 and "gpu-snapshot" in normal, "missing GPU presentation")
            check(capture.count("readback") == 1, "missing or duplicated readback positive control")
        else:
            check(not normal and not capture, "raster path emitted GPU activity")
    check(seen == expected_ids(), "incomplete capture identities")
    check(all(a > b for a, b in zip(dimensions["large"], dimensions["small"])), "resize not observed")
    return rows


def inspect_directory(directory: Path, request: str, backend: str, token: str, identity: dict,
                      adapter: str | None = None) -> dict:
    rows = validate_report(pixels.read_json(directory / "result.json"), request, backend, token, identity, adapter)
    data = {}
    results = []
    for row in rows:
        content = pixels.capture_bytes(directory, row)
        data[row["id"]] = content
        checks = pixels.inspect_pixels(content, row)
        e = row["extent"]
        image = row["id"] + ".png"
        (directory / image).write_bytes(pixels.png_bytes(content, e["pixel_width"], e["pixel_height"]))
        results.append(dict(id=row["id"], image=image, checks=checks,
                            sha256=hashlib.sha256(content).hexdigest()))
    comparisons = []
    for scene, size in itertools.product(pixels.SCENES, SIZES):
        a, b = f"{scene}-procedure-{size}", f"{scene}-datum-{size}"
        error = pixels.bounded_equal(data[a], data[b], 2, f"{a} versus {b}")
        comparisons.append(dict(procedure=a, datum=b, max_error=error, tolerance=2))
    result = dict(stage="0.61", status="passed", requested_renderer=request, backend=backend,
                  physical_display_verified=False, captures=results, bounded_comparisons=comparisons)
    (directory / "inspection.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    entries = "\n".join(f'<figure><figcaption>{html.escape(r["id"])}</figcaption><img src="{r["image"]}" alt="{html.escape(r["id"])}"></figure>' for r in results)
    (directory / "review.html").write_text(
        '<!doctype html><meta charset="utf-8"><title>Unified canvas review</title>'
        '<style>body{font-family:system-ui;max-width:1000px;margin:auto}img{max-width:100%;border:1px solid #bbb}figure{margin:2em 0}</style>'
        f'<h1>Unified canvas: {html.escape(request)} / {html.escape(backend)}</h1>'
        '<p>Explicit backing-pixel captures. Not screenshots or physical display certification.</p>' + entries, encoding="utf-8")
    return result

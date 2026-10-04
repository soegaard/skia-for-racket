"""0.60 independent pixel/receipt checks. No third-party Python dependencies.

CPU/GPU byte identity is deliberately NOT an acceptance requirement. Every
capture must independently exhibit the specified geometry, ink and opacity.
Procedure/datum and GPU surface/final-frame comparisons use bounded byte error.
"""
from __future__ import annotations

import hashlib
import html
import itertools
import json
import math
from pathlib import Path
import re
import struct
import zlib

SCENES = ("pict", "plot", "styles", "geometry")
MODES = ("direct", "procedure", "datum")
EXTENTS = {
    "1x": (320, 240, 320.0, 240.0),
    "2x": (640, 480, 320.0, 240.0),
    "asymmetric": (400, 360, 320.0, 240.0),
    "fractional": (641, 481, 320.5, 240.25),
}
COUNTS = {"native": 144, "gui": 48}


def require(value: object, message: str) -> None:
    if not value:
        raise ValueError(message)


def unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def read_json(path: Path) -> dict:
    require(path.is_file() and not path.is_symlink(), f"missing/unsafe JSON: {path.name}")
    require(path.stat().st_size <= 16 * 1024 * 1024, "JSON report exceeds bound")
    def nonfinite(value):
        raise ValueError(f"non-finite JSON number: {value}")
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object,
                      parse_constant=nonfinite)


def finite(value: object) -> bool:
    return type(value) in (int, float) and math.isfinite(value)


def expected_ids(suite: str) -> set[str]:
    require(suite in COUNTS, "unknown suite")
    targets = ("cpu", "surface", "frame") if suite == "native" else ("cpu", "gui")
    extents = EXTENTS if suite == "native" else ("small", "large")
    return {f"{target}-{scene}-{mode}-{extent}"
            for target, scene, mode, extent in itertools.product(targets, SCENES, MODES, extents)}


def io_kinds(events: object) -> list[str]:
    require(type(events) is list, "I/O ledger must be a list")
    require(all(type(e) is dict and type(e.get("kind")) is str for e in events), "invalid I/O event")
    return [e["kind"] for e in events]


def validate_structure(report: object, suite: str, token: str, backend: str, identity: dict) -> list[dict]:
    require(type(report) is dict, "report must be an object")
    require(type(report.get("schema")) is int and report["schema"] == 1, "wrong schema")
    require(report.get("stage") == "0.60" and report.get("suite") == suite, "wrong stage/suite")
    require(report.get("status") == "passed", "worker did not pass")
    require(report.get("run_token") == token, "stale/foreign run token")
    require(report.get("backend") == backend, "wrong selected backend")
    require(report.get("identity") == identity, "foreign Racket identity")
    require(report.get("physical_display_verified") is False, "unsupported physical-display claim")
    rows = report.get("captures")
    require(type(rows) is list and len(rows) == COUNTS[suite], "incomplete capture matrix")
    wanted = expected_ids(suite)
    seen = set()
    dimensions = {}
    for row in rows:
        require(type(row) is dict, "invalid capture")
        key = row.get("id")
        require(type(key) is str and key in wanted and key not in seen, "unknown/duplicate capture")
        seen.add(key)
        extent = row.get("extent")
        require(type(extent) is dict, "missing extent")
        name = extent.get("name")
        require(name in (EXTENTS if suite == "native" else ("small", "large")), "unknown extent")
        require(row.get("scene") in SCENES and row.get("mode") in MODES, "unknown workload")
        require(key == f'{row.get("target")}-{row["scene"]}-{row["mode"]}-{name}', "inconsistent capture identity")
        require(row.get("file") == key + ".rgba", "unsafe/noncanonical capture path")
        pw, ph = extent.get("pixel_width"), extent.get("pixel_height")
        lw, lh = extent.get("logical_width"), extent.get("logical_height")
        require(type(pw) is int and type(ph) is int and 1 <= pw <= 4096 and 1 <= ph <= 4096,
                "invalid physical dimensions")
        require(finite(lw) and finite(lh) and 320 <= lw <= 4096 and 240 <= lh <= 4096,
                "invalid logical dimensions")
        shape = (pw, ph, lw, lh)
        if suite == "native":
            require(shape == EXTENTS[name], "native extent does not match test case")
        require(name not in dimensions or dimensions[name] == shape, "geometry changed within a case")
        dimensions[name] = shape
        require(type(row.get("layout")) is dict, "missing layout")
        if row["scene"] == "plot":
            layout = row["layout"]
            for point in ("lower_left", "upper_right"):
                values = layout.get(point)
                require(type(values) is list and len(values) == 2 and all(finite(v) for v in values), "invalid plot layout")
            x0, y0 = layout["lower_left"]
            x1, y1 = layout["upper_right"]
            require(0 <= x0 < x1 <= 320 and 0 <= y1 < y0 <= 240, "out-of-scene plot layout")
        kinds = io_kinds(row.get("draw_io"))
        require("readback" not in kinds, "implicit readback during drawing/presentation")
        if row["target"] == "cpu":
            require(kinds == [], "CPU reference has unexpected GPU events")
        if row["target"] in ("frame", "gui"):
            require("gpu-snapshot" in kinds, "final frame has no GPU snapshot")
        if row["target"] == "gui":
            require(kinds.count("present-request") == 1, "normal GUI frame did not request one presentation")
    require(seen == wanted, "missing capture")
    if suite == "gui":
        require(dimensions["large"][2] > dimensions["small"][2], "GUI resize was not observed")
    checks = report.get("checks")
    require(type(checks) is dict, "missing lifecycle checks")
    expected_expired = 96 if suite == "native" else 48
    require(type(checks.get("expired_dcs")) is int and checks["expired_dcs"] == expected_expired,
            "missing expired-DC checks")
    require(checks.get("window_created") is (suite == "gui"), "incorrect GUI disclosure")
    require(checks.get("final_target_pixels") is (suite == "native"), "incorrect pixel-target disclosure")
    require(checks.get("context_closed" if suite == "native" else "canvas_closed") is True,
            "resources did not close")
    gpu_rows = {r["id"]: r for r in rows if r["target"] != "cpu"}
    transfers = checks.get("transfers")
    require(type(transfers) is list and len(transfers) == len(gpu_rows), "missing explicit transfer receipts")
    transfer_ids = set()
    for entry in transfers:
        require(type(entry) is dict and entry.get("id") in gpu_rows and entry["id"] not in transfer_ids,
                "duplicate/foreign transfer receipt")
        transfer_ids.add(entry["id"])
        require(io_kinds(entry.get("io")).count("readback") == 1, "capture did not record one explicit readback")
    if suite == "gui":
        frames = checks.get("normal_frames")
        require(type(frames) is list and len(frames) == 24, "missing normal GUI frames")
        frame_ids = set()
        for frame in frames:
            require(type(frame) is dict and frame.get("id") in gpu_rows and frame["id"] not in frame_ids,
                    "duplicate/foreign normal frame")
            frame_ids.add(frame["id"])
            require(frame.get("io") == gpu_rows[frame["id"]]["draw_io"], "normal-frame ledger mismatch")
    return rows


class Pixels:
    def __init__(self, data: bytes, extent: dict):
        self.data = data
        self.width, self.height = extent["pixel_width"], extent["pixel_height"]
        self.sx = self.width / extent["logical_width"]
        self.sy = self.height / extent["logical_height"]
        require(len(data) == self.width * self.height * 4, "wrong RGBA byte length")

    def at(self, x: float, y: float) -> tuple[int, ...]:
        px, py = math.floor(x * self.sx), math.floor(y * self.sy)
        require(0 <= px < self.width and 0 <= py < self.height, "probe outside capture")
        i = 4 * (px + py * self.width)
        return tuple(self.data[i:i + 4])

    def count(self, box: tuple[float, ...], predicate) -> int:
        x0, y0, x1, y1 = box
        total = 0
        for py in range(max(0, math.floor(y0 * self.sy)), min(self.height, math.ceil(y1 * self.sy))):
            for px in range(max(0, math.floor(x0 * self.sx)), min(self.width, math.ceil(x1 * self.sx))):
                i = 4 * (px + py * self.width)
                total += bool(predicate(*self.data[i:i + 4]))
        return total


def red(r, g, b, a): return r > 160 and g < 100 and b < 100 and a > 240

def blue(r, g, b, a): return b > 160 and r < 100 and g < 100 and a > 240

def white(r, g, b, a): return min(r, g, b) > 248 and a > 248


def inspect_pixels(data: bytes, row: dict) -> dict:
    p = Pixels(data, row["extent"])
    checks = {}
    def point(name, x, y, expected, tolerance=3):
        actual = p.at(x, y)
        require(all(abs(a - b) <= tolerance for a, b in zip(actual, expected)),
                f'{row["id"]}: {name}: {actual} != {expected}')
        checks[name] = list(actual)
    def ink(name, box, predicate, minimum=1):
        count = p.count(box, predicate)
        require(count >= minimum, f'{row["id"]}: missing {name}')
        checks[name] = count
    scene = row["scene"]
    if scene == "pict":
        point("red rectangle", 24, 24, (255, 0, 0, 255))
        point("isolated red", 18, 72, (255, 128, 128, 255))
        point("isolated overlap", 36, 72, (128, 128, 255, 255))
        point("bitmap", 164, 16, (20, 180, 60, 255))
        ink("navy text", (12, 126, 165, 172),
            lambda r, g, b, a: r < 160 and g < 160 and b > r + 20 and a > 240, 12)
        point("outside content", 300, 225, (255, 255, 255, 255))
    elif scene == "plot":
        layout = row["layout"]
        x0, y0 = layout["lower_left"]
        x1, y1 = layout["upper_right"]
        for i, (x, y, predicate) in enumerate(((-1.5, -.75, blue), (-.5, -.25, blue),
                                               (.5, .25, blue), (1.5, .75, blue),
                                               (-1, 1, red), (1, -1, red))):
            lx = x0 + (x + 2) / 4 * (x1 - x0)
            ly = y0 + (y + 1.5) / 3 * (y1 - y0)
            ink(f"data landmark {i}", (lx - 3, ly - 3, lx + 3, ly + 3), predicate)
        ink("title/legend ink", (0, 0, 320, 35), lambda r, g, b, a: max(r, g, b) < 180 and a > 240, 12)
    elif scene == "styles":
        require(red(*p.at(2, 8)) and blue(*p.at(13, 8)), f'{row["id"]}: linear gradient direction')
        checks["linear gradient"] = [list(p.at(2, 8)), list(p.at(13, 8))]
        require(red(*p.at(8, 24)) and blue(*p.at(14, 24)), f'{row["id"]}: radial gradient direction')
        checks["radial gradient"] = [list(p.at(8, 24)), list(p.at(14, 24))]
        for name, predicate in (("red", red), ("blue", blue),
                                ("green", lambda r, g, b, a: g > 160 and r < 100 and b < 100 and a > 240),
                                ("yellow", lambda r, g, b, a: min(r, g) > 160 and b < 100 and a > 240)):
            ink("stipple " + name, (17, 1, 31, 15), predicate, 2)
            ink("HiDPI stipple " + name, (49, 33, 63, 47), predicate, 2)
        ink("hatch lines", (33, 1, 47, 15), red, 4)
        ink("hatch gaps", (33, 1, 47, 15), white, 4)
        point("outside style grid", 300, 225, (255, 255, 255, 255))
    elif scene == "geometry":
        point("clip inside", 20, 20, (255, 0, 0, 255))
        point("clip outside", 45, 20, (255, 255, 255, 255))
        point("isolated red", 18, 72, (255, 128, 128, 255))
        point("isolated overlap", 36, 72, (128, 128, 255, 255))
        point("copy red", 110, 20, (255, 0, 0, 255))
        point("copy blue", 126, 20, (0, 0, 255, 255))
        point("transformed rectangle", 220, 135, (0, 255, 0, 255))
        point("outside content", 300, 225, (255, 255, 255, 255))
    else:
        raise ValueError("unknown pixel scene")
    return checks


def capture_bytes(directory: Path, row: dict) -> bytes:
    name = row["file"]
    require(name == row["id"] + ".rgba" and Path(name).name == name, "unsafe capture filename")
    path = directory / name
    require(path.is_file() and not path.is_symlink(), f"missing/unsafe capture: {name}")
    size = row["extent"]["pixel_width"] * row["extent"]["pixel_height"] * 4
    require(path.stat().st_size == size, f"wrong capture size: {name}")
    return path.read_bytes()


def bounded_equal(a: bytes, b: bytes, tolerance: int, message: str) -> int:
    require(len(a) == len(b), message + ": size mismatch")
    worst = max((abs(x - y) for x, y in zip(a, b)), default=0)
    require(worst <= tolerance, message + f": maximum channel error {worst} exceeds {tolerance}")
    return worst


def png_bytes(data: bytes, width: int, height: int) -> bytes:
    require(len(data) == width * height * 4, "invalid PNG input size")
    def chunk(kind, value):
        return struct.pack(">I", len(value)) + kind + value + struct.pack(">I", zlib.crc32(kind + value) & 0xffffffff)
    # RGBA captures are premultiplied; PNG stores straight alpha. Preserve
    # transparent/XOR style cells rather than darkening translucent samples.
    if any(a != 255 for a in data[3::4]):
        straight = bytearray(data)
        for i in range(0, len(straight), 4):
            alpha = straight[i + 3]
            for c in range(3):
                straight[i + c] = min(255, (straight[i + c] * 255 + alpha // 2) // alpha) if alpha else 0
        data = bytes(straight)
    scanlines = b"".join(b"\x00" + data[y * width * 4:(y + 1) * width * 4] for y in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(scanlines)) + chunk(b"IEND", b""))


def inspect_directory(directory: Path, suite: str, token: str, backend: str, identity: dict) -> dict:
    require(directory.is_dir() and not directory.is_symlink(), "unsafe suite directory")
    report = read_json(directory / (suite + ".json"))
    rows = validate_structure(report, suite, token, backend, identity)
    pixels = {}
    inspections = []
    for row in rows:
        data = capture_bytes(directory, row)
        checks = inspect_pixels(data, row)
        pixels[row["id"]] = data
        inspections.append({"id": row["id"], "sha256": hashlib.sha256(data).hexdigest(), "checks": checks})
    pairs = []
    for row in rows:
        key = row["id"]
        if row["mode"] == "procedure":
            other = key.replace("-procedure-", "-datum-")
            pairs.append({"left": key, "right": other, "max_error": bounded_equal(pixels[key], pixels[other], 2, key + " / datum")})
        if row["target"] == "surface":
            other = "frame-" + key[len("surface-"):]
            pairs.append({"left": key, "right": other, "max_error": bounded_equal(pixels[key], pixels[other], 3, key + " / final frame")})
    # Encode only after all acceptance checks; convert premultiplied RGBA
    # to PNG straight alpha for style cells that intentionally clear alpha.
    cards = []
    for row in rows:
        key = row["id"]
        image = key + ".png"
        (directory / image).write_bytes(png_bytes(pixels[key], row["extent"]["pixel_width"], row["extent"]["pixel_height"]))
        cards.append(f'<figure><figcaption>{html.escape(key)}</figcaption><img loading="lazy" src="{image}"></figure>')
    (directory / "review.html").write_text(
        '<!doctype html><meta charset="utf-8"><title>GPU DC consumer review</title>'
        '<style>body{font:16px system-ui;margin:2em}main{display:flex;flex-wrap:wrap;gap:1em}'
        'figure{margin:0}img{display:block;max-width:480px;border:1px solid}figcaption{margin:.5em 0}</style>'
        '<h1>0.60 GPU DC consumers</h1><p>Independent semantic probes passed. '
        'CPU/GPU byte identity and physical display output are not certified.</p><main>'
        + ''.join(cards) + '</main>', encoding="utf-8")
    result = {"suite": suite, "captures": inspections, "bounded_comparisons": pairs,
              "no_implicit_readback": True, "physical_display_verified": False}
    (directory / "inspection.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result

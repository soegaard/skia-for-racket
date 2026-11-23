#!/usr/bin/env python3
"""Compile, test, render and build Tutorials 16-20; never start a GUI or GPU example."""
from __future__ import annotations

import argparse
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
from urllib.parse import unquote, urlsplit
import uuid

ROOT = Path(__file__).resolve().parents[2]
TUTORIALS = ROOT / "scribblings" / "tutorials"
TOPICS = (
    ("navigation", "scene.rkt", "navigation.scrbl"),
    ("shaders", "waves.rkt", "shaders.scrbl"),
    ("pixels", "pixel-lab.rkt", "pixels.scrbl"),
    ("color-spaces", "color-study.rkt", "color-spaces.scrbl"),
    ("path-ops", "badge.rkt", "path-ops.scrbl"),
)

EXPECTED_PNGS = {
    "navigation": {"navigation.png": [800, 500]},
    "shaders": {"wave-frame.png": [760, 460]},
    "pixels": {"pixel-study.png": [780, 360], "duotone.png": [192, 128]},
    "color-spaces": {"color-study.png": [740, 490], "converted-gray.png": [1, 1]},
    "path-ops": {"cutout-badge.png": [720, 468]},
}


# Count placements, not unique PNG files: Scribble may reuse an identical image.
EXPECTED_FIGURES = {"navigation": 6, "shaders": 12, "pixels": 7,
                    "color-spaces": 5, "path-ops": 10}


def hashes():
    files = [p for topic, _, _ in TOPICS for p in (TUTORIALS / topic).iterdir()
             if p.is_file() and p.suffix in (".rkt", ".scrbl")]
    files += list((TUTORIALS / "support").glob("*.rkt"))
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(files)}


class Images(HTMLParser):
    def __init__(self):
        super().__init__()
        self.sources = []
        self.local_document_links = 0
        self.unresolved_references = 0

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "a" and urlsplit(attrs.get("href", "")).scheme == "file":
            self.local_document_links += 1
        if "badlink" in attrs.get("class", "").split():
            self.unresolved_references += 1
        if tag == "img":
            source = attrs.get("src")
            if source:
                self.sources.append(source)


def check_html(directory, expected_images=None):
    pages = list(directory.glob("*.html"))
    if not pages:
        raise RuntimeError("Scribble produced no HTML: " + str(directory))
    count = 0
    for page in pages:
        parsed = Images()
        parsed.feed(page.read_text(encoding="utf-8"))
        for source in parsed.sources:
            url = urlsplit(source)
            if not url.scheme and not url.netloc:
                if not (page.parent / unquote(url.path)).is_file():
                    raise RuntimeError("missing HTML image: " + source)
                count += 1
    if count == 0:
        raise RuntimeError("the tutorial contains no local image references")
    if expected_images is not None and count != expected_images:
        raise RuntimeError(
            f"expected {expected_images} figure placements, found {count}: {directory}")
    return count


def link_diagnostics(directory):
    local, unresolved = 0, 0
    for page in directory.glob("*.html"):
        parsed = Images()
        parsed.feed(page.read_text(encoding="utf-8"))
        local += parsed.local_document_links
        unresolved += parsed.unresolved_references
    return dict(local_document_links=local, unresolved_references=unresolved,
                cross_references_verified=False)


def png_sizes(directory):
    result = {}
    for path in directory.glob("*.png"):
        data = path.read_bytes()
        if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
            raise RuntimeError("invalid PNG header: " + str(path))
        result[path.name] = list(struct.unpack(">II", data[16:24]))
    if not result:
        raise RuntimeError("example produced no PNG: " + str(directory))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--racket", required=True, help="Racket executable; inherits PLTCOLLECTS")
    parser.add_argument("--directory", type=Path,
                        help="new output directory, outside tutorial sources")
    parser.add_argument("--online-doc-links", action="store_true",
                        help="redirect known installation-doc links to docs.racket-lang.org")
    args = parser.parse_args()
    racket = shutil.which(args.racket)
    if racket is None:
        parser.error("Racket executable not found: " + args.racket)
    directory = (args.directory or ROOT / "output" / ("tutorials-16-20-" + uuid.uuid4().hex))
    directory = directory.resolve()
    if directory == TUTORIALS.resolve() or TUTORIALS.resolve() in directory.parents:
        parser.error("output must not be inside the tutorial source tree")
    directory.mkdir(parents=True, exist_ok=False)
    report = dict(status="running", commands=[], pngs={}, html_images={}, html_links={},
                  online_doc_links=args.online_doc_links,
                  gui_executed=False, gpu_executed=False,
                  note="CPU examples and docs only; inspect GUI controls and figures separately.")
    before = hashes()

    def run(label, arguments, cwd=ROOT):
        command = [racket, *map(str, arguments)]
        log = directory / (label + ".log")
        entry = dict(label=label, command=command, log=log.name, status="running")
        report["commands"].append(entry)
        print(label, flush=True)
        with log.open("w", encoding="utf-8") as out:
            completed = subprocess.run(command, cwd=cwd, stdout=out,
                                       stderr=subprocess.STDOUT, timeout=600, check=False)
        entry["returncode"] = completed.returncode
        entry["status"] = "passed" if completed.returncode == 0 else "failed"
        if completed.returncode:
            raise RuntimeError(f"{label} failed; see {log}")

    try:
        run("racket-version", ["--version"])
        sources = [ROOT / path for path in before if path.endswith(".rkt")]
        run("compile", ["-l", "raco", "--", "make", *sources])
        tests = [TUTORIALS / topic / "tests.rkt" for topic, _, _ in TOPICS]
        run("tests", ["-l", "raco", "--", "test", TUTORIALS / "support/source.rkt", *tests])
        for topic, program, document in TOPICS:
            output = directory / topic
            output.mkdir()
            run(topic + "-example", [TUTORIALS / topic / program], cwd=output)
            report["pngs"][topic] = png_sizes(output)
            if report["pngs"][topic] != EXPECTED_PNGS[topic]:
                raise RuntimeError("unexpected PNG files or dimensions: " + topic)
            html = output / "html"
            html.mkdir()
            scribble = ["-l", "raco", "--", "scribble", "--html", "--dest", html]
            if args.online_doc_links:
                scribble += ["--redirect-main", "https://docs.racket-lang.org/"]
            run(topic + "-scribble", [*scribble, TUTORIALS / topic / document])
            report["html_images"][topic] = check_html(html, EXPECTED_FIGURES[topic])
            report["html_links"][topic] = link_diagnostics(html)
        if hashes() != before:
            raise RuntimeError("a tutorial source changed during validation")
        report["status"] = "passed"
    except Exception as error:
        report["status"] = "failed"
        report["error"] = f"{type(error).__name__}: {error}"
        for entry in report["commands"]:
            if entry["status"] == "running":
                entry["status"] = "failed"
        print(report["error"], file=sys.stderr)
    report["source_sha256"] = before
    (directory / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Tutorial batch: {report['status']}; output: {directory}")
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())

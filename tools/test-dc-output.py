#!/usr/bin/env python3
"""Synthetic PDF/SVG, pixel-oracle and runner tests. NOT Skia execution evidence."""
from __future__ import annotations
import base64
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image, ImageDraw
from pypdf import PdfWriter
from pypdf.generic import (ArrayObject, DecodedStreamObject, DictionaryObject,
                          FloatObject, NameObject, NumberObject, TextStringObject)
import dc_output_validation as c

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("dc_output_runner", HERE/"validate-dc-output.py")
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
IDENTITY = dict(version="9.3", os="unix", architecture="x86_64", vm="chez-scheme")
FULL = dict(IDENTITY, pointer_bytes=8)
TOKEN = "synthetic-document-worker"


def receipt():
    rows = []
    for name, spec in c.SPECS.items():
        groups = [dict(strategy="native", label="dc-path", pixel_size=False)]
        if spec["kind"] in ("mixed", "styles", "pict"):
            groups.append(dict(strategy="raster", label="dc-alpha", pixel_size=[400, 320]))
        if spec["kind"] == "mixed":
            groups.append(dict(strategy="raster", label="copy-island-64x32", pixel_size=[128, 64]))
        report = dict(schema=1, stage="0.63", backend=spec["format"], text_mode=spec["text_mode"],
                      command_count=5, dc_expired=True, groups=groups, native_groups=1,
                      raster_groups=len(groups)-1)
        rows.append(dict(spec, authoring_calls=spec["pages"], raster_callback_calls=1 if spec["kind"] == "mixed" else 0,
                         layout=dict(lower_left=[40, 200], upper_right=[290, 50]) if spec["kind"] == "plot" else {},
                         dc_reports=[copy.deepcopy(report) for _ in range(spec["pages"])],
                         audit_policy="error",
                         audit=dict(backend=spec["format"], mode="export", pages=spec["pages"], blocking=False)))
    return dict(schema=1, stage="0.63", status="passed", run_token=TOKEN, identity=IDENTITY,
                physical_display_verified=False, pdfa_certified=False, color_fidelity_certified=False,
                documents=rows)


def synthetic_pdf(path, *, native=True, pages=1, images=(), links=False, form=False, geometry=True, w=160, h=120):
    writer = PdfWriter()
    for index in range(pages):
        page = writer.add_blank_page(w, h)
        font = DictionaryObject({NameObject("/Type"): NameObject("/Font"), NameObject("/Subtype"): NameObject("/Type1"),
                                 NameObject("/BaseFont"): NameObject("/Helvetica")})
        resources = DictionaryObject({NameObject("/Font"): DictionaryObject({NameObject("/F1"): writer._add_object(font)})})
        stream = DecodedStreamObject()
        code = b"1 0 0 rg 8 8 24 18 re f\n" if geometry else b""
        if native:
            code += b"BT /F1 12 Tf 8 44 Td (SkiaDC063) Tj ET\n"
        xobjects = DictionaryObject()
        for n, (pw, ph) in enumerate(images):
            image = DecodedStreamObject()
            image.set_data(b"\xff\x00\x00"*(pw*ph))
            image.update({NameObject("/Type"): NameObject("/XObject"), NameObject("/Subtype"): NameObject("/Image"),
                          NameObject("/Width"): NumberObject(pw), NameObject("/Height"): NumberObject(ph),
                          NameObject("/BitsPerComponent"): NumberObject(8), NameObject("/ColorSpace"): NameObject("/DeviceRGB")})
            name = NameObject(f"/I{n}")
            xobjects[name] = writer._add_object(image)
            code += f"q 10 0 0 10 10 10 cm {name} Do Q\n".encode()
        if xobjects:
            resources[NameObject("/XObject")] = writer._add_object(xobjects)
        stream.set_data(code)
        if form:
            stream.update({NameObject("/Type"): NameObject("/XObject"), NameObject("/Subtype"): NameObject("/Form"),
                           NameObject("/BBox"): ArrayObject([NumberObject(0), NumberObject(0), NumberObject(w), NumberObject(h)]),
                           NameObject("/Resources"): writer._add_object(resources)})
            reference = writer._add_object(stream)
            page[NameObject("/Resources")] = DictionaryObject({NameObject("/XObject"): DictionaryObject({NameObject("/Fm"): reference})})
            content = DecodedStreamObject(); content.set_data(b"/Fm Do")
            page[NameObject("/Contents")] = writer._add_object(content)
        else:
            page[NameObject("/Resources")] = writer._add_object(resources)
            page[NameObject("/Contents")] = writer._add_object(stream)
        if links and index == 0:
            rect = ArrayObject([NumberObject(n) for n in (8, 8, 32, 26)])
            uri = DictionaryObject({NameObject("/Type"): NameObject("/Annot"), NameObject("/Subtype"): NameObject("/Link"),
                                    NameObject("/Rect"): rect, NameObject("/A"): DictionaryObject({NameObject("/S"): NameObject("/URI"),
                                                NameObject("/URI"): TextStringObject(c.URI)})})
            dest = DictionaryObject({NameObject("/Type"): NameObject("/Annot"), NameObject("/Subtype"): NameObject("/Link"),
                                     NameObject("/Rect"): rect, NameObject("/Dest"): TextStringObject(c.DEST)})
            page[NameObject("/Annots")] = ArrayObject([writer._add_object(uri), writer._add_object(dest)])
    if links:
        writer.add_named_destination(c.DEST, pages-1)
    with path.open("wb") as out:
        writer.write(out)


def synthetic_svg(path, *, native=True, images=(), links=False, gradient=True, geometry=True, w=160, h=120):
    body = ['<rect x="8" y="8" width="24" height="18" fill="red"/>'] if geometry else []
    if native: body.append('<text x="8" y="44">SkiaDC063</text>')
    if gradient: body.append('<defs><linearGradient id="g"><stop offset="0" stop-color="red"/></linearGradient></defs>')
    if links: body += [f'<a href="{c.URI}"><rect width="10" height="10"/></a>',
                       f'<view id="skia-{c.DEST}" viewBox="0 0 10 10"/>', f'<a href="#skia-{c.DEST}"/>']
    for pw, ph in images:
        stream = io.BytesIO(); Image.new("RGB", (pw, ph), "red").save(stream, format="PNG")
        body.append('<image width="10" height="10" href="data:image/png;base64,'+base64.b64encode(stream.getvalue()).decode()+'"/>')
    path.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}pt" height="{h}pt">'+''.join(body)+'</svg>')


def create_document(folder, row):
    sizes = ((128, 64), (400, 320)) if row["kind"] == "mixed" else ((12, 10),) if row["kind"] in ("pict", "styles") else ()
    maker = synthetic_pdf if row["format"] == "pdf" else synthetic_svg
    opts = dict(native=row["text_mode"] == "native" and row["kind"] not in ("units", "styles"),
                images=sizes, links=row["kind"] == "links", w=row["width_points"], h=row["height_points"])
    if row["format"] == "pdf": opts["pages"] = row["pages"]
    path = folder/row["file"]; maker(path, **opts); return path


class ReceiptTests(unittest.TestCase):
    def bad(self, mutation):
        value = receipt(); mutation(value)
        with self.assertRaises((ValueError, TypeError, KeyError)):
            c.validate_receipt(value, TOKEN, IDENTITY)
    def test_full_matrix(self): self.assertEqual(len(c.validate_receipt(receipt(), TOKEN, IDENTITY)), 24)
    def test_stale_token(self): self.bad(lambda r: r.update(run_token="old"))
    def test_foreign_identity(self): self.bad(lambda r: r.update(identity=dict(IDENTITY, os="windows")))
    def test_boolean_schema(self): self.bad(lambda r: r.update(schema=True))
    def test_old_stage(self): self.bad(lambda r: r.update(stage="0.62"))
    def test_failure(self): self.bad(lambda r: r.update(status="failed"))
    def test_missing_document(self): self.bad(lambda r: r["documents"].pop())
    def test_duplicate_document(self): self.bad(lambda r: r["documents"].__setitem__(0, r["documents"][1]))
    def test_renamed_document(self): self.bad(lambda r: r["documents"][0].update(file="../evil.pdf"))
    def test_page_count(self): self.bad(lambda r: r["documents"][0].update(pages=True))
    def test_callback_retried(self): self.bad(lambda r: r["documents"][0].update(authoring_calls=2))
    def test_raster_callback_retried(self): self.bad(lambda r: next(x for x in r["documents"] if x["kind"] == "mixed").update(raster_callback_calls=2))
    def test_no_expiry(self): self.bad(lambda r: r["documents"][0]["dc_reports"][0].update(dc_expired=False))
    def test_missing_dc_report(self): self.bad(lambda r: r["documents"][0].update(dc_reports=[]))
    def test_fake_command_count(self): self.bad(lambda r: r["documents"][0]["dc_reports"][0].update(command_count=True))
    def test_bad_extent(self): self.bad(lambda r: r["documents"][0].update(width_points=float("nan")))
    def test_mismatched_text_mode(self): self.bad(lambda r: r["documents"][0].update(text_mode="raster"))
    def test_rejected_group(self): self.bad(lambda r: r["documents"][0]["dc_reports"][0]["groups"][0].update(strategy="reject"))
    def test_wrong_group_count(self): self.bad(lambda r: r["documents"][0]["dc_reports"][0].update(native_groups=0))
    def test_strict_audit_failure(self): self.bad(lambda r: r["documents"][0]["audit"].update(blocking=True))
    def test_preflight_audit_is_not_export_evidence(self): self.bad(lambda r: r["documents"][0]["audit"].update(mode="preflight"))
    def test_non_strict_audit_policy(self): self.bad(lambda r: r["documents"][0].update(audit_policy="report"))
    def test_uncertified_display(self): self.bad(lambda r: r.update(physical_display_verified=True))
    def test_uncertified_pdfa(self): self.bad(lambda r: r.update(pdfa_certified=True))
    def test_missing_copy_island(self): self.bad(lambda r: next(x for x in r["documents"] if x["kind"] == "mixed")["dc_reports"][0]["groups"][-1].update(label="other"))
    def test_missing_pixel_extent(self): self.bad(lambda r: next(x for x in r["documents"] if x["kind"] == "mixed")["dc_reports"][0]["groups"][-1].update(pixel_size=False))
    def test_missing_plot_layout(self): self.bad(lambda r: next(x for x in r["documents"] if x["kind"] == "plot").update(layout={}))


class Documents(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup); self.root = Path(temp.name)
    def test_pdf_native_text_and_vector(self):
        path = self.root/"a.pdf"; synthetic_pdf(path)
        s = c.inspect_pdf(path); self.assertIn(c.TEXT, s["text"]); self.assertGreater(s["geometry"], 0); self.assertEqual(s["image_sizes"], [])
    def test_pdf_nested_form_is_not_mistaken_for_flat_raster(self):
        path = self.root/"a.pdf"; synthetic_pdf(path, form=True, images=((128, 64),))
        s = c.inspect_pdf(path); self.assertEqual(s["image_sizes"], [[128, 64]]); self.assertGreater(s["geometry"], 0)
        self.assertIn(c.TEXT, s["text"])
    def test_pdf_outlines_have_no_text_operations(self):
        path = self.root/"a.pdf"; synthetic_pdf(path, native=False)
        self.assertEqual(c.inspect_pdf(path)["text_operations"], 0)
    def test_pdf_links_and_named_destination(self):
        path = self.root/"a.pdf"; synthetic_pdf(path, links=True, pages=2)
        s = c.inspect_pdf(path); self.assertEqual(s["pages"], 2); self.assertIn(c.URI, s["uris"]); self.assertIn(c.DEST, s["named_destinations"])
    def test_svg_native_text_and_gradient(self):
        path = self.root/"a.svg"; synthetic_svg(path)
        s = c.inspect_svg(path); self.assertIn(c.TEXT, s["text"]); self.assertEqual(s["gradient_operations"], 1)
    def test_svg_embedded_png(self):
        path = self.root/"a.svg"; synthetic_svg(path, images=((128, 64),))
        self.assertEqual(c.inspect_svg(path)["image_sizes"], [[128, 64]])
    def test_svg_links(self):
        path = self.root/"a.svg"; synthetic_svg(path, links=True)
        s = c.inspect_svg(path); self.assertIn(c.URI, s["uris"]); self.assertIn("skia-"+c.DEST, s["named_destinations"])
    def test_external_svg_image_rejected(self):
        path = self.root/"a.svg"; path.write_text('<svg width="10" height="10"><image href="remote.png"/></svg>')
        with self.assertRaises(ValueError): c.inspect_svg(path)
    def test_svg_entity_rejected(self):
        path = self.root/"a.svg"; path.write_text('<!DOCTYPE svg [<!ENTITY x "bad">]><svg width="10" height="10"/>')
        with self.assertRaises(ValueError): c.inspect_svg(path)
    def test_blank_vector_document_rejected(self):
        row = c.SPECS["vector-pdf-native"]; path = self.root/row["file"]
        synthetic_pdf(path, geometry=False)
        with self.assertRaises(ValueError): c.inspect_document(path, row)
    def test_vector_raster_flattening_rejected(self):
        row = c.SPECS["vector-pdf-native"]; path = self.root/row["file"]
        synthetic_pdf(path, images=((160, 120),))
        with self.assertRaises(ValueError): c.inspect_document(path, row)
    def test_native_text_loss_rejected(self):
        row = c.SPECS["vector-pdf-native"]; path = self.root/row["file"]
        synthetic_pdf(path, native=False)
        with self.assertRaises(ValueError): c.inspect_document(path, row)
    def test_outline_text_leak_rejected(self):
        row = c.SPECS["vector-svg-outline"]; path = self.root/row["file"]
        synthetic_svg(path, native=True)
        with self.assertRaises(ValueError): c.inspect_document(path, row)
    def test_full_synthetic_matrix_inspected(self):
        rows = c.validate_receipt(receipt(), TOKEN, IDENTITY)
        summaries = [c.inspect_document(create_document(self.root, row), row) for row in rows]
        c.write_review(self.root, rows, summaries)
        self.assertEqual(len(summaries), 24); self.assertTrue((self.root/"review.html").is_file())
    def test_bad_pdf_rejected(self):
        path = self.root/"a.pdf"; path.write_bytes(b"%PDF-incomplete")
        with self.assertRaises(Exception): c.inspect_pdf(path)
    def test_missing_file_rejected(self):
        with self.assertRaises(ValueError): c.safe_file(self.root, "missing.pdf")
    def test_symlink_file_rejected(self):
        source = self.root/"real.pdf"; synthetic_pdf(source)
        (self.root/"alias.pdf").symlink_to(source)
        with self.assertRaises(ValueError): c.safe_file(self.root, "alias.pdf")
    def test_duplicate_json_keys_rejected(self):
        path = self.root/"receipt.json"; path.write_text('{"status":"failed","status":"passed"}')
        with self.assertRaises(ValueError): c.read_json(path)
    def test_nonfinite_json_rejected(self):
        path = self.root/"receipt.json"; path.write_text('{"size":NaN}')
        with self.assertRaises(ValueError): c.read_json(path)


def synthetic_pixels(row):
    image = Image.new("RGBA", (round(row["width_points"]*2), round(row["height_points"]*2)), "white")
    draw = ImageDraw.Draw(image)
    def fill(box, color): draw.rectangle(tuple(round(2*n) for n in box), fill=color)
    kind = row["kind"]
    if kind in ("vector", "mixed", "links"):
        fill((8, 8, 32, 26), "red"); fill((10, 46, 14, 52), "black")
    if kind == "vector":
        fill((56, 8, 84, 26), "blue"); fill((104, 8, 120, 24), (0, 255, 0, 255))
        fill((8, 80, 32, 96), "red"); fill((32, 80, 56, 96), "blue")
    elif kind == "mixed":
        fill((8, 68, 28, 92), (255, 128, 128, 255)); fill((28, 68, 68, 92), (128, 128, 255, 255))
        fill((108, 70, 124, 94), "red"); fill((124, 70, 140, 94), "blue")
    elif kind == "units": fill((3, 3, 15, 10), "red")
    elif kind == "styles":
        fill((0, 0, 8, 16), "red"); fill((8, 0, 16, 16), "blue")
        fill((18, 0, 22, 16), "red"); fill((22, 0, 28, 16), "blue")
    elif kind == "pict":
        fill((12, 12, 56, 40), "red"); fill((12, 64, 28, 88), (255, 128, 128, 255))
        fill((28, 64, 68, 88), (128, 128, 255, 255)); fill((160, 12, 172, 22), (20, 180, 60, 255))
        fill((20, 130, 30, 140), (0, 0, 128, 255))
    elif kind == "plot":
        lo, hi = row["layout"]["lower_left"], row["layout"]["upper_right"]
        for x, y, color in ((-1.5, -.75, "blue"), (-.5, -.25, "blue"), (.5, .25, "blue"), (1.5, .75, "blue"), (-1, 1, "red"), (1, -1, "red")):
            px, py = lo[0]+(x+2)/4*(hi[0]-lo[0]), lo[1]+(y+1.5)/3*(hi[1]-lo[1])
            fill((px-1, py-1, px+1, py+1), color)
        fill((10, 10, 15, 15), "black")
    return image


class Pixels(unittest.TestCase):
    def check(self, row, image):
        with tempfile.TemporaryDirectory() as t:
            path = Path(t)/"render.png"; image.save(path); return c.inspect_pixels(path, row)
    def test_every_synthetic_scene(self):
        for row in receipt()["documents"]:
            with self.subTest(id=row["id"]): self.assertTrue(self.check(row, synthetic_pixels(row))["semantic_pixels_passed"])
    def test_blank_is_not_a_pass(self):
        for row in receipt()["documents"]:
            with self.subTest(id=row["id"]), self.assertRaises(ValueError): self.check(row, Image.new("RGBA", synthetic_pixels(row).size, "white"))
    def test_wrong_opacity_is_not_tolerated(self):
        row = next(x for x in receipt()["documents"] if x["kind"] == "mixed")
        image = synthetic_pixels(row); image.putpixel((72, 160), (128, 64, 192, 255))
        with self.assertRaises(ValueError): self.check(row, image)
    def test_wrong_copy_is_not_tolerated(self):
        row = next(x for x in receipt()["documents"] if x["kind"] == "mixed")
        image = synthetic_pixels(row); image.putpixel((260, 160), (255, 0, 0, 255))
        with self.assertRaises(ValueError): self.check(row, image)
    def test_clip_leak_rejected(self):
        row = receipt()["documents"][0]; image = synthetic_pixels(row); image.putpixel((260, 28), (0, 255, 0, 255))
        with self.assertRaises(ValueError): self.check(row, image)
    def test_wrong_render_dimensions(self):
        row = receipt()["documents"][0]
        with self.assertRaises(ValueError): self.check(row, Image.new("RGBA", (10, 10), "red"))


def summary(name):
    n = v.COUNTS[name]
    return f"{n} success(es) 0 failure(s) 0 error(s) {n} test(s) run\n{name}: {n} cases, 0 failures\n"


def simulate(*, options=(), fail=None, missing=None, stale=False, mutate=False, inspect_fail=False):
    with tempfile.TemporaryDirectory() as t:
        root = Path(t); commands = []
        for name in v.SOURCES:
            path = root/name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text("synthetic")
        selected = str((root/"selected racket/racket").resolve())
        def which(name): return None if name == missing else selected if name == "racket" else str(root/"bin"/name)
        def run(self, argv, cwd):
            command = list(map(str, argv)); commands.append(command)
            if fail and any(x.endswith(fail) for x in command): raise RuntimeError("synthetic selected command failure")
            if command[1].endswith("ci-identity.rkt"): return json.dumps(FULL)
            for name in v.COUNTS:
                if command[1].endswith(name+"-test.rkt"): return summary(name)
            if command[1].endswith("dc-output-doctor.rkt"):
                docs = Path(command[command.index("--directory")+1]); docs.mkdir()
                token = command[command.index("--run-token")+1]
                value = receipt(); value["run_token"] = "stale" if stale else token
                (docs/"documents.json").write_text(json.dumps(value))
                for row in value["documents"]: (docs/row["file"]).write_bytes(b"synthetic")
                if mutate: (root/"dc-output.rkt").write_text("mutated")
                return "dc-output-documents: 24 documents; passed.\n"
            return ""
        def inspect(*args):
            if inspect_fail: raise ValueError("synthetic oracle failure")
            return dict(file=args[0].name, synthetic=True)
        with patch.object(v.shutil, "which", side_effect=which), patch.object(v.Runner, "run", new=run), \
             patch.object(c, "inspect_document", side_effect=inspect), \
             patch.object(c, "inspect_pixels", return_value=dict(file="synthetic.png", semantic_pixels_passed=True)), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code = v.main(["--racket", "racket", "--directory", str(root/"out"), *options], root=root)
        return code, json.loads((root/"out/validation.json").read_text()), commands, selected


class Completion(unittest.TestCase):
    def test_exact_suites(self):
        for name in v.COUNTS: v.suite_output(summary(name), name)
    def test_incomplete_suites_rejected(self):
        for name in v.COUNTS:
            for text in ("", summary(name)*2, summary(name).replace("0 failures", "1 failures"), summary(name)+"FAILURE\n"):
                with self.assertRaises(ValueError): v.suite_output(text, name)
    def test_worker_marker(self): v.worker_output("dc-output-documents: 24 documents; passed.\n")
    def test_incomplete_worker(self):
        for text in ("", "dc-output-documents: 23 documents; passed.\n", "ERROR\ndc-output-documents: 24 documents; passed.\n"):
            with self.assertRaises(ValueError): v.worker_output(text)
    def test_supported_identity(self): self.assertEqual(v.identity(FULL), FULL)
    def test_invalid_identity(self):
        for change in (dict(version="8.17"), dict(pointer_bytes=True), dict(vm="racket"), dict(version="unknown")):
            with self.assertRaises(ValueError): v.identity(dict(FULL, **change))
    def test_structure_only_does_not_claim_pixels(self):
        code, result, commands, selected = simulate()
        self.assertEqual(code, 0); self.assertFalse(result["independent_pixels_verified"])
        self.assertTrue(result["native_tests_passed"]); self.assertEqual(result["document_count"], 24)
        racket_commands = [cmd for cmd in commands if cmd[1].endswith(".rkt") or cmd[1] == "-l"]
        self.assertTrue(racket_commands)
        self.assertTrue(all(cmd[0] == selected for cmd in racket_commands))
        self.assertTrue(any("examples/dc-output.rkt" in cmd[-1].replace("\\", "/") for cmd in commands if "make" in cmd))
    def test_independent_renderers_are_executed(self):
        code, result, commands, _ = simulate(options=("--require-renderers",))
        self.assertEqual(code, 0); self.assertTrue(result["independent_pixels_verified"])
        self.assertEqual(sum(cmd[0].endswith(("pdftoppm", "rsvg-convert")) for cmd in commands), 24)
    def test_missing_racket_fails(self): self.assertEqual(simulate(missing="racket")[0], 1)
    def test_missing_renderer_fails(self): self.assertEqual(simulate(options=("--require-renderers",), missing="rsvg-convert")[0], 1)
    def test_baseline_failure_stops_worker(self):
        code, result, commands, _ = simulate(fail="run-tests.rkt")
        self.assertEqual(code, 1); self.assertFalse(result["baseline_passed"])
        self.assertFalse(any(cmd[1].endswith("dc-output-doctor.rkt") for cmd in commands))
    def test_native_failure_not_passed(self): self.assertEqual(simulate(fail="dc-output-native-test.rkt")[0], 1)
    def test_bad_receipt_fails(self): self.assertEqual(simulate(stale=True)[0], 1)
    def test_bad_document_fails(self): self.assertEqual(simulate(inspect_fail=True)[0], 1)
    def test_source_changed_fails(self):
        code, result, _, _ = simulate(mutate=True)
        self.assertEqual(code, 1); self.assertIn("source changed", result["error"])


class Sources(unittest.TestCase):
    def test_case_counts(self):
        for name, n in v.COUNTS.items():
            source = (HERE.parent/f"tests/{name}-test.rkt").read_text()
            self.assertEqual(source.count("(test-case "), n)
            self.assertIn(f"(define {name}-test-count {n})", source)
    def test_replay_reuses_native_callbacks(self):
        source = (HERE.parent/"private/dc-output-native.rkt").read_text()
        for term in ("draw-on-canvas!", "bitmap-on-canvas!", "dc-render-text-on-canvas!", "draw-output-group"):
            self.assertIn(term, source)
        self.assertNotIn("gpu-surface", source)
    def test_example_has_local_cli_state(self):
        source = (HERE.parent/"examples/dc-output.rkt").read_text()
        self.assertLess(source.index("(module+ main"), source.index("(define directory"))
        self.assertNotIn("racket/gui", source)
    def test_named_annotations_use_live_canvas(self):
        source = (HERE.parent/"private/dc-output-native.rkt").read_text()
        self.assertIn("canvas-define-destination!", source); self.assertIn("relative-state destination", source)
    def test_identity_shader_map_is_not_serialization_baggage(self):
        source = (HERE.parent/"private/dc-style-render.rkt").read_text()
        self.assertIn("dc-identity", source); self.assertIn("shader-with-local-matrix", source)
    def test_document_worker_uses_strict_export_audit(self):
        source = (HERE.parent/"tools/dc-output-doctor.rkt").read_text()
        self.assertIn("sk:output->bytes/audit pages fmt #:policy 'error", source)
        self.assertIn("'audit_policy \"error\"", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Dependency-free checks for the cartoon plank WALL LINING. Run from root."""
import importlib.util
import json
import math
import re
import struct
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ("Models/Wall_Lining_Straight.glb", "Models/Wall_Lining_Corner.glb")
STRAIGHT_WRAP = "Models/Wall_Lining_Straight.tscn"
CORNER_WRAP = "Models/Wall_Lining_Corner.tscn"
SHADER = "materials/wall_wood.gdshader"
MATERIAL = "materials/wall_wood_mat.tres"


def glb(path: Path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data)
    assert (magic, version, length) == (b"glTF", 2, len(data))
    size, kind = struct.unpack_from("<I4s", data, 12)
    assert kind == b"JSON"
    doc = json.loads(data[20:20 + size])
    offset = 20 + size
    size, kind = struct.unpack_from("<I4s", data, offset)
    assert kind == b"BIN\0"
    return doc, data[offset + 8:offset + 8 + size]


def accessor(doc, binary, index):
    a = doc["accessors"][index]
    view = doc["bufferViews"][a["bufferView"]]
    fmt = {5126: "f"}[a["componentType"]]
    n = {"VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    assert "byteStride" not in view
    base = view.get("byteOffset", 0) + a.get("byteOffset", 0)
    return list(struct.iter_unpack("<" + fmt * n,
                                   binary[base:base + a["count"] * n * 4]))


def mesh_data(path):
    doc, binary = glb(path)
    prim = doc["meshes"][0]["primitives"][0]
    a = prim["attributes"]
    return doc, {
        "pos": accessor(doc, binary, a["POSITION"]),
        "nrm": accessor(doc, binary, a["NORMAL"]),
        "col": accessor(doc, binary, a["COLOR_0"]),
        "uv": accessor(doc, binary, a["TEXCOORD_0"]),
    }


def generator():
    location = importlib.util.spec_from_file_location(
        "lining_gen", ROOT / "Tools" / "generate_wall_lining.py")
    module = importlib.util.module_from_spec(location)
    location.loader.exec_module(module)
    return module


class WallLining(unittest.TestCase):
    def test_assets_are_single_mesh_without_textures(self):
        for name in ASSETS:
            doc, data = mesh_data(ROOT / name)
            with self.subTest(name):
                self.assertEqual(doc["asset"]["generator"],
                                 "generate_wall_lining.py v3")
                self.assertEqual(len(doc["meshes"]), 1)
                self.assertEqual(len(doc["meshes"][0]["primitives"]), 1)
                self.assertEqual(len(doc["materials"]), 1)
                self.assertEqual(doc["meshes"][0]["primitives"][0]["material"], 0)
                for gone in ("images", "textures", "samplers"):
                    self.assertNotIn(gone, doc)
                self.assertNotIn("baseColorTexture",
                                 doc["materials"][0]["pbrMetallicRoughness"])
                attrs = doc["meshes"][0]["primitives"][0]["attributes"]
                self.assertEqual(set(attrs),
                                 {"POSITION", "NORMAL", "COLOR_0", "TEXCOORD_0"})
                self.assertEqual(len(data["pos"]), len(data["nrm"]))
                self.assertEqual(len(data["pos"]), len(data["col"]))
                self.assertEqual(len(data["pos"]), len(data["uv"]))
                self.assertEqual(len(data["pos"]) % 3, 0)
                self.assertGreater(len(data["pos"]) // 3, 1500)

    def test_geometry_has_no_degenerate_triangles_and_closed_grooves(self):
        for name in ASSETS:
            doc, data = mesh_data(ROOT / name)
            with self.subTest(name):
                pos = data["pos"]
                deg = 0
                for i in range(0, len(pos) - 2, 3):
                    a, b, c = pos[i:i + 3]
                    u = [b[k] - a[k] for k in range(3)]
                    v = [c[k] - a[k] for k in range(3)]
                    cross = [u[1] * v[2] - u[2] * v[1],
                             u[2] * v[0] - u[0] * v[2],
                             u[0] * v[1] - u[1] * v[0]]
                    if math.sqrt(sum(k * k for k in cross)) < 1e-9:
                        deg += 1
                self.assertEqual(deg, 0)
                xs = [p[0] for p in pos]
                ys = [p[1] for p in pos]
                zs = [p[2] for p in pos]
                self.assertGreaterEqual(min(ys), -0.001)
                self.assertLessEqual(max(ys), 27.001)
                self.assertGreaterEqual(min(xs), -0.001)
                self.assertLessEqual(max(xs), 6.401)
                # All lining sits ~30 mm in FRONT of the flat inner wall face.
                self.assertLess(min(zs), -1.04)
                self.assertGreater(max(zs), -1.03)
                # Feature flags: 0 face / 0.6 backing. No chamfer strips now:
                # GAP=0 and CH=0 mean neighbouring boards share an edge.
                flags = {round(c[1], 2) for c in data["col"]}
                self.assertIn(0.0, flags)
                self.assertIn(0.6, flags)
                self.assertNotIn(0.5, flags)
                self.assertNotIn(1.0, flags)
                self.assertTrue(all(0.0 <= c[0] <= 1.0 for c in data["col"]))
                # COLOR_0.b flags the four packed layouts (0, 1/3, 2/3, 1).
                slots = {round(c[2], 2) for c in data["col"]}
                self.assertEqual(slots, {0.0, 0.33, 0.67, 1.0})
                self.assertTrue(all(0.0 <= t[1] <= 1.0 for t in data["uv"]))
                self.assertGreater(max(t[0] for t in data["uv"]), 4.0)

    def test_boards_and_course_parameters(self):
        gen = generator()
        self.assertEqual(gen.ROWS, 12)
        self.assertAlmostEqual(gen.BH, 0.5, places=6)
        self.assertAlmostEqual(gen.W, 6.4, places=6)
        self.assertGreaterEqual(gen.MIN_LEN, 1.2)
        self.assertLessEqual(gen.MAX_LEN, 3.4)
        self.assertEqual(gen.FIBRES, 0)   # no waviness: flat board faces
        self.assertEqual(gen.WOBBLE, 0.0)
        self.assertEqual(gen.VARIANTS, 4)
        self.assertEqual(gen.VARIANT_DY, 7.0)
        self.assertEqual(len(gen.VARIANT_LEN), gen.VARIANTS)
        self.assertEqual(len(gen.VARIANT_ARC), gen.VARIANTS)
        # The four layouts must differ visibly in board count, not just tone.
        counts = []
        for v in range(gen.VARIANTS):
            cuts = gen.spans(gen.W, 41 + 101 * v, 0, *gen.VARIANT_LEN[v])
            counts.append(len(cuts))
        self.assertLessEqual(min(counts), 3)
        self.assertGreaterEqual(max(counts), 5)
        straight = gen.build_straight()
        corner = gen.build_corner()
        for mesh in (straight, corner):
            self.assertGreater(mesh.boards, 30)
        for name in ASSETS:
            doc, _ = mesh_data(ROOT / name)
            extra = doc["nodes"][0]["extras"]
            self.assertEqual(extra["rows"], 12)
            self.assertEqual(extra["material_count"], 1)
            self.assertFalse(extra["painted_details"])
            self.assertFalse(extra["textures"])
            self.assertIn("cartoon", extra["style"])
            self.assertGreaterEqual(extra["board_count"], 30)
            self.assertEqual(extra["fibres_per_board"], 0)
            self.assertEqual(extra["fibres"], 0)
            self.assertEqual(extra["variants"], gen.VARIANTS)
            self.assertEqual(extra["variant_step"], gen.VARIANT_DY)
            self.assertEqual(len(extra["variant_len"]), gen.VARIANTS)
            self.assertEqual(len(extra["variant_arc"]), gen.VARIANTS)
            self.assertNotIn("nail_count", extra)
            self.assertAlmostEqual(extra["v_groove"], gen.GAP, places=6)
            self.assertAlmostEqual(extra["chamfer"], gen.CH, places=6)

    def test_shader_uses_flat_colours_and_no_drawn_patterns(self):
        shader = (ROOT / SHADER).read_text()
        self.assertIn("shader_type spatial;", shader)
        self.assertIn("COLOR.r", shader)
        self.assertIn("COLOR.g", shader)
        self.assertIn("ALBEDO", shader)
        self.assertIn("MODEL_MATRIX", shader)
        self.assertIn("hash13", shader)
        self.assertIn("TIERS", shader)
        self.assertIn("LAYOUT_STEP", shader)
        self.assertIn("discard", shader)
        self.assertIn("v_slot", shader)
        self.assertIn("COLOR.b", shader)
        # Forbidden identifiers are checked in CODE, not in comments: the
        # header explicitly documents which drawn details were removed.
        code = "\n".join(line.split("//", 1)[0] for line in shader.splitlines())
        for forbidden in ("sampler2D", "texture(", "texture2D", "texelFetch",
                          "hint_albedo", ".png", ".jpg", "load(",
                          # Drawn surface patterns are deliberately absent.
                          "hash21", "vnoise", "sin(", "scratch", "patch",
                          "grain_lines", "wear", "UV.x", "UV.y",
                          "nail_metallic", "METALLIC"):
            self.assertNotIn(forbidden, code, forbidden)
        mat = (ROOT / MATERIAL).read_text()
        self.assertIn("type=\"ShaderMaterial\"", mat)
        self.assertIn("res://materials/wall_wood.gdshader", mat)
        self.assertIn("shader_parameter/groove_shade", mat)
        self.assertIn("shader_parameter/tone_contrast", mat)
        self.assertNotIn("shader_parameter/grain_lines", mat)
        self.assertNotIn("shader_parameter/wear", mat)
        self.assertNotIn("shader_parameter/nail_metallic", mat)

    def test_wrappers_apply_the_shader_material(self):
        for wrap in (STRAIGHT_WRAP, CORNER_WRAP):
            text = (ROOT / wrap).read_text()
            self.assertIn("res://materials/wall_wood_mat.tres", text)
            self.assertIn("material_override = ExtResource(\"2_mat\")", text)
            self.assertIn("res://Models/Wall_Lining_", text)

    def test_scene_has_twelve_lining_instances(self):
        text = (ROOT / "main.tscn").read_text()
        self.assertIn('[node name="WallLining" type="Node3D" parent="."', text)
        self.assertIn("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -6.4, 0, 10.4743)", text)
        straight = len(re.findall(r'instance=ExtResource\("15_lining_straight"\)', text))
        corner = len(re.findall(r'instance=ExtResource\("16_lining_corner"\)', text))
        self.assertEqual(straight, 8)
        self.assertEqual(corner, 4)
        # The original wall ring must remain untouched.
        self.assertEqual(text.count('parent="FirstFloor"'), 12)
        self.assertIn('[node name="FirstFloor" type="Node3D"', text)
        # Recompute the shader's layout pick for all 12 placed modules.
        picks = []
        lines = text.splitlines()
        for i, line in enumerate(lines):
            if '[node name="lining_' not in line:
                continue
            tx, tz = 0.0, 0.0
            if i + 1 < len(lines) and lines[i + 1].startswith("transform = Transform3D("):
                raw = re.search(r"Transform3D\(([^)]+)\)", lines[i + 1]).group(1)
                nums = [float(v) for v in re.findall(
                    r"-?\d+\.?\d*(?:e-?\d+)?", raw)]
                tx, tz = nums[9], nums[11]
            wx, wz = tx - 6.4, tz + 10.4743  # WallLining parent shift
            picks.append(int((math.floor(wx * 0.1 + 0.5)
                              + math.floor(wz * 0.2 + 0.5) + 3.0) % 4))
        self.assertEqual(len(picks), 12)
        self.assertEqual(set(picks), {0, 1, 2, 3})
        for i in range(12):
            self.assertNotEqual(picks[i], picks[(i + 1) % 12])

    def test_generator_is_byte_reproducible(self):
        gen = generator()
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            for name, builder, meta in (
                (gen.STRAIGHT, gen.build_straight,
                 {"kind": "straight", "width": gen.W, "height": gen.HGT}),
                (gen.CORNER, gen.build_corner,
                 {"kind": "corner", "radius": gen.ARC_R}),
            ):
                gen.write_glb(out / name, builder(), name[:-4], meta)
                self.assertEqual((out / name).read_bytes(),
                                 (ROOT / "Models" / name).read_bytes(), name)


if __name__ == "__main__":
    unittest.main()

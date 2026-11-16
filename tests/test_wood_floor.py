#!/usr/bin/env python3
"""Dependency-free checks for the wall-matched broad-board floor."""
import bisect
import json
import math
import struct
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Tools"))
import generate_wood_floor as gen  # noqa: E402
import generate_wood_floor_whole as whole  # noqa: E402

FLOOR_OFFSET = 0.02
CHECKER_TOP = 0.0
ALL_ASSETS = list(gen.ASSETS) + [whole.WHOLE_NAME]


def read_glb(path):
    data = Path(path).read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if (magic, version, length) != (b"glTF", 2, len(data)):
        raise ValueError("bad GLB header")
    jlen, jtype = struct.unpack_from("<I4s", data, 12)
    if jtype != b"JSON":
        raise ValueError("missing JSON chunk")
    doc = json.loads(data[20:20 + jlen])
    return doc, data[20 + jlen + 8:]


def positions(doc, blob):
    out = []
    for prim in doc["meshes"][0]["primitives"]:
        acc = doc["accessors"][prim["attributes"]["POSITION"]]
        view = doc["bufferViews"][acc["bufferView"]]
        base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        out.extend(struct.iter_unpack("<3f", blob[base:base + acc["count"] * 12]))
    return out


def point_in_poly(x, z, poly):
    hit = False
    for i, (x0, z0) in enumerate(poly):
        x1, z1 = poly[(i + 1) % len(poly)]
        if (z0 > z) != (z1 > z):
            xi = x0 + (z - z0) * (x1 - x0) / (z1 - z0)
            if xi > x:
                hit = not hit
    return hit


def find_interval(seams, value):
    return min(max(bisect.bisect_right(seams, value) - 1, 0), len(seams) - 2)


class WallMatchedWoodFloor(unittest.TestCase):
    def test_glbs_use_rough_wood_and_one_mesh(self):
        for name in ALL_ASSETS:
            doc, blob = read_glb(ROOT / "Models" / "Floor" / name)
            self.assertEqual(doc["asset"]["generator"], "generate_wood_floor.py v5")
            self.assertEqual(doc["asset"]["version"], "2.0")
            for gone in ("images", "textures", "samplers"):
                self.assertNotIn(gone, doc, name)
            self.assertEqual(len(doc["meshes"]), 1, name)
            self.assertEqual(len(doc["materials"]), len(gen.MATERIALS), name)
            self.assertEqual(len(doc["materials"]), 5, name)
            self.assertEqual(len(doc["nodes"][0]["extras"].get("style", "")) > 0, True)
            for material in doc["materials"]:
                pbr = material["pbrMetallicRoughness"]
                self.assertEqual(pbr["metallicFactor"], 0.0)
                self.assertGreaterEqual(pbr["roughnessFactor"], 0.9)
            extra = doc["nodes"][0]["extras"]
            self.assertTrue(extra["grain_grooves"], name)
            self.assertEqual(extra["material_count"], 5, name)
            self.assertEqual(extra["tone_count"], 4, name)
            self.assertAlmostEqual(extra["groove_depth"], gen.GROOVE, places=6)
            self.assertAlmostEqual(extra["top_inset"], gen.INSET, places=6)
            self.assertAlmostEqual(extra["subfloor_y"], gen.BASE_Y, places=6)
            self.assertGreaterEqual(extra["board_count"], 5, name)
            self.assertGreaterEqual(min(p[1] for p in positions(doc, blob)), gen.BASE_Y - 1e-5)

    def test_palette_is_quiet_smoky_brown_with_warm_oak_trim(self):
        self.assertEqual(gen.WOOD_HEX, "#5E544A")
        self.assertEqual(gen.FRAME_HEX, "#7A5230")
        self.assertEqual(gen.MATERIALS[4]["name"], "Oak_Perimeter_Frame")
        self.assertEqual(gen.MATERIALS[4]["pbrMetallicRoughness"]["baseColorFactor"][:3],
                         gen.linear(gen.FRAME_HEX))
        values = [tuple(int(color[k:k + 2], 16) for k in (1, 3, 5))
                  for color in gen.WOOD_TONES]
        for rgb in values:
            self.assertLessEqual(max(rgb) - min(rgb), 25)
        self.assertLessEqual(max(max(abs(a - b) for a, b in zip(values[0], c))
                                 for c in values[1:]), 8)
        self.assertGreaterEqual(gen.PLANK_LENGTH / gen.PLANK_WIDTH, 4.0)
        self.assertGreater(gen.FRAME_WIDTH, 0.2)

    def test_main_floor_has_staggered_boards_and_oak_perimeter_frame(self):
        doc, blob = read_glb(ROOT / "Models" / "Floor" / whole.WHOLE_NAME)
        extra = doc["nodes"][0]["extras"]
        self.assertTrue(extra["continuous"])
        self.assertTrue(extra["staggered_joints"])
        self.assertTrue(extra["perimeter_frame"])
        self.assertAlmostEqual(extra["frame_width"], gen.FRAME_WIDTH, places=6)
        self.assertAlmostEqual(extra["board_width"], gen.PLANK_WIDTH, places=6)
        self.assertAlmostEqual(extra["board_length"], gen.PLANK_LENGTH, places=6)
        self.assertGreaterEqual(extra["board_count"], 250)
        primitives = doc["meshes"][0]["primitives"]
        self.assertIn(gen.FRAME_MAT, [p["material"] for p in primitives])
        self.assertEqual(len(doc["meshes"]), 1)

        pts = positions(doc, blob)
        for axis in (0, 2):
            lo, hi = min(p[axis] for p in pts), max(p[axis] for p in pts)
            self.assertAlmostEqual(lo, -whole.H, delta=0.03)
            self.assertAlmostEqual(hi, whole.H, delta=0.03)
        y_values = [p[1] for p in pts]
        self.assertAlmostEqual(min(y_values), gen.BASE_Y, delta=1e-6)
        self.assertAlmostEqual(max(y_values), gen.TOP_Y, delta=1e-6)

        blocks = whole.whole_blocks()
        self.assertEqual(len(blocks), extra["board_count"])
        z_seams = whole.whole_grid()
        full_board_count = 0
        for (row, col), poly in blocks.items():
            x_seams = whole.row_seams(row)
            width = max(p[0] for p in poly) - min(p[0] for p in poly)
            depth = max(p[1] for p in poly) - min(p[1] for p in poly)
            self.assertLessEqual(width, x_seams[col + 1] - x_seams[col] + 1e-6)
            self.assertLessEqual(depth, z_seams[row + 1] - z_seams[row] + 1e-6)
            expected_area = ((x_seams[col + 1] - x_seams[col])
                             * (z_seams[row + 1] - z_seams[row]))
            if abs(gen.area(poly) - expected_area) < 1e-6:
                full_board_count += 1
                self.assertGreater(width / depth, 3.5)
        self.assertGreater(full_board_count, 100)

        # Alternate rows move their end joints by half a board.
        even = set(round(v, 5) for v in whole.row_seams(2)[1:-1])
        odd = set(round(v, 5) for v in whole.row_seams(3)[1:-1])
        self.assertFalse(even & odd)

    def test_clipped_field_has_no_holes_and_stays_inside_frame(self):
        blocks = whole.whole_blocks()
        zs = whole.whole_grid()
        inner = gen.inset_outline(whole.outer_boundary(), gen.FRAME_WIDTH)
        step = 0.13
        checked = 0
        for ix in range(int(2 * whole.H / step)):
            for iz in range(int(2 * whole.H / step)):
                x = -whole.H + (ix + 0.43) * step
                z = -whole.H + (iz + 0.57) * step
                if not point_in_poly(x, z, inner):
                    continue
                row = find_interval(zs, z)
                xs = whole.row_seams(row)
                col = find_interval(xs, x)
                poly = blocks.get((row, col))
                checked += 1
                self.assertIsNotNone(poly)
                self.assertTrue(point_in_poly(x, z, poly), (x, z))
        self.assertGreater(checked, 10000)

        # The underlay stays above the checkerboard collider, including below joints.
        self.assertGreater(FLOOR_OFFSET + gen.BASE_Y, CHECKER_TOP)
        self.assertGreater(FLOOR_OFFSET + gen.GROOVE_Y, CHECKER_TOP)
        self.assertAlmostEqual(FLOOR_OFFSET + gen.TOP_Y, 0.02)

    def test_generation_is_byte_reproducible(self):
        with tempfile.TemporaryDirectory() as tmp:
            for asset_id, (name, (w, d, corner)) in enumerate(gen.ASSETS.items()):
                tris, boards, width = gen.build_mesh(asset_id, w, d, corner)
                out = Path(tmp) / name
                gen.write_glb(out, tris, name[:-4], w, d, corner,
                              gen.asset_meta(width, boards))
                self.assertEqual(out.read_bytes(), (ROOT / "Models" / "Floor" / name).read_bytes(), name)
            tris, boards = whole.build_whole_floor()
            out = Path(tmp) / whole.WHOLE_NAME
            gen.write_glb(out, tris, "Wood_Floor_Whole", 2 * whole.H, 2 * whole.H,
                          False, whole.whole_meta(boards))
            self.assertEqual(out.read_bytes(),
                             (ROOT / "Models" / "Floor" / whole.WHOLE_NAME).read_bytes())

    def test_floor_node_still_covers_original_room_and_checkerboard_collider(self):
        text = (ROOT / "main.tscn").read_text()
        self.assertIn('path="res://Models/Floor/Wood_Floor_Whole.glb" id="13_woodwhole"', text)
        self.assertIn('name="floor_whole"', text)
        self.assertIn("size = Vector3(30, 1, 30)", text)
        self.assertIn(
            '[node name="Floor" type="StaticBody3D" parent="." unique_id=421905340]\n'
            'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.5, 0)', text)
        self.assertGreater(FLOOR_OFFSET + gen.BASE_Y, CHECKER_TOP)
        self.assertEqual(len(gen.floor_layout()), 16)


if __name__ == "__main__":
    unittest.main(verbosity=2)

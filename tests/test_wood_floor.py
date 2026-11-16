#!/usr/bin/env python3
"""Dependency-free checks for seven symmetric, controlled-chaos floor options."""
import hashlib
import math
import random
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
ALL_ASSETS = list(gen.ASSETS) + whole.VARIANT_NAMES


def read_glb(path):
    data = Path(path).read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if (magic, version, length) != (b"glTF", 2, len(data)):
        raise ValueError("bad GLB header")
    jlen, jtype = struct.unpack_from("<I4s", data, 12)
    if jtype != b"JSON":
        raise ValueError("missing JSON chunk")
    doc = __import__("json").loads(data[20:20 + jlen])
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


class SymmetricFloorOptions(unittest.TestCase):
    def test_assets_are_valid_warm_rough_wood_meshes(self):
        for name in ALL_ASSETS:
            doc, blob = read_glb(ROOT / "Models" / "Floor" / name)
            self.assertEqual(doc["asset"]["generator"], "generate_wood_floor.py v5", name)
            self.assertEqual(len(doc["meshes"]), 1, name)
            self.assertEqual(len(doc["materials"]), 5, name)
            for forbidden in ("images", "textures", "samplers"):
                self.assertNotIn(forbidden, doc, name)
            for material in doc["materials"]:
                pbr = material["pbrMetallicRoughness"]
                self.assertEqual(pbr["metallicFactor"], 0.0)
                self.assertGreaterEqual(pbr["roughnessFactor"], 0.9)
            extra = doc["nodes"][0]["extras"]
            self.assertTrue(extra["grain_grooves"], name)
            self.assertEqual(extra["material_count"], 5, name)
            self.assertEqual(extra["tone_count"], 4, name)
            self.assertGreaterEqual(len(positions(doc, blob)), 100, name)
            self.assertGreaterEqual(min(p[1] for p in positions(doc, blob)), gen.BASE_Y - 1e-5)

    def test_palette_is_warm_not_gray_and_ties_to_wall_oak(self):
        self.assertEqual(gen.WOOD_HEX, "#805637")
        self.assertEqual(gen.FRAME_HEX, "#7A5230")
        self.assertEqual(gen.MATERIALS[4]["name"], "Oak_Perimeter_Frame")
        tones = [tuple(int(color[k:k + 2], 16) for k in (1, 3, 5))
                 for color in gen.WOOD_TONES]
        for red, green, blue in tones:
            self.assertGreater(red, green)
            self.assertGreater(green, blue)

    def test_seven_distinct_variants_are_mirrored_patchwork(self):
        self.assertEqual(len(whole.VARIANT_NAMES), 7)
        fingerprints = set()
        for variant, name in enumerate(whole.VARIANT_NAMES):
            path = ROOT / "Models" / "Floor" / name
            doc, blob = read_glb(path)
            extra = doc["nodes"][0]["extras"]
            self.assertEqual(extra["variant"], variant + 1)
            self.assertTrue(extra["continuous"])
            self.assertTrue(extra["controlled_chaos"])
            self.assertTrue(extra["perimeter_frame"])
            self.assertEqual(extra["symmetry"], "four-way mirrored")
            self.assertEqual(extra["style"], "mirrored warm-oak patchwork")
            self.assertGreaterEqual(extra["tile_count"], 100)
            self.assertIn(gen.FRAME_MAT, [p["material"] for p in doc["meshes"][0]["primitives"]])
            pts = positions(doc, blob)
            for axis in (0, 2):
                self.assertAlmostEqual(min(p[axis] for p in pts), -whole.H, delta=0.03)
                self.assertAlmostEqual(max(p[axis] for p in pts), whole.H, delta=0.03)
            self.assertAlmostEqual(min(p[1] for p in pts), gen.BASE_Y, delta=1e-6)
            self.assertAlmostEqual(max(p[1] for p in pts), gen.TOP_Y, delta=1e-6)
            fingerprints.add(hashlib.sha256(path.read_bytes()).digest())
        self.assertEqual(len(fingerprints), 7)

    def test_each_mosaic_is_four_way_symmetric(self):
        for variant in range(7):
            blocks = whole.whole_blocks(variant)
            groups = {}
            style_groups = {}
            for key, _rect, direction, material, seed in whole.mirrored_tiles(variant):
                tile_id, sx, sz = key
                groups.setdefault(tile_id, set()).add((sx, sz))
                style_groups.setdefault(tile_id, set()).add((direction, material, seed))
            self.assertGreater(len(groups), 25)
            self.assertTrue(all(signs == {(-1, -1), (-1, 1), (1, -1), (1, 1)}
                                for signs in groups.values()))
            self.assertTrue(all(len(styles) == 1 for styles in style_groups.values()))

            # Different deterministic cuts, not seven color-only duplicates.
            rects = whole.quadrant_tiles(*whole.VARIANT_SPECS[variant])
            self.assertGreater(len(rects), 25)
        layouts = [whole.quadrant_tiles(*spec) for spec in whole.VARIANT_SPECS]
        self.assertEqual(len({repr(layout) for layout in layouts}), 7)

    def test_mirrored_tiles_cover_the_rounded_room_without_holes(self):
        inner = whole.inner_boundary()
        expected_area = gen.area(inner)
        hps = whole.polygon_halfplanes(inner)
        for variant in range(7):
            blocks = whole.whole_blocks(variant)
            # The mirrored guillotine rectangles partition the floor exactly;
            # clipping each piece to the same convex boundary preserves area.
            covered_area = sum(gen.area(poly) for poly in blocks.values())
            self.assertAlmostEqual(covered_area, expected_area, delta=0.01, msg=str(variant))

            rng = random.Random(variant + 500)
            tiles = list(whole.mirrored_tiles(variant))
            checked = 0
            for _ in range(160):
                x, z = rng.uniform(-whole.H, whole.H), rng.uniform(-whole.H, whole.H)
                if not all(a * x + b * z <= c + 1e-9 for a, b, c in hps):
                    continue
                candidate = next((key for key, (x0, x1, z0, z1), *_rest in tiles
                                  if x0 <= x <= x1 and z0 <= z <= z1), None)
                self.assertIsNotNone(candidate, (variant, x, z))
                self.assertTrue(point_in_poly(x, z, blocks[candidate]), (variant, x, z))
                checked += 1
            self.assertGreater(checked, 100)

        self.assertGreater(FLOOR_OFFSET + gen.BASE_Y, CHECKER_TOP)
        self.assertGreater(FLOOR_OFFSET + gen.GROOVE_Y, CHECKER_TOP)
        self.assertAlmostEqual(FLOOR_OFFSET + gen.TOP_Y, 0.02)

    def test_all_floor_assets_regenerate_byte_for_byte(self):
        with tempfile.TemporaryDirectory() as tmp:
            for asset_id, (name, (w, d, corner)) in enumerate(gen.ASSETS.items()):
                tris, boards, width = gen.build_mesh(asset_id, w, d, corner)
                out = Path(tmp) / name
                gen.write_glb(out, tris, name[:-4], w, d, corner,
                              gen.asset_meta(width, boards))
                self.assertEqual(out.read_bytes(),
                                 (ROOT / "Models" / "Floor" / name).read_bytes(), name)
            for variant, name in enumerate(whole.VARIANT_NAMES):
                tris, blocks = whole.build_whole_floor(variant)
                out = Path(tmp) / name
                gen.write_glb(out, tris, name[:-4], 2 * whole.H, 2 * whole.H,
                              False, whole.whole_meta(blocks, variant))
                self.assertEqual(out.read_bytes(),
                                 (ROOT / "Models" / "Floor" / name).read_bytes(), name)

    def test_main_scene_loads_and_documents_hotkey_selector(self):
        scene = (ROOT / "main.tscn").read_text()
        selector = (ROOT / "floor_variant_selector.gd").read_text()
        docs = (ROOT / "docs" / "floor_variants.md").read_text()
        self.assertIn('path="res://floor_variant_selector.gd"', scene)
        self.assertIn('name="WoodFloor" type="Node3D"', scene)
        self.assertIn('"res://Models/Floor/Wood_Floor_Variant_07.glb"', selector)
        self.assertIn("F1-F7", selector)
        self.assertIn("press **F1–F7**", docs)
        self.assertIn("size = Vector3(30, 1, 30)", scene)
        self.assertIn(
            '[node name="Floor" type="StaticBody3D" parent="." unique_id=421905340]\n'
            'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.5, 0)', scene)
        self.assertEqual(len(gen.floor_layout()), 16)


if __name__ == "__main__":
    unittest.main(verbosity=2)

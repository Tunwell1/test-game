#!/usr/bin/env python3
"""Dependency-free checks for the end-grain wooden floor.

    python tests/test_wood_floor.py -v
"""
import json
import math
import re
import struct
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Tools"))
import generate_wood_floor as gen  # noqa: E402
import generate_wood_floor_whole as whole  # noqa: E402

FLOOR_OFFSET = 0.02           # WoodFloor node in main.tscn
CHECKER_TOP = 0.0             # BoxMesh_floor (30 x 1 x 30) under Floor(-0.5)


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
        chunk = blob[base:base + acc["count"] * 12]
        out.extend(struct.iter_unpack("<3f", chunk))
    return out


def bounds(doc, blob):
    pts = positions(doc, blob)
    lo = [min(p[k] for p in pts) for k in range(3)]
    hi = [max(p[k] for p in pts) for k in range(3)]
    return lo, hi


def triangles(doc, blob):
    """Triangles grouped PER PRIMITIVE: never join vertices across material slots."""
    out = []
    for prim in doc["meshes"][0]["primitives"]:
        acc = doc["accessors"][prim["attributes"]["POSITION"]]
        view = doc["bufferViews"][acc["bufferView"]]
        base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        pts = list(struct.iter_unpack("<3f", blob[base:base + acc["count"] * 12]))
        out.extend(tuple(pts[i:i + 3]) for i in range(0, len(pts) - 2, 3))
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


ALL_ASSETS = list(gen.ASSETS) + [whole.WHOLE_NAME]


class WoodFloor(unittest.TestCase):
    def test_assets_are_valid_and_match_wall_style(self):
        for name in ALL_ASSETS:
            doc, blob = read_glb(ROOT / "Models" / "Floor" / name)
            self.assertEqual(doc["asset"]["generator"], "generate_wood_floor.py v4", name)
            self.assertEqual(doc["asset"]["version"], "2.0", name)
            for gone in ("images", "textures", "samplers"):
                self.assertNotIn(gone, doc, name)
            # ONE mesh with several CLOSE tone slots (the flat-colour ban was lifted).
            self.assertEqual(len(doc["meshes"]), 1, name)
            self.assertEqual(len(doc["materials"]), len(gen.MATERIALS), name)
            prims = doc["meshes"][0]["primitives"]
            self.assertGreaterEqual(len(prims), 1, name)
            self.assertLessEqual(len(prims), len(gen.MATERIALS), name)
            self.assertEqual(sorted(p["material"] for p in prims),
                             sorted(set(p["material"] for p in prims)), name)
            for prim in prims:
                self.assertLess(prim["material"], len(doc["materials"]), name)
            extra = doc["nodes"][0]["extras"]
            self.assertEqual(extra["material_count"], len(gen.MATERIALS), name)
            self.assertEqual(extra["tone_count"], len(gen.MATERIALS), name)
            self.assertFalse(extra["painted_details"], name)
            self.assertTrue(extra["grain_grooves"], name)
            self.assertIn("wood", extra["style"], name)
            self.assertAlmostEqual(extra["groove_depth"], gen.GROOVE, places=6)
            self.assertAlmostEqual(extra["top_inset"], gen.INSET, places=6)
            self.assertAlmostEqual(extra["subfloor_y"], gen.BASE_Y, places=6)
            self.assertGreaterEqual(extra["block_count"], 50, name)
            lo, hi = bounds(doc, blob)
            self.assertGreaterEqual(lo[1], gen.BASE_Y - 1e-5, name)
            self.assertLessEqual(hi[1], gen.TOP_Y + 0.003, name)
            self.assertGreaterEqual(hi[1], gen.TOP_Y, name)

        for name, (w, d, corner) in gen.ASSETS.items():
            doc, blob = read_glb(ROOT / "Models" / "Floor" / name)
            self.assertEqual(doc["nodes"][0]["extras"]["cell"], [w, d], name)
            self.assertEqual(doc["nodes"][0]["extras"]["corner"], corner, name)
            lo, hi = bounds(doc, blob)
            self.assertAlmostEqual(hi[0] - lo[0], w, delta=0.05, msg=name)
            self.assertAlmostEqual(hi[2] - lo[2], d, delta=0.05, msg=name)

    def test_close_tones_but_no_painted_details(self):
        # The flat-colour ban was lifted: 4 CLOSE oak tones, no 6-tone patchwork.
        self.assertEqual(len(gen.MATERIALS), 4)
        self.assertEqual(gen.WOOD_HEX, "#7A5230")
        self.assertEqual(gen.WOOD_TONES[0], gen.WOOD_HEX)
        base_rgb = [int(gen.WOOD_HEX[k:k + 2], 16) for k in (1, 3, 5)]
        for hex_color, mat in zip(gen.WOOD_TONES, gen.MATERIALS):
            rgb = [int(hex_color[k:k + 2], 16) for k in (1, 3, 5)]
            for channel, ref in zip(rgb, base_rgb):
                self.assertLessEqual(abs(channel - ref), 8,
                                     "tone must stay close to the base oak")
            pbr = mat["pbrMetallicRoughness"]
            self.assertEqual(pbr["baseColorFactor"][:3], gen.linear(hex_color))
            self.assertEqual(pbr["metallicFactor"], 0.0)
            self.assertAlmostEqual(pbr["roughnessFactor"], 0.9)
        # Ring/eye ornaments and all plank-era painted detail are gone.
        for gone in ("M_SIDE", "M_GRAIN", "M_NAIL", "M_BASE",
                     "GAP", "END_GAP", "THICK", "add_board",
                     "RING_CONTOURS", "RING_TWIST", "add_end_grain_top"):
            self.assertFalse(hasattr(gen, gone), "%s must not exist" % gone)
        self.assertTrue(hasattr(gen, "add_grain_top"))
        for gone in ("whole_rows", "whole_joints", "make_rows", "build_whole_rows"):
            self.assertFalse(hasattr(whole, gone), "%s must not exist" % gone)
        source = (ROOT / "Tools" / "generate_wood_floor.py").read_text()
        self.assertNotIn("GAP =", source)
        self.assertNotIn("THICK =", source)
        self.assertNotIn("RING_HEIGHTS", source)
        for name in ALL_ASSETS:
            doc, _ = read_glb(ROOT / "Models" / "Floor" / name)
            for gone in ("images", "textures", "samplers"):
                self.assertNotIn(gone, doc, name)
            self.assertFalse(doc["nodes"][0]["extras"]["painted_details"], name)

    def test_block_grid_is_one_scale_everywhere(self):
        self.assertGreaterEqual(gen.PITCH, 0.25)
        self.assertLessEqual(gen.PITCH, 0.35)
        self.assertEqual(gen.GRID_N, 55)
        seams = whole.whole_grid()
        self.assertEqual(len(seams), gen.GRID_N + 1)
        self.assertAlmostEqual(seams[0], -whole.H, places=6)
        self.assertAlmostEqual(seams[-1], whole.H, places=6)
        for a, b in zip(seams[:-1], seams[1:]):
            self.assertAlmostEqual(b - a, gen.PITCH, places=6)
        self.assertEqual(len(whole.rounded_square_halfplanes()),
                         4 * (gen.ARC_STEPS + 1))
        for name in ALL_ASSETS:
            doc, _ = read_glb(ROOT / "Models" / "Floor" / name)
            pitch = doc["nodes"][0]["extras"]["block_pitch"]
            self.assertGreaterEqual(pitch, 0.25, name)
            self.assertLessEqual(pitch, 0.35, name)
            self.assertLess(abs(pitch - gen.PITCH), 0.01, name)

    def test_whole_floor_is_wood_pavers_not_long_rows(self):
        doc, blob = read_glb(ROOT / "Models" / "Floor" / whole.WHOLE_NAME)
        for gone in ("images", "textures", "samplers"):
            self.assertNotIn(gone, doc)
        lo, hi = bounds(doc, blob)
        for axis in (0, 2):
            self.assertAlmostEqual(lo[axis], -whole.H, delta=0.03)
            self.assertAlmostEqual(hi[axis], whole.H, delta=0.03)

        blocks = whole.whole_blocks()
        extra = doc["nodes"][0]["extras"]
        self.assertGreater(len(blocks), 2500)
        self.assertEqual(extra["block_count"], len(blocks))
        self.assertEqual(extra["grid"], [gen.GRID_N, gen.GRID_N])
        self.assertTrue(extra["continuous"])
        self.assertTrue(extra["grain_grooves"])
        self.assertEqual(extra["tone_count"], len(gen.MATERIALS))
        self.assertGreaterEqual(extra["groove_depth"], 0.006)
        self.assertLessEqual(extra["groove_depth"], 0.010)

        # Every block is a small SQUARE, never a long plank / a long row.
        xs = set()
        zs = set()
        seams = whole.whole_grid()
        full_area = (seams[1] - seams[0]) ** 2
        for (i, j), poly in blocks.items():
            xs.add(i)
            zs.add(j)
            width = max(p[0] for p in poly) - min(p[0] for p in poly)
            depth = max(p[1] for p in poly) - min(p[1] for p in poly)
            self.assertLessEqual(width, gen.PITCH + 1e-6, (i, j))
            self.assertLessEqual(depth, gen.PITCH + 1e-6, (i, j))
            if abs(gen.area(poly) - full_area) < 1e-7:   # uncut cell = square
                self.assertAlmostEqual(width / depth, 1.0, delta=0.02, msg=str((i, j)))
        self.assertGreater(len(xs), 50)
        self.assertGreater(len(zs), 50)
        self.assertEqual(len(whole.whole_layout()), 1)

        # Real relief is present in the GLB, not a painted shade.
        ys = {round(p[1], 6) for p in positions(doc, blob)}
        self.assertGreaterEqual(len(ys), 5)
        self.assertIn(round(gen.BASE_Y, 6), ys)
        self.assertIn(round(gen.GROOVE_Y, 6), ys)
        self.assertIn(round(gen.TOP_Y, 6), ys)

    def test_no_through_gaps_geometry_closes(self):
        # V-groove: the flat top is inset, the full shared edge is 8 mm lower,
        # the continuous subfloor is 4 mm below that and ABOVE the gray floor.
        self.assertAlmostEqual(gen.GROOVE_Y, gen.TOP_Y - gen.GROOVE)
        self.assertLess(gen.BASE_Y, gen.GROOVE_Y)
        self.assertGreater(gen.GROOVE, 0.006)
        self.assertGreater(FLOOR_OFFSET + gen.BASE_Y, CHECKER_TOP)
        self.assertGreater(FLOOR_OFFSET + gen.GROOVE_Y, CHECKER_TOP)
        self.assertAlmostEqual(FLOOR_OFFSET + gen.TOP_Y, 0.02)

        doc, blob = read_glb(ROOT / "Models" / "Floor" / whole.WHOLE_NAME)
        tris = triangles(doc, blob)

        # One continuous solid subfloor plane covers the whole rounded square.
        base_tris = [t for t in tris
                     if all(abs(v[1] - gen.BASE_Y) < 1e-6 for v in t)]
        self.assertGreater(len(base_tris), 100)
        bx = [v[0] for t in base_tris for v in t]
        bz = [v[2] for t in base_tris for v in t]
        self.assertAlmostEqual(min(bx), -whole.H, delta=0.03)
        self.assertAlmostEqual(max(bx), whole.H, delta=0.03)
        self.assertAlmostEqual(min(bz), -whole.H, delta=0.03)
        self.assertAlmostEqual(max(bz), whole.H, delta=0.03)

        # Real chamfer faces join TOP_Y to the shared GROOVE_Y edge.
        chamfers = [t for t in tris
                    if any(abs(v[1] - gen.TOP_Y) < 1e-6 for v in t)
                    and any(abs(v[1] - gen.GROOVE_Y) < 1e-6 for v in t)]
        self.assertGreater(len(chamfers), 4 * len(whole.whole_blocks()))

        # Neighbouring blocks share the SAME seam interval (edge-to-edge).
        seams = whole.whole_grid()
        blocks = whole.whole_blocks()
        shared = 0
        for (i, j), poly in blocks.items():
            for other, axis, seam in (((i + 1, j), 0, seams[i + 1]),
                                      ((i, j + 1), 1, seams[j + 1])):
                if other not in blocks:
                    continue
                q = blocks[other]
                pa = [p[1 - axis] for p in poly if abs(p[axis] - seam) < 1e-6]
                qa = [p[1 - axis] for p in q if abs(p[axis] - seam) < 1e-6]
                if len(pa) < 2 or len(qa) < 2:
                    continue
                if max(pa) - min(pa) < 1e-6 or max(qa) - min(qa) < 1e-6:
                    continue
                self.assertAlmostEqual(min(pa), min(qa), delta=1e-6)
                self.assertAlmostEqual(max(pa), max(qa), delta=1e-6)
                shared += 1
        self.assertGreater(shared, 5000)

        # Point sampling: every point inside the wall boundary is covered by
        # exactly one block polygon, none is a hole and no block overflows its cell.
        hps = whole.rounded_square_halfplanes()
        pitch = seams[1] - seams[0]
        step = 0.11
        n = int(2 * whole.H / step)
        missing = 0
        checked = 0
        for ii in range(n):
            for jj in range(n):
                x = -whole.H + (ii + 0.37) * step
                z = -whole.H + (jj + 0.61) * step
                inside = all(a * x + b * z <= c + 1e-9 for a, b, c in hps)
                if not inside:
                    continue
                i = min(int((x + whole.H) / pitch), gen.GRID_N - 1)
                j = min(int((z + whole.H) / pitch), gen.GRID_N - 1)
                poly = blocks.get((i, j))
                checked += 1
                if poly is None or not point_in_poly(x, z, poly):
                    missing += 1
        self.assertGreater(checked, 20000)
        self.assertEqual(missing, 0, "through hole inside the rounded square")
        for (i, j), poly in blocks.items():
            for x, z in poly:
                self.assertGreaterEqual(x, seams[i] - 1e-6)
                self.assertLessEqual(x, seams[i + 1] + 1e-6)
                self.assertGreaterEqual(z, seams[j] - 1e-6)
                self.assertLessEqual(z, seams[j + 1] + 1e-6)

    def test_generator_reproduces_every_asset_byte_for_byte(self):
        with tempfile.TemporaryDirectory() as tmp:
            for asset_id, (name, (w, d, corner)) in enumerate(gen.ASSETS.items()):
                tris, blocks, pitch = gen.build_mesh(asset_id, w, d, corner)
                out = Path(tmp) / name
                gen.write_glb(out, tris, name[:-4], w, d, corner,
                              gen.asset_meta(pitch, blocks))
                self.assertEqual(out.read_bytes(),
                                 (ROOT / "Models" / "Floor" / name).read_bytes(), name)
            tris, blocks = whole.build_whole_floor()
            out = Path(tmp) / whole.WHOLE_NAME
            gen.write_glb(out, tris, "Wood_Floor_Whole", 2 * whole.H, 2 * whole.H,
                          False, whole.whole_meta(blocks))
            self.assertEqual(out.read_bytes(),
                             (ROOT / "Models" / "Floor" / whole.WHOLE_NAME).read_bytes())

    def test_modular_layout_still_covers_the_interior(self):
        """The 3 fallback assets remain a valid tiling for other rooms."""
        layout = gen.floor_layout()
        self.assertEqual(len(layout), 16)
        self.assertEqual(sum(1 for n, a, r, x, z in layout if a == "Wood_Floor.glb"), 4)
        self.assertEqual(sum(1 for n, a, r, x, z in layout if a == "Wood_Floor_Edge.glb"), 8)
        self.assertEqual(sum(1 for n, a, r, x, z in layout if a == "Wood_Floor_Corner.glb"), 4)
        r = gen.INNER_R
        expected = (2 * 6.4 + 2 * r) ** 2 - (4.0 - math.pi) * r * r
        covered = 4 * 6.4 ** 2 + 8 * 6.4 * r + math.pi * r * r
        self.assertAlmostEqual(covered, expected, places=6)

        def rotate(x, z, rot):
            return {0: (x, z), 90: (z, -x), 180: (-x, -z), 270: (-z, x)}[rot]

        boxes = []
        for name, asset, rot, ox, oz in layout:
            w, d, corner = gen.ASSETS[asset]
            x0, x1, z0, z1 = (0.0, w, 0.0, d) if corner else (0.0, w, -d, 0.0)
            pts = [rotate(x, z, rot) for x in (x0, x1) for z in (z0, z1)]
            xs = [ox + p[0] for p in pts]
            zs = [oz + p[1] for p in pts]
            boxes.append((name, (min(xs), min(zs), max(xs), max(zs))))
        half = 6.4 + r
        for name, b in boxes:
            self.assertGreaterEqual(b[0], -half - 0.005, name)
            self.assertGreaterEqual(b[1], -half - 0.005, name)
            self.assertLessEqual(b[2], half + 0.005, name)
            self.assertLessEqual(b[3], half + 0.005, name)
        for i, (na, a) in enumerate(boxes):
            for nb, b in boxes[i + 1:]:
                ox = min(a[2], b[2]) - max(a[0], b[0])
                oz = min(a[3], b[3]) - max(a[1], b[1])
                self.assertLessEqual(max(0.0, ox) * max(0.0, oz), 1e-6,
                                    "%s overlaps %s" % (na, nb))

    def test_main_scene_uses_one_continuous_floor(self):
        text = (ROOT / "main.tscn").read_text()
        self.assertIn('path="res://Models/Floor/Wood_Floor_Whole.glb" id="13_woodwhole"', text)
        for gone in ("floor_center_0", "floor_edge_top_0", "floor_corner_ne"):
            self.assertNotIn('name="%s"' % gone, text)
        parent = re.search(r'\[node name="WoodFloor" type="Node3D" parent="\."[^\]]*\]\n'
                           r'transform = Transform3D\(([^)]*)\)', text)
        self.assertIsNotNone(parent)
        self.assertAlmostEqual(float(parent.group(1).split(",")[10]), FLOOR_OFFSET)

        pattern = re.compile(
            r'\[node name="(\w+)" parent="WoodFloor"[^]]*instance=ExtResource\("([^"]+)"\)\]\n'
            r'transform = Transform3D\(([^)]*)\)')
        found = pattern.findall(text)
        self.assertEqual(len(found), 1, "scene must have exactly one floor instance")
        name, rid, values = found[0]
        self.assertEqual(name, "floor_whole")
        self.assertEqual(rid, "13_woodwhole")
        nums = [float(v.strip()) for v in values.split(",")]
        self.assertEqual(nums[:9], list(gen.ROTATIONS[0]))
        self.assertEqual(nums[9:], [0.0, 0.0, 0.0])

        # The checkerboard Floor mesh is still there (smoke test pairs it with
        # its collider); its top is at y = 0, BELOW the wooden subfloor.
        self.assertIn("size = Vector3(30, 1, 30)", text)
        self.assertIn(
            '[node name="Floor" type="StaticBody3D" parent="." unique_id=421905340]\n'
            'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.5, 0)', text)
        self.assertGreater(FLOOR_OFFSET + gen.BASE_Y, CHECKER_TOP)


if __name__ == "__main__":
    unittest.main(verbosity=2)

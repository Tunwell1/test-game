#!/usr/bin/env python3
"""Dependency-free GLB geometry, scale and scene checks; run from the project root."""
import importlib.util
import json
import math
from pathlib import Path
import re
import struct
import tempfile
import unittest

RADIUS = 4.0743
MODULE_LENGTH = 6.4
OUTER = RADIUS + 0.2
INNER = RADIUS - 1.0
Z_MIN = -RADIUS
Z_MAX = 0.2

CORNER_RESOURCE = "9_kek77"
IDENTITY = (
    [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]],
    [0.0, 0.0, 0.0],
)
# Exit transform of a straight module and of a corner, in module-local space.
# Matches Tools/wall_builder.gd: Basis(UP, PI/2) + Vector3(CORNER_STEP, 0, -CORNER_STEP).
EXIT_STRAIGHT = (IDENTITY[0], [MODULE_LENGTH, 0.0, 0.0])
EXIT_CORNER = (
    [[0.0, 0.0, 1.0], [0.0, 1.0, 0.0], [-1.0, 0.0, 0.0]],
    [RADIUS, 0.0, -RADIUS],
)


def glb(path: Path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data)
    assert (magic, version, length) == (b"glTF", 2, len(data))
    size, kind = struct.unpack_from("<I4s", data, 12)
    assert kind == b"JSON"
    doc = json.loads(data[20 : 20 + size])
    offset = 20 + size
    size, kind = struct.unpack_from("<I4s", data, offset)
    assert kind == b"BIN\0"
    return doc, data[offset + 8 : offset + 8 + size]


def read_accessor(doc, binary: bytes, index: int):
    a = doc["accessors"][index]
    view = doc["bufferViews"][a["bufferView"]]
    fmt_char = {5123: "H", 5125: "I", 5126: "f"}[a["componentType"]]
    count = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[a["type"]]
    assert "byteStride" not in view
    offset = view.get("byteOffset", 0) + a.get("byteOffset", 0)
    byte_len = a["count"] * count * struct.calcsize("<" + fmt_char)
    return list(struct.iter_unpack("<" + fmt_char * count, binary[offset : offset + byte_len]))


def matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def mv(a, v):
    return [sum(a[i][j] * v[j] for j in range(3)) for i in range(3)]


def compose(t1, t2):
    b1, o1 = t1
    b2, o2 = t2
    shifted = mv(b1, o2)
    return (matmul(b1, b2), [o1[i] + shifted[i] for i in range(3)])


def parse_first_floor(text: str):
    """Return [(name, kind, basis_rows, origin)] for FirstFloor children in file order."""
    lines = text.splitlines()
    nodes = []
    i = 0
    pattern = re.compile(
        r'\[node name="([^"]+)" parent="FirstFloor"[^]]*instance=ExtResource\("([^"]+)"\)\]'
    )
    while i < len(lines):
        match = pattern.match(lines[i])
        if not match:
            i += 1
            continue
        name, resource = match.group(1), match.group(2)
        flat = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]
        j = i + 1
        while j < len(lines) and not lines[j].startswith("["):
            if lines[j].startswith("transform = Transform3D("):
                flat = [
                    float(x) for x in lines[j].split("(", 1)[1].rstrip(")").split(",")
                ]
            j += 1
        self_basis = [flat[0:3], flat[3:6], flat[6:9]]
        nodes.append((name, "corner" if resource == CORNER_RESOURCE else "straight",
                      self_basis, flat[9:12]))
        i = j
    return nodes


class Corners(unittest.TestCase):
    def test_corner_wall_asset_and_scenes(self):
        path = Path("Models/Corner_Wall.glb")
        self.assertTrue(path.exists())
        # Guard against un-decimated multi-megabyte subdivision exports.
        self.assertLess(path.stat().st_size, 2_000_000)

        doc, binary = glb(path)
        self.assertEqual(doc["asset"]["version"], "2.0")
        self.assertEqual(len(doc["meshes"]), 1)
        mesh_nodes = [n for n in doc["nodes"] if "mesh" in n]
        self.assertEqual(len(mesh_nodes), 1)
        for key in ("translation", "rotation", "scale", "matrix"):
            self.assertNotIn(key, mesh_nodes[0])
        self.assertAlmostEqual(mesh_nodes[0]["extras"]["radius"], RADIUS)
        self.assertEqual(mesh_nodes[0]["extras"]["stone_scale"], "1:1")

        wall_doc, _ = glb(Path("Models/Wall.glb"))
        self.assertEqual(len(doc["materials"]), len(wall_doc["materials"]))

        vertices = []
        total_tris = 0
        for primitive in doc["meshes"][0]["primitives"]:
            attrs = primitive["attributes"]
            points = read_accessor(doc, binary, attrs["POSITION"])
            normals = read_accessor(doc, binary, attrs["NORMAL"])
            uvs = read_accessor(doc, binary, attrs["TEXCOORD_0"])
            self.assertEqual(len(points), len(normals))
            self.assertEqual(len(points), len(uvs))

            if "indices" in primitive:
                indices = [x[0] for x in read_accessor(doc, binary, primitive["indices"])]
            else:
                indices = list(range(len(points)))
            self.assertEqual(len(indices) % 3, 0)
            total_tris += len(indices) // 3

            for i in range(0, len(indices), 3):
                i0, i1, i2 = indices[i], indices[i + 1], indices[i + 2]
                a, b, c = points[i0], points[i1], points[i2]
                u = [b[j] - a[j] for j in range(3)]
                v = [c[j] - a[j] for j in range(3)]
                cross = [
                    u[1] * v[2] - u[2] * v[1],
                    u[2] * v[0] - u[0] * v[2],
                    u[0] * v[1] - u[1] * v[0],
                ]
                mag = math.sqrt(sum(x * x for x in cross))
                self.assertGreater(mag, 1e-7)
                for idx in (i0, i1, i2):
                    dot = sum(cross[j] * normals[idx][j] for j in range(3)) / mag
                    self.assertGreater(dot, 0.999)
            vertices.extend(points)

        self.assertLess(total_tris, 20_000)

        # Quarter annulus: 4.2743 x 4.2743 m footprint, 6 m tall.
        for axis, minimum, maximum in ((0, 0.0, OUTER), (1, 0.0, 6.0), (2, Z_MIN, Z_MAX)):
            self.assertAlmostEqual(min(p[axis] for p in vertices), minimum, delta=0.002)
            self.assertAlmostEqual(max(p[axis] for p in vertices), maximum, delta=0.002)

        # Every vertex lies on the 90-degree arc centred at (0, y, -RADIUS).
        for x, _y, z in vertices:
            r = math.hypot(x, z + RADIUS)
            theta = math.atan2(x, z + RADIUS)
            self.assertGreaterEqual(r, INNER - 0.05)
            self.assertLessEqual(r, OUTER + 0.05)
            self.assertGreaterEqual(theta, -0.02)
            self.assertLessEqual(theta, math.pi / 2.0 + 0.02)

        # Seams still join ordinary 6.4 m modules without a wrapper transform.
        entrance_z = [p[2] for p in vertices if p[0] < 0.01]
        exit_x = [p[0] for p in vertices if p[2] < Z_MIN + 0.01]
        self.assertAlmostEqual(min(entrance_z), -1.0, delta=0.002)
        self.assertAlmostEqual(max(entrance_z), 0.2, delta=0.002)
        self.assertAlmostEqual(min(exit_x), INNER, delta=0.002)
        self.assertAlmostEqual(max(exit_x), OUTER, delta=0.002)
        # One straight wall's worth of masonry, not the old stretched ~10.4 m.
        self.assertAlmostEqual(RADIUS * math.pi / 2.0, MODULE_LENGTH, delta=0.001)
        self.assertLess(OUTER * math.pi / 2.0, 7.0)

        wrapper = Path("Models/Corner_Wall_with_collision.tscn").read_text()
        self.assertIn("res://Models/Corner_Wall.glb", wrapper)
        self.assertIn("res://Models/static_mesh_collision.gd", wrapper)
        self.assertIn('name="ImportedModel"', wrapper)
        self.assertNotIn("transform =", wrapper)

        builder = Path("Tools/wall_builder.gd").read_text()
        self.assertIn('"corner": "res://Models/Corner_Wall_with_collision.tscn"', builder)
        self.assertIn(f"const CORNER_STEP := {RADIUS}", builder)

        main_scene = Path("main.tscn").read_text()
        self.assertIn("res://Models/Corner_Wall_with_collision.tscn", main_scene)
        self.assertIn('[node name="FirstFloor" type="Node3D"', main_scene)
        self.assertEqual(main_scene.count(f'instance=ExtResource("{CORNER_RESOURCE}")'), 4)

    def test_generator_reproduces_committed_asset(self):
        module = self._generator()
        self.assertAlmostEqual(module.DEFAULT_RADIUS, RADIUS)
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "corner.glb"
            module.build_corner_wall(module.CornerSpec(module.DEFAULT_RADIUS), out)
            self.assertEqual(out.read_bytes(), Path("Models/Corner_Wall.glb").read_bytes())

    def test_masonry_is_not_stretched(self):
        module = self._generator()
        spec = module.CornerSpec(RADIUS)
        # Along the neutral z = 0 plane, arc length must equal source wall length.
        x0 = spec.x_body_end - 2.0
        x1 = spec.x_body_end - 1.0
        self.assertAlmostEqual(spec.radius * (spec.theta(x1) - spec.theta(x0)), x1 - x0, places=6)
        # The clipped body and the exit post meet at the same angle (no gap).
        self.assertAlmostEqual(spec.theta(spec.x_body_end), spec.theta(module.X_POST_R), places=6)
        self.assertAlmostEqual(spec.theta(module.X_MAX), math.pi / 2.0, places=6)

    def test_arc_length_matches_wall_module(self):
        module = self._generator()
        spec = module.CornerSpec(RADIUS)
        self.assertAlmostEqual(spec.radius * math.pi / 2.0, module.MODULE_LENGTH, delta=0.001)
        # The whole source wall is used: the clipped middle is essentially zero,
        # so there is no stretching and no repeated masonry on the arc.
        self.assertLess(module.X_POST_R - spec.x_body_end, 0.001)
        self.assertGreater(spec.x_body_end - module.X_POST_L, 5.9)
        self.assertAlmostEqual(
            module.DEFAULT_RADIUS,
            math.floor((2.0 * module.MODULE_LENGTH / math.pi) * 10000) / 10000,
        )
        with self.assertRaises(ValueError):
            module.CornerSpec(6.2)

    def test_first_floor_ring_closes(self):
        text = Path("main.tscn").read_text()
        self.assertIn("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -6.4, 0, 10.4743)", text)
        nodes = parse_first_floor(text)
        self.assertEqual(len(nodes), 12)
        self.assertEqual(sum(1 for n in nodes if n[1] == "corner"), 4)
        self.assertEqual(sum(1 for n in nodes if n[1] == "straight"), 8)

        cursor = (IDENTITY[0], IDENTITY[1])
        for name, kind, basis, origin in nodes:
            # Each module must sit exactly at the running cursor.
            for i in range(3):
                for j in range(3):
                    self.assertAlmostEqual(basis[i][j], cursor[0][i][j], places=5, msg=name)
                self.assertAlmostEqual(origin[i], cursor[1][i], places=4, msg=name)
            cursor = compose((basis, origin), EXIT_CORNER if kind == "corner" else EXIT_STRAIGHT)

        # Four identical sides bring the cursor back to identity: closed ring.
        for i in range(3):
            for j in range(3):
                self.assertAlmostEqual(cursor[0][i][j], IDENTITY[0][i][j], places=5)
            self.assertAlmostEqual(cursor[1][i], 0.0, places=4)

    @staticmethod
    def _generator():
        location = importlib.util.spec_from_file_location(
            "corner_gen", Path("Tools/generate_wall_corners.py")
        )
        module = importlib.util.module_from_spec(location)
        location.loader.exec_module(module)
        return module


if __name__ == "__main__":
    unittest.main()

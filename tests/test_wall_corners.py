#!/usr/bin/env python3
"""Dependency-free GLB geometry and scene wrapper checks; run from the project root."""
import json
import math
from pathlib import Path
import struct
import unittest


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


class Corners(unittest.TestCase):
    def test_corner_wall_asset_and_scenes(self):
        path = Path("Models/Corner_Wall.glb")
        self.assertTrue(path.exists())
        # Guard against un-decimated multi-megabyte subdivision exports.
        self.assertLess(path.stat().st_size, 2_000_000)

        doc, binary = glb(path)
        self.assertEqual(len(doc["meshes"]), 1)
        mesh_nodes = [n for n in doc["nodes"] if "mesh" in n]
        self.assertEqual(len(mesh_nodes), 1)
        for key in ("translation", "rotation", "scale", "matrix"):
            self.assertNotIn(key, mesh_nodes[0])

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
        for axis, minimum, maximum in ((0, 0.0, 6.6), (1, 0.0, 6.0), (2, -6.4, 0.2)):
            self.assertAlmostEqual(min(p[axis] for p in vertices), minimum, delta=0.002)
            self.assertAlmostEqual(max(p[axis] for p in vertices), maximum, delta=0.002)

        # Entrance (x ≈ 0) and exit (z ≈ -6.4) seams must align with the 6.4 m modular grid.
        entrance_z = [p[2] for p in vertices if p[0] < 0.01]
        exit_x = [p[0] for p in vertices if p[2] < -6.39]
        self.assertAlmostEqual(min(entrance_z), -1.0, delta=0.002)
        self.assertAlmostEqual(max(entrance_z), 0.2, delta=0.002)
        self.assertAlmostEqual(min(exit_x), 5.4, delta=0.002)
        self.assertAlmostEqual(max(exit_x), 6.6, delta=0.002)

        wrapper = Path("Models/Corner_Wall_with_collision.tscn").read_text()
        self.assertIn("res://Models/Corner_Wall.glb", wrapper)
        self.assertIn("res://Models/static_mesh_collision.gd", wrapper)
        self.assertIn('name="ImportedModel"', wrapper)
        self.assertNotIn("transform =", wrapper)

        builder = Path("Tools/wall_builder.gd").read_text()
        self.assertIn('"corner": "res://Models/Corner_Wall_with_collision.tscn"', builder)

        main_scene = Path("main.tscn").read_text()
        self.assertIn("res://Models/Corner_Wall_with_collision.tscn", main_scene)


if __name__ == "__main__":
    unittest.main()

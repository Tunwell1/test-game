#!/usr/bin/env python3
"""Dependency-free GLB geometry/scene checks; run from the project root."""
import json
import math
from pathlib import Path
import struct
import unittest


def glb(path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from('<4sII', data)
    assert (magic, version, length) == (b'glTF', 2, len(data))
    size, kind = struct.unpack_from('<I4s', data, 12)
    assert kind == b'JSON'
    doc = json.loads(data[20:20 + size])
    offset = 20 + size
    size, kind = struct.unpack_from('<I4s', data, offset)
    assert kind == b'BIN\0'
    return doc, data[offset + 8:offset + 8 + size]


def floats(doc, binary, index):
    a = doc['accessors'][index]
    view = doc['bufferViews'][a['bufferView']]
    assert a['componentType'] == 5126
    count = {'VEC3': 3}[a['type']]
    assert 'byteStride' not in view
    offset = view.get('byteOffset', 0) + a.get('byteOffset', 0)
    return list(struct.iter_unpack('<' + 'f' * count, binary[offset:offset + a['count'] * count * 4]))


class Corners(unittest.TestCase):
    def test_assets(self):
        for name in ('90', 'smooth'):
            with self.subTest(name=name):
                path = Path(f'Models/Wall_corner_{name}.glb')
                doc, binary = glb(path)
                self.assertEqual(len(doc['meshes']), 1)
                self.assertEqual(len([n for n in doc['nodes'] if 'mesh' in n]), 1)
                vertices = []
                for primitive in doc['meshes'][0]['primitives']:
                    points = floats(doc, binary, primitive['attributes']['POSITION'])
                    normals = floats(doc, binary, primitive['attributes']['NORMAL'])
                    self.assertEqual(len(points), len(normals))
                    self.assertEqual(len(points) % 3, 0)
                    for i in range(0, len(points), 3):
                        a, b, c = points[i:i+3]
                        u = [b[j] - a[j] for j in range(3)]
                        v = [c[j] - a[j] for j in range(3)]
                        cross = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
                        mag = math.sqrt(sum(x*x for x in cross))
                        self.assertGreater(mag, 1e-7)
                        self.assertGreater(sum(cross[j] * normals[i][j] for j in range(3)) / mag, .999)
                    vertices.extend(points)
                for axis, minimum, maximum in ((0, 0, 6.6), (1, 0, 6), (2, -6.4, .2)):
                    self.assertAlmostEqual(min(p[axis] for p in vertices), minimum, delta=.001)
                    self.assertAlmostEqual(max(p[axis] for p in vertices), maximum, delta=.001)
                scene = Path(f'Models/Wall_corner_{name}_with_collision.tscn').read_text()
                self.assertIn(f'res://Models/Wall_corner_{name}.glb', scene)
                self.assertIn('res://Models/static_mesh_collision.gd', scene)
                self.assertIn('name="ImportedModel"', scene)
                self.assertNotIn('transform =', scene)


if __name__ == '__main__':
    unittest.main()

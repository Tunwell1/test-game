#!/usr/bin/env python3
"""Build the 6.4 x 6.4 m modular Corner_Wall.glb from Models/Wall.glb.

Uses only the Python standard library — run from the repository root:
    python3 Tools/generate_wall_corners.py

The generator bends Wall.glb onto a 90-degree outer corner arc of nominal radius
6.4 m centered at (0, y, -6.4) while:
  - shifting Z by -0.55414675 m so the entrance seam at x = 0 aligns with the
    modular wall plane (z in [-1.0, +0.2]) without needing a wrapper transform;
  - keeping both end half-posts at their exact 0.20 m width so corner-to-wall
    V-posts match straight wall joints;
  - slicing only horizontally along X (32 steps on curved timber/ledges, 12 steps
    on masonry, rigid un-stretched pebbles on the plinth) instead of uniform 3D
    subdivision, keeping the model lightweight (~7k triangles, <1 MB).
"""
import json
import math
from pathlib import Path
import struct

SOURCE = Path("Models/Wall.glb")
TARGET = Path("Models/Corner_Wall.glb")

RADIUS = 6.4
HALF_PI = math.pi / 2.0
# Aligns Wall.glb's raw Z [-0.44589..+0.75415] to modular Z [-1.0000..+0.2000].
Z_SHIFT = -0.55414675

X_MIN = -0.007502
X_POST_L = 0.2014
X_POST_R = 6.2014
X_MAX = 6.402498
THETA_POST = 0.20 / RADIUS

SMOOTH_STEPS = 32
STONE_STEPS = 12
PEBBLE_COUNT = 5
PEBBLE_SOURCE_CENTER_X = 1.2017


def load_glb(path: Path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if (magic, version, length) != (b"glTF", 2, len(data)):
        raise ValueError(f"Invalid GLB header in {path}")
    json_len, json_type = struct.unpack_from("<I4s", data, 12)
    if json_type != b"JSON":
        raise ValueError(f"Expected JSON chunk in {path}")
    doc = json.loads(data[20 : 20 + json_len])
    bin_offset = 20 + json_len
    bin_len, bin_type = struct.unpack_from("<I4s", data, bin_offset)
    if bin_type != b"BIN\x00":
        raise ValueError(f"Expected BIN chunk in {path}")
    blob = data[bin_offset + 8 : bin_offset + 8 + bin_len]
    return doc, blob


def read_accessor(doc, blob: bytes, idx: int):
    acc = doc["accessors"][idx]
    bv = doc["bufferViews"][acc["bufferView"]]
    fmt_char = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}[
        acc["componentType"]
    ]
    comp_size = struct.calcsize("<" + fmt_char)
    ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    stride = bv.get("byteStride", ncomp * comp_size)
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    fmt = "<" + fmt_char * ncomp
    return [struct.unpack_from(fmt, blob, base + i * stride) for i in range(acc["count"])]


def x_to_theta(x: float) -> float:
    if x <= 0.0015:
        return 0.0
    if x >= 6.4000:
        return HALF_PI
    if x <= X_POST_L:
        return (x - 0.0015) / (X_POST_L - 0.0015) * THETA_POST
    if x >= X_POST_R:
        return (HALF_PI - THETA_POST) + (x - X_POST_R) / (6.4000 - X_POST_R) * THETA_POST
    return THETA_POST + (x - X_POST_L) / (X_POST_R - X_POST_L) * (HALF_PI - 2.0 * THETA_POST)


def bend_point(x: float, y: float, z: float):
    theta = x_to_theta(x)
    r = RADIUS + z
    return (r * math.sin(theta), y, -RADIUS + r * math.cos(theta))


def clip_poly_x(poly, x_cut: float, keep_ge: bool):
    """Clip polygon [(x, y, z, u, v), ...] against x = x_cut with vertex snapping."""
    snap = 0.0015
    dists = []
    for p in poly:
        d = p[0] - x_cut
        dists.append(0.0 if abs(d) < snap else d)

    out = []
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        da, db = dists[i], dists[(i + 1) % n]
        ina = (da >= 0.0) if keep_ge else (da <= 0.0)
        inb = (db >= 0.0) if keep_ge else (db <= 0.0)
        if ina:
            out.append(a)
        if (da > 0.0 and db < 0.0) or (da < 0.0 and db > 0.0):
            t = da / (da - db)
            out.append(tuple(a[k] + (b[k] - a[k]) * t for k in range(5)))
    return out


def slice_tri_along_x(v0, v1, v2, cuts):
    lo = min(v0[0], v1[0], v2[0])
    hi = max(v0[0], v1[0], v2[0])
    rel = [c for c in cuts if lo + 0.002 < c < hi - 0.002]
    if not rel:
        return [(v0, v1, v2)]

    polys = [[v0, v1, v2]]
    for c in rel:
        next_polys = []
        for poly in polys:
            left = clip_poly_x(poly, c, False)
            right = clip_poly_x(poly, c, True)
            if len(left) >= 3:
                next_polys.append(left)
            if len(right) >= 3:
                next_polys.append(right)
        polys = next_polys

    tris = []
    for poly in polys:
        clean = []
        for p in poly:
            if not clean or sum((p[k] - clean[-1][k]) ** 2 for k in range(3)) > 1e-10:
                clean.append(p)
        if len(clean) >= 2 and sum((clean[0][k] - clean[-1][k]) ** 2 for k in range(3)) <= 1e-10:
            clean.pop()
        for i in range(1, len(clean) - 1):
            tris.append((clean[0], clean[i], clean[i + 1]))
    return tris


def build_corner_wall():
    src_doc, src_blob = load_glb(SOURCE)
    src_mesh = src_doc["meshes"][0]

    cuts_smooth = [
        X_POST_L + (X_POST_R - X_POST_L) * k / SMOOTH_STEPS for k in range(1, SMOOTH_STEPS)
    ]
    cuts_stone = [
        X_POST_L + (X_POST_R - X_POST_L) * k / STONE_STEPS for k in range(1, STONE_STEPS)
    ]

    bin_data = bytearray()
    buffer_views = []
    accessors = []
    primitives_out = []

    def append_buffer(raw: bytes, target: int) -> int:
        while len(bin_data) % 4:
            bin_data.append(0)
        offset = len(bin_data)
        bin_data.extend(raw)
        buffer_views.append(
            {
                "buffer": 0,
                "byteOffset": offset,
                "byteLength": len(raw),
                "target": target,
            }
        )
        return len(buffer_views) - 1

    total_tris = 0
    total_verts = 0

    for pi, prim in enumerate(src_mesh["primitives"]):
        pts = read_accessor(src_doc, src_blob, prim["attributes"]["POSITION"])
        uvs = read_accessor(src_doc, src_blob, prim["attributes"]["TEXCOORD_0"])
        inds = [x[0] for x in read_accessor(src_doc, src_blob, prim["indices"])]

        bent_tris = []
        if pi == 2:
            # Extract the first plinth pebble and place rigid copies evenly along the arc.
            pebble = []
            for i in range(0, len(inds), 3):
                i0, i1, i2 = inds[i], inds[i + 1], inds[i + 2]
                if max(pts[i0][0], pts[i1][0], pts[i2][0]) < 2.0:
                    pebble.append(
                        ((pts[i0], uvs[i0]), (pts[i1], uvs[i1]), (pts[i2], uvs[i2]))
                    )
            arc_span = HALF_PI - 2.0 * THETA_POST
            for k in range(PEBBLE_COUNT):
                theta_c = THETA_POST + arc_span * (k + 0.5) / PEBBLE_COUNT
                st, ct = math.sin(theta_c), math.cos(theta_c)
                for (pa, uva), (pb, uvb), (pc, uvc) in pebble:
                    tri_v = []
                    for p, uv in ((pa, uva), (pb, uvb), (pc, uvc)):
                        dx = p[0] - PEBBLE_SOURCE_CENTER_X
                        r = RADIUS + (p[2] + Z_SHIFT)
                        wx = r * st + dx * ct
                        wz = -RADIUS + r * ct - dx * st
                        tri_v.append((wx, p[1], wz, uv[0], uv[1]))
                    bent_tris.append(tuple(tri_v))
        else:
            cuts = (
                cuts_smooth
                if pi in (0, 1)
                else (cuts_stone if pi in (3, 4, 5, 6) else [])
            )
            for i in range(0, len(inds), 3):
                i0, i1, i2 = inds[i], inds[i + 1], inds[i + 2]
                v0 = (pts[i0][0], pts[i0][1], pts[i0][2] + Z_SHIFT, uvs[i0][0], uvs[i0][1])
                v1 = (pts[i1][0], pts[i1][1], pts[i1][2] + Z_SHIFT, uvs[i1][0], uvs[i1][1])
                v2 = (pts[i2][0], pts[i2][1], pts[i2][2] + Z_SHIFT, uvs[i2][0], uvs[i2][1])
                for a, b, c in slice_tri_along_x(v0, v1, v2, cuts):
                    ba = bend_point(a[0], a[1], a[2]) + (a[3], a[4])
                    bb = bend_point(b[0], b[1], b[2]) + (b[3], b[4])
                    bc = bend_point(c[0], c[1], c[2]) + (c[3], c[4])
                    bent_tris.append((ba, bb, bc))

        pos_list = []
        nrm_list = []
        uv_list = []
        idx_list = []
        vert_map = {}

        for a, b, c in bent_tris:
            ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
            vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
            nx = uy * vz - uz * vy
            ny = uz * vx - ux * vz
            nz = ux * vy - uy * vx
            mag = math.sqrt(nx * nx + ny * ny + nz * nz)
            if mag <= 1e-6:
                continue
            nx, ny, nz = nx / mag, ny / mag, nz / mag

            tri_indices = []
            for v in (a, b, c):
                key = (
                    round(v[0], 6),
                    round(v[1], 6),
                    round(v[2], 6),
                    round(nx, 5),
                    round(ny, 5),
                    round(nz, 5),
                    round(v[3], 5),
                    round(v[4], 5),
                )
                v_idx = vert_map.get(key)
                if v_idx is None:
                    v_idx = len(pos_list)
                    vert_map[key] = v_idx
                    pos_list.append((v[0], v[1], v[2]))
                    nrm_list.append((nx, ny, nz))
                    uv_list.append((v[3], v[4]))
                tri_indices.append(v_idx)
            idx_list.extend(tri_indices)

        vcount = len(pos_list)
        total_verts += vcount
        total_tris += len(idx_list) // 3

        pos_bytes = b"".join(struct.pack("<3f", *p) for p in pos_list)
        nrm_bytes = b"".join(struct.pack("<3f", *n) for n in nrm_list)
        uv_bytes = b"".join(struct.pack("<2f", *u) for u in uv_list)
        if vcount <= 65535:
            idx_comp_type = 5123  # UNSIGNED_SHORT
            idx_bytes = b"".join(struct.pack("<H", i) for i in idx_list)
        else:
            idx_comp_type = 5125  # UNSIGNED_INT
            idx_bytes = b"".join(struct.pack("<I", i) for i in idx_list)

        # Unpack rounded float32 positions so min/max match stored IEEE-754 floats exactly.
        stored_pos = list(struct.iter_unpack("<3f", pos_bytes))
        p_min = [min(p[axis] for p in stored_pos) for axis in range(3)]
        p_max = [max(p[axis] for p in stored_pos) for axis in range(3)]

        bv_pos = append_buffer(pos_bytes, 34962)
        bv_nrm = append_buffer(nrm_bytes, 34962)
        bv_uv = append_buffer(uv_bytes, 34962)
        bv_idx = append_buffer(idx_bytes, 34963)

        acc_pos = len(accessors)
        accessors.append(
            {
                "bufferView": bv_pos,
                "componentType": 5126,
                "count": vcount,
                "type": "VEC3",
                "min": p_min,
                "max": p_max,
            }
        )
        acc_nrm = len(accessors)
        accessors.append(
            {
                "bufferView": bv_nrm,
                "componentType": 5126,
                "count": vcount,
                "type": "VEC3",
            }
        )
        acc_uv = len(accessors)
        accessors.append(
            {
                "bufferView": bv_uv,
                "componentType": 5126,
                "count": vcount,
                "type": "VEC2",
            }
        )
        acc_idx = len(accessors)
        accessors.append(
            {
                "bufferView": bv_idx,
                "componentType": idx_comp_type,
                "count": len(idx_list),
                "type": "SCALAR",
            }
        )

        primitives_out.append(
            {
                "attributes": {
                    "POSITION": acc_pos,
                    "NORMAL": acc_nrm,
                    "TEXCOORD_0": acc_uv,
                },
                "indices": acc_idx,
                "material": prim["material"],
                "mode": 4,
            }
        )

    while len(bin_data) % 4:
        bin_data.append(0)

    out_doc = {
        "asset": {"generator": "generate_wall_corners.py", "version": "2.0"},
        "scene": 0,
        "scenes": [{"name": "Scene", "nodes": [0]}],
        "nodes": [{"mesh": 0, "name": "CornerWall"}],
        "materials": src_doc["materials"],
        "meshes": [{"name": "CornerWall", "primitives": primitives_out}],
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(bin_data)}],
    }

    json_bytes = json.dumps(out_doc, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4:
        json_bytes += b" "

    total_len = 12 + 8 + len(json_bytes) + 8 + len(bin_data)
    glb_bytes = (
        struct.pack("<4sII", b"glTF", 2, total_len)
        + struct.pack("<I4s", len(json_bytes), b"JSON")
        + json_bytes
        + struct.pack("<I4s", len(bin_data), b"BIN\x00")
        + bytes(bin_data)
    )
    TARGET.write_bytes(glb_bytes)
    print(
        f"{TARGET}: {len(glb_bytes):,} bytes ({len(glb_bytes) / 1024:.1f} KB), "
        f"{total_verts:,} vertices, {total_tris:,} triangles"
    )


if __name__ == "__main__":
    build_corner_wall()

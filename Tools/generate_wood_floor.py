#!/usr/bin/env python3
"""Generate a quiet, wall-matched timber floor for the first-floor ring.

    python Tools/generate_wood_floor.py            # 3 modular source GLBs
    python Tools/generate_wood_floor.py --layout  # print the fallback layout
    python Tools/generate_wood_floor_whole.py     # modular + continuous floor

The floor uses broad, staggered dark-smoked-oak boards, a restrained lengthwise
grain, shallow V-joints, and a warm oak perimeter frame that echoes the wall
posts. Geometry is clipped to the walls' rounded-square inner face. The whole
floor stays one mesh; a continuous subfloor closes every joint above the
checkerboard collider floor. Standard library only, byte reproducible.
"""
import json
import math
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "Models" / "Floor"

MODULE = 6.4
RADIUS = 4.0743
INNER_R = RADIUS - 1.0          # 3.0743 - wall inner arc / floor corner radius
H = MODULE + INNER_R            # 9.4743, half of the interior rounded square
ARC_STEPS = 28

PLANK_WIDTH = 0.52             # broad, readable boards instead of small tiles
PLANK_LENGTH = 2.4
FRAME_WIDTH = 0.28             # perimeter band in the warm wall-post oak
INSET = 0.012                  # subtle bevel at board joints
GROOVE = 0.0055                # shallow 5.5 mm V-joint
TOP_Y = 0.0                    # world 0.02 through the WoodFloor node
GROOVE_Y = TOP_Y - GROOVE
BASE_Y = TOP_Y - 0.0085        # subfloor remains above checkerboard collider
MIN_AREA = 1e-6

# Fine, shallow lengthwise grain: detail supports the boards instead of
# competing with the wall's large stylized forms.
GRAIN_LAND = (0.12, 0.22)
GRAIN_WIDTH = (0.010, 0.016)
GRAIN_DEPTH = (0.0007, 0.0014)
GRAIN_JITTER = 0.045

# Smoky brown-gray field with a little variation; warm oak is reserved for the
# border, visually tying the floor to the timber posts around the room.
WOOD_HEX = "#5E544A"
WOOD_TONES = ("#5E544A", "#61574D", "#5B5148", "#60564C")
FRAME_HEX = "#7A5230"

ASSETS = {
    "Wood_Floor.glb": (MODULE, MODULE, False),
    "Wood_Floor_Edge.glb": (MODULE, INNER_R, False),
    "Wood_Floor_Corner.glb": (INNER_R, INNER_R, True),
}


def linear(hex_color: str):
    out = []
    for k in (1, 3, 5):
        c = int(hex_color[k:k + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return out


MATERIALS = [{
    "name": "Wood" if i == 0 else "Wood_%d" % (i + 1),
    "doubleSided": True,
    "pbrMetallicRoughness": {
        "baseColorFactor": linear(hex_color) + [1.0],
        "metallicFactor": 0.0,
        "roughnessFactor": 0.9,
    },
} for i, hex_color in enumerate(WOOD_TONES)]
MATERIALS.append({
    "name": "Oak_Perimeter_Frame",
    "doubleSided": True,
    "pbrMetallicRoughness": {
        "baseColorFactor": linear(FRAME_HEX) + [1.0],
        "metallicFactor": 0.0,
        "roughnessFactor": 0.92,
    },
})
MAT = 0
FRAME_MAT = 4                         # warm oak perimeter band


def seed_for(asset_id, row, seg):
    h = (asset_id * 83492791 + row * 73856093 + seg * 19349663) & 0xFFFFFFFF
    h ^= h >> 13
    return (h * 1274126177) & 0xFFFFFFFF


def tone_for(seed, i, j):
    """Subtle board tones; no conspicuous checkerboard patches."""
    h = seed_for(seed, i, j)
    return (h % 2) * 2 + (seed_for(seed + 13, i, j) % 2)


# ---------------------------------------------------------------- 2D helpers

def clean(poly):
    out = []
    for p in poly:
        if not out or abs(p[0] - out[-1][0]) + abs(p[1] - out[-1][1]) > 1e-7:
            out.append(p)
    if len(out) > 1 and abs(out[0][0] - out[-1][0]) + abs(out[0][1] - out[-1][1]) < 1e-7:
        out.pop()
    return out if len(out) >= 3 else []


def signed_area(poly):
    return sum(poly[i][0] * poly[(i + 1) % len(poly)][1]
               - poly[(i + 1) % len(poly)][0] * poly[i][1]
               for i in range(len(poly))) / 2.0


def ccw(poly):
    return poly if signed_area(poly) > 0.0 else list(reversed(poly))


def centroid(poly):
    return (sum(p[0] for p in poly) / len(poly), sum(p[1] for p in poly) / len(poly))


def area(poly):
    return abs(signed_area(poly))


def clip(poly, a, b, c):
    """Sutherland-Hodgman: keep a*x + b*z <= c."""
    if not poly:
        return []
    out = []
    for i, p in enumerate(poly):
        q = poly[(i + 1) % len(poly)]
        dp = a * p[0] + b * p[1] - c
        dq = a * q[0] + b * q[1] - c
        inp, inq = dp <= 1e-9, dq <= 1e-9
        if inp:
            out.append(p)
        if inp != inq:
            t = dp / (dp - dq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return clean(out)


def corner_halfplanes():
    """x>=0, z>=0 and tangent lines of the r-circle (~2 mm under the wall)."""
    hp = [(-1.0, 0.0, 0.0), (0.0, -1.0, 0.0)]
    for i in range(ARC_STEPS + 1):
        t = (math.pi / 2.0) * i / ARC_STEPS
        hp.append((math.cos(t), math.sin(t), INNER_R))
    return hp


def clip_all(poly, hps):
    for a, b, c in hps:
        poly = clip(poly, a, b, c)
        if not poly:
            return []
    return poly


def rect(x0, z0, x1, z1):
    return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]


def expanded(poly, d):
    """Radial offset from the centroid (kept as a reusable 2D primitive)."""
    cx, cz = centroid(poly)
    out = []
    for x, z in poly:
        vx, vz = x - cx, z - cz
        length = math.hypot(vx, vz) or 1.0
        out.append((x + d * vx / length, z + d * vz / length))
    return out


def radial_shrink(poly, d):
    """Uniform radial inset: always keeps the vertex count and their order."""
    cx, cz = centroid(poly)
    mean_r = sum(math.hypot(x - cx, z - cz) for x, z in poly) / len(poly)
    k = max(0.55, 1.0 - d / max(mean_r, 1e-6))
    return [(cx + k * (x - cx), cz + k * (z - cz)) for x, z in poly]


def inradius(poly, cx, cz):
    """Distance from a point to the nearest edge of a convex polygon."""
    best = 1e9
    for i, (x0, z0) in enumerate(poly):
        x1, z1 = poly[(i + 1) % len(poly)]
        dx, dz = x1 - x0, z1 - z0
        length = math.hypot(dx, dz)
        if length < 1e-9:
            continue
        nx, nz = -dz / length, dx / length
        best = min(best, abs(nx * (cx - x0) + nz * (cz - z0)))
    return best


def inset_outline(poly, d):
    """True parallel inward offset of a CONVEX polygon, vertex i -> vertex i."""
    p = ccw(poly)
    n = len(p)
    cx, cz = centroid(p)
    if d > 0.8 * inradius(p, cx, cz):
        return radial_shrink(p, d)
    lines = []
    for i in range(n):
        x0, z0 = p[i]
        x1, z1 = p[(i + 1) % n]
        dx, dz = x1 - x0, z1 - z0
        length = math.hypot(dx, dz)
        if length < 1e-9:
            return radial_shrink(p, d)
        nx, nz = -dz / length, dx / length
        lines.append((nx, nz, nx * x0 + nz * z0 + d))
    out = []
    for i in range(n):
        a1, b1, c1 = lines[i - 1]
        a2, b2, c2 = lines[i]
        det = a1 * b2 - a2 * b1
        if abs(det) < 1e-12:
            return radial_shrink(p, d)
        out.append(((c1 * b2 - c2 * b1) / det, (a1 * c2 - a2 * c1) / det))
    if area(out) < MIN_AREA or area(out) >= area(p):
        return radial_shrink(p, d)
    return out


def block_grid(lo, hi, pitch):
    """Equal-sized cells, no slivers at the ends (the last cell is never tiny)."""
    n = max(1, int(round((hi - lo) / pitch)))
    return [lo + (hi - lo) * k / n for k in range(n + 1)]


# ------------------------------------------------------------- mesh building

def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def add_tri(tris, a, b, c, prefer=None, material=MAT):
    u, v = sub(b, a), sub(c, a)
    n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
    length = math.sqrt(sum(k * k for k in n))
    if length < 1e-9:
        return
    n = tuple(k / length for k in n)
    if prefer is not None and sum(n[k] * prefer[k] for k in range(3)) < 0.0:
        b, c = c, b
        n = tuple(-k for k in n)
    tris[material].append((a, b, c, n))


def add_top(tris, poly, y):
    for i in range(1, len(poly) - 1):
        add_tri(tris,
                (poly[0][0], y, poly[0][1]),
                (poly[i][0], y, poly[i][1]),
                (poly[i + 1][0], y, poly[i + 1][1]),
                (0.0, 1.0, 0.0))


def grain_strips(seed, vmin, vmax):
    """(v0, v1, y0, y1) strips: flat land, down-slope, up-slope."""
    out = []
    v = vmin - 0.05
    k = 0
    while v < vmax and k < 64:
        r1 = (seed_for(seed, k, 11) % 1000) / 1000.0
        r2 = (seed_for(seed, k, 13) % 1000) / 1000.0
        r3 = (seed_for(seed, k, 17) % 1000) / 1000.0
        land = GRAIN_LAND[0] + (GRAIN_LAND[1] - GRAIN_LAND[0]) * r1
        width = GRAIN_WIDTH[0] + (GRAIN_WIDTH[1] - GRAIN_WIDTH[0]) * r2
        depth = -(GRAIN_DEPTH[0] + (GRAIN_DEPTH[1] - GRAIN_DEPTH[0]) * r3)
        out.append((v, v + land, 0.0, 0.0))
        out.append((v + land, v + land + width / 2.0, 0.0, depth))
        out.append((v + land + width / 2.0, v + land + width, depth, 0.0))
        v += land + width
        k += 1
    return out


def add_grain_top(tris, poly, y, seed):
    """Real wood fibres: irregular shallow V-grooves running along the board."""
    r = (seed_for(seed, 0, 23) % 1000) / 1000.0
    theta = (r - 0.5) * 2.0 * GRAIN_JITTER
    nx, nz = -math.sin(theta), math.cos(theta)
    vs = [nx * p[0] + nz * p[1] for p in poly]
    vmin, vmax = min(vs) - 1e-6, max(vs) + 1e-6
    for v0, v1, h0, h1 in grain_strips(seed, vmin, vmax):
        if v1 <= vmin or v0 >= vmax:
            continue
        strip = clip_all(poly, [(nx, nz, v1), (-nx, -nz, -v0)])
        if len(strip) < 3:
            continue

        def y_at(p):
            t = (nx * p[0] + nz * p[1] - v0) / (v1 - v0)
            return y + h0 + (h1 - h0) * t

        c = centroid(strip)
        centre = (c[0], y_at(c), c[1])
        for i in range(len(strip)):
            a, b = strip[i], strip[(i + 1) % len(strip)]
            add_tri(tris, centre,
                    (a[0], y_at(a), a[1]), (b[0], y_at(b), b[1]),
                    (0.0, 1.0, 0.0))


def add_block(tris, poly, seed, mat=None):
    """One board: restrained lengthwise grain and shallow V-chamfer."""
    if mat is None:
        mat = MAT
    poly = ccw(clean(poly))
    if len(poly) < 3 or area(poly) < MIN_AREA:
        return
    local = {MAT: []}
    top = inset_outline(poly, INSET)
    if len(top) != len(poly):
        top = radial_shrink(poly, INSET)
    add_grain_top(local, top, TOP_Y, seed)
    cx, cz = centroid(poly)
    n = len(poly)
    for i in range(n):
        j = (i + 1) % n
        p, q = poly[i], poly[j]
        tp, tq = top[i], top[j]
        a = (tp[0], TOP_Y, tp[1])
        b = (tq[0], TOP_Y, tq[1])
        c = (q[0], GROOVE_Y, q[1])
        d = (p[0], GROOVE_Y, p[1])
        mx, mz = (p[0] + q[0]) / 2.0, (p[1] + q[1]) / 2.0
        prefer = (mx - cx, 0.0, mz - cz)
        add_tri(local, a, b, c, prefer)
        add_tri(local, a, c, d, prefer)
    tris.setdefault(mat, []).extend(local[MAT])


def add_subfloor(tris, base_poly):
    """Continuous solid wood under the V-grooves + a closed outer rim."""
    base = ccw(clean(base_poly))
    if len(base) < 3:
        return
    add_top(tris, base, BASE_Y)
    cx, cz = centroid(base)
    n = len(base)
    for i in range(n):
        p, q = base[i], base[(i + 1) % n]
        a = (p[0], GROOVE_Y, p[1])
        b = (q[0], GROOVE_Y, q[1])
        c = (q[0], BASE_Y, q[1])
        d = (p[0], BASE_Y, p[1])
        mx, mz = (p[0] + q[0]) / 2.0, (p[1] + q[1]) / 2.0
        prefer = (mx - cx, 0.0, mz - cz)
        add_tri(tris, a, b, c, prefer)
        add_tri(tris, a, c, d, prefer)



def empty_tris():
    return {i: [] for i in range(len(MATERIALS))}


def staggered_seams(lo, hi, target, shifted=False):
    """Even board lengths, with alternate rows shifted by half a board."""
    seams = block_grid(lo, hi, target)
    if not shifted or len(seams) < 3:
        return seams
    offset = (seams[1] - seams[0]) * 0.5
    return [lo] + [value + offset for value in seams[1:-1]] + [hi]


def build_board_rows(tris, x0, x1, z0, z1, hps, seed_base):
    """Emit broad clipped boards with half-board stagger between rows."""
    zs = block_grid(z0, z1, PLANK_WIDTH)
    boards = {}
    for row in range(len(zs) - 1):
        xs = staggered_seams(x0, x1, PLANK_LENGTH, bool(row % 2))
        for col in range(len(xs) - 1):
            poly = clean(clip_all(rect(xs[col], zs[row], xs[col + 1], zs[row + 1]), hps))
            if not poly or area(poly) < MIN_AREA:
                continue
            boards[(row, col)] = poly
            seed = seed_for(seed_base, row, col)
            add_block(tris, poly, seed, tone_for(seed_base, row, col))
    return boards, (zs[1] - zs[0] if len(zs) > 1 else 0.0)


def build_mesh(asset_id, width, depth, corner):
    tris = empty_tris()
    if corner:
        hps = corner_halfplanes()
        x0 = z0 = 0.0
        x1 = z1 = INNER_R
        base = clip_all(rect(x0, z0, x1, z1), hps)
    else:
        hps = []
        x0, x1, z0, z1 = 0.0, width, -depth, 0.0
        base = rect(x0, z0, x1, z1)
    add_subfloor(tris, base)
    boards, width_pitch = build_board_rows(tris, x0, x1, z0, z1, hps, asset_id + 1)
    return tris, boards, width_pitch


def asset_meta(pitch, blocks):
    """Node extras shared by main() and the byte-reproducibility test."""
    return {"board_width": round(pitch, 6), "board_count": len(blocks)}


def write_glb(path, tris, name, width, depth, corner, meta=None):
    blob = bytearray()
    views, accessors, primitives = [], [], []

    def append(raw, target):
        while len(blob) % 4:
            blob.append(0)
        offset = len(blob)
        blob.extend(raw)
        views.append({"buffer": 0, "byteOffset": offset,
                      "byteLength": len(raw), "target": target})
        return len(views) - 1

    total_tris = 0
    for mat_idx in sorted(tris):
        items = tris[mat_idx]
        if not items:
            continue
        total_tris += len(items)
        pos, nrm = [], []
        for a, b, c, n in items:
            for v in (a, b, c):
                pos.append(v)
                nrm.append(n)
        pb = b"".join(struct.pack("<3f", *p) for p in pos)
        nb = b"".join(struct.pack("<3f", *p) for p in nrm)
        bv_p = append(pb, 34962)
        bv_n = append(nb, 34962)
        pos_acc = len(accessors)
        accessors.append({"bufferView": bv_p, "componentType": 5126, "count": len(pos),
                          "type": "VEC3",
                          "min": [min(p[k] for p in pos) for k in range(3)],
                          "max": [max(p[k] for p in pos) for k in range(3)]})
        accessors.append({"bufferView": bv_n, "componentType": 5126,
                          "count": len(nrm), "type": "VEC3"})
        primitives.append({"attributes": {"POSITION": pos_acc, "NORMAL": pos_acc + 1},
                           "material": mat_idx, "mode": 4})

    while len(blob) % 4:
        blob.append(0)

    extras = {"cell": [width, depth], "corner": corner,
              "style": "staggered smoky-oak boards with warm oak perimeter frame",
              "material_count": len(MATERIALS), "tone_count": len(WOOD_TONES),
              "painted_details": False, "grain_grooves": True,
              "perimeter_frame": False, "frame_material": FRAME_MAT,
              "groove_depth": GROOVE, "top_inset": INSET,
              "subfloor_y": BASE_Y}
    if meta:
        extras.update(meta)
    doc = {
        "asset": {"generator": "generate_wood_floor.py v5", "version": "2.0"},
        "scene": 0,
        "scenes": [{"name": "Scene", "nodes": [0]}],
        "nodes": [{"mesh": 0, "name": name, "extras": extras}],
        "materials": MATERIALS,
        "meshes": [{"name": name, "primitives": primitives}],
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob)}],
    }
    jb = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    while len(jb) % 4:
        jb += b" "
    total = 12 + 8 + len(jb) + 8 + len(blob)
    data = (struct.pack("<4sII", b"glTF", 2, total)
            + struct.pack("<I4s", len(jb), b"JSON") + jb
            + struct.pack("<I4s", len(blob), b"BIN\x00") + bytes(blob))
    path.write_bytes(data)
    return len(data), total_tris


# ------------------------------------------------------------------- layout

ROTATIONS = {
    0: (1, 0, 0, 0, 1, 0, 0, 0, 1),
    90: (0, 0, 1, 0, 1, 0, -1, 0, 0),
    180: (-1, 0, 0, 0, 1, 0, 0, 0, -1),
    270: (0, 0, -1, 0, 1, 0, 1, 0, 0),
}


def floor_layout():
    """16 (name, asset, rotation, x, z) placements in world coordinates."""
    h = 6.4 + INNER_R
    out = []

    def add(name, asset, rot, x, z):
        out.append((name, asset, rot, x, z))

    for i, (x, z) in enumerate(((-6.4, 6.4), (0.0, 6.4), (-6.4, 0.0), (0.0, 0.0))):
        add("floor_center_%d" % i, "Wood_Floor.glb", 0, x, z)
    for i, x in enumerate((-6.4, 0.0)):
        add("floor_edge_top_%d" % i, "Wood_Floor_Edge.glb", 0, x, h)
    for i, x in enumerate((0.0, 6.4)):
        add("floor_edge_bottom_%d" % i, "Wood_Floor_Edge.glb", 180, x, -h)
    for i, z in enumerate((6.4, 0.0)):
        add("floor_edge_right_%d" % i, "Wood_Floor_Edge.glb", 90, h, z)
    for i, z in enumerate((-6.4, 0.0)):
        add("floor_edge_left_%d" % i, "Wood_Floor_Edge.glb", 270, -h, z)
    for name, rot, x, z in (("ne", 0, 6.4, 6.4), ("se", 90, 6.4, -6.4),
                            ("sw", 180, -6.4, -6.4), ("nw", 270, -6.4, 6.4)):
        add("floor_corner_%s" % name, "Wood_Floor_Corner.glb", rot, x, z)
    return out


def main():
    if "--layout" in sys.argv:
        for name, asset, rot, x, z in floor_layout():
            print("%-24s %-24s rot=%3d  x=%9.4f z=%9.4f" % (name, asset, rot, x, z))
        return
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for asset_id, (name, (width, depth, corner)) in enumerate(ASSETS.items()):
        stem = name[:-4]
        tris, blocks, pitch = build_mesh(asset_id, width, depth, corner)
        size, count = write_glb(OUT_DIR / name, tris, stem, width, depth, corner,
                                asset_meta(pitch, blocks))
        print("%s: %s bytes, %d triangles, %d boards, %.4f m board width"
              % (name, format(size, ","), count, len(blocks), pitch))


if __name__ == "__main__":
    main()

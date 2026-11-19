#!/usr/bin/env python3
"""Cartoon wooden PLANK LINING for the INNER faces of the first-floor walls.

    python Tools/generate_wall_lining.py

Writes exactly two GLBs (straight 6.4 x 6.0 m module + the R=3.0743 inner
corner arc), byte reproducible, stdlib only. NO textures / images anywhere.

Every plank is a real low-poly prism: 12 horizontal courses, unequal board
lengths with staggered butt joints, STRAIGHT edges. GAP=0 and CH=0: boards meet
edge to edge, NO dark gaps, NO chamfers, NO interior fibre lines. A continuous
backing plane sits behind the faces as a safety net, so nothing can show through.
Colour comes from ONE data channel, not bitmaps:

  COLOR_0.r = board tone tier (0..1, six tiers, permuted per instance in shader)
  COLOR_0.g = feature flag: 0 face / 0.5 chamfer / 0.6 backing

Each GLB packs FOUR different board layouts stacked along Y with a 1 m gap.
The shader picks one layout per placed module from its world position, so
neighbouring walls never show the same cuts, while there is still only ONE
straight asset and ONE corner asset. No second "pattern" GLB is needed.
materials/wall_wood.gdshader gives flat cartoon colours only. Drawn patterns
(wavy grain, worn patches, scratches, painted nail shine) are deliberately
absent. Flat faceted normals match the low-poly masonry on the OUTER side.
"""
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "Models"

# Inner wall face of Wall.glb AFTER the -0.5695177 wrapper shift:
# min(z) of Wall.glb is -0.446 -> -1.0155. Lining stands 30 mm in FRONT of it.
INNER_Z = -0.446 - 0.5695177
FACE_Z = INNER_Z - 0.030
BACK_Z = INNER_Z + 0.002
BASE_Z = INNER_Z + 0.020  # 20 mm BEHIND the wall face, never coplanar with it

W = 6.4                    # straight module width, matches Wall.glb
HGT = 6.0
ROWS = 12
BH = HGT / ROWS            # 0.5 m board course
GAP = 0.0                  # NO gaps: boards meet edge to edge
CH = 0.0                   # NO chamfer: flat faces, no dark V-grooves
SEG = 6                    # broken-edge control points per board
MIN_LEN = 1.45
MAX_LEN = 3.15
# Each packed layout gets a visibly different board length regime, so neighbouring
# modules cannot read as copies even before the per-instance tone permutation.
VARIANT_LEN = (
    (2.20, 3.10),   # 0: long boards, mostly 2 per course
    (0.95, 1.55),   # 1: short boards, 4-5 per course
    (1.50, 2.20),   # 2: medium boards, 3 per course
    (0.85, 2.60),   # 3: mixed lengths, variable count
)
VARIANT_ARC = (
    (0.22, 0.32),   # long arc boards, ~4 per quarter
    (0.10, 0.16),   # short arc boards, ~8 per quarter
    (0.15, 0.22),   # medium, ~5-6
    (0.09, 0.27),   # mixed
)
WOBBLE = 0.0               # NO wavy edges: straight board courses
FIBRES = 0                 # NO interior fibre lines: flat board faces
FIBRE_W = 0.0
FIBRE_D = 0.0
VARIANTS = 4               # board layouts packed in ONE GLB, picked in shader
VARIANT_DY = HGT + 1.0     # vertical gap between packed layouts

RADIUS = 4.0743            # corner arc centre is (0, y, -RADIUS)
ARC_R = RADIUS - 1.0       # 3.0743, inner wall arc
FACE_R = ARC_R - 0.030
BACK_R = ARC_R + 0.002
BASE_R = ARC_R + 0.020  # same 20 mm safety gap behind the corner wall
ARC_SEG = 4                # chords per corner board

MATERIAL = {
    "name": "WoodLining",
    "doubleSided": True,
    "pbrMetallicRoughness": {
        # Linear-space equivalent of #7A5230, the wall posts / floor oak.
        "baseColorFactor": [0.195365, 0.086511, 0.029557, 1.0],
        "metallicFactor": 0.0,
        "roughnessFactor": 0.9,
    },
}

STRAIGHT = "Wall_Lining_Straight.glb"
CORNER = "Wall_Lining_Corner.glb"


def h32(*parts):
    n = 2166136261
    for p in parts:
        n = ((n ^ int(p)) * 16777619) & 0xFFFFFFFF
    n ^= n >> 16
    n = (n * 2246822507) & 0xFFFFFFFF
    n ^= n >> 13
    return (n * 3266489909) & 0xFFFFFFFF


def rnd(*parts):
    return (h32(*parts) % 100000) / 100000.0


def tone(variant, row, board):
    """6 CLOSE cartoon tiers, deterministic per board, no big colour patches."""
    return (h32(77, variant, row, board) % 6) / 5.0


# ------------------------------------------------------------- triangle sink
class Mesh:
    def __init__(self):
        self.pos, self.nrm, self.col, self.uv = [], [], [], []
        self.boards = 0

    def tri(self, a, b, c, rgba, uvs, prefer=(0.0, 0.0, -1.0)):
        u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        v = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        n = (u[1] * v[2] - u[2] * v[1],
             u[2] * v[0] - u[0] * v[2],
             u[0] * v[1] - u[1] * v[0])
        length = math.sqrt(sum(k * k for k in n))
        if length < 1e-10:
            return
        n = tuple(k / length for k in n)
        if sum(n[k] * prefer[k] for k in range(3)) < 0.0:
            b, c = c, b
            uvs = (uvs[0], uvs[2], uvs[1])
            n = tuple(-k for k in n)
        for p, t in zip((a, b, c), uvs):
            self.pos.append(p)
            self.nrm.append(n)
            self.col.append(rgba)
            self.uv.append(t)

    def quad(self, a, b, c, d, rgba, uvs, prefer=(0.0, 0.0, -1.0)):
        self.tri(a, b, c, rgba, (uvs[0], uvs[1], uvs[2]), prefer)
        self.tri(a, c, d, rgba, (uvs[0], uvs[2], uvs[3]), prefer)


def stack(dst, src, dy, variant):
    """Append a variant mesh raised by dy; encode its index in COLOR_0.b."""
    flag = variant / (VARIANTS - 1)
    dst.pos.extend((x, y + dy, z) for x, y, z in src.pos)
    dst.nrm.extend(src.nrm)
    dst.col.extend((r, g, flag, a)
                   for r, g, _b, a in src.col)
    dst.uv.extend(src.uv)
    dst.boards += src.boards


def spans(width, seed, row, lo=MIN_LEN, hi=MAX_LEN):
    """Unequal board lengths with staggered butt joints (no tiny slivers)."""
    out, x, k = [], 0.0, 0
    while x < width - 1e-6:
        length = lo + (hi - lo) * rnd(seed, row, k, 1)
        end = min(width, x + length)
        if width - end < 0.55:
            end = width
        out.append((x, end))
        x = end
        k += 1
    return out


def edge_wobble(seed, row, board, k, upper):
    return (rnd(seed, row, board, 10 * k + (1 if upper else 2)) - 0.5) * 2.0 * WOBBLE


def fibre_breaks(seed, row, board, lo, hi, depth):
    """Y/Z breakpoints across one board. FIBRES=0 -> one flat quad."""
    span = hi - lo
    out = [(lo, 0.0)]
    for f in range(FIBRES):
        c = (lo + span * (f + 1) / (FIBRES + 1)
             + (rnd(seed, row, board, 30 + f) - 0.5) * 0.012)
        w = FIBRE_W * (0.8 + 0.4 * rnd(seed, row, board, 40 + f))
        out.append((c - w, 0.0))
        out.append((c, depth))
        out.append((c + w, 0.0))
    out.append((hi, 0.0))
    return out


# ------------------------------------------------------------ straight module
def build_straight_variant(variant):
    seed = 41 + 101 * variant
    m = Mesh()
    face = lambda s, f: (s, f, 0.0, 1.0)
    cham = lambda s: (s, 0.5, 0.0, 1.0)
    # Continuous backing: every V-groove has a dark wooden bottom, no holes.
    m.quad((0.0, 0.0, BASE_Z), (W, 0.0, BASE_Z), (W, HGT, BASE_Z),
           (0.0, HGT, BASE_Z), (0.25, 0.6, 0.0, 1.0),
           ((0.0, 0.0), (W, 0.0), (W, 1.0), (0.0, 1.0)))

    for row in range(ROWS):
        y0 = row * BH + GAP / 2
        y1 = (row + 1) * BH - GAP / 2
        cuts = spans(W, seed, row, *VARIANT_LEN[variant])
        for bi, (x0, x1) in enumerate(cuts):
            t = tone(variant, row, bi)
            a = x0 + (GAP / 2 if bi else 0.0)
            b = x1 - (GAP / 2 if bi < len(cuts) - 1 else 0.0)
            fa, fb = a + CH, b - CH
            if fb <= fa:
                continue
            xs = [fa + (fb - fa) * k / SEG for k in range(SEG + 1)]
            low = [y0 + CH for _k in range(SEG + 1)]
            high = [y1 - CH for _k in range(SEG + 1)]
            m.boards += 1

            for k in range(SEG):
                p, q = xs[k], xs[k + 1]
                lp, lq = low[k], low[k + 1]
                hp, hq = high[k], high[k + 1]
                # front face, broken edges, flat facets; NO interior lines
                bp = fibre_breaks(seed, row, bi, lp, hp, FIBRE_D)
                bq = fibre_breaks(seed, row, bi, lq, hq, FIBRE_D)
                for j in range(len(bp) - 1):
                    yp, dp = bp[j]
                    yq, dq = bq[j]
                    yn, en = bp[j + 1]
                    ym, fm = bq[j + 1]
                    m.quad((p, yp, FACE_Z + dp), (q, yq, FACE_Z + dq),
                           (q, ym, FACE_Z + fm), (p, yn, FACE_Z + en),
                           face(t, 0),
                           ((p, (yp - lp) / (hp - lp)),
                            (q, (yq - lq) / (hq - lq)),
                            (q, (ym - lq) / (hq - lq)),
                            (p, (yn - lp) / (hp - lp))))
                # With CH=0 there are no chamfers: two neighbouring boards
                # already share the exact same edge, so adding a dark strip
                # here would only draw a fake gap back on top of the wall.
                if CH > 0.0:
                    m.quad((p, hp, FACE_Z), (q, hq, FACE_Z),
                           (q, y1, BACK_Z), (p, y1, BACK_Z), cham(t),
                           ((p, 1.0), (q, 1.0), (q, 1.0), (p, 1.0)))
                    m.quad((p, y0, BACK_Z), (q, y0, BACK_Z),
                           (q, lq, FACE_Z), (p, lp, FACE_Z), cham(t),
                           ((p, 0.0), (q, 0.0), (q, 0.0), (p, 0.0)))

            if CH > 0.0:
                # chamfered butt ends
                for ex, inner, sgn in ((a, fa, 1.0), (b, fb, -1.0)):
                    yl, yh = low[0], high[0]
                    if sgn < 0:
                        yl, yh = low[-1], high[-1]
                    m.quad((ex, yl, BACK_Z), (inner, yl, FACE_Z),
                           (inner, yh, FACE_Z), (ex, yh, BACK_Z), cham(t),
                           ((ex, 0.0), (inner, 0.0), (inner, 1.0), (ex, 1.0)))

    return m


def build_straight():
    """Four different board layouts in ONE mesh, stacked along Y."""
    out = Mesh()
    for variant in range(VARIANTS):
        stack(out, build_straight_variant(variant), variant * VARIANT_DY, variant)
    return out


# --------------------------------------------------------------- corner arc
def arc_point(theta, y, r):
    return (r * math.sin(theta), y, -RADIUS + r * math.cos(theta))


def arc_basis(theta):
    return ((-math.sin(theta), 0.0, -math.cos(theta)),   # normal into the room
            (math.cos(theta), 0.0, -math.sin(theta)),    # tangent along arc
            (0.0, 1.0, 0.0))


def arc_spans(seed, row, lo=0.24, hi=0.44):
    out, t, k = [], 0.0, 0
    while t < math.pi / 2 - 1e-6:
        length = lo + (hi - lo) * rnd(seed, row, k, 3)   # radians per board
        end = min(math.pi / 2, t + length)
        if math.pi / 2 - end < 0.14:
            end = math.pi / 2
        out.append((t, end))
        t = end
        k += 1
    return out


def build_corner_variant(variant):
    seed = 97 + 53 * variant
    m = Mesh()
    face = lambda s, f: (s, f, 0.0, 1.0)
    cham = lambda s: (s, 0.5, 0.0, 1.0)
    steps = 24
    for k in range(steps):
        t0 = (math.pi / 2) * k / steps
        t1 = (math.pi / 2) * (k + 1) / steps
        m.quad(arc_point(t0, 0.0, BASE_R), arc_point(t1, 0.0, BASE_R),
               arc_point(t1, HGT, BASE_R), arc_point(t0, HGT, BASE_R),
               (0.25, 0.6, 0.0, 1.0),
               ((t0 * ARC_R, 0.0), (t1 * ARC_R, 0.0),
                (t1 * ARC_R, 1.0), (t0 * ARC_R, 1.0)), arc_basis((t0 + t1) / 2)[0])

    for row in range(ROWS):
        y0 = row * BH + GAP / 2
        y1 = (row + 1) * BH - GAP / 2
        cuts = arc_spans(seed, row, *VARIANT_ARC[variant])
        for bi, (t0, t1) in enumerate(cuts):
            tone_v = tone(variant, row, bi)
            a = t0 + (GAP / ARC_R if bi else 0.0)
            b = t1 - (GAP / ARC_R if bi < len(cuts) - 1 else 0.0)
            d = CH / ARC_R                # 0 => butt joints meet exactly
            ta, tb = a + d, b - d
            if tb <= ta:
                continue
            ts = [ta + (tb - ta) * k / ARC_SEG for k in range(ARC_SEG + 1)]
            low = [y0 + CH for _k in range(ARC_SEG + 1)]
            high = [y1 - CH for _k in range(ARC_SEG + 1)]
            m.boards += 1
            for k in range(ARC_SEG):
                p, q = ts[k], ts[k + 1]
                lp, lq, hp, hq = low[k], low[k + 1], high[k], high[k + 1]
                u0, u1 = p * ARC_R, q * ARC_R
                n = arc_basis((p + q) / 2)[0]
                bp = fibre_breaks(seed, row, bi, lp, hp, FIBRE_D)
                bq = fibre_breaks(seed, row, bi, lq, hq, FIBRE_D)
                for j in range(len(bp) - 1):
                    yp, dp = bp[j]
                    yq, dq = bq[j]
                    yn, en = bp[j + 1]
                    ym, fm = bq[j + 1]
                    m.quad(arc_point(p, yp, FACE_R + dp),
                           arc_point(q, yq, FACE_R + dq),
                           arc_point(q, ym, FACE_R + fm),
                           arc_point(p, yn, FACE_R + en),
                           face(tone_v, 0),
                           ((u0, (yp - lp) / (hp - lp)),
                            (u1, (yq - lq) / (hq - lq)),
                            (u1, (ym - lq) / (hq - lq)),
                            (u0, (yn - lp) / (hp - lp))), n)
                if CH > 0.0:
                    m.quad(arc_point(p, hp, FACE_R), arc_point(q, hq, FACE_R),
                           arc_point(q, y1, BACK_R), arc_point(p, y1, BACK_R),
                           cham(tone_v),
                           ((u0, 1.0), (u1, 1.0), (u1, 1.0), (u0, 1.0)), n)
                    m.quad(arc_point(p, y0, BACK_R), arc_point(q, y0, BACK_R),
                           arc_point(q, lq, FACE_R), arc_point(p, lp, FACE_R),
                           cham(tone_v),
                           ((u0, 0.0), (u1, 0.0), (u1, 0.0), (u0, 0.0)), n)
    return m


def build_corner():
    """Four different arc layouts in ONE mesh, stacked along Y."""
    out = Mesh()
    for variant in range(VARIANTS):
        stack(out, build_corner_variant(variant), variant * VARIANT_DY, variant)
    return out


# ------------------------------------------------------------------- GLB I/O
def write_glb(path, mesh, name, meta):
    blob = bytearray()
    views, accessors = [], []

    def append(raw, target):
        while len(blob) % 4:
            blob.append(0)
        off = len(blob)
        blob.extend(raw)
        views.append({"buffer": 0, "byteOffset": off,
                      "byteLength": len(raw), "target": target})
        return len(views) - 1

    packed = [
        ("POSITION", b"".join(struct.pack("<3f", *p) for p in mesh.pos), "VEC3",
         [min(p[k] for p in mesh.pos) for k in range(3)],
         [max(p[k] for p in mesh.pos) for k in range(3)]),
        ("NORMAL", b"".join(struct.pack("<3f", *p) for p in mesh.nrm), "VEC3",
         None, None),
        ("COLOR_0", b"".join(struct.pack("<4f", *p) for p in mesh.col), "VEC4",
         None, None),
        ("TEXCOORD_0", b"".join(struct.pack("<2f", *p) for p in mesh.uv), "VEC2",
         None, None),
    ]
    attrs = {}
    for key, raw, kind, lo, hi in packed:
        bv = append(raw, 34962)
        acc = {"bufferView": bv, "componentType": 5126,
               "count": len(raw) // struct.calcsize("<" + str({"VEC3": 3, "VEC4": 4, "VEC2": 2}[kind]) + "f"),
               "type": kind}
        if lo is not None:
            acc["min"], acc["max"] = lo, hi
        attrs[key] = len(accessors)
        accessors.append(acc)

    while len(blob) % 4:
        blob.append(0)

    extras = {
        "style": "cartoon plank lining, real fibre relief + 4 packed layouts",
        "generator_version": "generate_wall_lining.py v3",
        "rows": ROWS, "board_count": mesh.boards,
        "fibres_per_board": FIBRES, "fibres": mesh.boards * FIBRES,
        "variants": VARIANTS, "variant_step": VARIANT_DY,
        "variant_len": [[round(a, 3), round(b, 3)] for a, b in VARIANT_LEN],
        "variant_arc": [[round(a, 3), round(b, 3)] for a, b in VARIANT_ARC],
        "material_count": 1, "painted_details": False, "textures": False,
        "v_groove": GAP, "chamfer": CH, "face_z": round(FACE_Z, 6),
        "back_z": round(BACK_Z, 6),
    }
    extras.update(meta)
    doc = {
        "asset": {"generator": "generate_wall_lining.py v3", "version": "2.0"},
        "scene": 0,
        "scenes": [{"name": "Scene", "nodes": [0]}],
        "nodes": [{"mesh": 0, "name": name, "extras": extras}],
        "materials": [MATERIAL],
        "meshes": [{"name": name, "primitives": [
            {"attributes": attrs, "material": 0, "mode": 4}]}],
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
    return len(data), len(mesh.pos) // 3


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, builder, meta in (
        (STRAIGHT, build_straight, {"kind": "straight", "width": W, "height": HGT}),
        (CORNER, build_corner, {"kind": "corner", "radius": ARC_R}),
    ):
        mesh = builder()
        size, tris = write_glb(OUT_DIR / name, mesh, name[:-4], meta)
        print("%s: %s bytes, %d triangles, %d boards, %d fibres"
              % (name, format(size, ","), tris, mesh.boards,
                 mesh.boards * FIBRES))


if __name__ == "__main__":
    main()

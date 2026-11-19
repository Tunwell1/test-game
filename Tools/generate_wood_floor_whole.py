#!/usr/bin/env python3
"""Build the first-floor wooden floor as 16 SEPARATE modules (+ a reference mesh).

    python Tools/generate_wood_floor_whole.py            # regenerate ALL GLBs
    python Tools/generate_wood_floor_whole.py --layout  # print the placements

The SCENE uses 16 separate instances, like the 12 wall modules: a 4 x 4 grid of
~4.74 x 4.74 m modules, each holding 3 x 3 very large (1.57905 m) square wood
pavers. Module borders sit exactly ON paver grid lines, so no paver is ever cut
by a module boundary, and there are NO rotations -> no visible frame. The same
global paver grid / seed / boundary is used for every module, so grain and
V-grooves continue seamlessly across module seams.

`Wood_Floor_Whole.glb` is still generated as ONE continuous reference mesh for
the geometry tests (bounds, coverage, no through holes), but it is NOT used in
main.tscn any more. The three small modular assets remain reusable source pieces.

REAL geometry: real grain V-grooves, real 10 mm V-chamfers between pavers, one
continuous wood subfloor above the checkerboard collider floor. Standard library
only, byte reproducible.
"""
import math
import sys

import generate_wood_floor as g

WHOLE_NAME = "Wood_Floor_Whole.glb"
H = g.H                          # 9.4743, half of the interior rounded square
MODULE_N = 4                    # 4 x 4 = 16 separate scene objects
CELLS_PER_MODULE = g.GRID_N // MODULE_N   # 3 x 3 pavers per module
_BLOCKS = None


def rounded_square_halfplanes():
    """Tangent half-planes of the four r-circles = the convex interior boundary."""
    hp = []
    corners = ((6.4, 6.4, 0.0), (6.4, -6.4, -math.pi / 2),
               (-6.4, -6.4, math.pi), (-6.4, 6.4, math.pi / 2))
    for cx, cz, a0 in corners:
        for i in range(g.ARC_STEPS + 1):
            t = a0 + (math.pi / 2) * i / g.ARC_STEPS
            a, b = math.cos(t), math.sin(t)
            hp.append((a, b, g.INNER_R + a * cx + b * cz))
    return hp


def whole_grid():
    """13 seam values -> 12 equal cells, symmetric about the world origin."""
    return g.block_grid(-H, H, g.PITCH)


def whole_blocks():
    """{(column, row): clipped footprint polygon}; cached, no GLB needed."""
    global _BLOCKS
    if _BLOCKS is not None:
        return _BLOCKS
    xs = whole_grid()
    hps = rounded_square_halfplanes()
    blocks = {}
    for i in range(len(xs) - 1):
        for j in range(len(xs) - 1):
            poly = g.clean(g.clip_all(g.rect(xs[i], xs[j], xs[i + 1], xs[j + 1]), hps))
            if poly and g.area(poly) >= g.MIN_AREA:
                blocks[(i, j)] = poly
    _BLOCKS = blocks
    return blocks


def module_seams():
    """5 module borders, each exactly on a paver grid line."""
    seams = whole_grid()
    return [seams[k * CELLS_PER_MODULE] for k in range(MODULE_N + 1)]


def module_layout():
    """16 dicts: the separate GLB assets and their scene placements."""
    ms = module_seams()
    out = []
    for row in range(MODULE_N):
        for col in range(MODULE_N):
            tag = "%02d_%02d" % (row, col)
            out.append({
                "name": "Wood_Floor_Module_%s.glb" % tag,
                "stem": "Wood_Floor_Module_%s" % tag,
                "node": "floor_module_%s" % tag,
                "rid": "14_floor_%s" % tag,
                "row": row, "col": col,
                "x0": ms[col], "x1": ms[col + 1],
                "z0": ms[row], "z1": ms[row + 1],
            })
    return out


def build_module(m):
    """One module in LOCAL coordinates (its scene transform carries the origin)."""
    x0, z0 = m["x0"], m["z0"]
    hps = rounded_square_halfplanes()
    base = g.clip_all(g.rect(m["x0"], m["z0"], m["x1"], m["z1"]), hps)
    internal = module_seams()[1:-1]

    def keep_rim(p, q):
        """Skip shared internal seams: no coincident double rim walls."""
        gp = (p[0] + x0, p[1] + z0)
        gq = (q[0] + x0, q[1] + z0)
        for v in internal:
            if abs(gp[0] - v) < 1e-6 and abs(gq[0] - v) < 1e-6:
                return False
            if abs(gp[1] - v) < 1e-6 and abs(gq[1] - v) < 1e-6:
                return False
        return True

    tris = g.empty_tris()
    g.add_subfloor(tris, [(x - x0, z - z0) for x, z in base], keep_rim)
    own = {}
    for (i, j), poly in whole_blocks().items():
        if i // CELLS_PER_MODULE != m["col"] or j // CELLS_PER_MODULE != m["row"]:
            continue
        local = [(x - x0, z - z0) for x, z in poly]
        own[(i, j)] = local
        g.add_block(tris, local, g.seed_for(99, i, j), g.tone_for(99, i, j))
    return tris, own


def module_meta(m, blocks):
    """Node extras shared by main() and the byte-reproducibility test."""
    meta = g.asset_meta(g.PITCH, blocks)
    meta.update({"module": [m["row"], m["col"]], "modules": [MODULE_N, MODULE_N],
                 "cells_per_module": CELLS_PER_MODULE,
                 "origin": [m["x0"], m["z0"]], "continuous": False})
    return meta


def build_whole_floor():
    """The ONE continuous reference mesh (geometry truth for the tests)."""
    hps = rounded_square_halfplanes()
    tris = g.empty_tris()
    g.add_subfloor(tris, g.clip_all(g.rect(-H, -H, H, H), hps))
    blocks = whole_blocks()
    for (i, j), poly in blocks.items():
        g.add_block(tris, poly, g.seed_for(99, i, j), g.tone_for(99, i, j))
    return tris, blocks


def whole_meta(blocks):
    meta = g.asset_meta(g.PITCH, blocks)
    meta.update({"grid": [g.GRID_N, g.GRID_N], "continuous": True})
    return meta


def whole_layout():
    """Reference-only: the continuous mesh is no longer used in main.tscn."""
    return [("floor_whole", WHOLE_NAME, 0, 0.0, 0.0)]


def main():
    if "--layout" in sys.argv:
        for name, asset, rot, x, z in whole_layout():
            print("%-24s %-24s rot=%3d  x=%9.4f z=%9.4f" % (name, asset, rot, x, z))
        for m in module_layout():
            print("%-24s %-40s x=%9.4f z=%9.4f"
                  % (m["node"], m["name"], m["x0"], m["z0"]))
        return
    g.main()
    for m in module_layout():
        tris, blocks = build_module(m)
        size, count = g.write_glb(
            g.OUT_DIR / m["name"], tris, m["stem"],
            m["x1"] - m["x0"], m["z1"] - m["z0"], False,
            module_meta(m, blocks))
        print("%s: %s bytes, %d triangles, %d pavers, origin (%.5f, %.5f)"
              % (m["name"], format(size, ","), count, len(blocks), m["x0"], m["z0"]))
    tris, blocks = build_whole_floor()
    meta = whole_meta(blocks)
    size, count = g.write_glb(g.OUT_DIR / WHOLE_NAME, tris, "Wood_Floor_Whole",
                              2 * H, 2 * H, False, meta)
    print("%s: %s bytes, %d triangles, %d blocks, %.4f x %.4f m, REFERENCE ONLY"
          % (WHOLE_NAME, format(size, ","), count, len(blocks), 2 * H, 2 * H))


if __name__ == "__main__":
    main()

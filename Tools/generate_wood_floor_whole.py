#!/usr/bin/env python3
"""Build ONE continuous end-grain wooden floor for the first-floor ring.

    python Tools/generate_wood_floor_whole.py            # regenerate all 4 GLBs
    python Tools/generate_wood_floor_whole.py --layout  # print the placement

One 55 x 55 grid of ~0.3445 m square end-grain blocks, cut to the wall's
rounded-square inner face. No border frame, no cell seams, no rotated
instances, no long planks: the whole interior is a single mesh with real
growth-ring geometry per block and a closed 8 mm V-groove between blocks.
A continuous wood subfloor sits 4 mm under the groove bottom, above the
checkerboard collider floor, so no gap can ever look like a hole.

Reuses the primitives from generate_wood_floor.py. Standard library only,
byte reproducible. The three modular assets are still generated as reusable
source pieces.
"""
import math
import sys

import generate_wood_floor as g

WHOLE_NAME = "Wood_Floor_Whole.glb"
H = g.H                          # 9.4743, half of the interior rounded square
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
    """56 seam values -> 55 equal cells, symmetric about the world origin."""
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


def build_whole_floor():
    hps = rounded_square_halfplanes()
    tris = g.empty_tris()
    g.add_subfloor(tris, g.clip_all(g.rect(-H, -H, H, H), hps))
    blocks = whole_blocks()
    for (i, j), poly in blocks.items():
        g.add_block(tris, poly, g.seed_for(99, i, j), g.tone_for(99, i, j))
    return tris, blocks


def whole_meta(blocks):
    """Node extras shared by main() and the byte-reproducibility test."""
    meta = g.asset_meta(g.PITCH, blocks)
    meta.update({"grid": [g.GRID_N, g.GRID_N], "continuous": True})
    return meta


def whole_layout():
    return [("floor_whole", WHOLE_NAME, 0, 0.0, 0.0)]


def main():
    if "--layout" in sys.argv:
        for name, asset, rot, x, z in whole_layout():
            print("%-24s %-24s rot=%3d  x=%9.4f z=%9.4f" % (name, asset, rot, x, z))
        return
    g.main()
    tris, blocks = build_whole_floor()
    meta = whole_meta(blocks)
    size, count = g.write_glb(g.OUT_DIR / WHOLE_NAME, tris, "Wood_Floor_Whole",
                              2 * H, 2 * H, False, meta)
    print("%s: %s bytes, %d triangles, %d blocks, %.4f x %.4f m, one mesh"
          % (WHOLE_NAME, format(size, ","), count, len(blocks), 2 * H, 2 * H))


if __name__ == "__main__":
    main()

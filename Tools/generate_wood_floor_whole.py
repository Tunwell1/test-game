#!/usr/bin/env python3
"""Build the continuous broad-board floor used by the main scene.

    python Tools/generate_wood_floor_whole.py            # regenerate all 4 GLBs
    python Tools/generate_wood_floor_whole.py --layout  # print placement

The rounded-square room gets long smoky-oak boards with staggered end joints,
a quiet lengthwise grain, and a warm perimeter band that picks up the wall
posts. A single solid subfloor closes the shallow board joints above the
checkerboard collision floor. Standard library only, byte reproducible.
"""
import math
import sys

import generate_wood_floor as g

WHOLE_NAME = "Wood_Floor_Whole.glb"
H = g.MODULE + g.INNER_R


def rounded_square_halfplanes():
    """Tangent half-planes of the rounded-square interior wall boundary."""
    hp = []
    corners = ((6.4, 6.4, 0.0), (6.4, -6.4, -math.pi / 2),
               (-6.4, -6.4, math.pi), (-6.4, 6.4, math.pi / 2))
    for cx, cz, a0 in corners:
        for i in range(g.ARC_STEPS + 1):
            t = a0 + (math.pi / 2) * i / g.ARC_STEPS
            a, b = math.cos(t), math.sin(t)
            hp.append((a, b, g.INNER_R + a * cx + b * cz))
    return hp


def polygon_halfplanes(poly):
    """Return a*x+b*z<=c half-planes for a CCW convex polygon."""
    p = g.ccw(poly)
    hp = []
    for i, (x0, z0) in enumerate(p):
        x1, z1 = p[(i + 1) % len(p)]
        dx, dz = x1 - x0, z1 - z0
        length = math.hypot(dx, dz)
        if length < 1e-9:
            continue
        a, b = dz / length, -dx / length
        hp.append((a, b, a * x0 + b * z0))
    return hp


def outer_boundary():
    return g.ccw(g.clip_all(g.rect(-H, -H, H, H), rounded_square_halfplanes()))


def whole_grid():
    """Equal row boundaries across the room."""
    return g.block_grid(-H, H, g.PLANK_WIDTH)


def row_seams(row):
    return g.staggered_seams(-H, H, g.PLANK_LENGTH, bool(row % 2))


_BLOCKS = None


def whole_blocks():
    """{(row, column): clipped board footprint}, cached, no GLB needed."""
    global _BLOCKS
    if _BLOCKS is not None:
        return _BLOCKS
    zs = whole_grid()
    inner = g.inset_outline(outer_boundary(), g.FRAME_WIDTH)
    hps = polygon_halfplanes(inner)
    blocks = {}
    for row in range(len(zs) - 1):
        xs = row_seams(row)
        for col in range(len(xs) - 1):
            poly = g.clean(g.clip_all(g.rect(xs[col], zs[row], xs[col + 1], zs[row + 1]), hps))
            if poly and g.area(poly) >= g.MIN_AREA:
                blocks[(row, col)] = poly
    _BLOCKS = blocks
    return blocks


def add_perimeter_frame(tris, outer, inner):
    """Warm-oak continuous frame ring; shares its inner boundary with boards."""
    if len(outer) != len(inner):
        raise ValueError("perimeter frame outlines must have matching vertices")
    ring = {g.MAT: []}
    outer, inner = g.ccw(outer), g.ccw(inner)
    for i in range(len(outer)):
        j = (i + 1) % len(outer)
        a = (outer[i][0], g.TOP_Y, outer[i][1])
        b = (outer[j][0], g.TOP_Y, outer[j][1])
        c = (inner[j][0], g.TOP_Y, inner[j][1])
        d = (inner[i][0], g.TOP_Y, inner[i][1])
        g.add_tri(ring, a, b, c, (0.0, 1.0, 0.0))
        g.add_tri(ring, a, c, d, (0.0, 1.0, 0.0))
    tris[g.FRAME_MAT].extend(ring[g.MAT])


def build_whole_floor():
    outer = outer_boundary()
    inner = g.inset_outline(outer, g.FRAME_WIDTH)
    inner_hps = polygon_halfplanes(inner)
    tris = g.empty_tris()
    g.add_subfloor(tris, outer)
    add_perimeter_frame(tris, outer, inner)
    zs = whole_grid()
    blocks = {}
    for row in range(len(zs) - 1):
        xs = row_seams(row)
        for col in range(len(xs) - 1):
            poly = g.clean(g.clip_all(g.rect(xs[col], zs[row], xs[col + 1], zs[row + 1]), inner_hps))
            if not poly or g.area(poly) < g.MIN_AREA:
                continue
            blocks[(row, col)] = poly
            g.add_block(tris, poly, g.seed_for(99, row, col),
                        g.tone_for(99, row, col))
    return tris, blocks


def whole_meta(blocks):
    return {
        "board_count": len(blocks),
        "board_width": round(g.PLANK_WIDTH, 6),
        "board_length": round(g.PLANK_LENGTH, 6),
        "frame_width": round(g.FRAME_WIDTH, 6),
        "grid": [len(row_seams(0)) - 1, len(whole_grid()) - 1],
        "continuous": True,
        "staggered_joints": True,
        "perimeter_frame": True,
        "frame_material": g.FRAME_MAT,
    }


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
    print("%s: %s bytes, %d triangles, %d boards, %.4f x %.4f m, one mesh"
          % (WHOLE_NAME, format(size, ","), count, len(blocks), 2 * H, 2 * H))


if __name__ == "__main__":
    main()

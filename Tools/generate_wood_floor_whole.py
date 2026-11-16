#!/usr/bin/env python3
"""Build a warm basket-weave parquet floor for the first-floor ring.

    python Tools/generate_wood_floor_whole.py            # regenerate all 4 GLBs
    python Tools/generate_wood_floor_whole.py --layout  # print placement

The room is filled with square parquet panels. Each panel contains two short
boards, and neighboring panels alternate their direction for a woven pattern.
A warm oak perimeter band echoes the wall posts. The floor remains one mesh,
clipped to the rounded-square room, with a closed subfloor above the collider.
Standard library only, byte reproducible.
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
    """Equal square-panel boundaries across the rounded room's bounding box."""
    return g.block_grid(-H, H, g.PANEL_SIZE)


def panel_parts(row, col):
    """Two board rectangles and their grain axes for one woven square panel."""
    seams = whole_grid()
    x0, x1 = seams[col], seams[col + 1]
    z0, z1 = seams[row], seams[row + 1]
    if (row + col) % 2 == 0:
        mid = (z0 + z1) * 0.5
        return ((x0, x1, z0, mid, 0.0), (x0, x1, mid, z1, 0.0))
    mid = (x0 + x1) * 0.5
    return ((x0, mid, z0, z1, math.pi / 2), (mid, x1, z0, z1, math.pi / 2))


_BLOCKS = None


def whole_blocks():
    """{(row, column, half): clipped board footprint}, cached, no GLB needed."""
    global _BLOCKS
    if _BLOCKS is not None:
        return _BLOCKS
    seams = whole_grid()
    inner = g.inset_outline(outer_boundary(), g.FRAME_WIDTH)
    hps = polygon_halfplanes(inner)
    blocks = {}
    for row in range(len(seams) - 1):
        for col in range(len(seams) - 1):
            for part, (x0, x1, z0, z1, _direction) in enumerate(panel_parts(row, col)):
                poly = g.clean(g.clip_all(g.rect(x0, z0, x1, z1), hps))
                if poly and g.area(poly) >= g.MIN_AREA:
                    blocks[(row, col, part)] = poly
    _BLOCKS = blocks
    return blocks


def add_perimeter_frame(tris, outer, inner):
    """Warm-oak continuous frame ring; shares its inner boundary with parquet."""
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
    seams = whole_grid()
    blocks = {}
    for row in range(len(seams) - 1):
        for col in range(len(seams) - 1):
            tone = g.tone_for(99, row, col)
            for part, (x0, x1, z0, z1, direction) in enumerate(panel_parts(row, col)):
                poly = g.clean(g.clip_all(g.rect(x0, z0, x1, z1), inner_hps))
                if not poly or g.area(poly) < g.MIN_AREA:
                    continue
                blocks[(row, col, part)] = poly
                seed = g.seed_for(99 + part, row, col)
                g.add_block(tris, poly, seed, tone, direction)
    return tris, blocks


def whole_meta(blocks):
    panels_per_axis = len(whole_grid()) - 1
    return {
        "board_count": len(blocks),
        "panel_count": panels_per_axis * panels_per_axis,
        "panel_size": round(g.PANEL_SIZE, 6),
        "board_width": round(g.PLANK_WIDTH, 6),
        "board_length": round(g.PLANK_LENGTH, 6),
        "frame_width": round(g.FRAME_WIDTH, 6),
        "grid": [panels_per_axis, panels_per_axis],
        "style": "warm basket-weave square parquet",
        "continuous": True,
        "staggered_joints": False,
        "basket_weave": True,
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
    print("%s: %s bytes, %d triangles, %d parquet boards, %.4f x %.4f m, one mesh"
          % (WHOLE_NAME, format(size, ","), count, len(blocks), 2 * H, 2 * H))


if __name__ == "__main__":
    main()

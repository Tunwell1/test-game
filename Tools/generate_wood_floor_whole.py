#!/usr/bin/env python3
"""Generate seven mirrored, controlled-chaos wood floor candidates.

    python Tools/generate_wood_floor_whole.py            # regenerate all floors
    python Tools/generate_wood_floor_whole.py --layout  # print main placement

Each candidate is a warm wooden patchwork: irregular rectangular boards are
randomly subdivided inside one quadrant, then mirrored into the other three.
This keeps the room perfectly balanced while the varied board sizes and grain
axes add a little organic chaos. All variants share a warm-oak perimeter band
and a continuous subfloor above the collision floor. Standard library only.
"""
import math
import random
import sys

import generate_wood_floor as g

WHOLE_NAME = "Wood_Floor_Whole.glb"
VARIANT_NAMES = [WHOLE_NAME] + ["Wood_Floor_Variant_%02d.glb" % i for i in range(2, 8)]
H = g.MODULE + g.INNER_R

# Each seed gives a different mirrored cut pattern. The size cap and split
# chance alter the visual rhythm, not the symmetry or material palette.
VARIANT_SPECS = (
    (41, 2.45, 0.16),
    (83, 2.05, 0.24),
    (127, 2.70, 0.28),
    (191, 1.90, 0.13),
    (239, 2.35, 0.34),
    (307, 2.10, 0.30),
    (383, 2.60, 0.20),
)
MIN_TILE = 0.62


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


def inner_boundary():
    return g.inset_outline(outer_boundary(), g.FRAME_WIDTH)


def quadrant_tiles(seed, max_size, split_chance):
    """Deterministic guillotine mosaic in +X/+Z; mirrored at build time."""
    rng = random.Random(seed)
    pending = [(0.0, H, 0.0, H, 0)]
    tiles = []
    while pending:
        x0, x1, z0, z1, depth = pending.pop()
        width, height = x1 - x0, z1 - z0
        can_x = width >= MIN_TILE * 2.0
        can_z = height >= MIN_TILE * 2.0
        too_large = max(width, height) > max_size
        if depth < 12 and (too_large or (rng.random() < split_chance and (can_x or can_z))):
            if can_x and can_z:
                if width > max_size and height <= max_size:
                    axis = 0
                elif height > max_size and width <= max_size:
                    axis = 1
                elif abs(width - height) > 0.5:
                    axis = 0 if width > height else 1
                else:
                    axis = rng.randrange(2)
            elif can_x:
                axis = 0
            elif can_z:
                axis = 1
            else:
                axis = -1
            if axis == 0:
                low, high = x0 + MIN_TILE, x1 - MIN_TILE
                if low < high:
                    cut = low + (high - low) * rng.uniform(0.32, 0.68)
                    pending.extend(((x0, cut, z0, z1, depth + 1),
                                    (cut, x1, z0, z1, depth + 1)))
                    continue
            elif axis == 1:
                low, high = z0 + MIN_TILE, z1 - MIN_TILE
                if low < high:
                    cut = low + (high - low) * rng.uniform(0.32, 0.68)
                    pending.extend(((x0, x1, z0, cut, depth + 1),
                                    (x0, x1, cut, z1, depth + 1)))
                    continue
        tiles.append((x0, x1, z0, z1))
    return tiles


def mirrored_tiles(variant):
    """Yield a four-way symmetric tiling, including tile ids and signs."""
    seed, max_size, split_chance = VARIANT_SPECS[variant]
    for tile_id, (x0, x1, z0, z1) in enumerate(quadrant_tiles(seed, max_size, split_chance)):
        # A tile's grain follows its longer axis, with occasional cross-grain
        # pieces for an intentionally hand-laid, non-uniform parquet character.
        rng = random.Random(seed * 101 + tile_id * 17)
        along_x = (x1 - x0) >= (z1 - z0)
        if rng.random() < 0.22:
            along_x = not along_x
        direction = 0.0 if along_x else math.pi / 2.0
        material = g.tone_for(seed, tile_id, 7)
        for sx, sz in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
            xa, xb = (x0, x1) if sx > 0 else (-x1, -x0)
            za, zb = (z0, z1) if sz > 0 else (-z1, -z0)
            yield (tile_id, sx, sz), (xa, xb, za, zb), direction, material, seed


def whole_blocks(variant=0):
    """{(tile_id, x-sign, z-sign): clipped board footprint}."""
    hps = polygon_halfplanes(inner_boundary())
    blocks = {}
    for key, (x0, x1, z0, z1), _direction, _material, _seed in mirrored_tiles(variant):
        poly = g.clean(g.clip_all(g.rect(x0, z0, x1, z1), hps))
        if poly and g.area(poly) >= g.MIN_AREA:
            blocks[key] = poly
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


def build_whole_floor(variant=0):
    outer = outer_boundary()
    inner = g.inset_outline(outer, g.FRAME_WIDTH)
    hps = polygon_halfplanes(inner)
    tris = g.empty_tris()
    g.add_subfloor(tris, outer)
    add_perimeter_frame(tris, outer, inner)
    blocks = {}
    for key, (x0, x1, z0, z1), direction, material, seed in mirrored_tiles(variant):
        poly = g.clean(g.clip_all(g.rect(x0, z0, x1, z1), hps))
        if not poly or g.area(poly) < g.MIN_AREA:
            continue
        blocks[key] = poly
        tile_id, _sx, _sz = key
        # Reflected copies share the same grain seed as well as the same tone.
        board_seed = g.seed_for(seed + variant * 997, tile_id, 0)
        g.add_block(tris, poly, board_seed, material, direction)
    return tris, blocks


def whole_meta(blocks, variant=0):
    seed, max_size, split_chance = VARIANT_SPECS[variant]
    return {
        "variant": variant + 1,
        "variant_seed": seed,
        "tile_count": len(blocks),
        "max_tile_size": max_size,
        "split_chance": split_chance,
        "frame_width": round(g.FRAME_WIDTH, 6),
        "symmetry": "four-way mirrored",
        "controlled_chaos": True,
        "perimeter_frame": True,
        "frame_material": g.FRAME_MAT,
        "continuous": True,
        "style": "mirrored warm-oak patchwork",
    }


def whole_layout():
    return [("floor_whole", WHOLE_NAME, 0, 0.0, 0.0)]


def main():
    if "--layout" in sys.argv:
        for name, asset, rot, x, z in whole_layout():
            print("%-24s %-24s rot=%3d  x=%9.4f z=%9.4f" % (name, asset, rot, x, z))
        return
    g.main()
    for variant, name in enumerate(VARIANT_NAMES):
        tris, blocks = build_whole_floor(variant)
        size, count = g.write_glb(g.OUT_DIR / name, tris, name[:-4],
                                  2 * H, 2 * H, False, whole_meta(blocks, variant))
        print("%s: %s bytes, %d triangles, %d mirrored pieces"
              % (name, format(size, ","), count, len(blocks)))


if __name__ == "__main__":
    main()

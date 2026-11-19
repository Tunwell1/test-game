#!/usr/bin/env python3
"""Checks render sharpness settings: AA, tight glow, crisp particle sprites.

    python tests/test_render_sharpness.py -v
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "project.godot"
SCENE = ROOT / "main.tscn"
PROJECTILE = ROOT / "spell_projectile.gd"


class RenderSharpnessTests(unittest.TestCase):
    def test_antialiasing_and_anisotropy_enabled(self):
        text = PROJECT.read_text(encoding="utf-8")
        self.assertIn("anti_aliasing/quality/msaa_3d=3", text)
        self.assertIn("anti_aliasing/quality/fxaa=false", text)
        self.assertIn("textures/default_filters/anisotropic_filtering_level=4", text)

    def test_glow_is_disabled(self):
        text = SCENE.read_text(encoding="utf-8")
        self.assertIn("glow_enabled = false", text)
        self.assertNotIn("glow_levels/1", text)

    def test_particle_sprites_are_hard_geometric_shapes(self):
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("var size := 128", text)
        self.assertIn("1.0 - smoothstep(-edge, edge, sdf)", text)
        self.assertIn("mat.alpha_scissor_threshold = 0.5", text)
        self.assertNotIn("BLEND_MODE_ADD", text)
        self.assertIn("particles.draw_passes = 1", text)
        self.assertNotIn("draw_pass_2", text)

    def test_decals_are_high_res(self):
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("var size := 256", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)

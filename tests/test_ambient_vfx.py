#!/usr/bin/env python3
"""Dependency-free checks for the small ambient effects on the player.

    python tests/test_ambient_vfx.py -v
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLAYER = ROOT / "player.gd"
SMOKE = ROOT / "tests" / "smoke_gameplay.gd"


class AmbientVfxTests(unittest.TestCase):
    def test_player_has_tunable_exports(self):
        text = PLAYER.read_text(encoding="utf-8")
        self.assertIn('@export_group("Атмосфера")', text)
        for name in ("warm_light_enabled", "warm_light_color", "warm_light_energy",
                     "warm_light_range", "dust_enabled", "dust_amount"):
            self.assertRegex(text, r"@export(?:_range\([^)]*\))? var %s\b" % name)

    def test_warm_light_is_shadowless_and_flickers(self):
        text = PLAYER.read_text(encoding="utf-8")
        self.assertIn('var light := OmniLight3D.new()', text)
        self.assertIn('light.name = "WarmLight"', text)
        self.assertIn("light.shadow_enabled = false", text)
        self.assertIn("head.add_child(light)", text)
        self.assertIn("func _process(delta: float) -> void:", text)
        self.assertIn("_warm_light.light_energy = warm_light_energy * flicker", text)

    def test_dust_is_generated_without_assets(self):
        text = PLAYER.read_text(encoding="utf-8")
        self.assertIn('var particles := GPUParticles3D.new()', text)
        self.assertIn('particles.name = "DustMotes"', text)
        self.assertIn("particles.preprocess = 8.0", text)
        self.assertIn("particles.local_coords = false", text)
        self.assertIn("camera.add_child(particles)", text)
        self.assertIn("func _dust_dot_texture() -> ImageTexture:", text)
        self.assertIn("ImageTexture.create_from_image(img)", text)
        self.assertIn("material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED", text)

    def test_smoke_checks_both_effects(self):
        text = SMOKE.read_text(encoding="utf-8")
        self.assertIn("_ambient_vfx_ready(player)", text)
        self.assertIn('find_child("WarmLight", true, false) as OmniLight3D', text)
        self.assertIn('find_child("DustMotes", true, false) as GPUParticles3D', text)


if __name__ == "__main__":
    unittest.main(verbosity=2)

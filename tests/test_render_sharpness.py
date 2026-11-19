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

    def test_glow_is_narrow_and_hdr_only(self):
        # Свечение включено только для HDR-ядра магии: узкие уровни, без bloom,
        # порог 1.0 — стены и шахматный пол остаются матовыми и чёткими.
        text = SCENE.read_text(encoding="utf-8")
        self.assertIn("glow_enabled = true", text)
        self.assertIn("glow_bloom = 0.0", text)
        self.assertIn("glow_hdr_threshold = 1.0", text)
        # Широкие уровни (1–3) дают мыло на стенах — их быть не должно.
        self.assertNotIn("glow_levels/1", text)
        self.assertNotIn("glow_levels/2", text)
        self.assertNotIn("glow_levels/3", text)

    def test_glow_stays_off_wide_levels_and_bloom(self):
        text = SCENE.read_text(encoding="utf-8")
        self.assertIn("glow_levels/4 = 1.0", text)
        self.assertIn("glow_levels/5 = 0.45", text)
        self.assertIn("glow_intensity = 0.55", text)

    def test_only_fire_particles_glow(self):
        # Светится только огонь. Вода, ветер и камень — материя: если они
        # складываются со светом (BLEND_MODE_ADD), эффект читается как sci-fi.
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn('const ENERGY_PARTICLES := ["spark"]', text)
        self.assertIn("mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR", text)
        self.assertIn("mat.alpha_scissor_threshold = 0.5", text)
        self.assertIn("mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD", text)
        # Ветка аддитивности заканчивается на огне: капли, полосы и осколки
        # обрабатываются только в ветке освещённой материи.
        fire_branch = text.split("if ENERGY_PARTICLES.has(kind):", 1)[1].split(
            "match kind:", 1)[0]
        self.assertNotIn('"droplet"', fire_branch)
        self.assertNotIn('"streak"', fire_branch)
        self.assertNotIn('"shard"', fire_branch)

    def test_matter_particles_are_lit_and_matte(self):
        # Материя освещается сценой и не имеет эмиссии.
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX", text)
        self.assertIn("mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL", text)
        self.assertIn("static func _soft_dot_texture() -> ImageTexture:", text)
        self.assertIn("mat.albedo_texture = _soft_dot_texture()", text)

    def test_only_fire_emits_light(self):
        # Ни снаряд, ни удар не излучают свет, кроме огня.
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn('func _emits_light() -> bool:', text)
        self.assertIn('return visual == "fire" or visual == "lava"', text)
        self.assertIn('var impact_light := visual == "fire"', text)
        self.assertIn("if flash != null:", text)
        # В configure свет создаётся только через проверку _emits_light().
        self.assertIn("if _emits_light():", text)

    def test_particle_sprites_keep_geometric_silhouettes(self):
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("var size := 128", text)
        self.assertIn("1.0 - smoothstep(-edge, edge, sdf)", text)
        self.assertIn("particles.draw_passes = 1", text)
        self.assertNotIn("draw_pass_2", text)

    def test_contact_shadows_enabled(self):
        # Без SSAO магия «висит» над полом: контактных теней нет вообще.
        text = SCENE.read_text(encoding="utf-8")
        self.assertIn("ssao_enabled = true", text)
        self.assertIn("ssao_radius = 1.2", text)

    def test_decals_are_high_res(self):
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("var size := 256", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)

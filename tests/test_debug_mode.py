#!/usr/bin/env python3
"""Checks the F3 slow-motion and spell-speed debug mode.

    python tests/test_debug_mode.py -v
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HUD = ROOT / "hud.gd"
CASTER = ROOT / "spell_caster.gd"
SMOKE = ROOT / "tests" / "smoke_gameplay.gd"


class DebugModeTests(unittest.TestCase):
    def test_caster_exposes_speed_multiplier(self):
        text = CASTER.read_text(encoding="utf-8")
        self.assertIn("var speed_multiplier: float = 1.0", text)
        self.assertIn("proj.speed = data[\"speed\"] * speed_multiplier", text)

    def test_hud_defines_free_ranges_and_defaults(self):
        """Ограничений-списков нет: значения свободные, шаг фиксированный."""
        text = HUD.read_text(encoding="utf-8")
        self.assertIn("const TIME_STEP := 0.05", text)
        self.assertIn("const MAGIC_STEP := 0.05", text)
        self.assertIn("const TIME_MIN := 0.01", text)
        # По умолчанию в F3: время 1, магия 0.1.
        self.assertIn("const TIME_DEFAULT := 1.0", text)
        self.assertIn("const MAGIC_DEFAULT := 0.1", text)
        self.assertIn("var _time_scale := TIME_DEFAULT", text)
        self.assertIn("var _magic_speed := MAGIC_DEFAULT", text)
        # Старые жёсткие индексы в списках больше не управляют значениями.
        self.assertNotIn("var _time_scale_index", text)
        self.assertNotIn("var _magic_speed_index", text)
        self.assertNotIn("clampi(_time_scale_index", text)

    def test_debug_values_are_clamped_not_listed(self):
        text = HUD.read_text(encoding="utf-8")
        self.assertIn("_time_scale = clampf(_time_scale, TIME_MIN, 16.0)", text)
        self.assertIn("_magic_speed = clampf(_magic_speed, MAGIC_MIN, 16.0)", text)
        # Shift даёт ступени из списка, без Shift — мелкий шаг.
        self.assertIn("var coarse := key.shift_pressed", text)
        self.assertIn("_step(_time_scale, TIME_STEP, TIME_SCALES, coarse, false)", text)
        self.assertIn("_step(_magic_speed, MAGIC_STEP, MAGIC_SPEEDS, coarse, true)", text)
        # Ступени не потолок: если дальше ступени нет, шагаем по step.
        self.assertIn("if is_equal_approx(snapped, from):", text)

    def test_hud_handles_debug_hotkeys(self):
        text = HUD.read_text(encoding="utf-8")
        self.assertIn("func _unhandled_input(event: InputEvent) -> void:", text)
        for key in ("KEY_F3", "KEY_MINUS", "KEY_EQUAL",
                    "KEY_BRACKETLEFT", "KEY_BRACKETRIGHT"):
            self.assertIn(key, text)
        self.assertIn("func _apply_debug_settings() -> void:", text)
        self.assertIn("Engine.time_scale = maxf(_time_scale, TIME_MIN)", text)
        self.assertIn("player.spell_caster.speed_multiplier = _magic_speed", text)
        self.assertIn("Engine.time_scale = 1.0", text)

    def test_hud_draws_debug_readout(self):
        text = HUD.read_text(encoding="utf-8")
        self.assertIn("func _draw_debug(s: Vector2) -> void:", text)
        self.assertIn("РЕЖИМ ПРОСМОТРА", text)
        self.assertIn("%.0f → %.0f м/с", text)
        self.assertIn("if _debug_visible:", text)
        self.assertIn("_draw_debug(s)", text)

    def test_smoke_checks_debug_controls(self):
        text = SMOKE.read_text(encoding="utf-8")
        self.assertIn("slow motion and spell speed debug controls", text)
        self.assertIn("func _debug_controls_work(", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Checks for the shared reference-inspired interface style.

    python tests/test_ui_style_thin.py -v
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
THEME = ROOT / "ui_theme.gd"
HUD = ROOT / "hud.gd"
PAUSE = ROOT / "pause_menu.gd"


class ReferenceStyleTests(unittest.TestCase):
    def test_palette(self):
        text = THEME.read_text(encoding="utf-8")
        self.assertIn("const GOLD := Color(0.824, 0.667, 0.388)", text)
        self.assertIn("const MUTED := Color(0.557, 0.580, 0.635)", text)
        self.assertIn("const PARCHMENT := Color(0.914, 0.898, 0.855)", text)
        self.assertIn("const BORDER := Color(GOLD.r, GOLD.g, GOLD.b, 0.30)", text)

    def test_controls_use_sharp_one_pixel_borders(self):
        text = THEME.read_text(encoding="utf-8")
        self.assertIn("BORDER, 0, 1, 18, 11", text)
        self.assertIn('t.set_stylebox("panel", "PanelContainer", box(BG_SOLID, BORDER, 0, 1, 26, 22))',
                      text)
        self.assertNotIn("BORDER, 6, 1, 18, 11", text)

    def test_theme_has_shared_reference_helpers(self):
        text = THEME.read_text(encoding="utf-8")
        self.assertIn("static func draw_reference_panel(ci: CanvasItem, rect: Rect2, tint: Color,",
                      text)
        self.assertIn("static func draw_crest(ci: CanvasItem, center: Vector2, tint: Color,", text)
        self.assertIn("static func draw_sparkles(ci: CanvasItem, rect: Rect2, time: float,", text)
        self.assertIn("var inner := rect.grow(-inset)", text)

    def test_hud_is_free_of_heavy_effects(self):
        text = HUD.read_text(encoding="utf-8")
        for forbidden in ("UiTheme.draw_frame(", "UiTheme.draw_glow(", "_scrim",
                          "_grad_cache", "_bar_gradient", "pulse_low",
                          "UiTheme.draw_diamond(hud_canvas, tip",
                          "UiTheme.draw_arcane_ring("):
            self.assertNotIn(forbidden, text)

    def test_bars_are_wide_and_graphic(self):
        text = HUD.read_text(encoding="utf-8")
        self.assertIn("const MARGIN := 44.0", text)
        self.assertIn("const BAR_WIDTH := 260.0", text)
        self.assertIn("Rect2(left, Vector2(fill_w, 5.0))", text)
        self.assertIn("Color(tint.r, tint.g, tint.b, 0.92 * alpha)", text)
        self.assertIn("Color(1, 1, 1, 0.35 * alpha)", text)

    def test_labels_are_sharp(self):
        text = HUD.read_text(encoding="utf-8")
        self.assertIn("title, 9, title_color, 0.0", text)
        self.assertIn("value_text, 15, value_color, 0.0", text)

    def test_spell_slot_is_frameless(self):
        text = HUD.read_text(encoding="utf-8")
        self.assertIn("Vector2(268.0, 76.0)", text)
        self.assertIn("var tx := rect.position.x + 95.0", text)
        self.assertNotIn("UiTheme.draw_reference_panel(hud_canvas", text)
        self.assertNotIn("var div_x :=", text)
        self.assertNotIn("_draw_edge_arms(", text)
        self.assertNotIn("func _draw_edge_arms", text)
        self.assertIn("var name_size := 19", text)

    def test_school_and_death_use_shared_panel(self):
        text = HUD.read_text(encoding="utf-8")
        self.assertIn("UiTheme.draw_reference_panel(school_screen, panel, UiTheme.GOLD, a, 14.0)",
                      text)
        self.assertIn("UiTheme.draw_reference_panel(school_screen, rect, tint,\n"
                      "\t\t\tminf(1.0, 0.72 * card_a + (0.18 if hovered else 0.0)), 7.0)",
                      text)
        self.assertIn("UiTheme.draw_reference_panel(death_screen, panel, UiTheme.BLOOD, a, 12.0)",
                      text)
        self.assertIn("UiTheme.draw_crest(school_screen,", text)
        self.assertIn("UiTheme.draw_crest(death_screen,", text)
        self.assertIn("UiTheme.draw_sparkles(school_screen,", text)
        self.assertIn("UiTheme.draw_sparkles(death_screen,", text)

    def test_school_choice_accepts_mouse(self):
        text = HUD.read_text(encoding="utf-8")
        self.assertIn("school_screen.mouse_filter = Control.MOUSE_FILTER_STOP", text)
        self.assertIn("school_screen.gui_input.connect(_on_school_gui_input)", text)
        self.assertIn("func _on_school_gui_input(", text)
        self.assertIn("InputEventMouseButton", text)
        self.assertIn("MOUSE_BUTTON_LEFT", text)
        self.assertIn("player.magic_book.choose_primary(MagicBook.BASE_SCHOOLS[index])", text)
        self.assertIn("_school_card_rects.append(rect)", text)
        self.assertIn("Input.CURSOR_POINTING_HAND", text)

    def test_pause_menu_is_centered(self):
        text = PAUSE.read_text(encoding="utf-8")
        self.assertIn("const PANEL_W := 420.0", text)
        self.assertIn("const PANEL_H := 420.0", text)
        self.assertIn("main_group.set_anchors_preset(Control.PRESET_CENTER)", text)
        self.assertNotIn("const MARGIN := 110.0", text)

    def test_pause_menu_uses_shared_panel_and_underlines(self):
        text = PAUSE.read_text(encoding="utf-8")
        self.assertIn("UiTheme.draw_reference_panel(root, panel, UiTheme.GOLD, a)", text)
        self.assertIn("UiTheme.draw_crest(root, Vector2(panel.position.x + panel.size.x * 0.5,",
                      text)
        self.assertIn("UiTheme.draw_sparkles(root, panel, _time, UiTheme.GOLD, a)", text)
        self.assertIn("button.draw.connect(_draw_menu_button.bind", text)
        self.assertIn("var underline := UiTheme.fade(UiTheme.GOLD,", text)
        self.assertIn("button.draw_colored_polygon(pts", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)

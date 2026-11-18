#!/usr/bin/env python3
"""Dependency-free checks for the first-person camera rig.

    python tests/test_first_person_camera.py -v
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLAYER_TSCN = ROOT / "player.tscn"
PLAYER_GD = ROOT / "player.gd"
SMOKE = ROOT / "tests" / "smoke_gameplay.gd"


class FirstPersonCameraTests(unittest.TestCase):
    def test_scene_has_no_spring_arm(self):
        text = PLAYER_TSCN.read_text(encoding="utf-8")
        self.assertNotIn("SpringArm3D", text)
        self.assertNotIn("spring_length", text)
        self.assertIn('[node name="Camera3D" type="Camera3D" parent="Head"]', text)
        self.assertIn('[node name="InteractRay" type="RayCast3D" parent="Head/Camera3D"]', text)

    def test_script_has_no_boom_references(self):
        text = PLAYER_GD.read_text(encoding="utf-8")
        for forbidden in ("camera_boom", "SpringArm3D", "spring_length", "add_excluded_object"):
            self.assertNotIn(forbidden, text)
        self.assertIn('@onready var camera: Camera3D = $Head/Camera3D', text)
        self.assertIn("@onready var interact_ray: RayCast3D = $Head/Camera3D/InteractRay", text)
        self.assertIn("var bob_node: Node3D = camera", text)

    def test_smoke_checks_camera_rig(self):
        text = SMOKE.read_text(encoding="utf-8")
        self.assertIn("_first_person_camera_ready(player)", text)
        self.assertIn('player.find_children("*", "SpringArm3D", true, false)', text)


if __name__ == "__main__":
    unittest.main(verbosity=2)

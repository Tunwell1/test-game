"""Статические проверки GDScript, которые не требуют установленного Godot.

Раунд 5 начался с рантайм-ошибки «Could not resolve external class member
"acquire"»: скрипт не парсился, и весь `class_name SpellPool` пропадал, но ни
один тест этого не поймал. Здесь эти проверки закрепляются как тесты, чтобы
такой класс ошибок больше не доходил до сборки руками.
"""
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "Tools"


class GdScriptStatic(unittest.TestCase):
    def _run(self, *args):
        return subprocess.run(args, cwd=ROOT, capture_output=True, text=True)

    def test_symbols_and_string_calls_resolve(self):
        """Все Class.member, obj.member и call("имя") указывают на реальный код."""
        result = self._run(sys.executable, str(TOOLS / "check_gdscript_symbols.py"))
        self.assertEqual(result.returncode, 0,
                         "неразрешённые члены:\n" + result.stdout + result.stderr)

    @unittest.skipUnless(
        shutil.which("gdparse") or Path("/tmp/v1/bin/gdparse").exists(),
        "gdparse (pip install gdtoolkit) недоступен — синтаксис не проверяется")
    def test_every_script_parses(self):
        """Каждый .gd разбирается парсером GDScript, а не «выглядит нормально»."""
        gdparse = shutil.which("gdparse") or "/tmp/v1/bin/gdparse"
        scripts = sorted(ROOT.glob("*.gd")) + sorted((ROOT / "tests").glob("*.gd"))
        self.assertTrue(scripts, "не найдено ни одного .gd")
        broken = []
        for path in scripts:
            result = self._run(gdparse, str(path))
            if result.stdout.strip() or result.stderr.strip():
                broken.append("%s:\n%s%s" % (path.relative_to(ROOT),
                                             result.stdout, result.stderr))
        self.assertEqual(broken, [], "ошибки синтаксиса:\n" + "\n".join(broken))

    def test_checker_catches_renamed_member(self):
        """Сам чекер обязан падать, если метод переименован: проверка проверки."""
        target = ROOT / "spell_pool.gd"
        original = target.read_text(encoding="utf-8")
        broken = original.replace("func release(", "func release_renamed(")
        self.assertNotEqual(original, broken, "в spell_pool.gd нет func release(")
        try:
            target.write_text(broken, encoding="utf-8")
            result = self._run(sys.executable,
                               str(TOOLS / "check_gdscript_symbols.py"))
            self.assertEqual(result.returncode, 1,
                             "чекер не увидел переименованный release()")
            self.assertIn("release", result.stdout)
        finally:
            target.write_text(original, encoding="utf-8")

    def test_shader_macros_declared(self):
        """Godot 4 не знает SCREEN_TEXTURE без uniform с hint_screen_texture."""
        for path in ROOT.glob("*.gd"):
            text = path.read_text(encoding="utf-8")
            if "texture(SCREEN_TEXTURE" in text:
                self.assertIn("hint_screen_texture", text,
                              f"{path.name}: SCREEN_TEXTURE без uniform")


if __name__ == "__main__":
    unittest.main()

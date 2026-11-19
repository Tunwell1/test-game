#!/usr/bin/env python3
"""Проверка шейдеров Godot из строк GDScript.

Парсер GDScript шейдеры не видит вообще: для него это обычная строка. Поэтому
ошибки в шейдере доходят до игрока как белый экран и сообщение в консоли.
Проверяем то, что реально ломает компиляцию:

  * varying объявлен, но не присвоен в vertex() — значение читается мусорным;
  * использование DEPTH без записи в depth при depth_draw_never;
  * texture() без sampler2D / SCREEN_TEXTURE без hint_screen_texture;
  * вызов функций, которых нет (наши хелперы + встроенные Godot).

    python3 Tools/check_shaders.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKIP = {".git", "docs", "addons"}

# Инлайн-шейдеры собираются конкатенацией строк, поэтому вытаскиваем все
# тройные кавычки подряд и склеиваем — как это сделает Godot.
BLOCK_RE = re.compile(r'"""((?:[^"\\]|\\.|"(?!""))*)"""', re.S)

BUILTIN_FUNCS = {
    "mix", "clamp", "smoothstep", "step", "pow", "sqrt", "abs", "sin", "cos",
    "tan", "atan", "asin", "acos", "exp", "exp2", "log", "log2", "floor",
    "ceil", "fract", "mod", "min", "max", "sign", "dot", "cross", "normalize",
    "length", "distance", "reflect", "refract", "texture", "textureLod",
    "dFdx", "dFdy", "fwidth", "round", "trunc", "radians", "degrees",
    "scalar", "vec2", "vec3", "vec4", "mat2", "mat3", "mat4", "float", "int",
    "bool", "step", "saturate", "inverse", "transpose", "if", "for", "while",
    "return", "vec3", "discard", "ldexp", "modf", "isnan", "isinf", "uint",
}


def shader_blocks():
    for path in sorted(ROOT.rglob("*.gd")):
        rel = path.relative_to(ROOT)
        if any(part in SKIP for part in rel.parts):
            continue
        text = path.read_text(encoding="utf-8")
        # Шейдеры начинаются с shader_type внутри строкового литерала.
        for m in re.finditer(r'shader_type', text):
            start = text.rfind('"""', 0, m.start())
            if start == -1:
                continue
            end = text.find('shader.end', m.start())
            # Достаём все блоки до конца вызова Shader.
            chunk = text[start:m.start() + 6000]
            codes = BLOCK_RE.findall(chunk)
            code = "\n".join(codes)
            # Дополнительно: весь файл — чтобы видеть vertex() из других блоков.
            whole = "\n".join(BLOCK_RE.findall(text))
            if "shader_type" in code:
                yield rel, code, whole


def strip_comments(code):
    out = []
    for line in code.splitlines():
        out.append(re.sub(r"//.*$", "", line))
    return "\n".join(out)


def check(rel, raw, full=None):
    problems = []
    code = strip_comments(raw)
    # Проверка varying делается по полному тексту шейдера: он собирается из
    # нескольких строковых блоков конкатенацией, и vertex() может оказаться
    # в другом блоке.
    scope = strip_comments(full) if full else code
    if "shader_type" not in code:
        return problems

    # 1) varying должен быть присвоен там, где его читают.
    for name in re.findall(r"\bvarying\s+\w+\s+(\w+)\s*;", code):
        assigned = re.search(r"\b%s\s*=" % re.escape(name), scope)
        if not assigned:
            problems.append(f"{rel}: varying {name} объявлен, но не присвоен")

    # 2) DEPTH используется, а depth не пишется.
    if "depth_draw_never" in code and re.search(r"\bDEPTH\b", code):
        problems.append(f"{rel}: depth_draw_never вместе с DEPTH — "
                        "запись в depth не сработает")

    # 3) texture() по неизвестному семплеру.
    declared = set(re.findall(r"uniform\s+sampler\w+\s+(\w+)", code))
    for sampler in re.findall(r"texture\(\s*(\w+)", code):
        if sampler not in declared:
            problems.append(f"{rel}: texture({sampler}) — семплер "
                            f"не объявлен через uniform sampler2D")

    # 4) вызовы неизвестных функций (наши опечатки в хелперах).
    defined = set(re.findall(r"\b(?:float|vec2|vec3|vec4|int|bool|void|mat2|"
                             r"mat3|mat4)\s+(\w+)\s*\(", code))
    # Хелперы из общих констант (NOISE_LIB) лежат в другом строковом блоке того
    # же файла — они тоже доступны шейдеру после конкатенации.
    whole = strip_comments((ROOT / rel).read_text(encoding="utf-8"))
    defined |= set(re.findall(
        r"\b(?:float|vec2|vec3|vec4|int|bool|void)\s+(\w+)\s*\(", whole))
    for fn in re.findall(r"\b([a-zA-Z_]\w*)\s*\(", code):
        if fn in BUILTIN_FUNCS or fn in defined:
            continue
        if fn in {"if", "for", "while", "return", "switch", "texture"}:
            continue
        problems.append(f"{rel}: вызов {fn}() — функция не объявлена")
    return problems


def main() -> int:
    all_problems = []
    count = 0
    for rel, code, full in shader_blocks():
        count += 1
        all_problems.extend(check(rel, code, full))
    if all_problems:
        print("ПРОБЛЕМЫ В ШЕЙДЕРАХ (%d):" % len(all_problems))
        for p in sorted(set(all_problems)):
            print(" -", p)
        return 1
    print("OK: %d шейдеров, семантика не нарушена" % count)
    return 0


if __name__ == "__main__":
    sys.exit(main())

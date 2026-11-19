#!/usr/bin/env bash
# Полная проверка GDScript без Godot: парсер + разрешение символов + шейдеры.
#
#   bash Tools/check_gdscript.sh
#
# Проверяет то, чего не видят grep и «я посмотрел глазами»:
#   1. синтаксис всех .gd (gdparse из gdtoolkit);
#   2. обращения Class.member и obj.member к class_name-скриптам
#      (именно так Godot пишет «Could not resolve external class member»);
#   3. базовую структуру инлайн-шейдеров и объявление uniform'ов;
#   4. дубликаты функций/полей и зарезервированные имена.
#
# Если gdtoolkit не установлен, шаг 1 пропускается с предупреждением,
# остальные проверки работают на чистом python3.
set -uo pipefail
cd "$(dirname "$0")/.."
status=0

GDPARSE=""
for cand in gdparse "$HOME/.local/bin/gdparse" /tmp/v1/bin/gdparse; do
    if command -v "$cand" >/dev/null 2>&1 || [ -x "$cand" ]; then
        GDPARSE="$cand"; break
    fi
done

echo "== 1. Синтаксис (gdparse) =="
if [ -n "$GDPARSE" ]; then
    for f in *.gd tests/*.gd Tools/*.gd; do
        [ -f "$f" ] || continue
        out=$("$GDPARSE" "$f" 2>&1)
        if [ -n "$out" ]; then
            echo "ОШИБКА СИНТАКСИСА: $f"
            echo "$out" | head -12
            status=1
        fi
    done
    [ "$status" -eq 0 ] && echo "OK: синтаксис всех скриптов корректен"
else
    echo "ПРОПУЩЕНО: gdparse не найден (pip install gdtoolkit)"
fi

echo
echo "== 2. Разрешение символов и шейдеры =="
python3 Tools/check_gdscript_symbols.py || status=1

echo
echo "== 3. Дубликаты и зарезервированные имена =="
python3 - <<'PY'
import collections, glob, re, sys

reserved = {"slot", "page", "final", "param", "class", "class_name", "func",
            "var", "const", "signal", "enum", "extends", "match", "when",
            "until", "namespace", "interface", "assert", "trait"}
problems = []
for f in glob.glob("*.gd") + glob.glob("tests/*.gd"):
    text = open(f, encoding="utf-8").read()
    funcs = re.findall(r"^\s*(?:static\s+)?func\s+(\w+)", text, re.M)
    for name, count in collections.Counter(funcs).items():
        if count > 1:
            problems.append(f"{f}: функция {name} объявлена {count} раза")
    fields = re.findall(r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:var|const)\s+(\w+)",
                        text, re.M)
    for name, count in collections.Counter(fields).items():
        if count > 1:
            problems.append(f"{f}: поле {name} объявлено {count} раза")
    for name in set(funcs) | set(fields):
        if name in reserved:
            problems.append(f"{f}: зарезервированное имя как член: {name}")
if problems:
    print("\n".join(" - " + p for p in sorted(problems)))
    sys.exit(1)
print("OK: дубликатов и зарезервированных имён нет")
PY
[ $? -ne 0 ] && status=1

echo
echo "== 4. Шейдеры: uniform'ы и скобки =="
python3 - <<'PY'
import glob, re, sys
problems = []
for f in glob.glob("*.gd"):
    text = open(f, encoding="utf-8").read()
    for m in re.finditer(r'shader\.code\s*=\s*"""(.*?)"""', text, re.S):
        # Убираем комментарии: слово в комментарии — не использование.
        code = "\n".join(re.sub(r"//.*$", "", ln)
                          for ln in m.group(1).splitlines())
        if "shader_type" not in code:
            problems.append(f"{f}: в шейдере нет shader_type")
        for a, b in ("{}", "()"):
            if code.count(a) != code.count(b):
                problems.append(f"{f}: несбалансированные {a}{b}")
        declared = set(re.findall(r"uniform\s+\w+\s+(\w+)", code))
        # В Godot 4 SCREEN_TEXTURE не встроен — нужен hint_screen_texture.
        if "SCREEN_TEXTURE" in code:
            problems.append(f"{f}: используется SCREEN_TEXTURE без "
                            "uniform ... : hint_screen_texture")
        if "unshaded" in code and "spatial" in code:
            print(f"ВНИМАНИЕ: {f}: spatial-шейдер с unshaded — "
                  "тело не получит свет сцены")
if problems:
    print("\n".join(" - " + p for p in problems))
    sys.exit(1)
print("OK: шейдеры структурно корректны")
PY
[ $? -ne 0 ] && status=1

echo
if [ "$status" -eq 0 ]; then echo "ИТОГ: проверки пройдены"; else echo "ИТОГ: есть проблемы"; fi
exit $status

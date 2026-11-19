#!/usr/bin/env python3
"""Проверка, что обращения вида `Class.member` и `obj.member` разрешаются.

Godot в песочнице недоступен, но именно этот класс ошибок («Could not resolve
external class member X») ловится символическим разбором: собираем члены всех
class_name-скриптов и сверяем обращения к ним из других файлов.

    python3 Tools/check_gdscript_symbols.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKIP_DIRS = {"Tools", "tests", "docs", ".git"}

CLASS_RE = re.compile(r"^class_name\s+(\w+)", re.M)
EXTENDS_RE = re.compile(r"^extends\s+(\w+)", re.M)
FUNC_RE = re.compile(r"^\s*(?:static\s+)?func\s+(\w+)", re.M)
VAR_RE = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*var\s+(\w+)", re.M)
CONST_RE = re.compile(r"^\s*const\s+(\w+)", re.M)
SIGNAL_RE = re.compile(r"^\s*signal\s+(\w+)", re.M)
ENUM_RE = re.compile(r"^\s*enum\s+(\w+)", re.M)

# Встроенные классы, которые точно есть: их члены не проверяем.
BUILTIN = {
    "Node", "Node2D", "Node3D", "CanvasLayer", "Control", "ColorRect", "Area3D",
    "CharacterBody3D", "StaticBody3D", "RigidBody3D", "MeshInstance3D",
    "OmniLight3D", "DirectionalLight3D", "Camera3D", "CollisionShape3D",
    "RayCast3D", "ShapeCast3D", "AudioStreamPlayer3D", "GPUParticles3D",
    "Decal", "Label3D", "WorldEnvironment", "SceneTree", "RefCounted",
    "Resource", "Object", "Material", "StandardMaterial3D", "ShaderMaterial",
    "Shader", "Mesh", "ArrayMesh", "BoxMesh", "SphereMesh", "CapsuleMesh",
    "QuadMesh", "TorusMesh", "SurfaceTool", "ParticleProcessMaterial",
    "GradientTexture1D", "CurveTexture", "ImageTexture", "Image",
    "AudioStreamWAV", "InputEventKey", "InputEventJoypadButton",
    "InputEventJoypadMotion", "PhysicsRayQueryParameters3D",
    "ConfigFile", "Tween", "Timer", "Curve", "Gradient", "Font", "Vector2",
    "Vector3", "Color", "Basis", "Transform3D", "Quaternion", "AABB", "RID",
    "Dictionary", "Array", "String", "PackedByteArray", "PackedFloat32Array",
    "PackedColorArray", "PackedStringArray", "CollisionObject3D", "Environment",
    "ProceduralSkyMaterial", "Sky", "TorusShape3D", "SphereShape3D",
    "CapsuleShape3D", "BoxShape3D", "BoxMesh", "Input", "Engine", "OS",
    "PhysicsServer3D", "RandomNumberGenerator", "Theme", "StyleBoxFlat",
    "Label", "Button", "Panel", "VBoxContainer", "HBoxContainer", "MarginContainer",
    "ScrollContainer", "Slider", "HScrollBar", "OptionButton", "CheckButton",
    "AudioServer", "DisplayServer", "Viewport", "Window", "Resource", "PackedScene",
}


# Члены, унаследованные от встроенных Node/Object: их не проверяем.
INHERITED = {
    "name", "global_position", "position", "global_transform", "transform",
    "rotation", "basis", "scale", "visible", "queue_free", "free",
    "get_parent", "get_tree", "add_child", "remove_child", "get_children",
    "get_instance_id", "is_inside_tree", "is_instance_valid", "set",
    "get", "call", "has_method", "connect", "emit_signal", "is_queued_for_deletion",
    "process_mode", "owner", "get_node", "find_child", "find_children",
    "add_to_group", "is_in_group", "set_process", "set_physics_process",
    "duplicate", "get_class", "notification", "to_string", "create_tween",
    "get_path", "get_rid", "look_at", "rotate_y", "rotate_x", "rotate_object_local",
    "get_world_3d", "entered_tree", "exiting_tree", "ready",
}

RETURN_RE = re.compile(
    r"^\s*(?:static\s+)?func\s+(\w+)\s*\([^)]*\)\s*->\s*([\w\[\]]+)", re.M)


def collect_files():
    out = []
    for path in ROOT.rglob("*.gd"):
        rel = path.relative_to(ROOT)
        if any(part in SKIP_DIRS for part in rel.parts):
            continue
        out.append(path)
    return sorted(out)


def build_table(files):
    classes = {}
    for path in files:
        text = path.read_text(encoding="utf-8")
        m = CLASS_RE.search(text)
        if not m:
            continue
        name = m.group(1)
        members = set()
        for rx in (FUNC_RE, VAR_RE, CONST_RE, SIGNAL_RE, ENUM_RE):
            members.update(rx.findall(text))
        # enum-значения тоже доступны как члены
        for block in re.findall(r"enum\s+\w+\s*\{(.*?)\}", text, re.S):
            for item in block.split(","):
                key = item.split("=")[0].strip()
                if key:
                    members.add(key)
        parent = EXTENDS_RE.search(text)
        classes[name] = {
            "members": members,
            "parent": parent.group(1) if parent else "",
            "returns": dict(RETURN_RE.findall(text)),
            "file": path,
        }
    return classes


def resolve(classes, name, seen=None):
    """Все члены класса вместе с унаследованными от class_name-родителей."""
    seen = seen or set()
    if name in seen or name not in classes:
        return set()
    seen.add(name)
    info = classes[name]
    members = set(info["members"])
    members |= resolve(classes, info["parent"], seen)
    return members


# Только методы самого движка, которые вызывают по строке через интерфейс.
# Всё остальное сверяется с реальными объявлениями func.
BUILTIN_METHODS = {"queue_free", "free", "duplicate", "call_deferred"}

FUNC_NAME_RE = re.compile(r"^\s*(?:static\s+)?func\s+(\w+)", re.M)


def declared_functions():
    """Все имена func из всех .gd проекта, включая тесты и Tools."""
    names = set(BUILTIN_METHODS)
    for path in ROOT.rglob("*.gd"):
        rel = path.relative_to(ROOT)
        if any(part in {".git", "docs", "addons"} for part in rel.parts):
            continue
        names.update(FUNC_NAME_RE.findall(path.read_text(encoding="utf-8")))
    return names


def check_string_calls(classes):
    """Сверяет строковые имена методов с реально объявленными функциями.

    `pool.call("release", self)` или `has_method("apply")` не ловятся ни
    парсером, ни проверкой Class.member, а в рантайме дают «Function not
    found in base self» / молча не срабатывают.
    """
    known = declared_functions()
    problems = []
    for path in ROOT.rglob("*.gd"):
        rel = path.relative_to(ROOT)
        if any(part in {".git", "docs", "addons"} for part in rel.parts):
            continue
        text = path.read_text(encoding="utf-8")
        for method in re.findall(
                r'\.(?:call|callv|has_method|emit_signal)\(\s*"([A-Za-z_]\w*)"',
                text):
            if method not in known:
                problems.append(
                    f'{rel}: call("{method}") — функция нигде не объявлена')
    return problems


def main() -> int:
    files = collect_files()
    classes = build_table(files)
    problems = []

    # Типизированные переменные и параметры: var x: ClassName / (x: ClassName)
    typed_re = re.compile(
        r"(?:var|const)\s+(\w+)\s*:\s*(\w+)|(\w+)\s*:\s*(\w+)\s*[,)]")
    for path in files:
        text = path.read_text(encoding="utf-8")
        # 1) статические обращения Class.member
        for cls_token, member in re.findall(r"\b([A-Z]\w+)\.(\w+)\b", text):
            if cls_token not in classes:
                continue
            allowed = resolve(classes, cls_token)
            if (member not in allowed and member not in ("new",)
                    and member not in INHERITED):
                problems.append(
                    f"{path.relative_to(ROOT)}: {cls_token}.{member} — "
                    f"нет такого члена у class_name {cls_token}")
        # 2) обращения через типизированную переменную
        typed = {}
        for m in typed_re.finditer(text):
            if m.group(1):
                typed[m.group(1)] = m.group(2)
            elif m.group(3):
                typed[m.group(3)] = m.group(4)
        # 3) вывод типа из `var x := Cls.method(...)` — именно на этом Godot
        #    падал с «Could not resolve external class member».
        for var_name, cls_token, method in re.findall(
                r"\bvar\s+(\w+)\s*:=\s*([A-Z]\w+)\.(\w+)\s*\(", text):
            if cls_token not in classes:
                continue
            ret = classes[cls_token]["returns"].get(method, "")
            ret = ret.strip("[]")
            if ret in classes:
                typed[var_name] = ret
        for var_name, cls_name in typed.items():
            if cls_name not in classes:
                continue
            allowed = resolve(classes, cls_name)
            for member in re.findall(
                    r"\b%s\.(\w+)\b" % re.escape(var_name), text):
                if member not in allowed and member not in INHERITED:
                    problems.append(
                        f"{path.relative_to(ROOT)}: {var_name}({cls_name})."
                        f"{member} — нет такого члена")

    # 4) Строковые вызовы: pool.call("release", self) / has_method("release").
    #    Их не ловит ни парсер, ни проверка Class.member, а падают они в рантайме
    #    как «Function not found in base self».
    string_calls = check_string_calls(classes)
    problems.extend(string_calls)

    if problems:
        print("НЕРАЗРЕШЁННЫЕ ОБРАЩЕНИЯ (%d):" % len(problems))
        for p in sorted(set(problems)):
            print(" -", p)
        return 1
    print("OK: все обращения к class_name-членам разрешаются (%d классов)"
          % len(classes))
    return 0


if __name__ == "__main__":
    sys.exit(main())

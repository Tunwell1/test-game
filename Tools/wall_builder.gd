@tool
extends EditorScript

## Ставит пролёт стены из готовых модулей Models/*_with_collision.tscn.
## Открыть этот файл в редакторе и нажать File > Run (Ctrl+Shift+X).
##
## У прямых модулей общий пивот — левый нижний угол, ширина 6.4 м,
## стык — это x = 0, 6.4, 12.8, ... Угол — дуга радиуса CORNER_STEP,
## он сдвигает ряд на CORNER_STEP и поворачивает его на +90°.
## Модули кладутся внутрь узла WallRun: его двигают и поворачивают целиком.
## Повторный запуск продолжает от последнего распознанного модуля в дереве.
##
## После расстановки скрипт сверяет локальные габариты прямых модулей и
## предупреждает, если пивот или передняя плоскость отличаются от остальных.

const MODULE_WIDTH := 6.4
## Радиус дуги угла на плоскости z = 0 (см. Tools/generate_wall_corners.py).
## Подобран так, что четверть дуги равна одному прямому модулю:
## CORNER_STEP * PI / 2 = 6.4 м, то есть вся кладка Wall.glb уходит в угол
## без растяжения, обрезки и повтора. Угол занимает CORNER_STEP + 0.2 м по
## каждой оси и сдвигает продолжение ряда на CORNER_STEP, а не на полный шаг
## 6.4 м; остаток 6.4 - CORNER_STEP закрывает угловой ассет пола (полная
## клетка 6.4 x 6.4 м), поэтому третьего «узкого» ассета не нужно.
const CORNER_STEP := 4.0743
## Допуск по X (в метрах). Ошибка пивота — это сантиметры и метры, не мм.
const X_TOLERANCE := 0.02
## Допуск по передней плоскости: у моделей она гуляет на 1.5 см из-за арта.
const Z_TOLERANCE := 0.03
const MODULES := {
	"wall": "res://Models/Wall_with_collision.tscn",
	"window": "res://Models/Wall_and_window_with_collision.tscn",
	"two_windows": "res://Models/Wall_and_two_windows_with_collision.tscn",
	"door": "res://Models/Wall_door_with_collision.tscn",
	"corner": "res://Models/Corner_Wall_with_collision.tscn",
}
## Порядок модулей. Углы поворачивают дальнейший ряд на +90° вокруг Y.
## Например: ["wall", "corner", "wall"].
const PATTERN := ["door", "window", "wall", "two_windows", "wall"]


func _run() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		push_error("Wall builder: открой сцену, в которую ставить стену.")
		return

	var run := scene_root.get_node_or_null("WallRun") as Node3D
	var cursor := Transform3D.IDENTITY
	if run == null:
		run = Node3D.new()
		run.name = "WallRun"
		scene_root.add_child(run)
		run.owner = scene_root
	else:
		cursor = _next_transform(run)

	var placed := 0
	var front_z := 0.0
	var have_front := false
	for index in PATTERN.size():
		var key: String = PATTERN[index]
		if not MODULES.has(key):
			push_error("Wall builder: неизвестный модуль «%s»." % key)
			continue
		var packed := load(MODULES[key]) as PackedScene
		if packed == null:
			push_error("Wall builder: не найдена сцена «%s»." % key)
			continue
		var module := packed.instantiate() as Node3D
		if module == null:
			push_error("Wall builder: «%s» — не Node3D-сцена." % key)
			continue
		module.name = "%s_%02d" % [key, index]
		module.transform = cursor
		run.add_child(module)
		# Только корень инстанса: внутренние узлы остаются за .tscn модуля.
		module.owner = scene_root

		# Габариты прямого модуля проверяются в его локальных осях,
		# поэтому контроль остаётся правильным и после поворота угла.
		if not _is_corner(key):
			var bounds := _mesh_bounds(module, module)
			if not have_front and bounds.size != Vector3.ZERO:
				front_z = bounds.end.z
				have_front = true
			_check_module(module, bounds, 0.0, front_z)
		cursor = module.transform * _exit_transform(_is_corner(key))
		placed += 1

	EditorInterface.mark_scene_as_unsaved()
	print("Wall builder: добавлено модулей %d." % placed)


## Предупреждает, если модуль встал не туда: сдвинут пивот или глубина.
func _check_module(module: Node3D, bounds: AABB, expected_x: float, front_z: float) -> void:
	if bounds.size == Vector3.ZERO:
		push_warning("Wall builder: у «%s» нет мешей — габариты не проверить." % module.name)
		return
	var dx := bounds.position.x - expected_x
	if absf(dx) > X_TOLERANCE:
		push_warning(
			(
				"Wall builder: «%s» смещён на %+.3f м по X. Проверь сдвиг ImportedModel в его .tscn."
				% [module.name, dx]
			)
		)
	var dz := bounds.end.z - front_z
	if absf(dz) > Z_TOLERANCE:
		push_warning(
			(
				"Wall builder: «%s»: передняя плоскость %+.3f, у первого %+.3f."
				% [module.name, bounds.end.z, front_z]
			)
		)


## Габариты всех мешей модуля в выбранной системе координат.
func _mesh_bounds(module: Node3D, space: Node3D) -> AABB:
	var to_space := space.global_transform.affine_inverse()
	var result := AABB()
	var have := false
	var stack: Array[Node] = [module]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh != null:
				var box: AABB = (
					(to_space * mesh_instance.global_transform) * mesh_instance.mesh.get_aabb()
				)
				result = box if not have else result.merge(box)
				have = true
		stack.append_array(node.get_children())
	return result


## Выход из модуля в его локальной системе координат.
func _exit_transform(corner: bool) -> Transform3D:
	if corner:
		return Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(CORNER_STEP, 0.0, -CORNER_STEP))
	return Transform3D(Basis.IDENTITY, Vector3(MODULE_WIDTH, 0.0, 0.0))


func _is_corner(key: String) -> bool:
	return key == "corner"


## Продолжение от последнего известного инстанса в порядке дерева сцены.
func _next_transform(run: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	for child in run.get_children():
		if not child is Node3D:
			continue
		for key in MODULES:
			if child.scene_file_path == MODULES[key]:
				result = (child as Node3D).transform * _exit_transform(_is_corner(key))
				break
	return result

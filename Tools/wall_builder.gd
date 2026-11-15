@tool
extends EditorScript

## Ставит пролёт стены из готовых модулей Models/*_with_collision.tscn.
## Открыть этот файл в редакторе и нажать File > Run (Ctrl+Shift+X).
##
## У всех модулей общий пивот — левый нижний угол, ширина 6.4 м,
## поэтому стык без подгонки руками — это просто x = 0, 6.4, 12.8, ...
## Модули кладутся внутрь узла WallRun: его двигают и поворачивают целиком.
## Повторный запуск достраивает пролёт справа от уже собранного.
##
## После расстановки скрипт сверяет реальные габариты мешей и пишет в консоль
## предупреждение, если модуль стоит не на шаге или его пивот/глубина
## разъехались с остальными — то есть если правили .tscn обёртки или .glb.

const MODULE_WIDTH := 6.4
## Допуск по X (в метрах). Ошибка пивота — это сантиметры и метры, не мм.
const X_TOLERANCE := 0.02
## Допуск по передней плоскости: у моделей она гуляет на 1.5 см из-за арта.
const Z_TOLERANCE := 0.03
const MODULES := {
	"wall": "res://Models/Wall_with_collision.tscn",
	"window": "res://Models/Wall_and_window_with_collision.tscn",
	"two_windows": "res://Models/Wall_and_two_windows_with_collision.tscn",
	"door": "res://Models/Wall_door_with_collision.tscn",
}
## Порядок модулей. Ключи — из MODULES, длина любая.
const PATTERN := ["door", "window", "wall", "two_windows", "wall"]


func _run() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		push_error("Wall builder: открой сцену, в которую ставить стену.")
		return

	var run := scene_root.get_node_or_null("WallRun") as Node3D
	var start_x := 0.0
	if run == null:
		run = Node3D.new()
		run.name = "WallRun"
		scene_root.add_child(run)
		run.owner = scene_root
	else:
		start_x = _right_edge(run)

	var placed := 0
	var front_z := 0.0
	var have_front := false
	for index in PATTERN.size():
		var key: String = PATTERN[index]
		var packed := load(MODULES[key]) as PackedScene
		if packed == null:
			push_error("Wall builder: не найдена сцена «%s»." % key)
			continue
		var module := packed.instantiate() as Node3D
		if module == null:
			push_error("Wall builder: «%s» — не Node3D-сцена." % key)
			continue
		module.name = "%s_%02d" % [key, index]
		module.position = Vector3(start_x + placed * MODULE_WIDTH, 0.0, 0.0)
		run.add_child(module)
		# Только корень инстанса: внутренние узлы остаются за .tscn модуля.
		module.owner = scene_root

		var bounds := _mesh_bounds(module, run)
		if not have_front:
			front_z = bounds.end.z
			have_front = true
		else:
			_check_module(module, bounds, module.position.x, front_z)
		placed += 1

	EditorInterface.mark_scene_as_unsaved()
	print("Wall builder: модулей %d, длина пролёта %.1f м." % [placed, placed * MODULE_WIDTH])


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


## Габариты всех мешей модуля в системе координат пролёта.
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


## Правый край уже собранного пролёта.
func _right_edge(run: Node3D) -> float:
	var right := 0.0
	for child in run.get_children():
		if child is Node3D:
			right = maxf(right, (child as Node3D).position.x + MODULE_WIDTH)
	return right

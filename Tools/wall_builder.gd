@tool
extends EditorScript

## Ставит пролёт стены из готовых модулей Models/*_with_collision.tscn.
## Открыть этот файл в редакторе и нажать File > Run (Ctrl+Shift+X).
##
## У всех модулей общий пивот — левый нижний угол, ширина 6.4 м,
## поэтому стык без подгонки руками — это просто x = 0, 6.4, 12.8, ...
## Модули кладутся внутрь узла WallRun: его двигают и поворачивают целиком.
## Повторный запуск достраивает пролёт справа от уже собранного.

const MODULE_WIDTH := 6.4
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
		placed += 1

	EditorInterface.mark_scene_as_unsaved()
	print("Wall builder: модулей %d, длина пролёта %.1f м." % [placed, placed * MODULE_WIDTH])


## Правый край уже собранного пролёта.
func _right_edge(run: Node3D) -> float:
	var right := 0.0
	for child in run.get_children():
		if child is Node3D:
			right = maxf(right, (child as Node3D).position.x + MODULE_WIDTH)
	return right

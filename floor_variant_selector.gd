extends Node3D

## Lets you compare the seven mirrored floor candidates in the running scene.
## Press F1-F7 to load a floor; only the selected mesh stays in the scene.
const FLOOR_SCENES: Array[String] = [
	"res://Models/Floor/Wood_Floor_Whole.glb",
	"res://Models/Floor/Wood_Floor_Variant_02.glb",
	"res://Models/Floor/Wood_Floor_Variant_03.glb",
	"res://Models/Floor/Wood_Floor_Variant_04.glb",
	"res://Models/Floor/Wood_Floor_Variant_05.glb",
	"res://Models/Floor/Wood_Floor_Variant_06.glb",
	"res://Models/Floor/Wood_Floor_Variant_07.glb",
]
const HOTKEYS := [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7]

var current_floor: Node3D
var current_index := -1


func _ready() -> void:
	_show_floor(0)


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	for index in HOTKEYS.size():
		if key_event.keycode == HOTKEYS[index]:
			_show_floor(index)
			get_viewport().set_input_as_handled()
			return


func _show_floor(index: int) -> void:
	if index < 0 or index >= FLOOR_SCENES.size():
		return
	if current_floor != null:
		current_floor.queue_free()
		current_floor = null

	var packed := load(FLOOR_SCENES[index]) as PackedScene
	if packed == null:
		push_error("Floor preview: could not load %s" % FLOOR_SCENES[index])
		return
	current_floor = packed.instantiate() as Node3D
	if current_floor == null:
		push_error("Floor preview: %s is not a Node3D scene" % FLOOR_SCENES[index])
		return
	current_floor.name = "floor_option_%02d" % (index + 1)
	add_child(current_floor)
	current_index = index
	print("Floor option %d/%d — press F1-F7 to compare" % [index + 1, FLOOR_SCENES.size()])

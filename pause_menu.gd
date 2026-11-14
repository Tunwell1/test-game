extends CanvasLayer

## Меню паузы: ESC ставит игру на паузу и освобождает мышь.

var panel: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10

	panel = Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -130.0
	box.offset_right = 130.0
	box.offset_top = -110.0
	box.offset_bottom = 110.0
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Пауза"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)

	var resume := Button.new()
	resume.text = "Продолжить"
	resume.custom_minimum_size = Vector2(240, 40)
	resume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resume.pressed.connect(_set_paused.bind(false))
	box.add_child(resume)

	var restart := Button.new()
	restart.text = "Перезапустить"
	restart.pressed.connect(func():
		get_tree().paused = false
		get_tree().reload_current_scene())
	box.add_child(restart)

	var quit := Button.new()
	quit.text = "Выход"
	quit.pressed.connect(func(): get_tree().quit())
	box.add_child(quit)

	_set_paused(false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif not get_tree().paused and event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _set_paused(value: bool) -> void:
	get_tree().paused = value
	panel.visible = value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED

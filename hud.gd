extends CanvasLayer

## HUD: прицел, полоска выносливости, подсказка взаимодействия.
## Элементы создаются кодом; скрипт должен быть дочерним узлом Player.

@onready var player: Player = get_parent() as Player

var crosshair: Control
var stamina_bar: ProgressBar
var prompt_label: Label
var stamina_alpha: float = 0.0

func _ready() -> void:
	# Прицел
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair)
	add_child(crosshair)

	# Выносливость
	stamina_bar = ProgressBar.new()
	stamina_bar.show_percentage = false
	stamina_bar.custom_minimum_size = Vector2(240, 8)
	stamina_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	stamina_bar.offset_left = -120
	stamina_bar.offset_right = 120
	stamina_bar.offset_top = -48
	stamina_bar.offset_bottom = -40
	stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamina_bar.modulate.a = 0.0
	add_child(stamina_bar)

	# Подсказка
	prompt_label = Label.new()
	prompt_label.text = "[E] Взаимодействовать"
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	prompt_label.offset_left = -150
	prompt_label.offset_right = 150
	prompt_label.offset_top = 30
	prompt_label.offset_bottom = 60
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_label.visible = false
	add_child(prompt_label)

func _draw_crosshair() -> void:
	var col := Color(1, 1, 1, 0.85)
	var target := player != null and player.has_interact_target()
	var gap := 6.0 if target else 4.0
	crosshair.draw_circle(Vector2.ZERO, 1.5, col)
	if target:
		for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			crosshair.draw_line(dir * gap, dir * (gap + 5.0), col, 1.5)

var _last_target := false

func _process(delta: float) -> void:
	if player == null:
		return

	var target := player.has_interact_target()
	prompt_label.visible = target
	if target != _last_target:
		_last_target = target
		crosshair.queue_redraw()

	stamina_bar.max_value = player.stamina_max
	stamina_bar.value = player.stamina
	var want_show := player.stamina < player.stamina_max - 0.5
	stamina_alpha = move_toward(stamina_alpha, 1.0 if want_show else 0.0, delta * (6.0 if want_show else 2.0))
	stamina_bar.modulate = Color(1.0, 0.45, 0.35, stamina_alpha) if player.exhausted else Color(1, 1, 1, stamina_alpha)

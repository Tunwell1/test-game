extends CanvasLayer

## HUD: прицел, полоска выносливости, подсказка взаимодействия.
## Элементы создаются кодом; скрипт должен быть дочерним узлом Player.

@onready var player: Player = get_parent() as Player

var crosshair: Control
var stamina_bar: ProgressBar
var prompt_label: Label
var health_bar: ProgressBar
var mana_bar: ProgressBar
var death_label: Label
var school_label: Label
var spell_label: Label
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

	# Здоровье и мана (слева внизу)
	health_bar = _make_bar(-48, Color(0.85, 0.2, 0.2))
	mana_bar = _make_bar(-34, Color(0.25, 0.5, 1.0))

	# Выбор стартовой школы магии
	school_label = Label.new()
	school_label.text = "Выберите направление магии:\n[1] Огонь   [2] Ветер   [3] Вода   [4] Земля"
	school_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	school_label.set_anchors_preset(Control.PRESET_CENTER)
	school_label.offset_left = -250
	school_label.offset_right = 250
	school_label.offset_top = -120
	school_label.offset_bottom = -60
	school_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(school_label)

	# Текущее заклинание
	spell_label = Label.new()
	spell_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	spell_label.offset_left = 20
	spell_label.offset_top = -26
	spell_label.offset_bottom = -4
	spell_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(spell_label)

	# Экран смерти
	death_label = Label.new()
	death_label.text = "Вы погибли\n[E] Возродиться"
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.set_anchors_preset(Control.PRESET_CENTER)
	death_label.offset_left = -150
	death_label.offset_right = 150
	death_label.offset_top = -30
	death_label.offset_bottom = 30
	death_label.visible = false
	add_child(death_label)

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

func _make_bar(top: float, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar.offset_left = 20
	bar.offset_right = 260
	bar.offset_top = top
	bar.offset_bottom = top + 10
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	add_child(bar)
	return bar

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

	health_bar.max_value = player.health_max
	health_bar.value = player.health
	mana_bar.max_value = player.mana_max
	mana_bar.value = player.mana
	death_label.visible = player.is_dead
	var book := player.magic_book
	school_label.visible = book != null and book.primary_school == -1 and not player.is_dead
	var sid := player.spell_caster.selected_spell() if player.spell_caster else ""
	spell_label.text = SpellCaster.SPELLS[sid]["name"] + "  [Q] сменить, [F] применить" if sid != "" else ""
	if player.is_dead and Input.is_action_just_pressed("interact"):
		player.respawn()
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

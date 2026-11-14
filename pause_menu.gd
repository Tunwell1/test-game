extends CanvasLayer

## Меню паузы в том же арканном языке, что и HUD: чернильный затемняющий
## слой, вращающееся кольцо, серифный заголовок, пункты-строки с золотой
## чертой при наведении.

const MARGIN := 110.0

var root: Control
var main_group: VBoxContainer
var settings_group: VBoxContainer
var settings_open := false
var volume_slider: HSlider
var volume_label: Label
var sensitivity_slider: HSlider
var sensitivity_label: Label

var _paused := false
var _base_sensitivity := 0.0
var _time := 0.0
var _visible_amount := 0.0
var _scrim: GradientTexture2D
var _settings := ConfigFile.new()
var _saved_volume_percent: float = 100.0
var _saved_sensitivity_percent: float = 100.0
const SETTINGS_PATH := "user://settings.cfg"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_load_settings()
	_build()
	_apply_saved_settings()
	_set_paused(false)

func _load_settings() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		_saved_volume_percent = round(db_to_linear(AudioServer.get_bus_volume_db(bus)) * 100.0)
	if _settings.load(SETTINGS_PATH) == OK:
		_saved_volume_percent = float(_settings.get_value("audio", "volume_percent", _saved_volume_percent))
		_saved_sensitivity_percent = float(_settings.get_value("controls", "sensitivity_percent", 100.0))
	_saved_volume_percent = clampf(_saved_volume_percent, 0.0, 100.0)
	_saved_sensitivity_percent = clampf(_saved_sensitivity_percent, 25.0, 200.0)

func _apply_saved_settings() -> void:
	_apply_volume(_saved_volume_percent)
	if volume_label:
		volume_label.text = "%d%%" % int(round(_saved_volume_percent))
	if volume_slider:
		volume_slider.value = _saved_volume_percent
	if sensitivity_label:
		sensitivity_label.text = "%d%%" % int(round(_saved_sensitivity_percent))
	if sensitivity_slider:
		sensitivity_slider.value = _saved_sensitivity_percent
	var p := _player()
	if p != null:
		p.mouse_sensitivity = _base_sensitivity * _saved_sensitivity_percent / 100.0

func _apply_volume(value: float) -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, value <= 0.0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(value / 100.0, 0.001)))

func _save_settings() -> void:
	_settings.set_value("audio", "volume_percent", _saved_volume_percent)
	_settings.set_value("controls", "sensitivity_percent", _saved_sensitivity_percent)
	_settings.save(SETTINGS_PATH)

func _exit_tree() -> void:
	_save_settings()

func _build() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.draw.connect(_draw_backdrop)
	add_child(root)

	main_group = _make_group()
	main_group.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	main_group.offset_left = MARGIN
	main_group.offset_right = MARGIN + 380.0
	main_group.offset_top = -230.0
	main_group.offset_bottom = 230.0
	root.add_child(main_group)

	main_group.add_child(_label("ПЕРЕДЫШКА   ·   I", 9, UiTheme.fade(UiTheme.GOLD, 0.9), true))
	var title := _serif_label("Пауза", 46, UiTheme.PARCHMENT)
	main_group.add_child(title)
	main_group.add_child(_rule(UiTheme.fade(UiTheme.GOLD, 0.55), 250.0))
	main_group.add_child(_spacer(4))

	_add_action("Продолжить", "ESC", func(): _set_paused(false), true)
	_add_action("Настройки", "II", _toggle_settings)
	_add_action("Начать заново", "III", _restart)
	_add_action("Выйти из игры", "IV", func(): get_tree().quit())

	main_group.add_child(_spacer(10))
	main_group.add_child(_rule(Color(1, 1, 1, 0.10), 250.0))
	main_group.add_child(_label("МИР ПОДОЖДЁТ. ТВОЯ ИСТОРИЯ — НЕТ.", 8,
		UiTheme.fade(UiTheme.MUTED, 0.85), true))

	_build_settings()

# --- Компоновка ------------------------------------------------------------

func _make_group() -> VBoxContainer:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 14)
	group.mouse_filter = Control.MOUSE_FILTER_PASS
	return group

func _serif_label(caption: String, size: int, tint: Color) -> Label:
	var l := Label.new()
	l.text = caption
	l.add_theme_font_override("font", UiTheme.serif())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", tint)
	l.add_theme_constant_override("outline_size", 0)
	return l

func _label(caption: String, size: int, tint: Color, tracked := false) -> Label:
	var l := Label.new()
	l.text = caption
	l.add_theme_font_override("font", UiTheme.caps(2) if tracked else UiTheme.sans())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", tint)
	l.add_theme_constant_override("outline_size", 0)
	return l

func _rule(tint: Color, width: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(width, 7)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.draw.connect(func():
		var w := minf(width, holder.size.x)
		var y := 3.0
		holder.draw_line(Vector2(0, y), Vector2(w * 0.5 - 6.0, y), tint, 1.0, true)
		holder.draw_line(Vector2(w * 0.5 + 6.0, y), Vector2(w, y), tint, 1.0, true)
		UiTheme.draw_diamond(holder, Vector2(w * 0.5, y), 2.4, 2.4, tint)
		UiTheme.draw_diamond(holder, Vector2(w * 0.5, y), 5.0, 5.0,
			Color(tint.r, tint.g, tint.b, tint.a * 0.3), false))
	return holder

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _add_action(caption: String, key: String, callback: Callable, primary := false) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	main_group.add_child(row)

	var button := Button.new()
	button.text = caption
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(300, 40 if primary else 36)
	button.add_theme_font_override("font", UiTheme.serif() if primary else UiTheme.sans())
	button.add_theme_font_size_override("font_size", 22 if primary else 17)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var empty := StyleBoxFlat.new()
	empty.bg_color = Color(0, 0, 0, 0)
	empty.content_margin_left = 18.0
	empty.content_margin_right = 6.0
	empty.content_margin_top = 5.0
	empty.content_margin_bottom = 5.0

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.96, 0.78, 0.49, 0.07)
	hover.border_color = UiTheme.GOLD
	hover.border_width_left = 2
	hover.content_margin_left = 20.0
	hover.content_margin_right = 6.0
	hover.content_margin_top = 5.0
	hover.content_margin_bottom = 5.0

	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", empty)
	button.add_theme_color_override("font_color", UiTheme.PARCHMENT if primary
		else Color(0.80, 0.81, 0.84))
	button.add_theme_color_override("font_hover_color", UiTheme.GOLD)
	button.add_theme_color_override("font_pressed_color", UiTheme.GOLD)
	button.pressed.connect(callback)
	row.add_child(button)

	var hint := _label(key, 8, UiTheme.fade(UiTheme.MUTED, 0.75), true)
	hint.custom_minimum_size = Vector2(40, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(hint)

func _build_settings() -> void:
	settings_group = _make_group()
	settings_group.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	settings_group.offset_left = MARGIN
	settings_group.offset_right = MARGIN + 420.0
	settings_group.offset_top = -190.0
	settings_group.offset_bottom = 190.0
	settings_group.visible = false
	root.add_child(settings_group)

	settings_group.add_child(_label("ПЕРЕДЫШКА   ·   II", 9, UiTheme.fade(UiTheme.GOLD, 0.9), true))
	settings_group.add_child(_serif_label("Настройки", 38, UiTheme.PARCHMENT))
	settings_group.add_child(_rule(UiTheme.fade(UiTheme.GOLD, 0.55), 320.0))
	settings_group.add_child(_spacer(8))

	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 12)
	settings_group.add_child(vol_row)
	var vol_label := _label("ГРОМКОСТЬ", 9, UiTheme.fade(UiTheme.MUTED, 0.95), true)
	vol_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vol_row.add_child(vol_label)
	var bus_pct := int(round(_saved_volume_percent))
	volume_label = _serif_label("%d%%" % bus_pct, 16, UiTheme.GOLD)
	vol_row.add_child(volume_label)
	volume_slider = _new_slider(0, 100, bus_pct)
	volume_slider.value_changed.connect(_on_volume_changed)
	settings_group.add_child(volume_slider)

	settings_group.add_child(_spacer(4))
	var sens_row := HBoxContainer.new()
	sens_row.add_theme_constant_override("separation", 12)
	sens_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_group.add_child(sens_row)
	var sens_label := _label("ЧУВСТВИТЕЛЬНОСТЬ МЫШИ", 9, UiTheme.fade(UiTheme.MUTED, 0.95), true)
	sens_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sens_row.add_child(sens_label)
	sensitivity_label = _serif_label("100%", 16, UiTheme.GOLD)
	sens_row.add_child(sensitivity_label)
	var p := _player()
	_base_sensitivity = p.mouse_sensitivity if p != null else 0.0025
	sensitivity_slider = _new_slider(25, 200, _saved_sensitivity_percent)
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	settings_group.add_child(sensitivity_slider)

	settings_group.add_child(_spacer(8))
	settings_group.add_child(_rule(Color(1, 1, 1, 0.10), 320.0))
	settings_group.add_child(_label("Настройки сохраняются между запусками.", 10,
		UiTheme.fade(UiTheme.MUTED, 0.8)))

	var back := Button.new()
	back.text = "Назад"
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.add_theme_font_override("font", UiTheme.serif())
	back.add_theme_font_size_override("font_size", 19)
	back.custom_minimum_size = Vector2(200, 36)
	var plain := StyleBoxFlat.new()
	plain.bg_color = Color(0, 0, 0, 0)
	plain.content_margin_left = 18.0
	plain.content_margin_top = 5.0
	plain.content_margin_bottom = 5.0
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.96, 0.78, 0.49, 0.07)
	hover.border_color = UiTheme.GOLD
	hover.border_width_left = 2
	hover.content_margin_left = 20.0
	hover.content_margin_top = 5.0
	hover.content_margin_bottom = 5.0
	back.add_theme_stylebox_override("normal", plain)
	back.add_theme_stylebox_override("hover", hover)
	back.add_theme_stylebox_override("pressed", hover)
	back.add_theme_stylebox_override("focus", plain)
	back.add_theme_color_override("font_color", UiTheme.PARCHMENT)
	back.add_theme_color_override("font_hover_color", UiTheme.GOLD)
	back.pressed.connect(_toggle_settings)
	settings_group.add_child(back)

func _new_slider(minimum: float, maximum: float, initial: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.value = initial
	slider.custom_minimum_size = Vector2(340, 22)
	slider.theme = UiTheme.build_theme()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return slider

# --- Отрисовка фона --------------------------------------------------------

func _draw_backdrop() -> void:
	if root == null:
		return
	var s := root.size
	if s.x < 100 or s.y < 100:
		return
	var a := _visible_amount
	if a <= 0.001:
		return

	if _scrim == null:
		_scrim = UiTheme.vertical_gradient(Color(0.020, 0.026, 0.036, 0.94),
			Color(0.010, 0.013, 0.020, 0.97))
	root.draw_texture_rect(_scrim, Rect2(Vector2.ZERO, s), false, Color(1, 1, 1, a))

	# Крупное кольцо за текстом: атмосфера, а не рамка.
	var center := Vector2(s.x * 0.5, s.y * 0.52)
	UiTheme.draw_arcane_ring(root, center, minf(s.y, s.x) * 0.44, UiTheme.fade(UiTheme.GOLD, 0.55 * a),
		_time * 0.05, 72)

	# Вертикальная золотая нить, задающая левую ось композиции.
	root.draw_rect(Rect2(Vector2(MARGIN - 34.0, s.y * 0.16), Vector2(1, s.y * 0.68)),
		UiTheme.fade(UiTheme.GOLD, 0.34 * a), true)
	UiTheme.draw_diamond(root, Vector2(MARGIN - 33.5, s.y * 0.16), 3.0, 3.0,
		UiTheme.fade(UiTheme.GOLD, 0.7 * a))
	UiTheme.draw_diamond(root, Vector2(MARGIN - 33.5, s.y * 0.84), 3.0, 3.0,
		UiTheme.fade(UiTheme.GOLD, 0.7 * a))

	# Тонкая разделительная линия справа — «водяной знак» макета.
	root.draw_rect(Rect2(Vector2(s.x * 0.62, 0), Vector2(1, s.y)),
		Color(1, 1, 1, 0.030 * a), true)

func _process(delta: float) -> void:
	_time += delta
	var target := 1.0 if _paused else 0.0
	_visible_amount = move_toward(_visible_amount, target, delta * 6.0)
	if root != null:
		root.modulate.a = _visible_amount
		# Скрываем только после полного затухания, иначе анимация закрытия не видна.
		root.visible = _visible_amount > 0.001
		if root.visible:
			root.queue_redraw()

# --- Логика ----------------------------------------------------------------

func _player() -> Player:
	var p := get_parent() as Player
	if p != null:
		return p
	return get_tree().get_first_node_in_group("player") as Player

func _on_volume_changed(value: float) -> void:
	volume_label.text = "%d%%" % int(value)
	_saved_volume_percent = value
	_apply_volume(value)
	_save_settings()

func _on_sensitivity_changed(value: float) -> void:
	sensitivity_label.text = "%d%%" % int(value)
	_saved_sensitivity_percent = value
	_save_settings()
	var p := _player()
	if p != null:
		if _base_sensitivity <= 0.0:
			_base_sensitivity = p.mouse_sensitivity
		p.mouse_sensitivity = _base_sensitivity * value / 100.0

func _toggle_settings() -> void:
	settings_open = not settings_open
	main_group.visible = not settings_open
	settings_group.visible = settings_open
	root.queue_redraw()

func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _is_school_choice_open():
			# Нельзя пропустить первый выбор школы обычным снятием паузы.
			get_viewport().set_input_as_handled()
			return
		if settings_open:
			_toggle_settings()
		else:
			_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif not get_tree().paused and event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _is_school_choice_open() -> bool:
	var p := get_parent() as Player
	return p != null and p.magic_book != null and p.magic_book.primary_school == -1 \
		and not p.is_dead

func _set_paused(value: bool) -> void:
	_paused = value
	get_tree().paused = value
	settings_open = false
	if settings_group:
		settings_group.visible = false
	if main_group:
		main_group.visible = true
	if value:
		_time = 0.0
	# Видимость узла ведёт _process: он скрывает фон только после затухания,
	# поэтому анимация закрытия меню действительно видна.
	root.visible = root.visible or value
	root.modulate.a = _visible_amount
	root.queue_redraw()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED

extends CanvasLayer

## Меню паузы в том же арканном языке, что и HUD: чернильный затемняющий
## слой, вращающееся кольцо, серифный заголовок, пункты-строки с золотой
## чертой при наведении.

const MARGIN := 110.0
const SETTINGS_PATH := "user://settings.cfg"
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const WINDOW_MODES := [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN,
	DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
const REBIND_ACTIONS := [
	{"action": "move_forward", "label": "Движение вперёд"},
	{"action": "move_back", "label": "Движение назад"},
	{"action": "move_left", "label": "Движение влево"},
	{"action": "move_right", "label": "Движение вправо"},
	{"action": "jump", "label": "Прыжок"},
	{"action": "sprint", "label": "Бег"},
	{"action": "crouch", "label": "Присесть"},
	{"action": "interact", "label": "Взаимодействие"},
	{"action": "cast_spell", "label": "Применить заклинание"},
	{"action": "next_spell", "label": "Следующее заклинание"},
	{"action": "pick_school_1", "label": "Школа 1"},
	{"action": "pick_school_2", "label": "Школа 2"},
	{"action": "pick_school_3", "label": "Школа 3"},
	{"action": "pick_school_4", "label": "Школа 4"},
]

var root: Control
var main_group: VBoxContainer
var settings_scroll: ScrollContainer
var settings_group: VBoxContainer
var binding_buttons: Dictionary = {}
var binding_hint: Label
var _binding_action: String = ""
var settings_open := false
var volume_slider: HSlider
var volume_label: Label
var sensitivity_slider: HSlider
var sensitivity_label: Label
var window_mode_option: OptionButton
var resolution_option: OptionButton

var _paused := false
var _base_sensitivity := 0.0
var _time := 0.0
var _visible_amount := 0.0
var _scrim: GradientTexture2D
var _settings := ConfigFile.new()
var _saved_volume_percent: float = 100.0
var _saved_sensitivity_percent: float = 100.0
var _saved_window_mode: int = DisplayServer.WINDOW_MODE_WINDOWED
var _saved_resolution_index: int = 0
var _saved_bindings: Dictionary = {}

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
		_saved_window_mode = int(_settings.get_value("display", "window_mode", _saved_window_mode))
		_saved_resolution_index = int(_settings.get_value("display", "resolution_index", _saved_resolution_index))
		for action in _settings.get_section_keys("bindings"):
			_saved_bindings[action] = _settings.get_value("bindings", action)
	_saved_volume_percent = clampf(_saved_volume_percent, 0.0, 100.0)
	_saved_sensitivity_percent = clampf(_saved_sensitivity_percent, 25.0, 200.0)
	_saved_resolution_index = clampi(_saved_resolution_index, 0, RESOLUTIONS.size() - 1)
	if not WINDOW_MODES.has(_saved_window_mode):
		_saved_window_mode = DisplayServer.WINDOW_MODE_WINDOWED

func _apply_saved_settings() -> void:
	_apply_volume(_saved_volume_percent)
	_apply_display_settings()
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
	call_deferred("_apply_saved_bindings")

func _apply_volume(value: float) -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, value <= 0.0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(value / 100.0, 0.001)))

func _apply_display_settings() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_size(RESOLUTIONS[_saved_resolution_index])
	DisplayServer.window_set_mode(_saved_window_mode)

func _save_settings() -> void:
	_settings.set_value("audio", "volume_percent", _saved_volume_percent)
	_settings.set_value("controls", "sensitivity_percent", _saved_sensitivity_percent)
	_settings.set_value("display", "window_mode", _saved_window_mode)
	_settings.set_value("display", "resolution_index", _saved_resolution_index)
	for action in _saved_bindings:
		_settings.set_value("bindings", action, _saved_bindings[action])
	_settings.save(SETTINGS_PATH)

func _apply_saved_bindings() -> void:
	for action_variant in _saved_bindings:
		var action := str(action_variant)
		var binding_variant: Variant = _saved_bindings[action_variant]
		if not InputMap.has_action(action) or typeof(binding_variant) != TYPE_DICTIONARY:
			continue
		var binding: Dictionary = binding_variant
		var kind := str(binding.get("kind", ""))
		for existing in InputMap.action_get_events(action):
			if kind == "key" and existing is InputEventKey:
				InputMap.action_erase_event(action, existing)
			elif kind != "key" and (existing is InputEventJoypadButton or existing is InputEventJoypadMotion):
				InputMap.action_erase_event(action, existing)
		var event := _event_from_binding(binding)
		if event != null:
			InputMap.action_add_event(action, event)
	call_deferred("_refresh_binding_buttons")

func _event_from_binding(binding: Dictionary) -> InputEvent:
	match str(binding.get("kind", "")):
		"key":
			var event := InputEventKey.new()
			event.physical_keycode = int(binding.get("code", 0))
			return event
		"button":
			var event := InputEventJoypadButton.new()
			event.button_index = int(binding.get("code", 0))
			return event
		"axis":
			var event := InputEventJoypadMotion.new()
			event.axis = int(binding.get("code", 0))
			event.axis_value = float(binding.get("sign", 1.0))
			return event
	return null

func _refresh_binding_buttons() -> void:
	for action in binding_buttons:
		var button := binding_buttons[action] as Button
		if is_instance_valid(button):
			button.text = _binding_text(str(action))

func _binding_text(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return event.as_text()
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return event.as_text()
	return "—"

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
	settings_scroll = ScrollContainer.new()
	settings_scroll.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	settings_scroll.offset_left = MARGIN
	settings_scroll.offset_right = MARGIN + 440.0
	settings_scroll.offset_top = -190.0
	settings_scroll.offset_bottom = 190.0
	settings_scroll.visible = false
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(settings_scroll)

	settings_group = _make_group()
	settings_group.custom_minimum_size = Vector2(420.0, 780.0)
	settings_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_scroll.add_child(settings_group)

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

	var resolution_row := HBoxContainer.new()
	resolution_row.add_theme_constant_override("separation", 12)
	settings_group.add_child(resolution_row)
	var resolution_label := _label("РАЗРЕШЕНИЕ", 9, UiTheme.fade(UiTheme.MUTED, 0.95), true)
	resolution_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resolution_row.add_child(resolution_label)
	resolution_option = OptionButton.new()
	resolution_option.custom_minimum_size.x = 180.0
	for i in RESOLUTIONS.size():
		var resolution: Vector2i = RESOLUTIONS[i]
		resolution_option.add_item("%d × %d" % [resolution.x, resolution.y], i)
	resolution_option.select(_saved_resolution_index)
	resolution_option.disabled = _saved_window_mode != DisplayServer.WINDOW_MODE_WINDOWED
	resolution_option.item_selected.connect(_on_resolution_selected)
	resolution_row.add_child(resolution_option)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 12)
	settings_group.add_child(mode_row)
	var mode_label := _label("РЕЖИМ ОКНА", 9, UiTheme.fade(UiTheme.MUTED, 0.95), true)
	mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(mode_label)
	window_mode_option = OptionButton.new()
	window_mode_option.custom_minimum_size.x = 180.0
	window_mode_option.add_item("Оконный", DisplayServer.WINDOW_MODE_WINDOWED)
	window_mode_option.add_item("Полный экран", DisplayServer.WINDOW_MODE_FULLSCREEN)
	window_mode_option.add_item("Эксклюзивный полный экран", DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	window_mode_option.select(WINDOW_MODES.find(_saved_window_mode))
	window_mode_option.item_selected.connect(_on_window_mode_selected)
	mode_row.add_child(window_mode_option)

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

	settings_group.add_child(_spacer(4))
	settings_group.add_child(_rule(UiTheme.fade(UiTheme.GOLD, 0.4), 320.0))
	settings_group.add_child(_label("УПРАВЛЕНИЕ · КЛАВИАТУРА / ГЕЙМПАД", 9,
		UiTheme.fade(UiTheme.GOLD, 0.9), true))
	binding_hint = _label("Нажмите действие, затем клавишу или кнопку.", 10,
		UiTheme.fade(UiTheme.MUTED, 0.85))
	settings_group.add_child(binding_hint)
	var reset_bindings := Button.new()
	reset_bindings.text = "Вернуть управление по умолчанию"
	reset_bindings.pressed.connect(_reset_bindings)
	settings_group.add_child(reset_bindings)
	_build_binding_rows()

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

func _build_binding_rows() -> void:
	for binding in REBIND_ACTIONS:
		var action := str(binding["action"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		settings_group.add_child(row)
		var caption := _label(str(binding["label"]), 12, UiTheme.PARCHMENT)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(caption)
		var button := Button.new()
		button.text = "…"
		button.custom_minimum_size = Vector2(145.0, 30.0)
		button.pressed.connect(_begin_rebind.bind(action))
		row.add_child(button)
		binding_buttons[action] = button
	call_deferred("_refresh_binding_buttons")

func _begin_rebind(action: String) -> void:
	_binding_action = action
	var button := binding_buttons.get(action) as Button
	if button != null:
		button.text = "Нажмите…"
	binding_hint.text = "Нажмите клавишу, кнопку или наклоните стик. ESC — отмена."

func _capture_binding(event: InputEvent) -> bool:
	if _binding_action.is_empty():
		return false
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return true
		if key_event.keycode == KEY_ESCAPE:
			_binding_action = ""
			binding_hint.text = "Переназначение отменено."
			_refresh_binding_buttons()
			return true
		var physical := int(key_event.physical_keycode)
		if physical == 0:
			physical = int(key_event.keycode)
		if physical <= 0:
			return true
		_save_binding({"kind": "key", "code": physical})
		return true
	if event is InputEventJoypadButton and event.is_pressed():
		var joy_button := event as InputEventJoypadButton
		_save_binding({"kind": "button", "code": int(joy_button.button_index)})
		return true
	if event is InputEventJoypadMotion:
		var joy_motion := event as InputEventJoypadMotion
		if absf(joy_motion.axis_value) >= 0.75:
			_save_binding({"kind": "axis", "code": int(joy_motion.axis),
				"sign": signf(joy_motion.axis_value)})
		return true
	return true

func _save_binding(binding: Dictionary) -> void:
	var action := _binding_action
	if not InputMap.has_action(action):
		_binding_action = ""
		return
	var kind := str(binding["kind"])
	for existing in InputMap.action_get_events(action):
		if kind == "key" and existing is InputEventKey:
			InputMap.action_erase_event(action, existing)
		elif kind != "key" and (existing is InputEventJoypadButton or existing is InputEventJoypadMotion):
			InputMap.action_erase_event(action, existing)
	var input_event := _event_from_binding(binding)
	if input_event != null:
		InputMap.action_add_event(action, input_event)
	_saved_bindings[action] = binding
	_binding_action = ""
	binding_hint.text = "Назначение сохранено."
	_refresh_binding_buttons()
	_save_settings()

func _reset_bindings() -> void:
	_binding_action = ""
	_saved_bindings.clear()
	_settings.erase_section("bindings")
	for binding in REBIND_ACTIONS:
		var action := str(binding["action"])
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for existing in InputMap.action_get_events(action):
			InputMap.action_erase_event(action, existing)
	var p := _player()
	if p != null:
		p._setup_input_actions()
		if p.spell_caster != null:
			p.spell_caster._add_actions()
	binding_hint.text = "Управление сброшено."
	_refresh_binding_buttons()
	_save_settings()

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

func _on_resolution_selected(index: int) -> void:
	_saved_resolution_index = clampi(index, 0, RESOLUTIONS.size() - 1)
	if _saved_window_mode == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_size(RESOLUTIONS[_saved_resolution_index])
	_save_settings()

func _on_window_mode_selected(index: int) -> void:
	_saved_window_mode = window_mode_option.get_item_id(index)
	resolution_option.disabled = _saved_window_mode != DisplayServer.WINDOW_MODE_WINDOWED
	if _saved_window_mode == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_size(RESOLUTIONS[_saved_resolution_index])
	DisplayServer.window_set_mode(_saved_window_mode)
	_save_settings()

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
	settings_scroll.visible = settings_open
	root.queue_redraw()

func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _input(event: InputEvent) -> void:
	if _capture_binding(event):
		get_viewport().set_input_as_handled()

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
		settings_scroll.visible = false
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

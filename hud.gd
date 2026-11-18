extends CanvasLayer

## HUD без рамок: приглушённая палитра, тонкие полосы ресурсов, сигил заклинания
## и прицел живут прямо поверх мира. Двойные панели с рамкой остаются только
## на экранах паузы, выбора школы и смерти — там, где игра останавливается.

@onready var player: Player = get_parent() as Player

const MARGIN := 44.0
const BAR_WIDTH := 260.0

var hud_canvas: Control
var school_screen: Control
var death_screen: Control

var spell_name: String = ""
var spell_school: String = ""
var spell_cost: float = 0.0
var spell_tint: Color = UiTheme.GOLD

var _last_spell := ""
var _last_health := -1.0
var _hit_flash := 0.0
var _stamina_alpha := 0.0
var _time := 0.0
var _school_t := 0.0
var _death_t := 0.0
var _school_pause_active := false
var _interface_scale := 1.0
var _school_card_rects: Array[Rect2] = []
var _hovered_school: int = -1


func _ready() -> void:
	# Выбор школы должен работать, пока остальной мир стоит на паузе.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5

	hud_canvas = _make_layer()
	hud_canvas.draw.connect(_draw_hud)

	school_screen = _make_layer()
	school_screen.visible = false
	school_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	school_screen.gui_input.connect(_on_school_gui_input)
	school_screen.draw.connect(_draw_school_screen)

	death_screen = _make_layer()
	death_screen.visible = false
	death_screen.draw.connect(_draw_death_screen)
	get_viewport().size_changed.connect(_apply_interface_scale)
	_apply_interface_scale()

func set_interface_scale(value: float) -> void:
	_interface_scale = clampf(value, 0.5, 2.0)
	_apply_interface_scale()

func _apply_interface_scale() -> void:
	if not is_inside_tree():
		return
	var logical_size := get_viewport().get_visible_rect().size / _interface_scale
	# Drawing uses the expanded logical viewport so the scaled canvas still reaches
	# every screen edge instead of magnifying a fixed-size canvas into a crop.
	for canvas in [hud_canvas, school_screen, death_screen]:
		if canvas == null:
			continue
		canvas.position = Vector2.ZERO
		canvas.size = logical_size
	transform = Transform2D(Vector2(_interface_scale, 0.0),
		Vector2(0.0, _interface_scale), Vector2.ZERO)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED and is_node_ready():
		_apply_interface_scale()

func _make_layer() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c

func _exit_tree() -> void:
	if _school_pause_active and is_instance_valid(get_tree()):
		get_tree().paused = false

# ===========================================================================
#  HUD
# ===========================================================================

func _draw_hud() -> void:
	if player == null or player.is_dead or school_screen.visible:
		return
	var s := hud_canvas.size
	if s.x < 200 or s.y < 200:
		return

	var serif := UiTheme.serif()
	var caps := UiTheme.caps(2)
	var caps_tight := UiTheme.caps(1)

	# У HUD нет ни подложки, ни рамок: мир остаётся чистым и хорошо читаемым.
	_draw_resources(serif, caps, caps_tight, s)
	_draw_reticle(caps_tight, s)
	_draw_spell_slot(serif, caps, caps_tight, s)

func _draw_resources(serif: Font, caps: Font, caps_tight: Font, s: Vector2) -> void:
	var x := MARGIN + 2.0
	var base_y := s.y - MARGIN - 6.0
	var health_color := UiTheme.flash_tint(UiTheme.HEALTH, _hit_flash,
		Color(1.0, 0.72, 0.62))

	var health_ratio := clampf(player.health / maxf(player.health_max, 1.0), 0.0, 1.0)
	var mana_ratio := clampf(player.mana / maxf(player.mana_max, 1.0), 0.0, 1.0)

	_draw_resource(serif, caps, caps_tight, x, base_y, "ЗДОРОВЬЕ", player.health,
		player.health_max, health_ratio, health_color, 1.0)

	_draw_resource(serif, caps, caps_tight, x, base_y - 44.0, "МАНА", player.mana,
		player.mana_max, mana_ratio, UiTheme.MANA, 1.0)

	if _stamina_alpha > 0.012:
		var a := _stamina_alpha
		var st_color := UiTheme.STAMINA
		if player.exhausted:
			st_color = Color(1.0, 0.38, 0.32).lerp(UiTheme.STAMINA, 0.15 + 0.15 * sin(_time * 9.0))
		_draw_resource(serif, caps, caps_tight, x, base_y - 88.0, "ВЫНОСЛИВОСТЬ",
			player.stamina, player.stamina_max,
			clampf(player.stamina / maxf(player.stamina_max, 1.0), 0.0, 1.0),
			st_color, a)

func _draw_resource(serif: Font, caps: Font, caps_tight: Font, x: float, baseline: float,
		title: String, value: float, maximum: float, ratio: float, tint: Color,
		alpha: float) -> void:
	var title_color := UiTheme.fade(UiTheme.MUTED, 1.0 * alpha)
	UiTheme.draw_text(hud_canvas, caps, Vector2(x, baseline), title, 9, title_color, 0.0)

	var value_text := "%d" % int(ceil(value))
	var max_text := "/ %d" % int(round(maximum))
	var max_w := UiTheme.text_width(caps_tight, max_text, 8)
	UiTheme.draw_text_right(hud_canvas, caps_tight, x + BAR_WIDTH, baseline,
		max_text, 8, UiTheme.fade(UiTheme.MUTED, 0.62 * alpha), 0.6)
	var value_color := UiTheme.fade(UiTheme.PARCHMENT.lerp(tint, 0.28), 0.92 * alpha)
	UiTheme.draw_text_right(hud_canvas, serif, x + BAR_WIDTH - max_w - 5.0, baseline + 1.0,
		value_text, 15, value_color, 0.0)

	# Дорожка: глубокая канавка с бликом сверху.
	var bar_y := baseline + 8.0
	var left := Vector2(x, bar_y)
	hud_canvas.draw_rect(Rect2(left, Vector2(BAR_WIDTH, 5.0)), Color(0.0, 0.0, 0.0, 0.52 * alpha), true)
	hud_canvas.draw_line(left, left + Vector2(BAR_WIDTH, 0.0), UiTheme.fade(UiTheme.GOLD, 0.25 * alpha), 1.0, true)

	if ratio > 0.002:
		var fill_w := maxf(BAR_WIDTH * ratio, 3.0)
		hud_canvas.draw_rect(Rect2(left, Vector2(fill_w, 5.0)),
			Color(tint.r, tint.g, tint.b, 0.92 * alpha), true)
		hud_canvas.draw_line(left, Vector2(x + fill_w, bar_y),
			Color(1, 1, 1, 0.35 * alpha), 1.0, true)
		hud_canvas.draw_line(Vector2(x + fill_w, bar_y),
			Vector2(x + fill_w, bar_y + 5.0), UiTheme.fade(tint, 0.95 * alpha), 1.0, true)

## Прицел: точка, четыре засечки; при цели — раскрытое кольцо и подсказка.
func _draw_reticle(caps: Font, s: Vector2) -> void:
	var center := s * 0.5
	var active := player.has_interact_target()
	var tint := UiTheme.GOLD if active else Color(0.94, 0.94, 0.92, 0.62)

	if active:
		var pulse := 0.5 + 0.5 * sin(_time * 3.4)
		hud_canvas.draw_arc(center, 15.0, 0.0, TAU, 48, UiTheme.fade(UiTheme.GOLD, 0.45), 1.0, true)
		hud_canvas.draw_arc(center, 18.0, 0.0, TAU, 48, UiTheme.fade(UiTheme.GOLD, 0.22), 1.0, true)
		hud_canvas.draw_circle(center, 1.8, tint)
		for i in 4:
			var a := _time * 1.6 + TAU * float(i) / 4.0
			var d := Vector2(cos(a), sin(a))
			UiTheme.draw_diamond(hud_canvas, center + d * (11.0 + pulse * 1.6), 1.8, 3.2,
				UiTheme.fade(UiTheme.GOLD, 0.5 + 0.35 * pulse))
		var label := "ВЗАИМОДЕЙСТВИЕ"
		var target := player.interact_ray.get_collider() if player.interact_ray else null
		if target != null and target.has_method("get_interaction_prompt"):
			label = str(target.call("get_interaction_prompt"))
		var w := UiTheme.text_width(caps, label, 8)
		var text_y := center.y + 40.0
		UiTheme.draw_text_center(hud_canvas, caps, center.x, text_y, label, 8,
			UiTheme.fade(UiTheme.PARCHMENT, 0.78), 1.0)
		var cap_rect := Rect2(center.x - 9.0, text_y + 6.0, 18.0, 16.0)
		UiTheme.draw_keycap(hud_canvas, cap_rect, "E", UiTheme.GOLD, 10)
	else:
		hud_canvas.draw_circle(center, 1.5, tint)
		var dirs := [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]
		for i in 4:
			var d: Vector2 = dirs[i]
			hud_canvas.draw_line(center + d * 4.5, center + d * 8.5,
				UiTheme.fade(tint, 0.55), 1.0, true)

## Слот заклинания: сигил, название и горячие клавиши без панели и рамки.
func _draw_spell_slot(serif: Font, caps: Font, caps_tight: Font, s: Vector2) -> void:
	var rect := Rect2(Vector2(s.x - MARGIN - 268.0, s.y - MARGIN - 76.0), Vector2(268.0, 76.0))

	var school := -1
	var cd_total := 0.0
	var cd_left := 0.0
	if player.spell_caster:
		cd_left = player.spell_caster.cooldown_timer
		var id := player.spell_caster.selected_spell()
		if id != "" and SpellCaster.SPELLS.has(id):
			school = int(SpellCaster.SPELLS[id]["school"])
			cd_total = float(SpellCaster.SPELLS[id]["cooldown"])

	var sigil_center := rect.position + Vector2(45.0, 41.0)
	var sigil_r := 21.0
	var ready := cd_total <= 0.0 or cd_left <= 0.001

	if cd_total > 0.0 and cd_left > 0.001:
		var frac := clampf(1.0 - cd_left / cd_total, 0.0, 1.0)
		hud_canvas.draw_arc(sigil_center, sigil_r + 5.0, -PI * 0.5, -PI * 0.5 + TAU * frac,
			64, UiTheme.fade(spell_tint, 0.85), 1.5, true)
	UiTheme.draw_school_sigil(hud_canvas, sigil_center, sigil_r, school,
		UiTheme.fade(spell_tint, 1.0 if ready else 0.42), 1.6)

	var tx := rect.position.x + 95.0
	var available := rect.end.x - 12.0 - tx
	UiTheme.draw_text(hud_canvas, caps, Vector2(tx, rect.position.y + 24.0), "ЗАКЛИНАНИЕ",
		8, UiTheme.fade(UiTheme.GOLD, 0.90), 0.0)
	UiTheme.draw_keycap(hud_canvas, Rect2(rect.end.x - 32.0, rect.position.y + 10.0, 20.0, 17.0),
		"F", UiTheme.GOLD, 10)

	var name_size := 19
	while name_size > 11 and UiTheme.text_width(serif, spell_name, name_size) > available:
		name_size -= 1
	UiTheme.draw_text(hud_canvas, serif, Vector2(tx, rect.position.y + 48.0), spell_name,
		name_size, UiTheme.PARCHMENT, 0.0)

	var meta := spell_school
	if spell_cost > 0.0:
		meta += "   ·   %d МАНЫ" % int(spell_cost)
	UiTheme.draw_text(hud_canvas, caps_tight, Vector2(tx, rect.position.y + 66.0), meta, 8,
		UiTheme.fade(spell_tint, 0.92), 0.0)

	UiTheme.draw_keycap(hud_canvas, Rect2(rect.end.x - 32.0, rect.end.y - 27.0, 20.0, 17.0),
		"Q", UiTheme.fade(UiTheme.MUTED, 0.95), 10)

# ===========================================================================
#  Выбор школы
# ===========================================================================

func _school_card_at(point: Vector2) -> int:
	for i in _school_card_rects.size():
		if _school_card_rects[i].has_point(point):
			return i
	return -1

func _on_school_gui_input(event: InputEvent) -> void:
	if not school_screen.visible:
		return
	if event is InputEventMouseMotion:
		var index := _school_card_at(event.position)
		if index != _hovered_school:
			_hovered_school = index
			_apply_school_cursor()
			school_screen.queue_redraw()
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		var index := _school_card_at(mouse.position)
		if index < 0 or player == null or player.magic_book == null:
			return
		player.magic_book.choose_primary(MagicBook.BASE_SCHOOLS[index])
		get_viewport().set_input_as_handled()

func _apply_school_cursor() -> void:
	if _hovered_school >= 0 and school_screen.visible:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _draw_school_screen() -> void:
	var s := school_screen.size
	if s.x < 200 or s.y < 200:
		return
	var serif := UiTheme.serif()
	var title_font := UiTheme.tracked(serif, 2)
	var caps := UiTheme.caps(3)
	var caps_tight := UiTheme.caps(1)
	var fade_in := clampf(_school_t / 0.45, 0.0, 1.0)
	var a := 1.0 - pow(1.0 - fade_in, 3.0)

	school_screen.draw_rect(Rect2(Vector2.ZERO, s), Color(0.014, 0.017, 0.024, 0.62 * a), true)

	var center := s * 0.5
	var panel := Rect2(center - Vector2(360.0, 220.0), Vector2(720.0, 440.0))
	panel.position.y += (1.0 - a) * 12.0
	UiTheme.draw_reference_panel(school_screen, panel, UiTheme.GOLD, a, 14.0)
	UiTheme.draw_crest(school_screen, Vector2(panel.position.x + panel.size.x * 0.5,
		panel.position.y - 20.0), UiTheme.GOLD, a)
	UiTheme.draw_sparkles(school_screen, panel, _time, UiTheme.GOLD, 0.7 * a)

	var cx := panel.position.x + panel.size.x * 0.5
	var top := panel.position.y

	UiTheme.draw_text_center(school_screen, title_font, cx, top + 64.0, "ВЫБОР ШКОЛЫ", 30,
		UiTheme.fade(UiTheme.PARCHMENT, a), 0.0)
	var sub := "Выбор определит первое заклинание. Остальные школы откроются позже."
	UiTheme.draw_text_center(school_screen, caps_tight, cx, top + 92.0, sub, 9,
		UiTheme.fade(UiTheme.MUTED, a), 1.0)

	_draw_school_cards(serif, caps, caps_tight, panel, a)

	UiTheme.draw_divider(school_screen, Vector2(cx, panel.end.y - 44.0), 240.0,
		UiTheme.fade(UiTheme.GOLD, 0.45 * a))
	UiTheme.draw_text_center(school_screen, caps, cx, panel.end.y - 20.0,
		"МАГИЯ БЕЗМОЛВНА — НАМЕРЕНИЯ ДОСТАТОЧНО", 8, UiTheme.fade(UiTheme.MUTED, 0.75 * a), 1.0)

func _draw_school_cards(serif: Font, caps: Font, caps_tight: Font, panel: Rect2, a: float) -> void:
	var names := ["Огонь", "Ветер", "Вода", "Земля"]
	var descs := ["ВОЛЯ В ПЛАМЕНИ", "СКОРОСТЬ ПОТОКА", "ХЛАДНОКРОВИЕ", "СИЛА ОПОРЫ"]
	var keys := ["1", "2", "3", "4"]
	var card_w := 138.0
	var gap := 16.0
	var total := card_w * 4.0 + gap * 3.0
	var x0 := panel.position.x + (panel.size.x - total) * 0.5
	var y0 := panel.position.y + 168.0
	var card_h := 178.0
	_school_card_rects.clear()

	for i in 4:
		var tint := UiTheme.school_color(i)
		var rect := Rect2(Vector2(x0 + float(i) * (card_w + gap), y0), Vector2(card_w, card_h))
		_school_card_rects.append(rect)
		var cx := rect.position.x + card_w * 0.5
		var t := clampf((_school_t - 0.12 * float(i)) / 0.5, 0.0, 1.0)
		var card_a := a * (1.0 - pow(1.0 - t, 3.0))
		var hovered := i == _hovered_school

		UiTheme.draw_reference_panel(school_screen, rect, tint,
			minf(1.0, 0.72 * card_a + (0.18 if hovered else 0.0)), 7.0)

		var sigil_center := Vector2(cx, rect.position.y + 50.0)
		var breathe := 1.0 + 0.03 * sin(_time * 1.7 + float(i) * 1.1)
		school_screen.draw_arc(sigil_center, 31.0, 0.0, TAU, 48,
			UiTheme.fade(tint, 0.20 * card_a), 1.0, true)
		UiTheme.draw_school_sigil(school_screen, sigil_center, 23.0 * breathe, i,
			UiTheme.fade(tint, card_a), 1.6)

		UiTheme.draw_text_center(school_screen, serif, cx, rect.position.y + 110.0, names[i],
			18, UiTheme.fade(UiTheme.PARCHMENT, card_a if hovered else card_a * 0.92), 1.0)
		var name_w := UiTheme.text_width(serif, names[i], 18)
		school_screen.draw_line(Vector2(cx - name_w * 0.5, rect.position.y + 118.0),
			Vector2(cx + name_w * 0.5, rect.position.y + 118.0),
			UiTheme.fade(tint, (0.95 if hovered else 0.70) * card_a), 1.0, true)
		UiTheme.draw_text_center(school_screen, caps_tight, cx, rect.position.y + 136.0,
			descs[i], 8, UiTheme.fade(UiTheme.MUTED, 0.92 * card_a), 1.0)
		UiTheme.draw_keycap(school_screen, Rect2(cx - 11.0, rect.position.y + 148.0, 22.0, 18.0),
			keys[i], UiTheme.fade(tint, card_a), 10)

# ===========================================================================
#  Экран смерти
# ===========================================================================

func _draw_death_screen() -> void:
	var s := death_screen.size
	if s.x < 200 or s.y < 200:
		return
	var serif := UiTheme.serif()
	var title_font := UiTheme.tracked(serif, 3)
	var caps_tight := UiTheme.caps(1)
	var a := clampf(_death_t / 0.7, 0.0, 1.0)
	a = 1.0 - pow(1.0 - a, 3.0)
	var center := s * 0.5

	death_screen.draw_rect(Rect2(Vector2.ZERO, s), Color(0.045, 0.010, 0.014, 0.55 * a), true)

	var panel := Rect2(center - Vector2(240.0, 120.0), Vector2(480.0, 240.0))
	UiTheme.draw_reference_panel(death_screen, panel, UiTheme.BLOOD, a, 12.0)
	UiTheme.draw_crest(death_screen, Vector2(panel.position.x + panel.size.x * 0.5,
		panel.position.y - 20.0), UiTheme.BLOOD, a)
	UiTheme.draw_sparkles(death_screen, panel, _time, UiTheme.BLOOD, 0.6 * a)

	var cx := panel.position.x + panel.size.x * 0.5
	var top := panel.position.y

	UiTheme.draw_text_center(death_screen, title_font, cx, top + 70.0, "ПУТЬ ПРЕРВАН", 30,
		UiTheme.fade(UiTheme.PARCHMENT, a), 0.0)
	UiTheme.draw_divider(death_screen, Vector2(cx, top + 100.0), 240.0,
		UiTheme.fade(UiTheme.BLOOD, 0.55 * a))

	var hint := "ВОЗРОДИТЬСЯ"
	var hint_w := UiTheme.text_width(caps_tight, hint, 9)
	var group_w := 30.0 + hint_w
	var start_x := cx - group_w * 0.5
	var cap_rect := Rect2(start_x, top + 146.0, 20.0, 17.0)
	UiTheme.draw_keycap(death_screen, cap_rect, "E", UiTheme.fade(UiTheme.GOLD, a), 10)
	var text_x := start_x + 30.0
	UiTheme.draw_text(death_screen, caps_tight, Vector2(text_x, top + 159.0), hint, 9,
		UiTheme.fade(UiTheme.PARCHMENT, 0.85 * a), 1.0)
	death_screen.draw_line(Vector2(text_x, top + 166.0), Vector2(text_x + hint_w, top + 166.0),
		UiTheme.fade(UiTheme.GOLD, 0.65 * a), 1.0, true)

# ===========================================================================
#  Состояние
# ===========================================================================

func _process(delta: float) -> void:
	if player == null:
		return
	_time += delta
	var dead := player.is_dead
	var book := player.magic_book
	var choosing := book != null and book.primary_school == -1 and not dead

	if choosing:
		_school_t += delta
	else:
		_school_t = 0.0
	if dead:
		_death_t += delta
	else:
		_death_t = 0.0

	if school_screen.visible != choosing:
		school_screen.visible = choosing
	if death_screen.visible != dead:
		death_screen.visible = dead
	if not choosing:
		_school_card_rects.clear()
		if _hovered_school != -1:
			_hovered_school = -1
			_apply_school_cursor()

	if choosing != _school_pause_active:
		_school_pause_active = choosing
		# Пауза именно игрового мира: слои выбора и ввод продолжают работать.
		get_tree().paused = choosing
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if choosing else Input.MOUSE_MODE_CAPTURED

	if choosing:
		school_screen.queue_redraw()
	if dead:
		death_screen.queue_redraw()

	if player.health < _last_health - 0.1:
		_hit_flash = 0.30
	_last_health = player.health
	_hit_flash = move_toward(_hit_flash, 0.0, delta * 1.6)

	var sid := player.spell_caster.selected_spell() if player.spell_caster else ""
	if sid != _last_spell:
		_last_spell = sid
		if sid != "" and SpellCaster.SPELLS.has(sid):
			var data: Dictionary = SpellCaster.SPELLS[sid]
			spell_name = str(data["name"])
			spell_school = book.school_name(data["school"]).to_upper() if book else ""
			spell_tint = UiTheme.school_color(data["school"])
			spell_cost = float(data["mana"])
		else:
			spell_name = "НЕТ ЗАКЛИНАНИЯ"
			spell_school = "ВЫБЕРИ ШКОЛУ"
			spell_tint = UiTheme.MUTED
			spell_cost = 0.0

	var wants_stamina := player.stamina < player.stamina_max - 0.5 and not dead
	_stamina_alpha = move_toward(_stamina_alpha, 1.0 if wants_stamina else 0.0,
		delta * (5.0 if wants_stamina else 1.5))

	hud_canvas.queue_redraw()

	if dead and Input.is_action_just_pressed("interact"):
		player.respawn()

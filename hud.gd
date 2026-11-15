extends CanvasLayer

## HUD: диегетическая «арканная» типографика без карточек и рамок вокруг
## каждого элемента. Ресурсы — тонкие полосы с золотой оправой, заклинание —
## сигнал в правом нижнем углу, прицел — маленький сигил в центре.
## Выбор школы и экран смерти рисуются здесь же, в том же языке.

@onready var player: Player = get_parent() as Player

const MARGIN := 38.0
const BAR_WIDTH := 212.0
## Тёмная заливка внутри золотой оправы окон: без неё панели «светятся".
const PANEL_TOP := Color(0.075, 0.082, 0.104, 0.96)
const PANEL_BOTTOM := Color(0.028, 0.032, 0.044, 0.98)
const PANEL_DARK := Color(0.0, 0.0, 0.0, 0.35)

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

var _scrim: GradientTexture2D
var _grad_cache: Dictionary = {}

func _ready() -> void:
	# Выбор школы должен работать, пока остальной мир стоит на паузе.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	_scrim = UiTheme.vertical_gradient(Color(0.02, 0.024, 0.032, 0.72), Color(0.012, 0.014, 0.02, 0.92))

	hud_canvas = _make_layer()
	hud_canvas.draw.connect(_draw_hud)

	school_screen = _make_layer()
	school_screen.visible = false
	school_screen.draw.connect(_draw_school_screen)

	death_screen = _make_layer()
	death_screen.visible = false
	death_screen.draw.connect(_draw_death_screen)
	_apply_interface_scale()

func set_interface_scale(value: float) -> void:
	_interface_scale = clampf(value, 0.5, 2.0)
	_apply_interface_scale()

func _apply_interface_scale() -> void:
	if not is_inside_tree():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var centered_offset := viewport_size * (1.0 - _interface_scale) * 0.5
	transform = Transform2D(Vector2(_interface_scale, 0.0),
		Vector2(0.0, _interface_scale), centered_offset)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED and is_node_ready():
		_apply_interface_scale()

func _make_layer() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c

func _exit_tree() -> void:
	if _school_pause_active and is_instance_valid(get_tree()):
		get_tree().paused = false

## Вертикальный градиент для заливки полосы, кэшируется по цвету.
func _bar_gradient(tint: Color) -> GradientTexture2D:
	var key := tint.to_html()
	if not _grad_cache.has(key):
		_grad_cache[key] = UiTheme.vertical_gradient(tint.lightened(0.42), tint.darkened(0.18))
	return _grad_cache[key]

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

	# У HUD нет глухой подложки: мир остаётся чистым и хорошо читаемым.
	_draw_edge_arms(s)
	_draw_resources(serif, caps, caps_tight, s)
	_draw_reticle(caps_tight, s)
	_draw_spell_slot(serif, caps, caps_tight, s)

## Тонкие угловые засечки по краям экрана: рамка без рамки.
func _draw_edge_arms(s: Vector2) -> void:
	var tint := Color(0.93, 0.78, 0.49, 0.20)
	var arm := 26.0
	var inset := 18.0
	var pts := [
		[Vector2(inset, inset), Vector2(1, 1)],
		[Vector2(s.x - inset, inset), Vector2(-1, 1)],
		[Vector2(s.x - inset, s.y - inset), Vector2(-1, -1)],
		[Vector2(inset, s.y - inset), Vector2(1, -1)],
	]
	for p in pts:
		var c: Vector2 = p[0]
		var d: Vector2 = p[1]
		hud_canvas.draw_line(c, c + Vector2(d.x * arm, 0.0), tint, 1.0, true)
		hud_canvas.draw_line(c, c + Vector2(0.0, d.y * arm), tint, 1.0, true)

func _draw_resources(serif: Font, caps: Font, caps_tight: Font, s: Vector2) -> void:
	var x := MARGIN + 2.0
	var base_y := s.y - MARGIN - 6.0
	var health_color := UiTheme.flash_tint(UiTheme.HEALTH, _hit_flash,
		Color(1.0, 0.72, 0.62))

	var health_ratio := clampf(player.health / maxf(player.health_max, 1.0), 0.0, 1.0)
	var mana_ratio := clampf(player.mana / maxf(player.mana_max, 1.0), 0.0, 1.0)

	_draw_resource(serif, caps, caps_tight, x, base_y, "ЗДОРОВЬЕ", player.health,
		player.health_max, health_ratio, health_color, 1.0, true)

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
		alpha: float, pulse_low: bool = false) -> void:
	var title_color := UiTheme.fade(UiTheme.MUTED, 1.0 * alpha)
	UiTheme.draw_text(hud_canvas, caps, Vector2(x, baseline), title, 9, title_color, 1.0)

	var value_text := "%d" % int(ceil(value))
	var max_text := "/ %d" % int(round(maximum))
	var max_w := UiTheme.text_width(caps_tight, max_text, 8)
	UiTheme.draw_text_right(hud_canvas, caps_tight, x + BAR_WIDTH, baseline,
		max_text, 8, UiTheme.fade(UiTheme.MUTED, 0.62 * alpha), 1.0)
	var value_color := UiTheme.fade(UiTheme.PARCHMENT.lerp(tint, 0.28), 0.96 * alpha)
	UiTheme.draw_text_right(hud_canvas, serif, x + BAR_WIDTH - max_w - 5.0, baseline + 1.0,
		value_text, 14, value_color, 1.0)

	# Дорожка: глубокая канавка с бликом сверху.
	var bar_y := baseline + 8.0
	var left := Vector2(x, bar_y)
	hud_canvas.draw_rect(Rect2(left, Vector2(BAR_WIDTH, 3.0)), Color(0.0, 0.0, 0.0, 0.34 * alpha), true)
	hud_canvas.draw_line(left, left + Vector2(BAR_WIDTH, 0.0), Color(1, 1, 1, 0.07 * alpha), 1.0, true)

	if ratio > 0.002:
		var fill_w := maxf(BAR_WIDTH * ratio, 3.0)
		if ratio < 0.3 and pulse_low:
			UiTheme.draw_glow(hud_canvas, Vector2(x + BAR_WIDTH * 0.5, bar_y + 1.0),
				BAR_WIDTH * 0.62, Color(0.8, 0.12, 0.14, (0.16 + 0.1 * sin(_time * 6.0)) * alpha))
		hud_canvas.draw_texture_rect(_bar_gradient(tint),
			Rect2(left, Vector2(fill_w, 3.0)), false, Color(1, 1, 1, alpha))
		# Световая «нить» по верхней кромке заливки.
		hud_canvas.draw_line(left + Vector2(0.0, 0.0), Vector2(x + fill_w, bar_y),
			Color(1, 1, 1, 0.30 * alpha), 1.0, true)
		# Огранённый наконечник.
		var tip := Vector2(x + fill_w, bar_y + 1.5)
		UiTheme.draw_diamond(hud_canvas, tip, 2.4, 4.2, UiTheme.fade(tint, 0.95 * alpha))

## Прицел: точка, четыре засечки; при цели — раскрытое кольцо и подсказка.
func _draw_reticle(caps: Font, s: Vector2) -> void:
	var center := s * 0.5
	var active := player.has_interact_target()
	var tint := UiTheme.GOLD if active else Color(0.94, 0.94, 0.92, 0.62)

	if active:
		var pulse := 0.5 + 0.5 * sin(_time * 3.4)
		UiTheme.draw_arcane_ring(hud_canvas, center, 15.0, UiTheme.fade(UiTheme.GOLD, 0.55),
			_time * 0.55, 16)
		hud_canvas.draw_circle(center, 1.8, tint)
		for i in 4:
			var a := _time * 1.6 + TAU * float(i) / 4.0
			var d := Vector2(cos(a), sin(a))
			UiTheme.draw_diamond(hud_canvas, center + d * (11.0 + pulse * 1.6), 1.8, 3.2,
				UiTheme.fade(UiTheme.GOLD, 0.5 + 0.35 * pulse))
		var label := "ВЗАИМОДЕЙСТВИЕ"
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

## Слот заклинания: сигил школы в золотой оправе + название и горячие клавиши.
func _draw_spell_slot(serif: Font, caps: Font, caps_tight: Font, s: Vector2) -> void:
	var rect := Rect2(Vector2(s.x - MARGIN - 250.0, s.y - MARGIN - 82.0), Vector2(250.0, 82.0))

	# Подложка: мягкий градиент, тающая к краям.
	hud_canvas.draw_rect(rect, Color(0.02, 0.024, 0.032, 0.55), true)
	hud_canvas.draw_texture_rect(_scrim, rect, false, Color(1, 1, 1, 0.5))
	UiTheme.draw_frame(hud_canvas, rect, UiTheme.fade(UiTheme.GOLD, 0.30), 14.0)

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

	UiTheme.draw_glow(hud_canvas, sigil_center, sigil_r * 1.9,
		UiTheme.fade(spell_tint, 0.16 if ready else 0.08))
	hud_canvas.draw_arc(sigil_center, sigil_r + 5.0, 0.0, TAU, 64,
		UiTheme.fade(UiTheme.GOLD, 0.26), 1.0, true)
	hud_canvas.draw_arc(sigil_center, sigil_r + 8.0, 0.0, TAU, 64,
		UiTheme.fade(spell_tint, 0.14), 1.0, true)
	if cd_total > 0.0 and cd_left > 0.001:
		var frac := clampf(1.0 - cd_left / cd_total, 0.0, 1.0)
		hud_canvas.draw_arc(sigil_center, sigil_r + 5.0, -PI * 0.5, -PI * 0.5 + TAU * frac,
			64, UiTheme.fade(spell_tint, 0.92), 2.0, true)
	UiTheme.draw_school_sigil(hud_canvas, sigil_center, sigil_r, school,
		UiTheme.fade(spell_tint, 1.0 if ready else 0.42), 1.6)

	# Разделительная нить между сигилом и текстом.
	var div_x := rect.position.x + 82.0
	hud_canvas.draw_line(Vector2(div_x, rect.position.y + 14.0), Vector2(div_x, rect.end.y - 14.0),
		UiTheme.fade(UiTheme.GOLD, 0.16), 1.0, true)

	var tx := div_x + 13.0
	var available := rect.end.x - 12.0 - tx
	UiTheme.draw_text(hud_canvas, caps, Vector2(tx, rect.position.y + 24.0), "ЗАКЛИНАНИЕ",
		8, UiTheme.fade(UiTheme.GOLD, 0.70), 1.0)
	UiTheme.draw_keycap(hud_canvas, Rect2(rect.end.x - 32.0, rect.position.y + 10.0, 20.0, 17.0),
		"F", UiTheme.GOLD, 10)

	var name_size := 18
	while name_size > 11 and UiTheme.text_width(serif, spell_name, name_size) > available:
		name_size -= 1
	UiTheme.draw_text(hud_canvas, serif, Vector2(tx, rect.position.y + 48.0), spell_name,
		name_size, UiTheme.PARCHMENT, 1.0)

	var meta := spell_school
	if spell_cost > 0.0:
		meta += "   ·   %d МАНЫ" % int(spell_cost)
	UiTheme.draw_text(hud_canvas, caps_tight, Vector2(tx, rect.position.y + 66.0), meta, 8,
		UiTheme.fade(spell_tint, 0.85), 1.0)

	UiTheme.draw_keycap(hud_canvas, Rect2(rect.end.x - 32.0, rect.end.y - 27.0, 20.0, 17.0),
		"Q", UiTheme.fade(UiTheme.MUTED, 0.95), 10)

# ===========================================================================
#  Выбор школы
# ===========================================================================

func _draw_school_screen() -> void:
	var s := school_screen.size
	if s.x < 200 or s.y < 200:
		return
	var serif := UiTheme.serif()
	var caps := UiTheme.caps(3)
	var caps_tight := UiTheme.caps(1)
	var fade_in := clampf(_school_t / 0.45, 0.0, 1.0)
	var ease_out := 1.0 - pow(1.0 - fade_in, 3.0)

	school_screen.draw_rect(Rect2(Vector2.ZERO, s), Color(0.014, 0.017, 0.024, 0.80 * ease_out), true)

	var center := s * 0.5
	UiTheme.draw_arcane_ring(school_screen, center, 300.0, UiTheme.fade(UiTheme.GOLD, 0.5 * ease_out),
		_time * 0.06, 60)

	var panel := Rect2(center - Vector2(340.0, 212.0), Vector2(680.0, 424.0))
	panel.position.y += (1.0 - ease_out) * 12.0
	var a := ease_out

	# Панель: чернильный градиент + золотая оправа с углами.
	school_screen.draw_texture_rect(UiTheme.vertical_gradient(
		UiTheme.fade(PANEL_TOP, a), UiTheme.fade(PANEL_BOTTOM, a)), panel, false)
	school_screen.draw_rect(panel, UiTheme.fade(PANEL_DARK, a), true)
	UiTheme.draw_frame(school_screen, panel, UiTheme.fade(UiTheme.GOLD, a), 30.0)

	# Внутренняя тонкая рамка-«ободок».
	var inner := panel.grow(-11.0)
	school_screen.draw_rect(inner, UiTheme.fade(Color(1, 1, 1, 0.05), a), false, 1.0, true)

	var cx := panel.position.x + panel.size.x * 0.5
	var top := panel.position.y

	UiTheme.draw_text_center(school_screen, caps, cx, top + 52.0, "НАСЛЕДИЕ   ·   I", 9,
		UiTheme.fade(UiTheme.GOLD, 0.92 * a), 1.0)

	var title := "Какой стихии доверишься?"
	UiTheme.draw_text_center(school_screen, serif, cx, top + 96.0, title, 31,
		UiTheme.fade(UiTheme.PARCHMENT, a), 1.5)

	UiTheme.draw_divider(school_screen, Vector2(cx, top + 118.0), 320.0, UiTheme.fade(UiTheme.GOLD, a))

	var sub := "Выбор определит первое заклинание. Остальные школы откроются позже."
	UiTheme.draw_text_center(school_screen, caps_tight, cx, top + 142.0, sub, 9,
		UiTheme.fade(UiTheme.MUTED, a), 1.0)

	_draw_school_cards(serif, caps, caps_tight, panel, a)

	UiTheme.draw_divider(school_screen, Vector2(cx, panel.end.y - 52.0), 260.0,
		UiTheme.fade(UiTheme.GOLD, 0.5 * a))
	UiTheme.draw_text_center(school_screen, caps, cx, panel.end.y - 26.0,
		"МАГИЯ БЕЗМОЛВНА — НАМЕРЕНИЯ ДОСТАТОЧНО", 8, UiTheme.fade(UiTheme.MUTED, 0.8 * a), 1.0)

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

	for i in 4:
		var tint := UiTheme.school_color(i)
		var rect := Rect2(Vector2(x0 + float(i) * (card_w + gap), y0), Vector2(card_w, card_h))
		var cx := rect.position.x + card_w * 0.5

		# Карточка: тёмная плашка с цветным ореолом сверху, раскрывающимся по времени.
		var t := clampf((_school_t - 0.12 * float(i)) / 0.5, 0.0, 1.0)
		var card_a := a * (1.0 - pow(1.0 - t, 3.0))
		school_screen.draw_rect(rect, Color(0.012, 0.015, 0.022, 0.55 * card_a), true)
		school_screen.draw_texture_rect(UiTheme.vertical_gradient(
			UiTheme.fade(tint, 0.16 * card_a), Color(0, 0, 0, 0)), rect, false)
		school_screen.draw_rect(rect, UiTheme.fade(tint, 0.22 * card_a), false, 1.0, true)
		# Уголки карточки.
		var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)]
		for c in 4:
			var corner: Vector2 = corners[c]
			var dx := 1.0 if c == 0 or c == 3 else -1.0
			var dy := 1.0 if c == 0 or c == 1 else -1.0
			school_screen.draw_line(corner, corner + Vector2(dx * 12.0, 0.0),
				UiTheme.fade(tint, 0.85 * card_a), 1.5, true)
			school_screen.draw_line(corner, corner + Vector2(0.0, dy * 12.0),
				UiTheme.fade(tint, 0.85 * card_a), 1.5, true)

		var sigil_center := Vector2(cx, rect.position.y + 52.0)
		var breathe := 1.0 + 0.03 * sin(_time * 1.7 + float(i) * 1.1)
		UiTheme.draw_glow(school_screen, sigil_center, 40.0 * breathe,
			UiTheme.fade(tint, 0.22 * card_a))
		school_screen.draw_arc(sigil_center, 31.0, 0.0, TAU, 48,
			UiTheme.fade(tint, 0.20 * card_a), 1.0, true)
		UiTheme.draw_school_sigil(school_screen, sigil_center, 23.0 * breathe, i,
			UiTheme.fade(tint, card_a), 1.6)

		UiTheme.draw_text_center(school_screen, serif, cx, rect.position.y + 112.0, names[i],
			18, UiTheme.fade(UiTheme.PARCHMENT, card_a), 1.0)
		UiTheme.draw_text_center(school_screen, caps_tight, cx, rect.position.y + 130.0,
			descs[i], 8, UiTheme.fade(UiTheme.MUTED, 0.92 * card_a), 1.0)

		UiTheme.draw_divider(school_screen, Vector2(cx, rect.position.y + 145.0), 56.0,
			UiTheme.fade(tint, 0.45 * card_a))
		UiTheme.draw_keycap(school_screen, Rect2(cx - 11.0, rect.position.y + 154.0, 22.0, 18.0),
			keys[i], UiTheme.fade(tint, card_a), 10)

# ===========================================================================
#  Экран смерти
# ===========================================================================

func _draw_death_screen() -> void:
	var s := death_screen.size
	if s.x < 200 or s.y < 200:
		return
	var serif := UiTheme.serif()
	var caps := UiTheme.caps(3)
	var caps_tight := UiTheme.caps(1)
	var a := clampf(_death_t / 0.7, 0.0, 1.0)
	a = 1.0 - pow(1.0 - a, 3.0)
	var center := s * 0.5

	death_screen.draw_rect(Rect2(Vector2.ZERO, s), Color(0.05, 0.012, 0.016, 0.72 * a), true)
	UiTheme.draw_arcane_ring(death_screen, center, 220.0, UiTheme.fade(UiTheme.BLOOD, 0.45 * a),
		_time * 0.05, 40)

	var panel := Rect2(center - Vector2(230.0, 108.0), Vector2(460.0, 216.0))
	death_screen.draw_texture_rect(UiTheme.vertical_gradient(
		UiTheme.fade(Color(0.085, 0.036, 0.044, 0.96), a),
		UiTheme.fade(Color(0.026, 0.014, 0.018, 0.98), a)), panel, false)
	death_screen.draw_rect(panel, UiTheme.fade(PANEL_DARK, a), true)
	UiTheme.draw_frame(death_screen, panel, UiTheme.fade(UiTheme.BLOOD, 0.85 * a), 26.0)

	var cx := panel.position.x + panel.size.x * 0.5
	var top := panel.position.y

	UiTheme.draw_text_center(death_screen, caps, cx, top + 44.0, "КОНЕЦ ЭТОЙ ЖИЗНИ", 9,
		UiTheme.fade(UiTheme.BLOOD.lightened(0.25), a), 1.0)
	UiTheme.draw_text_center(death_screen, serif, cx, top + 92.0, "Путь прерван", 34,
		UiTheme.fade(UiTheme.PARCHMENT, a), 1.5)
	UiTheme.draw_divider(death_screen, Vector2(cx, top + 114.0), 240.0,
		UiTheme.fade(UiTheme.BLOOD, 0.6 * a))

	var cap_rect := Rect2(cx - 66.0, top + 146.0, 20.0, 17.0)
	UiTheme.draw_keycap(death_screen, cap_rect, "E", UiTheme.fade(UiTheme.GOLD, a), 10)
	UiTheme.draw_text(death_screen, caps_tight, Vector2(cap_rect.end.x + 10.0, top + 159.0),
		"ВОЗРОДИТЬСЯ", 9, UiTheme.fade(UiTheme.PARCHMENT, 0.85 * a), 1.0)

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

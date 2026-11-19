class_name UiTheme
extends RefCounted

## Единый визуальный язык интерфейса.
##
## Тёмная «чернильная» палитра с золотым акцентом, серифные заголовки,
## разрядка (tracking) для малых капителей и орнаменты, нарисованные кодом.
## Всё рисуется вручную, чтобы интерфейс не выглядел как набор дефолтных
## элементов движка.

# --- Палитра ---------------------------------------------------------------

const INK := Color(0.035, 0.040, 0.052)
const INK_SOFT := Color(0.070, 0.077, 0.094)
const PARCHMENT := Color(0.914, 0.898, 0.855)
const TEXT := PARCHMENT
const MUTED := Color(0.557, 0.580, 0.635)
const GOLD := Color(0.824, 0.667, 0.388)
const GOLD_DEEP := Color(0.541, 0.435, 0.259)
const ACCENT := GOLD
const BLOOD := Color(0.847, 0.357, 0.357)
const HEALTH := BLOOD
const MANA := Color(0.373, 0.549, 0.878)
const STAMINA := Color(0.718, 0.741, 0.420)

const BG := Color(0.035, 0.040, 0.052, 0.82)
const BG_SOLID := Color(0.062, 0.069, 0.084, 0.97)
const BORDER := Color(GOLD.r, GOLD.g, GOLD.b, 0.30)

const SCHOOL_COLORS := {
	MagicBook.School.FIRE: Color(1.0, 0.482, 0.196),
	MagicBook.School.WIND: Color(0.749, 0.933, 0.949),
	MagicBook.School.WATER: Color(0.290, 0.588, 1.0),
	MagicBook.School.EARTH: Color(0.725, 0.573, 0.373),
}

# --- Шрифты ----------------------------------------------------------------

static var _serif: Font = null
static var _sans: Font = null
static var _fonts: Dictionary = {}

## Заголовки и цифры: серифный шрифт системы, с кириллицей.
static func serif() -> Font:
	if _serif == null:
		_serif = _system_font(["Georgia", "Constantia", "Palatino Linotype", "Cambria",
			"Noto Serif", "DejaVu Serif", "Times New Roman"])
	return _serif

## Текстовый интерфейсный шрифт.
static func sans() -> Font:
	if _sans == null:
		_sans = _system_font(["Segoe UI", "Inter", "Noto Sans", "DejaVu Sans", "Arial"])
	return _sans

## Малые капители с разрядкой: подписи, рубрики, подсказки.
static func caps(spacing: int = 2) -> Font:
	return tracked(sans(), spacing)

static func tracked(base: Font, spacing: int) -> Font:
	var key := "%d_%d" % [base.get_instance_id(), spacing]
	if not _fonts.has(key):
		var fv := FontVariation.new()
		fv.base_font = base
		fv.spacing_glyph = spacing
		_fonts[key] = fv
	return _fonts[key]

static func _system_font(names: Array) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.hinting = TextServer.HINTING_LIGHT
	return f

# --- Работа с цветом -------------------------------------------------------

static func fade(c: Color, k: float) -> Color:
	return Color(c.r, c.g, c.b, clampf(c.a * k, 0.0, 1.0))

## Цвет заливки ресурса, слегка высветленный вспышкой урона.
static func flash_tint(base: Color, amount: float, color: Color) -> Color:
	return base.lerp(color, clampf(amount, 0.0, 1.0))

# --- Текст -----------------------------------------------------------------

static func text_width(font: Font, text: String, size: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

## Текст с мягкой тенью вместо грубой обводки — читается и не «шумит».
static func draw_text(ci: CanvasItem, font: Font, pos: Vector2, text: String, size: int,
		color: Color, shadow: float = 1.0) -> float:
	if shadow > 0.0:
		ci.draw_string(font, pos + Vector2(0.0, shadow), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			size, Color(0.0, 0.0, 0.0, 0.55 * color.a))
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return text_width(font, text, size)

## Текст, выровненный по правому краю. Возвращает ширину.
static func draw_text_right(ci: CanvasItem, font: Font, right_edge: float, baseline: float,
		text: String, size: int, color: Color, shadow: float = 1.0) -> float:
	var w := text_width(font, text, size)
	draw_text(ci, font, Vector2(right_edge - w, baseline), text, size, color, shadow)
	return w

## Текст, выровненный по центру. Возвращает ширину.
static func draw_text_center(ci: CanvasItem, font: Font, center_x: float, baseline: float,
		text: String, size: int, color: Color, shadow: float = 1.0) -> float:
	var w := text_width(font, text, size)
	draw_text(ci, font, Vector2(center_x - w * 0.5, baseline), text, size, color, shadow)
	return w

# --- Геометрия -------------------------------------------------------------

static func diamond_points(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0.0, -ry),
		center + Vector2(rx, 0.0),
		center + Vector2(0.0, ry),
		center + Vector2(-rx, 0.0),
	])

static func draw_diamond(ci: CanvasItem, center: Vector2, rx: float, ry: float, color: Color,
		filled: bool = true) -> void:
	var pts := diamond_points(center, rx, ry)
	if filled:
		ci.draw_colored_polygon(pts, color)
	else:
		pts.append(pts[0])
		ci.draw_polyline(pts, color, 1.0, true)

static func polyline_closed(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	closed.append(points[0])
	return closed

## Клавиша-«кепка»: [E], [F], [Q].
static func draw_keycap(ci: CanvasItem, rect: Rect2, key: String, tint: Color,
		font_size: int = 10) -> void:
	ci.draw_rect(rect, Color(0.086, 0.094, 0.113, 0.88), true)
	ci.draw_rect(rect, fade(tint, 0.42), false, 1.0, true)
	ci.draw_line(rect.position + Vector2(1.0, 1.0), Vector2(rect.end.x - 1.0, rect.position.y + 1.0),
		Color(1.0, 1.0, 1.0, 0.10), 1.0, true)
	var font := caps(1)
	draw_text_center(ci, font, rect.position.x + rect.size.x * 0.5,
		rect.position.y + rect.size.y * 0.5 + font_size * 0.36, key, font_size, tint, 0.0)

# --- Орнаменты -------------------------------------------------------------

## Тонкая линия с ромбом в середине — разделитель разделов.
static func draw_divider(ci: CanvasItem, center: Vector2, width: float, tint: Color) -> void:
	var half := width * 0.5
	ci.draw_line(center - Vector2(half, 0.0), center - Vector2(5.0, 0.0), fade(tint, 0.30), 1.0, true)
	ci.draw_line(center + Vector2(5.0, 0.0), center + Vector2(half, 0.0), fade(tint, 0.30), 1.0, true)
	draw_diamond(ci, center, 3.0, 3.0, fade(tint, 0.85))
	draw_diamond(ci, center, 6.0, 6.0, fade(tint, 0.22), false)

## Рамка с усиленными углами: дешёвая по геометрии, дорогая по ощущению.
static func draw_frame(ci: CanvasItem, rect: Rect2, tint: Color, arm: float = 22.0) -> void:
	ci.draw_rect(rect, fade(tint, 0.30), false, 1.0, true)
	var inner := rect.grow(-4.0)
	ci.draw_rect(inner, fade(tint, 0.14), false, 1.0, true)
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y)]
	var dirs := [Vector2(1.0, 1.0), Vector2(-1.0, 1.0), Vector2(-1.0, -1.0), Vector2(1.0, -1.0)]
	for i in 4:
		var c: Vector2 = corners[i]
		var d: Vector2 = dirs[i]
		ci.draw_line(c, c + Vector2(d.x * arm, 0.0), fade(tint, 0.95), 1.5, true)
		ci.draw_line(c, c + Vector2(0.0, d.y * arm), fade(tint, 0.95), 1.5, true)
		draw_diamond(ci, c + d * 3.0, 2.4, 2.4, tint)

## Медленно вращающееся арканное кольцо (фон/атмосфера).
static func draw_arcane_ring(ci: CanvasItem, center: Vector2, radius: float, tint: Color,
		phase: float = 0.0, ticks: int = 48) -> void:
	ci.draw_arc(center, radius, 0.0, TAU, 96, fade(tint, 0.55), 1.0, true)
	ci.draw_arc(center, radius * 0.86, 0.0, TAU, 96, fade(tint, 0.35), 1.0, true)
	var r0 := radius * 0.86
	for i in ticks:
		var a := phase + TAU * float(i) / float(ticks)
		var dir := Vector2(cos(a), sin(a))
		var r1 := radius * (1.0 if i % 4 == 0 else 0.945)
		ci.draw_line(center + dir * r0, center + dir * r1, fade(tint, 0.30 if i % 4 != 0 else 0.75), 1.0, true)
	for i in 4:
		var a := phase * 2.0 + TAU * float(i) / 4.0
		draw_diamond(ci, center + Vector2(cos(a), sin(a)) * radius * 1.05, 3.0, 5.5, fade(tint, 0.6))

# --- Сигилы школ -----------------------------------------------------------

## Рисованный знак стихии. Тонкая линия + подсветка, без внешних ассетов.
static func draw_school_sigil(ci: CanvasItem, center: Vector2, radius: float, school: int,
		tint: Color, width: float = 1.5) -> void:
	var glow := fade(tint, 0.20)
	match school:
		MagicBook.School.FIRE:
			_tri(ci, center, radius, -PI * 0.5, tint, width)
			_tri(ci, center, radius * 0.44, PI * 0.5, fade(tint, 0.75), width * 0.8)
			for i in 3:
				var a := -PI * 0.5 + TAU * float(i) / 3.0
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(center + d * radius * 1.12, center + d * radius * 1.34, fade(tint, 0.55), width, true)
			ci.draw_circle(center, radius * 0.10, tint)
			ci.draw_circle(center, radius * 0.30, glow)
		MagicBook.School.WIND:
			for i in 3:
				var r := radius * (0.98 - 0.26 * float(i))
				var a0 := -PI * 0.92 + float(i) * 0.30
				ci.draw_arc(center, r, a0, a0 + PI * 0.92, 28, fade(tint, 1.0 - 0.24 * float(i)), width, true)
			ci.draw_circle(center + Vector2(radius * 0.10, 0.0), radius * 0.09, tint)
		MagicBook.School.WATER:
			var cr := radius * 0.58
			var cc := center + Vector2(0.0, radius * 0.26)
			ci.draw_arc(cc, cr, 0.0, TAU, 40, tint, width, true)
			var shoulder := 0.72
			ci.draw_line(cc + Vector2(-cr * shoulder, -cr * shoulder),
				center + Vector2(0.0, -radius * 0.98), tint, width, true)
			ci.draw_line(cc + Vector2(cr * shoulder, -cr * shoulder),
				center + Vector2(0.0, -radius * 0.98), tint, width, true)
			ci.draw_circle(cc + Vector2(0.0, cr * 0.15), radius * 0.11, tint)
		MagicBook.School.EARTH:
			var h := radius * 0.82
			var sq := PackedVector2Array([
				center + Vector2(-h, -h), center + Vector2(h, -h),
				center + Vector2(h, h), center + Vector2(-h, h)])
			ci.draw_polyline(polyline_closed(sq), tint, width, true)
			draw_diamond(ci, center, radius * 0.40, radius * 0.40, fade(tint, 0.85), false)
			ci.draw_line(center + Vector2(0.0, -radius * 1.02), center + Vector2(0.0, -radius * 1.24),
				fade(tint, 0.55), width, true)
		_:
			ci.draw_arc(center, radius * 0.85, 0.0, TAU, 40, tint, width, true)
			ci.draw_circle(center, radius * 0.14, tint)

static func _tri(ci: CanvasItem, center: Vector2, radius: float, rotation: float, tint: Color,
		width: float) -> void:
	var pts := PackedVector2Array()
	for i in 3:
		var a := rotation + TAU * float(i) / 3.0
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	ci.draw_polyline(polyline_closed(pts), tint, width, true)

# --- Текстуры-подложки -----------------------------------------------------

static var _glow_tex: GradientTexture2D = null

## Мягкое радиальное свечение (для подсветки сигилов).
static func glow_texture() -> GradientTexture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.34, Color(1, 1, 1, 0.42))
		_glow_tex = _radial(g)
	return _glow_tex

static func draw_glow(ci: CanvasItem, center: Vector2, radius: float, tint: Color) -> void:
	ci.draw_texture_rect(glow_texture(),
		Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, tint)

static func vertical_gradient(top: Color, bottom: Color) -> GradientTexture2D:
	var g := _gradient(top, bottom)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 8
	t.height = 256
	t.fill_from = Vector2(0.0, 0.0)
	t.fill_to = Vector2(0.0, 1.0)
	return t

static func horizontal_gradient(left: Color, right: Color) -> GradientTexture2D:
	var g := _gradient(left, right)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 8
	t.fill_from = Vector2(0.0, 0.0)
	t.fill_to = Vector2(1.0, 0.0)
	return t

static func radial_gradient(inner: Color, outer: Color) -> GradientTexture2D:
	return _radial(_gradient(inner, outer))

static func _gradient(from: Color, to: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(1, to)
	return g

static func _radial(g: Gradient) -> GradientTexture2D:
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 256
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t

static var _panel_gradient: GradientTexture2D = null

## Градиент для полупрозрачной панели-референса. Кэшируется, чтобы редкие
## перерисовки меню не создавали новую текстуру каждый кадр.
static func panel_gradient() -> GradientTexture2D:
	if _panel_gradient == null:
		_panel_gradient = vertical_gradient(
			Color(0.105, 0.138, 0.176, 0.82), Color(0.020, 0.036, 0.058, 0.90))
	return _panel_gradient

## Панель по присланному референсу: двойная волосяная рамка, срезанные углы
## и короткие перекрестия по середине сторон.
static func draw_reference_panel(ci: CanvasItem, rect: Rect2, tint: Color,
		a: float = 1.0, inset: float = 12.0) -> void:
	ci.draw_texture_rect(panel_gradient(), rect, false, Color(1, 1, 1, a))
	ci.draw_rect(rect, fade(tint, 0.52 * a), false, 1.0, true)
	var inner := rect.grow(-inset)
	ci.draw_rect(inner, fade(tint, 0.26 * a), false, 1.0, true)

	var outer_corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y)]
	var inner_corners := [inner.position, Vector2(inner.end.x, inner.position.y), inner.end,
		Vector2(inner.position.x, inner.end.y)]
	var dirs := [Vector2(1.0, 1.0), Vector2(-1.0, 1.0), Vector2(-1.0, -1.0), Vector2(1.0, -1.0)]
	for i in 4:
		var c: Vector2 = outer_corners[i]
		var ic: Vector2 = inner_corners[i]
		var d: Vector2 = dirs[i]
		ci.draw_line(c + d * 5.0, ic - d * 5.0, fade(tint, 0.70 * a), 1.0, true)

	var mid := rect.position + rect.size * 0.5
	ci.draw_line(Vector2(rect.position.x - 6.0, mid.y), Vector2(rect.position.x + 6.0, mid.y),
		fade(tint, 0.55 * a), 1.0, true)
	ci.draw_line(Vector2(rect.end.x - 6.0, mid.y), Vector2(rect.end.x + 6.0, mid.y),
		fade(tint, 0.55 * a), 1.0, true)
	ci.draw_line(Vector2(mid.x, rect.position.y - 6.0), Vector2(mid.x, rect.position.y + 6.0),
		fade(tint, 0.35 * a), 1.0, true)
	ci.draw_line(Vector2(mid.x, rect.end.y - 6.0), Vector2(mid.x, rect.end.y + 6.0),
		fade(tint, 0.35 * a), 1.0, true)

## Небольшой знак над верхней кромкой панели.
static func draw_crest(ci: CanvasItem, center: Vector2, tint: Color, a: float = 1.0) -> void:
	var gold := fade(tint, 0.92 * a)
	var r := 14.0
	for i in 3:
		var ang := -PI * 0.5 + TAU * float(i) / 3.0
		var d := Vector2(cos(ang), sin(ang))
		var c := center + d * r * 0.42
		ci.draw_arc(c, r * 0.58, ang - 1.05, ang + 1.05, 20, gold, 1.3, true)
	draw_diamond(ci, center, 3.0, 5.0, gold)

## Редкие мерцающие точки вокруг панели. Позиции фиксированы, чтобы не «дёргалось».
static func draw_sparkles(ci: CanvasItem, rect: Rect2, time: float, tint: Color,
		a: float = 1.0) -> void:
	var offsets := [
		Vector2(-0.56, -0.56), Vector2(-0.34, -0.66), Vector2(0.30, -0.62),
		Vector2(0.56, -0.48), Vector2(-0.62, -0.18), Vector2(0.62, -0.10),
		Vector2(-0.58, 0.28), Vector2(0.60, 0.34), Vector2(-0.42, 0.60),
		Vector2(0.38, 0.62), Vector2(0.06, -0.72), Vector2(-0.10, 0.68),
	]
	var center := rect.position + rect.size * 0.5
	for i in offsets.size():
		var p: Vector2 = offsets[i]
		var pos := center + Vector2(p.x * rect.size.x, p.y * rect.size.y)
		var twinkle := 0.5 + 0.5 * sin(time * 1.7 + float(i) * 1.9)
		ci.draw_circle(pos, 1.0 + 0.8 * twinkle,
			fade(tint, (0.20 + 0.45 * twinkle) * a))

## Ромбовидный «бегунок» слайдера, сгенерированный попиксельно.
static func diamond_texture(size: int, tint: Color) -> ImageTexture:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := (float(size) - 1.0) * 0.5
	for y in size:
		for x in size:
			var d := absf(float(x) - c) + absf(float(y) - c)
			var a := clampf(c - d + 0.75, 0.0, 1.0)
			if a > 0.0:
				img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, tint.a * a))
	return ImageTexture.create_from_image(img)

# --- Стили -----------------------------------------------------------------

static func box(bg: Color, border: Color = BORDER, radius: int = 8, border_w: int = 1,
		margin_h: float = 14.0, margin_v: float = 10.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	sb.anti_aliasing = true
	return sb

## Минимальный набор тем для элементов управления (слайдеры, панели).
static func build_theme() -> Theme:
	var t := Theme.new()

	t.set_font("font", "Label", sans())
	t.set_font_size("font_size", "Label", 15)
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("outline_size", "Label", 0)

	var normal := box(Color(0.055, 0.062, 0.078, 0.94), BORDER, 0, 1, 18, 11)
	var hover := box(Color(0.085, 0.095, 0.115, 0.96), fade(GOLD, 0.55), 0, 1, 18, 11)
	var pressed := box(Color(0.045, 0.052, 0.066, 1.0), fade(GOLD, 0.85), 0, 1, 18, 11)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), fade(GOLD, 0.50), 0, 1, 18, 11))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", PARCHMENT)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_font_size("font_size", "Button", 16)

	t.set_stylebox("panel", "PanelContainer", box(BG_SOLID, BORDER, 0, 1, 26, 22))

	# Слайдер: тонкая дорожка, золотая заливка, ромбовидный бегунок.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.10)
	track.set_corner_radius_all(1)
	track.content_margin_top = 2.0
	track.content_margin_bottom = 2.0
	track.anti_aliasing = true
	var fill := StyleBoxFlat.new()
	fill.bg_color = fade(GOLD, 0.85)
	fill.set_corner_radius_all(1)
	fill.content_margin_top = 2.0
	fill.content_margin_bottom = 2.0
	fill.anti_aliasing = true
	var fill_hi := fill.duplicate() as StyleBoxFlat
	fill_hi.bg_color = GOLD
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	t.set_icon("grabber", "HSlider", diamond_texture(16, fade(GOLD, 0.85)))
	t.set_icon("grabber_highlight", "HSlider", diamond_texture(16, GOLD))
	return t

## Клавиша-«кепка» как контрол (для компоновки в контейнерах).
static func keycap(text: String, font_size: int = 12) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", box(Color(1, 1, 1, 0.07), fade(GOLD, 0.42), 3, 1, 7, 2))
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", caps(1))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", GOLD)
	pc.add_child(l)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pc

static func school_color(school: int) -> Color:
	return SCHOOL_COLORS.get(school, GOLD)

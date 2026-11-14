class_name StatBar
extends Control

## Полоска ресурса для второстепенных панелей: тонкая дорожка, градиентная
## заливка, «след» после потери и огранённый наконечник — в стиле HUD.

var value: float = 100.0
var max_value: float = 100.0
var color: Color = Color.WHITE
var show_text: bool = true
var pulse_when_low: bool = false
## Толщина полосы в пикселях.
var thickness: float = 3.0

var _shown: float = 100.0
var _trail: float = 100.0
var _trail_delay: float = 0.0
var _prev: float = 100.0
var _t: float = 0.0
var _grad: GradientTexture2D

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_values(v: float, m: float) -> void:
	max_value = maxf(m, 0.001)
	value = clampf(v, 0.0, max_value)

func snap() -> void:
	_shown = value
	_trail = value
	_prev = value

func _gradient_for(tint: Color) -> GradientTexture2D:
	if _grad == null:
		_grad = UiTheme.vertical_gradient(tint.lightened(0.42), tint.darkened(0.18))
	return _grad

func _process(delta: float) -> void:
	_t += delta
	if value < _prev - 0.01:
		_trail_delay = 0.45
	_prev = value
	_shown = lerpf(_shown, value, 1.0 - exp(-14.0 * delta))
	if _trail <= value:
		_trail = value
	else:
		_trail_delay -= delta
		if _trail_delay <= 0.0:
			_trail = move_toward(_trail, value, max_value * 0.35 * delta)
	queue_redraw()

func _draw() -> void:
	var bar_h := minf(thickness, size.y)

	var track := Rect2(Vector2(0, 0), Vector2(size.x, bar_h))
	draw_rect(track, Color(0.0, 0.0, 0.0, 0.34), true)
	draw_line(track.position, track.position + Vector2(track.size.x, 0.0),
		Color(1, 1, 1, 0.07), 1.0, true)

	var col := color
	if pulse_when_low and value / max_value < 0.25:
		col = color.lerp(Color(1, 1, 1), 0.25 + 0.25 * sin(_t * 7.0))

	if _trail > _shown + 0.01:
		var tw := maxf(size.x * _trail / max_value, 2.0)
		draw_rect(Rect2(track.position, Vector2(tw, bar_h)), Color(1, 1, 1, 0.30), true)

	if _shown > 0.005:
		var fw := maxf(size.x * _shown / max_value, 2.0)
		draw_texture_rect(_gradient_for(col), Rect2(track.position, Vector2(fw, bar_h)), false)
		draw_line(track.position, track.position + Vector2(fw, 0.0), Color(1, 1, 1, 0.30),
			1.0, true)
		UiTheme.draw_diamond(self, Vector2(fw, bar_h * 0.5), 2.4, bar_h * 1.4,
			Color(col.r, col.g, col.b, 0.95))

	if show_text and size.y >= 18.0:
		var txt := "%d" % ceili(value)
		var font := UiTheme.serif()
		var fs := int(minf(size.y * 0.72, 15.0))
		UiTheme.draw_text_right(self, font, size.x, fs, txt, fs, Color(1, 1, 1, 0.95), 1.0)

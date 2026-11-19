class_name SpellScreenFx
extends ColorRect

## Экранная постобработка магии. Отдельного пост-эффекта в сцене не было
## вообще, а именно он даёт «дорогое» ощущение: работает со всем кадром, а не
## с горсткой частиц.
##
## Слои:
## - вспышка (flash) в цвет школы при касте и при попадании рядом с игроком;
## - виньетка, которая на миг сжимается — глаз фокусируется на прицеле;
## - хроматическое смещение на сильном ударе;
## - тёплое затемнение по краям у огня, холодное — у воды/ветра.

## Текущая интенсивность вспышки, 0..1. Затухает сама.
var flash: float = 0.0
var flash_color: Color = Color.WHITE
## Резкость виньетки, 0..1: поднимается при касте, отпускает через 0.3 с.
var focus: float = 0.0
## Хроматика, 0..1: только на тяжёлых ударах, иначе картинка «мылится».
var aberration: float = 0.0
## Постоянная базовая виньетка: тёмный коридор должен давить по краям.
const BASE_VIGNETTE := 0.35

static var _shader: Shader = null

static func create(host: Node) -> SpellScreenFx:
	var fx := SpellScreenFx.new()
	fx.name = "SpellScreenFx"
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.material = _material()
	host.add_child(fx)
	# ВАЖНО: родитель — CanvasLayer, а не Control. В этом случае anchors НЕ
	# раскладывают узел, и ColorRect остался бы размером 0x0 (эффект не виден).
	# Поэтому размер задаём от вьюпорта и следим за его изменением.
	fx._sync_size()
	if not fx.get_viewport().size_changed.is_connected(fx._sync_size):
		fx.get_viewport().size_changed.connect(fx._sync_size)
	return fx

func _sync_size() -> void:
	var vp := get_viewport()
	if vp != null:
		size = vp.get_visible_rect().size
		position = Vector2.ZERO

static func _material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _get_shader()
	return mat

static func _get_shader() -> Shader:
	if _shader != null:
		return _shader
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

// В Godot 4 SCREEN_TEXTURE не встроен: его нужно объявить как uniform
// с hint_screen_texture, иначе шейдер не компилируется.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 flash_color : source_color = vec4(1.0, 0.5, 0.15, 1.0);
uniform float flash = 0.0;
uniform float focus = 0.0;
uniform float aberration = 0.0;
uniform float vignette_base = 0.35;

void fragment() {
	vec2 uv = SCREEN_UV;
	// Хроматика: разводим каналы к краям кадра, а не целиком.
	vec2 offset = (uv - 0.5) * aberration * 0.02;
	float r = texture(screen_tex, uv + offset).r;
	float g = texture(screen_tex, uv).g;
	float b = texture(screen_tex, uv - offset).b;
	vec3 col = vec3(r, g, b);

	// Виньетка: базовая + сжатие на касте.
	float d = length(uv - 0.5) * 1.4142;
	float vig = smoothstep(0.45, 1.05, d) * (vignette_base + focus * 0.45);
	col *= 1.0 - vig;

	// Вспышка: складывается, но не выжигает картинку в белый.
	col = mix(col, col + flash_color.rgb * 0.65, flash * 0.85);

	COLOR = vec4(col, 1.0);
}
"""
	_shader = shader
	return shader

func _ready() -> void:
	# Постобработка не должна перехватывать мышь и жить на паузе отдельно.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true

## Вспышка каста: короткая и неяркая, это подсветка кадра, а не засветка.
func on_cast(color: Color) -> void:
	flash_color = color
	flash = maxf(flash, 0.22)
	focus = maxf(focus, 0.55)

## Удар рядом с игроком: чем ближе, тем сильнее кадр отзывается.
func on_impact(color: Color, distance: float, heavy: bool) -> void:
	var closeness := clampf(1.0 - distance / 12.0, 0.0, 1.0)
	if closeness <= 0.0:
		return
	flash_color = color
	flash = maxf(flash, 0.30 * closeness + (0.18 if heavy else 0.0))
	focus = maxf(focus, 0.35 * closeness)
	if heavy:
		aberration = maxf(aberration, 0.7 * closeness)

func _process(delta: float) -> void:
	flash = move_toward(flash, 0.0, delta * 2.6)
	focus = move_toward(focus, 0.0, delta * 3.2)
	aberration = move_toward(aberration, 0.0, delta * 2.2)
	var mat := material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("flash_color", flash_color)
	mat.set_shader_parameter("flash", flash)
	mat.set_shader_parameter("focus", focus)
	mat.set_shader_parameter("aberration", aberration)
	mat.set_shader_parameter("vignette_base", BASE_VIGNETTE)
	# Когда всё по нулям, узел ничего не рисует — экономия на полном экране.
	visible = flash > 0.001 or focus > 0.001 or aberration > 0.001

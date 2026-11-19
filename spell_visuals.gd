class_name SpellVisuals
extends RefCounted

## Внешний вид снаряда по школе магии.
##
## Раньше все четыре школы собирались одним приёмом: билборд-частицы плюс
## побольше/поменьше эмиссии. Отсюда все жалобы разом — огонь светился
## оболочкой, ветер был «частичками», вода — голубой заливкой, камень — мылом.
## Материя у школ разная, поэтому здесь у каждой свой шейдер:
##
##   огонь  — светящийся газ, яркость в ядре, тёмные остывшие края;
##   ветер  — прозрачный воздух: преломляет фон, сам почти невидим;
##   вода   — жидкость: преломление + fresnel + поглощение по толщине;
##   земля  — твёрдое тело: матовый камень, никакого свечения и rim.
##
## Разбор источников — docs/notes/spell-materials-research.md.

const KIND_FIRE := 0
const KIND_WIND := 1
const KIND_WATER := 2
const KIND_EARTH := 3

static var _shaders: Dictionary = {}


static func kind_of(visual: String) -> int:
	match visual:
		"wind":
			return KIND_WIND
		"water":
			return KIND_WATER
		"earth":
			return KIND_EARTH
	return KIND_FIRE


static func emits_light(visual: String) -> bool:
	# Светится только то, что физически излучает. Вода, воздух и камень —
	# нет: у них отражение и преломление, а не собственный свет.
	return kind_of(visual) == KIND_FIRE


static func emit_strength(visual: String) -> float:
	return 0.0 if not emits_light(visual) else 1.0


# --- Тела ------------------------------------------------------------------

## Геометрия тела. Каждая школа — своя форма, а не общий октаэдр.
static func body_mesh(visual: String) -> ArrayMesh:
	match kind_of(visual):
		KIND_WIND:
			return _air_stream()
		KIND_WATER:
			return _droplet(0.115, 0.40)
		KIND_EARTH:
			return _rock(0.175, 7)
	return _flame_spindle(0.16, 0.46)


## Пламя-веретено: тело вращения, заострённое к носу и растянутое в хвост.
## Профиль задаётся по высоте, поэтому огонь читается как вытянутый язык,
## а не как шар.
static func _flame_spindle(radius: float, length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 12
	var segments := 12
	var prev := PackedVector3Array()
	for i in rings + 1:
		var t := float(i) / float(rings)
		# Толщина: узкий нос, широкое брюхо, рваный хвост.
		var r := radius * sin(pow(t, 0.62) * PI) * (1.0 - 0.35 * t)
		# Смещение оси: пламя загибается, а не висит по линейке.
		var axis := Vector3(sin(t * 3.1) * radius * 0.45, 0.0,
			(t - 0.5) * length)
		var ring := PackedVector3Array()
		for j in segments:
			var a := TAU * float(j) / float(segments)
			# Рваная кромка: на хвосте срезаем сегменты по-разному.
			var wobble := 1.0 + 0.16 * sin(a * 5.0 + t * 9.0) * t
			ring.append(axis + Vector3(cos(a) * r * wobble, sin(a) * r * wobble, 0.0))
		if i > 0:
			for j in segments:
				var j2 := (j + 1) % segments
				var a0 := prev[j]
				var a1 := prev[j2]
				var b0 := ring[j]
				var b1 := ring[j2]
				st.add_vertex(a0); st.add_vertex(b0); st.add_vertex(b1)
				st.add_vertex(a0); st.add_vertex(b1); st.add_vertex(a1)
		prev = ring
	st.generate_normals()
	return st.commit()


## Вода: капля с тупым носом и хвостом-слезой.
static func _droplet(radius: float, length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 14
	var segments := 14
	var prev := PackedVector3Array()
	for i in rings + 1:
		var t := float(i) / float(rings)
		# Нос полукруглый, хвост вытягивается в остриё (капля в полёте).
		var r := radius * sqrt(maxf(sin(pow(t, 0.42) * PI), 0.0)) * (1.0 - 0.85 * t * t)
		var z := (t - 0.42) * length
		var ring := PackedVector3Array()
		for j in segments:
			var a := TAU * float(j) / float(segments)
			ring.append(Vector3(cos(a) * r, sin(a) * r, z))
		if i > 0:
			for j in segments:
				var j2 := (j + 1) % segments
				st.add_vertex(prev[j]); st.add_vertex(ring[j]); st.add_vertex(ring[j2])
				st.add_vertex(prev[j]); st.add_vertex(ring[j2]); st.add_vertex(prev[j2])
		prev = ring
	st.generate_normals()
	return st.commit()


## Земля: гранёный камень. Фасетки вместо гладкой сферы — силуэт жёсткий,
## нормали плоские, поэтому камень не «мылится» под светом.
static func _rock(radius: float, facets: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring_count := 3
	var points: Array = []
	for i in ring_count + 1:
		var t := float(i) / float(ring_count)
		var r := radius * (1.0 - 0.30 * cos(t * PI))
		var y := (t - 0.5) * radius * 1.7
		var ring := PackedVector3Array()
		for j in facets:
			var a := TAU * float(j) / float(facets) + float(i) * 0.31
			# Неровный вылет вершин: камень колотый, а не точеный.
			var jitter := 1.0 + 0.22 * sin(float(j) * 12.9898 + float(i) * 7.7)
			ring.append(Vector3(cos(a) * r * jitter, y + 0.06 * sin(a * 3.0),
				sin(a) * r * jitter))
		points.append(ring)
	for i in ring_count:
		var lo: PackedVector3Array = points[i]
		var hi: PackedVector3Array = points[i + 1]
		for j in facets:
			var j2 := (j + 1) % facets
			# Плоские грани: каждая треугольная фасетка получает свою нормаль.
			st.add_vertex(lo[j]); st.add_vertex(hi[j]); st.add_vertex(hi[j2])
			st.add_vertex(lo[j]); st.add_vertex(hi[j2]); st.add_vertex(lo[j2])
	st.generate_normals()
	return st.commit()


## Ветер: не отдельное «тело», а длинная струя за наконечником. Форма —
## веретено, вытянутое назад, с мягким срезом. Всё, что видит игрок, — это
## преломление фона внутри струи, поэтому геометрия обязана быть длинной и
## гладкой: короткие ленты читаются как палки.
static func _air_stream() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 16
	var segments := 14
	var prev := PackedVector3Array()
	for i in rings + 1:
		var t := float(i) / float(rings)
		# Наконечник (t=0) острый, дальше струя расширяется и тает к хвосту.
		var r := 0.105 * sin(pow(t, 0.75) * PI) * (1.0 - 0.15 * t)
		var z := (0.25 - t) * 1.8
		var ring := PackedVector3Array()
		for j in segments:
			var a := TAU * float(j) / float(segments)
			# Лёгкая волна по кромке: струя не идеальный цилиндр.
			var wobble := 1.0 + 0.10 * sin(a * 3.0 + t * 10.0)
			ring.append(Vector3(cos(a) * r * wobble, sin(a) * r * wobble, z))
		if i > 0:
			for j in segments:
				var j2 := (j + 1) % segments
				st.add_vertex(prev[j]); st.add_vertex(ring[j]); st.add_vertex(ring[j2])
				st.add_vertex(prev[j]); st.add_vertex(ring[j2]); st.add_vertex(prev[j2])
		prev = ring
	st.generate_normals()
	return st.commit()


# --- Материалы --------------------------------------------------------------

static func body_material(visual: String, tint: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _shader(kind_of(visual))
	mat.set_shader_parameter("tint", tint)
	return mat


static func _shader(kind: int) -> Shader:
	if _shaders.has(kind):
		return _shaders[kind]
	var code := _flame_shader()
	match kind:
		KIND_WIND:
			code = _air_shader()
		KIND_WATER:
			code = _liquid_shader()
		KIND_EARTH:
			code = _stone_shader()
	var shader := Shader.new()
	shader.code = code
	_shaders[kind] = shader
	return shader


## ОБЩИЕ ХЕЛПЕРЫ ШЕЙДЕРОВ -----------------------------------------------------
## 3D value noise и fbm: без внешних текстур, одинаково на любом драйвере.
const NOISE_LIB := """
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

float fbm3(vec3 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		total += vnoise(p) * amp;
		p *= 2.02;
		amp *= 0.5;
	}
	return total;
}
"""


## ОГОНЬ.
## Прокрутка текстуры читается как «слайд уезжает за кадр», поэтому здесь
## плотность строится из 3D-fbm, адвектируемой вдоль оси пламени, с эрозией по
## высоте: язык истончается к хвосту и рвётся на угли. Яркость — в ядре,
## остывшие края уходят в тёмный дым. Никакого rim-свечения по контуру.
static func _flame_shader() -> String:
	return """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.62, 0.25, 1.0);
uniform float intensity = 1.0;
uniform float speed = 1.0;

varying vec3 v_local;

""" + NOISE_LIB + """

void vertex() {
	v_local = VERTEX;
	// Пламя дышит: низкочастотное смещение вдоль нормали, тем сильнее,
	// чем дальше от носа — язык колышется, а не пульсирует целиком.
	float along = clamp((v_local.z + 0.23) / 0.46, 0.0, 1.0);
	VERTEX += NORMAL * sin(TIME * 6.0 + v_local.z * 12.0) * 0.018 * along;
	VERTEX.x += sin(TIME * 9.0 + v_local.z * 18.0) * 0.012 * along;
}

void fragment() {
	// Локальные координаты вдоль оси полёта (z) — «высота» пламени.
	float axis = clamp((v_local.z + 0.23) / 0.46, 0.0, 1.0);
	float radial = clamp(length(v_local.xy) / 0.16, 0.0, 1.0);

	// Адвекция: смещение вдоль пламени со временем. Две фазы со crossfade,
	// чтобы не было видимого перезапуска прокрутки.
	vec3 p = vec3(v_local.xy * 6.0, axis * 3.0 - TIME * speed * 2.2);
	float phase = fract(TIME * speed * 0.55);
	float d0 = fbm3(p + vec3(0.0, 0.0, -phase * 2.0));
	float d1 = fbm3(p + vec3(0.0, 0.0, -(phase - 1.0) * 2.0));
	float w = abs(phase * 2.0 - 1.0);
	float density = mix(d0, d1, w) * 1.35;

	// Эрозия по высоте: к хвосту плотность режется быстрее.
	density -= axis * 0.55;
	// Края истончаются: тело яркое в середине, к силуэту — дым.
	density -= radial * radial * 0.55;

	float heat = clamp(density, 0.0, 1.0);
	// Четырёхступенчатый ramp: тёмное тело -> оранжевый -> жёлтый -> ядро.
	vec3 body = tint.rgb * 0.45;
	vec3 hot = mix(tint.rgb, vec3(1.0, 0.86, 0.55), 0.55);
	vec3 core = vec3(1.0, 0.96, 0.86);
	vec3 col = mix(body, hot, smoothstep(0.15, 0.60, heat));
	col = mix(col, core, smoothstep(0.62, 0.95, heat));

	// Холодная кайма на самых остывших языках: без неё огонь — одно
	// оранжевое семейство и читается как пластик.
	vec3 cool = mix(tint.rgb * 0.3, vec3(0.35, 0.22, 0.30), 0.55);
	col = mix(cool, col, smoothstep(0.0, 0.22, heat));

	ALBEDO = vec3(0.06, 0.04, 0.035);
	// Светится только раскалённая часть: остывший хвост остаётся дымом.
	EMISSION = col * pow(heat, 1.35) * 3.2 * intensity;
	ALPHA = clamp(heat * 1.25, 0.0, 1.0);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
"""


## ВЕТЕР.
## Воздух невидим: видно только то, как он искажает мир. Поэтому у ветра нет
## «тела» — только длинная струя за снарядом, которая сдвигает фон по шуму и
## краем показывает «плёнку» наружу. Прошлая версия оставляла в кадре три
## крученые ленты-параллелепипеда — это читалось как геометрия, а не воздух.
static func _air_shader() -> String:
	return """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.86, 0.93, 1.0, 1.0);
uniform float distortion = 0.06;
uniform float speed = 1.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying vec3 v_local;

""" + NOISE_LIB + """

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	// along: 0 — наконечник впереди, 1 — хвост струи. Струя тянется назад,
	// поэтому за снарядом воздух «течёт» в кадре сам собой.
	float along = clamp((v_local.z + 0.9) / 1.8, 0.0, 1.0);

	// Турбулентность течёт вдоль струи и заметно быстрее снаряда: именно
	// движение возмущения, а не форма, читается как поток воздуха.
	vec3 p = vec3(v_local.xy * 5.0, along * 7.0 - TIME * speed * 7.0);
	float turb = fbm3(p);
	float fine = fbm3(p * 2.7 + vec3(0.0, 0.0, -TIME * speed * 11.0));

	// Смещение фона: единственное, что реально показывает воздух.
	vec2 offset = (vec2(turb, fine) - 0.5) * distortion * (1.0 - along * 0.45);
	vec3 behind = texture(screen_tex, SCREEN_UV + offset).rgb;

	// Границы струи по радиусу: ядро полностью прозрачное, края ловят свет.
	float radius = length(v_local.xy) / 0.115;
	float edge = smoothstep(0.35, 1.0, radius);

	// Плёнка по кромке: чуть светлее фона, чтобы форма читалась без заливки.
	vec3 film = (behind + tint.rgb * 0.22) * 0.55 + tint.rgb * 0.06;
	ALBEDO = mix(behind * 1.02, film, edge * 0.75);
	EMISSION = behind * 0.06 * (1.0 - edge);
	ALPHA = clamp(edge * (0.10 + 0.22 * turb) + turb * 0.05, 0.0, 0.5);
	ALPHA *= 1.0 - smoothstep(0.75, 1.0, along) * 0.8;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
"""


## ВОДА.
## Главная причина «краски» — в шейдере была ошибка: объявлен varying v_local,
## но не присвоен в vertex(), поэтому толщина слоя всегда была нулевой и
## поглощение не работало. Теперь толщина считается из геометрии капли, фон
## преломляется, по кромке fresnel, и всё это без постоянной альфы-заливки.
static func _liquid_shader() -> String:
	return """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.40, 0.62, 0.72, 1.0);
uniform float distortion = 0.10;
uniform float absorption = 9.0;
uniform float speed = 1.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying vec3 v_local;

""" + NOISE_LIB + """

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	// Толщина воды в этой точке: у центра капли путь луча максимален,
	// у кромки стремится к нулю. Это и делает воду объёмной.
	float radial = clamp(length(v_local.xy) / 0.115, 0.0, 1.0);
	float thickness = 0.22 * sqrt(max(1.0 - radial * radial, 0.0));

	// Рябь на поверхности: крупная медленная + мелкая быстрая.
	vec3 p = vec3(v_local.xy * 10.0, v_local.z * 5.0 - TIME * speed * 3.0);
	float nx = fbm3(p) - 0.5;
	float ny = fbm3(p + vec3(23.0, 7.0, 0.0)) - 0.5;
	float ripple = (fbm3(p * 3.1) - 0.5) * 0.35;
	float fdx = nx + ripple;
	float fdy = ny + ripple;

	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	// Schlick: у кромки отражение почти единица, в центре прозрачно.
	float fresnel = 0.02 + 0.98 * pow(1.0 - facing, 4.5);

	// Beer–Lambert: свет гасится по толщине. Красный канал гаснет сильнее —
	// именно поэтому глубина у воды сине-зелёная, а не серая.
	vec3 sigma = vec3(1.0, 0.55, 0.32) * absorption;
	vec3 transmittance = exp(-sigma * thickness);

	vec2 offset = vec2(fdx, fdy) * distortion * (0.4 + thickness);
	vec3 behind = texture(screen_tex, SCREEN_UV - offset).rgb;
	vec3 through = behind * transmittance;

	// Свет, который прошёл сквозь каплю и вышел с её дальней стороны:
	// добавляет «внутреннего» свечения жидкости, но не самосвета.
	vec3 glow_inside = tint.rgb * (1.0 - transmittance) * 0.55;

	ALBEDO = through * 0.75 + glow_inside;
	EMISSION = through * (1.0 - transmittance) * 0.5;
	// Альфа целиком из физики: где тонко — прозрачно, где толсто — плотно,
	// по кромке — отражение. Константы вроде 0.55 больше нет.
	ALPHA = clamp(0.08 + (1.0 - transmittance.r) * 0.85 + fresnel * 0.30,
		0.0, 0.96);
	ROUGHNESS = 0.02;
	METALLIC = 0.0;
	SPECULAR = 0.95;
}
"""


## ЗЕМЛЯ.
## Твёрдое тело: матовый камень с крупой, плоские грани, никакого свечения и
## никакого rim. Размытость прошлой версии шла от мягких круглых спрайтов —
## здесь силуэт задаёт геометрия.
static func _stone_shader() -> String:
	return """
shader_type spatial;
render_mode cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.50, 0.45, 0.38, 1.0);
uniform float grain_scale = 34.0;

varying vec3 v_world;

""" + NOISE_LIB + """

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Трипланарная крупа: у камня разная шероховатость на гранях, но без
	// текстур и без UV — модель процедурная.
	vec3 w = v_world * grain_scale;
	float grain = fbm3(w) * 0.5 + fbm3(w * 3.7) * 0.5;
	// Трещины: тонкие тёмные линии по крупной сетке шума.
	float crevice = smoothstep(0.62, 0.78, fbm3(w * 0.35));

	vec3 col = tint.rgb * (0.72 + grain * 0.5);
	col *= 1.0 - crevice * 0.45;

	// Мелкие осколки-вкрапления: чуть более светлые зёрна кварца.
	float quartz = step(0.86, grain);
	col = mix(col, col * 1.45 + vec3(0.05), quartz);

	// Жёсткая кромка: тонкая светлая линия по граням. Именно она даёт
	// «чёткость» камня, которую прошлая версия размывала частицами.
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float facet_edge = smoothstep(0.55, 0.85, 1.0 - facing);
	col += vec3(0.16, 0.15, 0.13) * facet_edge;

	ALBEDO = col;
	ROUGHNESS = 0.94 - quartz * 0.25;
	METALLIC = 0.0;
	SPECULAR = 0.15;
	// Лёгкий фейк-AO по нормали: низ камня темнее, объём читается даже
	// в тени, но без подсветки контура.
	AO = clamp(0.75 + NORMAL.y * 0.25, 0.45, 1.0);
	AO_LIGHT_AFFECT = 0.6;
}
"""

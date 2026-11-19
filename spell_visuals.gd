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
			return _spiral_ribbons(3)
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


## Ветер: несколько спиральных лент вдоль оси полёта. Тонкие жёсткие штрихи
## читаются как струи воздуха; равномерное облако точек — как пыль.
static func _spiral_ribbons(count: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 26
	for k in count:
		var phase := TAU * float(k) / float(count)
		var radius := 0.085 + 0.03 * float(k)
		var prev_center := Vector3.ZERO
		var prev_side := Vector3.ZERO
		for i in segs + 1:
			var t := float(i) / float(segs)
			# Лента закручивается: угол растёт вдоль оси.
			var a := phase + t * 8.4
			var taper := sin(t * PI) * 0.5 + 0.5
			var center := Vector3(cos(a) * radius * taper,
				sin(a) * radius * taper, (t - 0.5) * 0.72)
			var tangent := Vector3(cos(a + 0.35), sin(a + 0.35), 0.35).normalized()
			var side := tangent.cross(Vector3(0.0, 0.0, 1.0)).normalized() \
				* (0.010 + 0.006 * taper)
			if i > 0:
				st.add_vertex(prev_center - prev_side)
				st.add_vertex(center - side)
				st.add_vertex(center + side)
				st.add_vertex(prev_center - prev_side)
				st.add_vertex(center + side)
				st.add_vertex(prev_center + prev_side)
				# Вторая сторона ленты: видно и с изнанки (cull_disabled тоже есть,
				# но свои нормали дают верный блик с обеих сторон).
				st.add_vertex(prev_center + prev_side)
				st.add_vertex(center + side)
				st.add_vertex(center - side)
				st.add_vertex(prev_center + prev_side)
				st.add_vertex(center - side)
				st.add_vertex(prev_center - prev_side)
			prev_center = center
			prev_side = side
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
## Воздух невидим; видно только то, как он искажает мир. Поэтому тело ветра —
## тонкая плёнка, которая сдвигает SCREEN_UV по шуму (преломление). Плюс слабый
## глянцевый блик по кромке, чтобы лента не была совсем невидимой.
static func _air_shader() -> String:
	return """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.86, 0.93, 1.0, 1.0);
uniform float distortion = 0.022;
uniform float speed = 1.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying vec3 v_local;

""" + NOISE_LIB + """

void vertex() {
	v_local = VERTEX;
	// Ленты изгибаются в полёте: волна бежит по ним с носа в хвост.
	float along = clamp((v_local.z + 0.36) / 0.72, 0.0, 1.0);
	VERTEX.xy += normalize(VERTEX.xy + vec3(0.001)) \
		* sin(TIME * 7.0 * speed - along * 9.0) * 0.014;
}

void fragment() {
	float along = clamp((v_local.z + 0.36) / 0.72, 0.0, 1.0);
	// Шум течёт вдоль ленты: направление движения читается по смещению фона.
	vec3 p = vec3(v_local.xy * 8.0, along * 5.0 - TIME * speed * 6.0);
	float n = fbm3(p);
	float ripple = fbm3(p * 2.3 + vec3(0.0, 0.0, -TIME * speed * 9.0));

	// Преломление: мир за струёй сдвигается. Именно это читается как «воздух
	// движется» — частицы показывают только то, что в воздухе летит.
	vec2 offset = (vec2(n, ripple) - 0.5) * distortion;
	vec3 behind = texture(screen_tex, SCREEN_UV + offset).rgb;

	// Кромка ловит свет: очень слабый блик, ровно чтобы форма была видна.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = pow(1.0 - facing, 3.0);

	ALBEDO = tint.rgb * 0.25 + behind * 0.85;
	EMISSION = behind * 0.12;
	ALPHA = clamp(0.10 + edge * 0.30, 0.0, 0.55);
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
	SPECULAR = edge * 0.35;
}
"""


## ВОДА.
## Три вещи одновременно: преломление фона, fresnel по кромке и поглощение по
## толщине (закон Бера — Ламберта). Постоянная альфа = «голубая краска»,
## переменная по толщине = жидкость.
static func _liquid_shader() -> String:
	return """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled,
	world_vertex_coords;

uniform vec4 tint : source_color = vec4(0.42, 0.66, 0.80, 1.0);
uniform float distortion = 0.045;
uniform float absorption = 2.6;
uniform float thickest = 0.16;
uniform float speed = 1.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

varying vec3 v_local;

""" + NOISE_LIB + """

void vertex() {
	// v_local нужен фрагменту, чтобы посчитать толщину слоя воды в точке.
	v_local = VERTEX;
}

void fragment() {
	// Толщина воды в этой точке: у центра капли путь длиннее, у кромки короче.
	float radial = clamp(length(v_local.xy) / 0.115, 0.0, 1.0);
	float thickness = thickest * sqrt(max(0.0, 1.0 - radial * radial));

	// Поверхностная рябь: мелкая, быстрая, не ломает силуэт.
	vec3 p = vec3(v_local.xy * 14.0, v_local.z * 6.0 - TIME * speed * 4.0);
	float nx = fbm3(p) - 0.5;
	float ny = fbm3(p + vec3(17.0, 3.0, 0.0)) - 0.5;
	vec3 n = normalize(vec3(nx, ny, 0.65));

	float facing = clamp(dot(n, normalize(VIEW)), 0.0, 1.0);
	// Schlick: у кромки отражение, в центре — прозрачность.
	float fresnel = pow(1.0 - facing, 4.0);

	// Beer–Lambert: чем толще слой, тем сильнее гасится проходящий цвет.
	vec3 transmittance = exp(-tint.rgb * absorption * thickness * 6.0);
	vec2 offset = vec2(nx, ny) * distortion;
	vec3 behind = texture(screen_tex, SCREEN_UV - offset).rgb;
	vec3 refracted = behind * transmittance;

	// Мутная глубина: цвет воды виден только там, где слой толстый.
	vec3 volume = tint.rgb * smoothstep(0.02, thickest, thickness) * 0.55;

	ALBEDO = refracted * 0.55 + volume;
	EMISSION = refracted * (1.0 - transmittance) * 0.35;
	ALPHA = clamp(0.18 + (1.0 - transmittance.r) * 0.55 + fresnel * 0.35,
		0.0, 0.92);
	ROUGHNESS = 0.03;
	METALLIC = 0.0;
	SPECULAR = 0.9;
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

class_name SpellProjectile
extends Area3D

## Снаряд заклинания. Форма, полёт, след и попадание зависят от школы:
## огонь — искры и горение, ветер — лента-вихрь и толчок, вода — струя
## со всплеском, земля — тяжёлый осколок с пылью.

var direction: Vector3 = Vector3.FORWARD
var speed: float = 20.0
var damage: float = 10.0
var knockback: float = 0.0
var effect: String = ""
var lifetime: float = 4.0
var caster: Node3D = null
var visual: String = ""
var tint: Color = Color.WHITE

var _spent: bool = false
var _time: float = 0.0
var _mesh: MeshInstance3D = null
var _trail: GPUParticles3D = null
var _light: OmniLight3D = null
var _smoke: GPUParticles3D = null
## Медленные шлейфы пламени: второй слой огня, который остаётся в мире.
var _flames: GPUParticles3D = null
## Пул: снаряд не удаляется после попадания, а гаснет и возвращается в пул.
## Поле публичное (pooled), т.к. его выставляет пул, а не сам снаряд.
var pooled: bool = false
## Ключ материала тела: по нему пул раскладывает свободные снаряды.
var body_cache_key: String = ""
## Базовый цвет материала: пул перекрашивает снаряд, не создавая новый.
var _mesh_mat: Material = null
var _emission_base: Color = Color.WHITE

## Процедурные спрайты частиц: жёсткие геометрические силуэты с тонкой
## сглаженной кромкой (одна треть пикселя). Никаких мягких ореолов —
## графика выглядит намеренно плоской и резкой. Кэшируются на класс.
static var _particle_textures: Dictionary = {}

static func _particle_texture(kind: String) -> ImageTexture:
	if _particle_textures.has(kind):
		return _particle_textures[kind]
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (float(size) - 1.0) * 0.5
	var edge := 1.0 / c
	for y in size:
		for x in size:
			var d := Vector2(float(x) - c, float(y) - c)
			var sdf := 0.0
			match kind:
				"spark":
					# Ромб с заострёнными концами.
					sdf = maxf(absf(d.x) / (c * 0.20)
						+ absf(d.y) / (c * 0.90) * 0.18,
						absf(d.y) / (c * 0.92)) - 1.0
				"streak":
					# Узкая полоска с острыми концами.
					sdf = maxf(absf(d.x) / (c * 0.16) + absf(d.y) / (c * 1.4) * 0.25,
						absf(d.y) / (c * 0.92)) - 1.0
				"droplet":
					# Шестиугольник: читается как гранёная капля.
					sdf = maxf(absf(d.x) / (c * 0.68),
						absf(d.y) / c + absf(d.x) / (c * 1.36)) - 1.0
				"shard":
					# Треугольный осколок.
					sdf = maxf(absf(d.x) / (c * 0.62) + d.y / (c * 1.1) + 0.55,
						absf(d.y + c * 0.45) / (c * 0.55)) - 1.0
				_:
					# Гексагон для дыма и «сбора» энергии.
					sdf = maxf(absf(d.x) / (c * 0.86),
						absf(d.y) / (c * 0.96) + absf(d.x) / (c * 1.72)) - 1.0
			var a := 1.0 - smoothstep(-edge, edge, sdf)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(a, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_particle_textures[kind] = tex
	return tex

## Затухание частиц по времени жизни: яркий старт, hold, плавный уход в ноль.
static func _fade_ramp(hold: float = 0.85) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, hold, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.0)])
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	return tex

## Изменение размера частицы за жизнь: искры сдуваются, капли разлетаются.
static func _scale_curve(from: float, to: float) -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, from))
	curve.add_point(Vector2(1.0, to))
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex

## Ориентация ударного кольца по нормали поверхности (ось тора — +Y).
static func _ring_basis(normal: Vector3) -> Basis:
	if normal.dot(Vector3.UP) < -0.999:
		return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, normal))

func _ready() -> void:
	# Мир (1), интерактивные объекты (4), враги (8)
	collision_layer = 0
	collision_mask = 1 | 4 | 8
	body_entered.connect(_on_body_entered)

func _exit_tree() -> void:
	# Явно останавливаем петлю: иначе playback удерживает WAV после удаления.
	for child in get_children():
		if child is AudioStreamPlayer3D:
			(child as AudioStreamPlayer3D).stop()

## Взять/вернуть булев флаг пула явно, чтобы пул не лез в «приватное» поле.
func mark_pooled(value: bool = true) -> void:
	pooled = value

## Материал тела зависит от школы; форма у камня и огня общая, но цвет разный,
## поэтому пул различает снаряды по ключу «школа + форма».
static func body_key(visual: String) -> String:
	return visual if visual != "" else "default"

func configure() -> void:
	body_cache_key = body_key(visual)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	shape.shape = sphere
	add_child(shape)
	build_visuals()

## Светится только огонь — по названию школы, а не по конкретному заклинанию,
## чтобы производные школы (лава, молния) могли светиться, когда появятся.
func _emits_light() -> bool:
	return visual == "fire" or visual == "lava" or visual == "lightning"

## Пул переиспользует снаряд под другую школу: тело и след пересобираются,
## материалы создаются один раз за переключение, а не на каждый каст.
func rebuild_for(new_visual: String) -> void:
	if new_visual == visual and _mesh != null:
		return
	visual = new_visual
	body_cache_key = body_key(new_visual)
	if _mesh != null:
		_mesh.queue_free()
		_mesh = null
	if _trail != null:
		_trail.queue_free()
		_trail = null
	if _smoke != null:
		_smoke.queue_free()
		_smoke = null
	if _flames != null:
		_flames.queue_free()
		_flames = null
	if _light != null:
		_light.queue_free()
		_light = null
	build_visuals()

func build_visuals() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _build_mesh()
	_mesh_mat = _body_material()
	_mesh.material_override = _mesh_mat
	# Снаряд не появляется готовым: первые 60 мс он «выстреливается» из руки,
	# иначе глаз читает мгновенную подмену объекта, а не бросок.
	_mesh.scale = Vector3.ONE * 0.35
	if visual == "water":
		# CapsuleMesh длинной осью идёт по Y — поворачиваем её по полёту.
		_mesh.rotation.x = PI * 0.5
	add_child(_mesh)
	_trail = _make_trail()
	if _trail != null:
		add_child(_trail)
	if _emits_light():
		_light = OmniLight3D.new()
		_light.light_color = tint
		_light.omni_range = 5.4
		_light.light_energy = 2.6
		_light.omni_attenuation = 1.4
		# Тень у огня: без неё источник света выглядит «нарисованным», потому
		# что ничего не затеняет. Один источник с тенями коридор потянет.
		_light.shadow_enabled = true
		_light.shadow_blur = 1.2
		add_child(_light)
		_smoke = _make_smoke()
		add_child(_smoke)
		_flames = _make_flames()
		add_child(_flames)

## Перекраска без пересборки материалов: пул переиспользует тело снаряда,
## а школа у него может быть другой.
func apply_tint(new_tint: Color, new_visual: String = "") -> void:
	tint = new_tint
	if new_visual != "":
		rebuild_for(new_visual)
	if _mesh_mat is ShaderMaterial:
		var mat := _mesh_mat as ShaderMaterial
		var alpha := 1.0 if visual == "fire" else 0.72
		mat.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b, alpha))
	elif _mesh_mat is StandardMaterial3D:
		(_mesh_mat as StandardMaterial3D).albedo_color = tint
	# Частицы наследуют цвет через вершинный цвет материала — нужно обновить
	# альбедо у следов и дыма, иначе новый снаряд полетит в цвете прошлого.
	if _trail != null:
		_set_particle_color(_trail, Color(tint.r, tint.g, tint.b, 0.85))
	if _smoke != null:
		_set_particle_color(_smoke, Color(0.16, 0.14, 0.13, 0.26))
	if _flames != null:
		_set_particle_color(_flames, Color(1.0, 0.62, 0.22, 0.55))
	if _light != null:
		_light.light_color = tint

func _set_particle_color(particles: GPUParticles3D, color: Color) -> void:
	var quad := particles.draw_pass_1 as QuadMesh
	if quad == null or quad.material == null:
		return
	var mat := quad.material as StandardMaterial3D
	if mat == null:
		return
	if mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
		# Аддитивные (огонь) несут HDR-множитель, иначе glow их не видит.
		mat.albedo_color = Color(color.r, color.g, color.b,
			color.a) * Color(1.7, 1.7, 1.7, 1.0)
	else:
		mat.albedo_color = color

## Запуск полёта. Вызывается после входа в дерево, поэтому звук стартует
## ровно в момент вылета — и для нового объекта, и для взятого из пула.
func launch() -> void:
	_spent = false
	_time = 0.0
	visible = true
	set_physics_process(true)
	if _mesh != null:
		_mesh.scale = Vector3.ONE * 0.35
	if _trail != null:
		_trail.restart()
	if _smoke != null:
		_smoke.restart()
	if _flames != null:
		_flames.restart()
	var flight := SpellAudio.play_at(self, Vector3.ZERO,
		SpellAudio.flight_stream(visual), -16.0, "SpellFlightAudio")
	if flight != null:
		flight.max_distance = 18.0

## Возврат в пул: снаряд гаснет и засыпает вместо queue_free. Визуальные
## эффекты попадания уже отвязаны от снаряда и живут в сцене сами.
func _recycle() -> void:
	_spent = true
	set_physics_process(false)
	# Звуки полёта гасим сразу: висящая петля выдаёт, что объект жив.
	for child in get_children():
		if child is AudioStreamPlayer3D:
			(child as AudioStreamPlayer3D).stop()
			child.queue_free()
	if _trail != null:
		_trail.emitting = false
	if _smoke != null:
		_smoke.emitting = false
	visible = false
	if pooled:
		# Настоящий пул: убираем из сцены и держим в резерве.
		var pool := get_tree().get_first_node_in_group("spell_pool")
		if pool != null and pool.has_method("release"):
			pool.call("release", self)
			return
	queue_free()

# --- Форма снаряда ---------------------------------------------------------

func _build_mesh() -> Mesh:
	# Огонь — не один октаэдр: ядро плюс два лепестка сзади. Одно тело всегда
	# читается как наклейка, а наложение трёх объёмов даёт «клубок пламени».
	if visual == "fire":
		return _fire_body()
	match visual:
		"wind":
			return _ribbon(0.16, 0.55, 1.5)
		"water":
			var cap := CapsuleMesh.new()
			cap.radius = 0.11
			cap.height = 0.34
			cap.radial_segments = 10
			cap.rings = 6
			return cap
		"earth":
			return _octahedron(Vector3(0.19, 0.19, 0.19), 0.0)
	var fallback := SphereMesh.new()
	fallback.radius = 0.15
	fallback.height = 0.3
	return fallback

## Огненное тело: ядро + два вытянутых лепестка, сросшихся в комок.
func _fire_body() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_octahedron(st, Vector3(0.15, 0.19, 0.15), 0.10, Vector3.ZERO)
	_append_octahedron(st, Vector3(0.10, 0.26, 0.10), 0.16, Vector3(0.0, 0.0, 0.10))
	_append_octahedron(st, Vector3(0.13, 0.12, 0.13), 0.12, Vector3(0.0, 0.03, -0.09))
	st.generate_normals()
	return st.commit()

func _append_octahedron(st: SurfaceTool, size: Vector3, jitter: float, offset: Vector3) -> void:
	var pts := [
		Vector3(size.x, 0.0, 0.0), Vector3(-size.x, 0.0, 0.0),
		Vector3(0.0, size.y, 0.0), Vector3(0.0, -size.y, 0.0),
		Vector3(0.0, 0.0, size.z), Vector3(0.0, 0.0, -size.z),
	]
	if jitter > 0.0:
		for i in pts.size():
			var p: Vector3 = pts[i]
			pts[i] = p * (1.0 + sin(float(i) * 12.9898 + offset.z * 7.0) * jitter)
	var faces := [
		[2, 0, 4], [2, 4, 1], [2, 1, 5], [2, 5, 0],
		[3, 4, 0], [3, 1, 4], [3, 5, 1], [3, 0, 5],
	]
	for f in faces:
		st.add_vertex(pts[int(f[0])] + offset)
		st.add_vertex(pts[int(f[1])] + offset)
		st.add_vertex(pts[int(f[2])] + offset)

func _octahedron(size: Vector3, jitter: float) -> ArrayMesh:
	var pts := [
		Vector3(size.x, 0.0, 0.0), Vector3(-size.x, 0.0, 0.0),
		Vector3(0.0, size.y, 0.0), Vector3(0.0, -size.y, 0.0),
		Vector3(0.0, 0.0, size.z), Vector3(0.0, 0.0, -size.z),
	]
	if jitter > 0.0:
		for i in pts.size():
			var p: Vector3 = pts[i]
			pts[i] = p * (1.0 + sin(float(i) * 12.9898) * jitter)
	var faces := [
		[2, 0, 4], [2, 4, 1], [2, 1, 5], [2, 5, 0],
		[3, 4, 0], [3, 1, 4], [3, 5, 1], [3, 0, 5],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		st.add_vertex(pts[int(f[0])])
		st.add_vertex(pts[int(f[1])])
		st.add_vertex(pts[int(f[2])])
	st.generate_normals()
	return st.commit()

func _ribbon(width: float, radius: float, arc: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 8
	for i in segs:
		var a0 := -arc * 0.5 + arc * float(i) / float(segs)
		var a1 := -arc * 0.5 + arc * float(i + 1) / float(segs)
		var p0 := Vector3(sin(a0) * radius, cos(a0) * radius - radius, 0.0)
		var p1 := Vector3(sin(a1) * radius, cos(a1) * radius - radius, 0.0)
		var t0 := Vector3(cos(a0), -sin(a0), 0.0).normalized()
		var t1 := Vector3(cos(a1), -sin(a1), 0.0).normalized()
		var n0 := Vector3(-t0.y, t0.x, 0.0) * (width * 0.5)
		var n1 := Vector3(-t1.y, t1.x, 0.0) * (width * 0.5)
		var a := p0 - n0
		var b := p0 + n0
		var c := p1 + n1
		var d := p1 - n1
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)
		st.add_vertex(c); st.add_vertex(b); st.add_vertex(a)
		st.add_vertex(d); st.add_vertex(c); st.add_vertex(a)
	st.generate_normals()
	return st.commit()

## Один общий шейдер для «живых» школ: 0 — огонь, 1 — ветер, 2 — вода.
## Камень остаётся на StandardMaterial3D — ему нужен матовый шероховатый камень.
static var _spell_shader: Shader = null

static func _shader() -> Shader:
	if _spell_shader != null:
		return _spell_shader
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
// ВАЖНО: никакого unshaded. Прошлая версия рисовала снаряд поверх мира и
// подделывала свет ручным ламбертом — поэтому любая магия выглядела наклейкой.
// Теперь тело получает настоящий свет сцены, тени и блики.
render_mode blend_mix, cull_disabled, depth_draw_opaque;

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float mode = 0.0;          // 0 огонь, 1 ветер, 2 вода
uniform float speed = 1.0;
uniform float warmth = 1.0;        // насколько тело «раскалено»

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
	if (mode < 0.5) {
		// Пламя дышит: смещение по нормали на низкой частоте.
		VERTEX += NORMAL * sin(TIME * speed * 5.0 + VERTEX.y * 9.0) * 0.012;
	} else if (mode < 1.5) {
		// Ветер: лента изгибается, а не мерцает полосами.
		VERTEX.z += sin(VERTEX.x * 14.0 + TIME * speed * 4.0) * 0.02;
	}
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	// Мягкая кромка силуэта: не ступенька, а плавный переход.
	float rim = pow(1.0 - facing, 2.5);

	if (mode < 0.5) {
		// Огонь: раскалённое ядро + эмиссия > 1 уходит в узкий glow.
		// ALBEDO держим тёмным, чтобы тело читалось на фоне собственного света.
		float heat = mix(0.55, 1.0, warmth);
		ALBEDO = tint.rgb * 0.35;
		EMISSION = mix(tint.rgb, vec3(2.4, 1.5, 0.5), rim) * heat * 1.8;
		ALPHA = 1.0;
	} else if (mode < 1.5) {
		// Ветер — почти невидимый воздух: тонкая плёнка, ловящая свет.
		ALBEDO = tint.rgb;
		ROUGHNESS = 0.85;
		METALLIC = 0.0;
		ALPHA = 0.28 + rim * 0.35;
	} else {
		// Вода: гладкая, прозрачная, с сильным бликом — она обязана ловить
		// солнце и окружение. Это и есть «дорогой» вид без всякого свечения.
		ALBEDO = tint.rgb * 0.9;
		ROUGHNESS = 0.04;
		METALLIC = 0.0;
		SPECULAR = 0.85;
		// В глубине капли цвет темнее — объём читается за счёт толщины.
		ALPHA = 0.55 + rim * 0.4;
	}
}
"""
	_spell_shader = shader
	return shader

func _body_material() -> Material:
	var modes := {"fire": 0.0, "wind": 1.0, "water": 2.0}
	if modes.has(visual):
		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = _shader()
		# Огонь — единственный источник света среди тел снарядов.
		shader_mat.set_shader_parameter("tint", tint)
		shader_mat.set_shader_parameter("mode", float(modes[visual]))
		shader_mat.set_shader_parameter("warmth", 1.0)
		shader_mat.set_shader_parameter("speed",
			1.6 if visual == "wind" else 1.0)
		return shader_mat
	# Земля: обычный освещённый камень. Ключевое — он получает свет сцены
	# и отбрасывает тень; никакой эмиссии и никакого unshaded.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.metallic_specular = 0.12
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Тёплый оттенок в тенях: камень не должен проваливаться в чёрный.
	mat.rim_enabled = true
	mat.rim = 0.25
	mat.rim_tint = 0.4
	return mat

## Частицы — это материя, а не голограммы. Аддитивное свечение разрешено
## только огню: искры пламени физически излучают свет. Капли воды, пыль,
## осколки камня и полосы ветра свет НЕ излучают — они либо просвечивают,
## либо рассеивают его, поэтому рисуются обычной альфой с освещением.
## HDR-ядро (> 1.0) оставлено только огню: без него glow нечего показывать.
const ENERGY_PARTICLES := ["spark"]

static func particle_material(kind: String, color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _particle_texture(kind)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	if ENERGY_PARTICLES.has(kind):
		# Искры огня: складываются со светом и выходят за 1.0 в узкий glow.
		mat.albedo_color = Color(color.r, color.g, color.b,
			color.a) * Color(1.7, 1.7, 1.7, 1.0)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		return mat
	# Материя: освещённая, с шероховатостью или прозрачностью — по типу.
	# Билборд разворачивает квад к камере, и нормаль у него остаётся «в камеру»,
	# поэтому ламберт одинаков у всех частиц. Поворачиваем нормаль к небу:
	# тогда капля ловит блик сверху, а не выглядит плоским кружком.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.billboard_keep_scale = true
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	match kind:
		"droplet":
			# Вода просвечивает: гладкая, с лёгким отражением, но без свечения.
			mat.roughness = 0.05
			mat.metallic_specular = 0.8
		"streak":
			# Ветер — мутная плёнка, почти без блика.
			mat.roughness = 0.9
			mat.albedo_color = Color(color.r, color.g, color.b, color.a * 0.55)
		"shard":
			# Камень матовый и шершавый.
			mat.roughness = 0.95
		_:
			# Дым и пыль: мягкая точка, максимально матовая.
			mat.roughness = 1.0
			mat.albedo_texture = _soft_dot_texture()
	return mat

## Мягкий круг для дыма и пыли: плотное ядро, плавная кромка.
static var _soft_dot: ImageTexture = null

static func _soft_dot_texture() -> ImageTexture:
	if _soft_dot != null:
		return _soft_dot
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(float(size - 1) * 0.5, float(size - 1) * 0.5)
	for y in size:
		for x in size:
			var d := Vector2(float(x), float(y)).distance_to(centre) / centre.x
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a * (1.5 - 0.5 * d)))
	_soft_dot = ImageTexture.create_from_image(img)
	return _soft_dot

# --- След ------------------------------------------------------------------

func _make_trail() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "SpellTrail"
	particles.draw_passes = 1
	particles.lifetime = 0.7
	# ВАЖНО: local_coords = false. Частицы остаются в мире и отстают от
	# снаряда — только так за 22 м/с успевает родиться видимый шлейф.
	# С local_coords = true они летят вместе с ним и не накапливаются.
	particles.local_coords = false
	particles.preprocess = 0.25
	particles.visibility_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3.0, 3.0, 3.0))

	var kind := "soft"
	var base_size := 0.18
	match visual:
		"fire":
			kind = "spark"
			base_size = 0.22
		"wind":
			kind = "streak"
			base_size = 0.28
		"water":
			# Не «искры воды», а разлетающиеся брызги: мягкие капли.
			kind = "droplet"
			base_size = 0.16
		"earth":
			# Не осколки-искры, а пыль: мелкая, матовая, оседает вниз.
			kind = "soft"
			base_size = 0.34

	var quad := QuadMesh.new()
	quad.size = Vector2(base_size, base_size)
	quad.material = particle_material(kind, Color(tint.r, tint.g, tint.b, 0.85))
	particles.draw_pass_1 = quad

	var process := ParticleProcessMaterial.new()
	match visual:
		"fire":
			particles.amount = 38
			particles.lifetime = 0.8
			process.direction = Vector3(0.0, 1.0, 0.0)
			process.spread = 35.0
			process.initial_velocity_min = 0.4
			process.initial_velocity_max = 1.2
			process.gravity = Vector3(0.0, 1.5, 0.0)
		"wind":
			particles.amount = 18
			particles.lifetime = 0.45
			process.direction = Vector3(0.0, 0.0, 1.0)
			process.spread = 18.0
			process.initial_velocity_min = 0.8
			process.initial_velocity_max = 1.8
			process.gravity = Vector3.ZERO
		"water":
			particles.amount = 34
			process.direction = Vector3(0.0, 0.0, 1.0)
			process.spread = 24.0
			process.initial_velocity_min = 0.8
			process.initial_velocity_max = 1.6
			# Настоящие брызги падают: без положительной гравитации они висят
			# в воздухе и читаются как светящийся шлейф.
			process.gravity = Vector3(0.0, -6.0, 0.0)
		"earth":
			particles.amount = 24
			particles.lifetime = 1.0
			process.direction = Vector3(0.0, 0.4, 1.0)
			process.spread = 70.0
			process.initial_velocity_min = 0.1
			process.initial_velocity_max = 0.5
			process.gravity = Vector3(0.0, -0.6, 0.0)
	process.scale_min = 0.55
	process.scale_max = 1.35
	process.color_ramp = _fade_ramp(0.85)
	if visual == "earth":
		# Пыль расходится и размывается, а не съёживается в точку.
		process.scale_curve = _scale_curve(0.6, 2.6)
	elif visual == "water":
		process.scale_curve = _scale_curve(1.0, 1.2)
	else:
		process.scale_curve = _scale_curve(1.0, 0.3)
	if visual == "fire" or visual == "wind":
		process.turbulence_enabled = true
		process.turbulence_noise_strength = 0.35 if visual == "fire" else 0.5
		process.turbulence_noise_scale = 1.2
		process.turbulence_noise_speed = Vector3(0.8, 0.8, 0.8)
	particles.process_material = process
	particles.emitting = true
	return particles

## Шлейф пламени: медленные крупные языки, которые отстают от снаряда и
## складываются в объём. Одни мелкие искры на быстром объекте не читаются.
func _make_flames() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "SpellFlames"
	particles.amount = 26
	particles.lifetime = 0.55
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-2.0, -2.0, -2.0), Vector3(4.0, 4.0, 4.0))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.34, 0.34)
	quad.material = particle_material("soft", Color(1.0, 0.62, 0.22, 0.55))
	particles.draw_pass_1 = quad
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.12
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 60.0
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.5
	# Пламя всплывает медленно: шлейф не должен улетать вместе со снарядом.
	process.gravity = Vector3(0.0, 1.1, 0.0)
	process.damping_min = 1.5
	process.damping_max = 2.5
	process.scale_min = 0.7
	process.scale_max = 1.4
	process.color_ramp = _fade_ramp(0.6)
	process.scale_curve = _scale_curve(0.6, 1.9)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.55
	process.turbulence_noise_scale = 1.4
	process.turbulence_noise_speed = Vector3(0.9, 0.9, 0.9)
	particles.process_material = process
	particles.emitting = true
	return particles

## Дым за огненным снарядом: крупные тёмные частицы всплывают и расходятся.
func _make_smoke() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "SpellSmoke"
	particles.amount = 18
	particles.lifetime = 1.1
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-1.0, -1.0, -1.0), Vector3(2.0, 2.0, 2.0))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.42, 0.42)
	quad.material = particle_material("soft", Color(0.16, 0.14, 0.13, 0.26))
	particles.draw_pass_1 = quad
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 25.0
	process.initial_velocity_min = 0.3
	process.initial_velocity_max = 0.8
	process.gravity = Vector3(0.0, 0.8, 0.0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.35
	process.turbulence_noise_scale = 1.5
	process.turbulence_noise_speed = Vector3(0.7, 0.7, 0.7)
	process.scale_min = 0.4
	process.scale_max = 0.9
	process.color_ramp = _fade_ramp(0.85)
	process.scale_curve = _scale_curve(0.7, 2.4)
	particles.process_material = process
	particles.emitting = true
	return particles

# --- Полёт -----------------------------------------------------------------

## Множитель скорости по времени полёта. Постоянная скорость — главная
## причина, по которой снаряд читается как «телепорт в направлении прицела»:
## у настоящего броска есть разгон у руки и сопротивление среды.
func _speed_factor() -> float:
	match visual:
		"wind":
			# Порыв разгоняется: воздух толкает снаряд вперёд.
			return lerpf(0.65, 1.25, clampf(_time / 0.35, 0.0, 1.0))
		"water":
			# Струя быстро теряет энергию: вода тяжёлая.
			return lerpf(1.30, 0.60, clampf(_time / 0.45, 0.0, 1.0))
		"earth":
			# Брошенный камень живёт по баллистике, скорость почти не падает.
			return lerpf(0.85, 1.0, clampf(_time / 0.2, 0.0, 1.0))
	# Огонь: сгусток летит ровно, но чуть тормозит о воздух.
	return lerpf(1.0, 0.92, clampf(_time / 0.6, 0.0, 1.0))

func _physics_process(delta: float) -> void:
	_time += delta
	# Масштаб «выхлопа»: 0.35 -> 1.0 за 60 мс.
	if _mesh != null and _mesh.scale.x < 1.0:
		var grow := 1.0 - pow(1.0 - clampf(_time / 0.06, 0.0, 1.0), 3.0)
		_mesh.scale = Vector3.ONE * lerpf(0.35, 1.0, grow)
	var from := global_position
	var motion := direction * speed * _speed_factor() * delta
	match visual:
		"fire":
			motion += Vector3(sin(_time * 9.0) * 0.35, 0.45, 0.0) * delta
			if _mesh != null:
				_mesh.rotation.z += 2.2 * delta
			# Пламя не горит ровно: свет дрожит на двух частотах.
			if _light != null:
				_light.light_energy = 2.4 + 0.35 * sin(_time * 21.0) + 0.2 * sin(_time * 33.0)
		"wind":
			motion += Vector3(sin(_time * 16.0) * 1.1, cos(_time * 13.0) * 0.45, 0.0) * delta
			if _mesh != null:
				_mesh.rotation.z = sin(_time * 8.0) * 0.5
		"water":
			motion *= 0.92 + 0.16 * sin(_time * 18.0)
			motion += Vector3(0.0, -1.8, 0.0) * delta
			if _mesh != null:
				_mesh.rotation.z += 0.5 * delta
		"earth":
			# Настоящая дуга: камень сначала летит вверх, потом падает.
			# Прямая линия выдаёт «лазер», а не брошенный осколок.
			motion += Vector3(0.0, -7.5 * _time + 2.2, 0.0) * delta
			if _mesh != null:
				_mesh.rotation += Vector3(1.4, 2.2, 0.9) * delta

	var to := from + motion
	# Area3D-сигналы могут пропустить тонкое препятствие за тик — проверяем сегмент.
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.position
		var body := hit.collider as Node3D
		if body != null:
			_apply_hit(body, hit.normal)
			return
	global_position = to
	lifetime -= delta
	if lifetime <= 0.0:
		_recycle()

func _on_body_entered(body: Node3D) -> void:
	_apply_hit(body)

func _apply_hit(body: Node3D, normal: Vector3 = Vector3.ZERO) -> void:
	if _spent or body == caster or not is_instance_valid(body):
		return
	_spent = true
	if damage > 0.0 and body.has_method("take_damage"):
		body.call("take_damage", damage)
	if knockback > 0.0:
		if body is RigidBody3D:
			(body as RigidBody3D).apply_central_impulse(direction * knockback)
		elif body.has_method("apply_knockback"):
			body.call("apply_knockback", direction * knockback)
	if effect != "" and body.has_method("on_spell_effect"):
		body.call("on_spell_effect", effect)
	_spawn_impact(body, normal)
	_recycle()

# --- Попадание -------------------------------------------------------------

func _spawn_impact(body: Node3D, normal: Vector3 = Vector3.ZERO) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		scene = get_parent()
	if scene == null:
		return
	var fx := Node3D.new()
	fx.name = "SpellImpact"
	scene.add_child(fx)
	fx.global_position = global_position

	# Нормаль поверхности: кольцо ложится на стену/пол, а не висит горизонтально.
	var n := normal
	if n.length_squared() < 0.0001:
		n = -direction
	n = n.normalized()

	var ring_color := tint
	var ring_life := 0.6
	var ring_scale := 2.8
	var flash_energy := 2.5
	# Свет от удара излучает только огонь. Камень, вода и ветер не «вспыхивают»:
	# у настоящего камня — пыль и hitstop, у воды — брызги, у ветра — порыв.
	var impact_light := visual == "fire"
	match visual:
		"fire":
			ring_life = 0.6
			ring_scale = 2.4
			flash_energy = 9.0
			fx.add_child(_make_burst(34, Color(1.0, 0.55, 0.15, 0.9), 0.6, 1.8,
				0.7, 0.18, Vector3(0.0, 1.8, 0.0), 40.0, "spark"))
		"wind":
			ring_color = Color(0.80, 0.92, 1.0)
			ring_life = 0.4
			ring_scale = 4.2
			fx.add_child(_make_burst(34, Color(0.85, 0.96, 1.0, 0.7), 1.4, 3.0,
				0.45, 0.24, Vector3.ZERO, 180.0, "streak"))
		"water":
			ring_color = Color(0.45, 0.62, 0.78)
			ring_life = 0.5
			ring_scale = 2.6
			# Брызги: капли просвечивают, но не светятся — обычная альфа.
			fx.add_child(_make_burst(30, Color(0.52, 0.70, 0.88, 0.75), 0.7, 1.8,
				0.6, 0.14, Vector3(0.0, -4.5, 0.0), 70.0, "droplet"))
			var burn: Variant = body.get("burn_timer") if body != null else null
			if burn != null and float(burn) > 0.0:
				fx.add_child(_make_burst(22, Color(0.92, 0.96, 1.0, 0.45), 0.3, 0.9,
					0.7, 0.22, Vector3(0.0, 1.2, 0.0), 60.0, "soft"))
		"earth":
			ring_color = Color(0.62, 0.52, 0.40)
			ring_life = 0.7
			ring_scale = 2.0
			flash_energy = 2.0
			# Пыль: расширяющееся облако у пола, без светящихся искр.
			fx.add_child(_make_burst(26, Color(0.55, 0.47, 0.38, 0.55), 0.2, 0.8,
				1.4, 0.42, Vector3(0.0, -1.6, 0.0), 90.0, "soft"))
			fx.add_child(_make_burst(14, Color(0.48, 0.40, 0.32, 0.9), 0.6, 1.6,
				0.8, 0.14, Vector3(0.0, -3.0, 0.0), 50.0, "shard"))

	# Вспышка света в точке удара — только у огня.
	var flash: OmniLight3D = null
	if impact_light:
		flash = OmniLight3D.new()
		flash.name = "ImpactFlash"
		flash.light_color = ring_color
		flash.light_energy = flash_energy
		flash.omni_range = 6.5
		flash.omni_attenuation = 1.5
		fx.add_child(flash)

	if visual == "earth":
		_heavy_hitstop()

	# Звук удара в цвет школы + низкий саб-слой: высокий «хлопок» без низа
	# звучит дёшево, вес удара даёт именно саб.
	SpellAudio.play_at(fx, Vector3.ZERO, SpellAudio.impact_stream(visual), -6.0, "ImpactAudio")
	SpellAudio.play_at(fx, Vector3.ZERO, SpellAudio.sub_stream(visual), -10.0, "ImpactSubAudio")

	# След на поверхности: копоть, мокрое пятно, трещина. Ветер следов не оставляет.
	var decal_kind := ""
	match visual:
		"fire":
			decal_kind = "scorch"
		"water":
			decal_kind = "wet"
		"earth":
			decal_kind = "crack"
	if decal_kind != "":
		_spawn_decal(scene, n, decal_kind)

	# Тёплое/холодное пятно на полу и стенах: магия оставляет след в мире.
	_spawn_glow_pool(scene, n)

	var torus := TorusMesh.new()
	torus.inner_radius = 0.11
	torus.outer_radius = 0.17
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(ring_color.r, ring_color.g, ring_color.b,
		0.8 if impact_light else 0.55)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if impact_light:
		# Ударное кольцо огня светится вместе со вспышкой (HDR + аддитив).
		ring_mat.emission_enabled = true
		ring_mat.emission = ring_color
		ring_mat.emission_energy_multiplier = 2.2
		ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	else:
		# У земли и воды кольцо — расходящаяся волна materia: обычная альфа,
		# освещено сценой, без собственного света.
		ring_mat.roughness = 0.9
	torus.material = ring_mat
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.basis = _ring_basis(n)
	fx.add_child(ring)

	var tween := fx.create_tween()
	tween.tween_property(ring, "scale", Vector3(ring_scale, ring_scale, ring_scale), ring_life)
	tween.parallel().tween_property(ring_mat, "albedo_color",
		Color(ring_color.r, ring_color.g, ring_color.b, 0.0), ring_life)
	# Свет удара живёт двумя фазами: резкий пик (0.16 с) и длинный тёплый
	# остаток (0.5 с). Одиночная короткая вспышка не успевает «лечь» на стены,
	# поэтому помещение не реагирует на магию.
	if flash != null:
		# Отдельный твин: два Tweener на одно свойство в одном Tween
		# конфликтуют (это прямо запрещено в документации Tween).
		var ft := flash.create_tween()
		ft.tween_property(flash, "light_energy", flash_energy * 0.30, 0.14)
		ft.tween_property(flash, "light_energy", 0.0, 0.55)
	get_tree().create_timer(0.9, true, false, true).timeout.connect(fx.queue_free)

## Пятно света на поверхности: дешёвый способ показать, что удар «зажёг»
## место. Использует тот же узкий glow, что и огонь, но без частиц.
func _spawn_glow_pool(scene: Node, normal: Vector3) -> void:
	var color := tint
	var radius := 1.2
	var duration := 0.6
	var energy := 1.6
	match visual:
		"fire":
			color = Color(1.0, 0.55, 0.18)
			radius = 1.6
			duration = 0.9
			energy = 2.2
		"water":
			color = Color(0.42, 0.62, 0.86)
			radius = 1.1
			energy = 0.8
		"earth":
			color = Color(0.62, 0.52, 0.40)
			radius = 0.9
			energy = 0.5
		_:
			# Ветер не оставляет следов: он уносит их с собой.
			return
	var quad := QuadMesh.new()
	quad.size = Vector2(radius, radius)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _soft_dot_texture()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = mat
	var pool := MeshInstance3D.new()
	pool.name = "SpellGlowPool"
	pool.mesh = quad
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(pool)
	pool.global_position = global_position + normal * 0.03
	pool.global_transform.basis = _ring_basis(normal)
	pool.global_position = global_position + normal * 0.03
	var tw := pool.create_tween()
	tw.tween_property(mat, "albedo_color",
		Color(color.r, color.g, color.b, 0.0), duration)
	tw.tween_callback(pool.queue_free)

## Короткий hitstop для тяжёлого удара камня. Таймер игнорирует time_scale
## (иначе при замедлении F3 пауза растягивается), исходный масштаб возвращается.
static var _hitstop_active: bool = false

func _heavy_hitstop() -> void:
	if _hitstop_active:
		return
	_hitstop_active = true
	var previous := Engine.time_scale
	Engine.time_scale = 0.15
	get_tree().create_timer(0.045, true, false, true).timeout.connect(func() -> void:
		Engine.time_scale = previous
		_hitstop_active = false)

# --- Следы на поверхностях ---------------------------------------------------

static var _decal_textures: Dictionary = {}

## Процедурные текстуры декалей: копоть с рваными краями, мокрое пятно,
## звёздная трещина. Кэшируются на класс.
static func _decal_texture(kind: String) -> ImageTexture:
	if _decal_textures.has(kind):
		return _decal_textures[kind]
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (float(size) - 1.0) * 0.5
	var base := Color(0.05, 0.04, 0.03)
	match kind:
		"wet":
			base = Color(0.05, 0.08, 0.12)
		"crack":
			base = Color(0.09, 0.07, 0.05)
	for y in size:
		for x in size:
			var d := Vector2(float(x) - c, float(y) - c) / c
			var r := d.length()
			var a := 0.0
			match kind:
				"scorch":
					# Угловая звезда вместо размытой копоти.
					var theta := atan2(d.y, d.x)
					var s := r * (0.88 + 0.16 * cos(theta * 7.0))
					a = 1.0 - smoothstep(0.96, 1.04, s)
				"wet":
					# Гексагон.
					var s2 := maxf(absf(d.x) / 0.86,
						absf(d.y) / 0.96 + absf(d.x) / 1.72)
					a = 1.0 - smoothstep(0.96, 1.04, s2)
				"crack":
					var theta2 := atan2(d.y, d.x)
					var line := 1.0 - smoothstep(0.05, 0.09,
						absf(sin(theta2 * 3.0 + r * 3.0)))
					a = line * (1.0 - smoothstep(0.90, 1.0, r))
			img.set_pixel(x, y, Color(base.r, base.g, base.b, clampf(a, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_decal_textures[kind] = tex
	return tex

static func _hash2(x: int, y: int) -> float:
	var h := sin(float(x) * 12.9898 + float(y) * 78.233) * 43758.5453
	return h - floorf(h)

## Декаль живёт дольше вспышки: ложится по нормали, ориентируется по полёту,
## через несколько секунд плавно выцветает и удаляется.
func _spawn_decal(scene: Node, normal: Vector3, kind: String) -> void:
	var decal := Decal.new()
	decal.name = "SpellDecal"
	decal.texture_albedo = _decal_texture(kind)
	var size := 1.1
	match kind:
		"wet":
			size = 1.3
		"crack":
			size = 0.9
	decal.size = Vector3(size, size, 0.35)
	scene.add_child(decal)
	decal.global_position = global_position + normal * 0.05
	# Ось проекции декали (-Z) смотрит внутрь поверхности.
	var up := direction - normal * direction.dot(normal)
	if up.length_squared() < 0.001:
		up = Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT
	var gt := decal.global_transform
	gt.basis = Basis.looking_at(-normal, up.normalized())
	decal.global_transform = gt
	# Случайный поворот вокруг нормали, чтобы следы не повторялись.
	decal.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	var fade := decal.create_tween()
	fade.tween_interval(7.0)
	fade.tween_property(decal, "modulate", Color(1.0, 1.0, 1.0, 0.0), 2.0)
	get_tree().create_timer(9.5, true, false, true).timeout.connect(decal.queue_free)

func _make_burst(count: int, color: Color, speed_min: float, speed_max: float,
		life: float, size: float, gravity: Vector3, spread: float,
		kind: String = "soft") -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = count
	particles.draw_passes = 1
	particles.lifetime = life
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-2.0, -2.0, -2.0), Vector3(4.0, 4.0, 4.0))
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = particle_material(kind, color)
	particles.draw_pass_1 = quad

	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = spread
	process.initial_velocity_min = speed_min
	process.initial_velocity_max = speed_max
	process.gravity = gravity
	process.scale_min = 0.6
	process.scale_max = 1.3
	process.color_ramp = _fade_ramp(0.85)
	var scale_from := 1.0
	var scale_to := 0.5
	match kind:
		"spark":
			scale_to = 0.12
		"droplet":
			scale_from = 0.7
			scale_to = 1.4
		"streak":
			scale_to = 0.45
		"shard":
			scale_to = 0.3
	process.scale_curve = _scale_curve(scale_from, scale_to)
	if kind == "spark" or kind == "streak":
		process.turbulence_enabled = true
		process.turbulence_noise_strength = 0.4 if kind == "spark" else 0.6
		process.turbulence_noise_scale = 1.0
		process.turbulence_noise_speed = Vector3(1.0, 1.0, 1.0)
	particles.process_material = process
	particles.emitting = true
	return particles

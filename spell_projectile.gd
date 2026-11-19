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
	# Звук полёта запускается только после входа в дерево (иначе play() ошибется).
	var flight := SpellAudio.play_at(self, Vector3.ZERO,
		SpellAudio.flight_stream(visual), -16.0, "SpellFlightAudio")
	if flight != null:
		flight.max_distance = 18.0

func _exit_tree() -> void:
	# Явно останавливаем петлю: иначе playback удерживает WAV после удаления.
	for child in get_children():
		if child is AudioStreamPlayer3D:
			(child as AudioStreamPlayer3D).stop()

func configure() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	shape.shape = sphere
	add_child(shape)

	_mesh = MeshInstance3D.new()
	_mesh.mesh = _build_mesh()
	_mesh.material_override = _body_material()
	if visual == "water":
		# CapsuleMesh длинной осью идёт по Y — поворачиваем её по полёту.
		_mesh.rotation.x = PI * 0.5
	add_child(_mesh)

	_trail = _make_trail()
	if _trail != null:
		add_child(_trail)

	_light = OmniLight3D.new()
	_light.light_color = tint
	_light.omni_range = 3.4 if visual == "earth" else 4.0
	_light.light_energy = 0.8 if visual == "wind" else 1.0
	add_child(_light)

	if visual == "fire":
		add_child(_make_smoke())

# --- Форма снаряда ---------------------------------------------------------

func _build_mesh() -> Mesh:
	match visual:
		"fire":
			return _octahedron(Vector3(0.17, 0.20, 0.17), 0.14)
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
render_mode unshaded, cull_disabled;

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float mode = 0.0;
uniform float speed = 1.0;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
	// Квадратная волна вместо плавного шума: форма дёргается, а не дышит.
	if (mode < 0.5) {
		VERTEX += NORMAL * step(0.4, sin(TIME * speed * 9.0 + VERTEX.y * 14.0)) * 0.025;
	} else if (mode < 1.5) {
		VERTEX.z += sin(VERTEX.x * 26.0 + TIME * speed * 11.0) * 0.02;
	}
}

void fragment() {
	// Плоские грани, жёсткий контур по краю силуэта — никаких градиентов шума.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = step(0.80, 1.0 - facing);
	float facet = step(0.0, NORMAL.y) * 0.12;
	vec3 col = tint.rgb * (0.85 + facet);
	if (mode < 0.5) {
		float band = step(0.0, sin(v_local.y * 26.0 - TIME * speed * 12.0));
		col = mix(col, vec3(1.0, 0.90, 0.55), band * 0.35);
	} else if (mode < 1.5) {
		float band = step(0.0, sin(v_local.x * 30.0 - TIME * speed * 14.0));
		col *= 0.70 + 0.30 * band;
	} else {
		float band = step(0.0, sin(v_local.y * 24.0 - TIME * speed * 10.0));
		col *= 0.85 + 0.15 * band;
	}
	col = mix(col, vec3(1.0), rim * 0.85);
	ALBEDO = col;
	ALPHA = tint.a;
}
"""
	_spell_shader = shader
	return shader

func _body_material() -> Material:
	var modes := {"fire": 0.0, "wind": 1.0, "water": 2.0}
	if modes.has(visual):
		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = _shader()
		var shader_tint := Color(tint.r, tint.g, tint.b,
			0.55 if visual == "wind" or visual == "water" else 1.0)
		shader_mat.set_shader_parameter("tint", shader_tint)
		shader_mat.set_shader_parameter("mode", float(modes[visual]))
		shader_mat.set_shader_parameter("speed",
			1.6 if visual == "wind" else 1.0)
		return shader_mat
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(tint.r, tint.g, tint.b,
		0.72 if visual == "wind" or visual == "water" else 1.0)
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 1.2 if visual == "fire" else 0.7
	mat.roughness = 0.3
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if visual == "wind" or visual == "water":
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

## Все частицы — альфа-cutout: чёткий силуэт, никаких полупрозрачных ореолов.
## Цвет ramp перемножается с альбедо только для выцветания, не для размытия.
func _particle_material(kind: String, color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _particle_texture(kind)
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.alpha_scissor_threshold = 0.5
	mat.vertex_color_use_as_albedo = true
	return mat

# --- След ------------------------------------------------------------------

func _make_trail() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "SpellTrail"
	# Один проход: никаких мягких ядер и аддитивных ореолов.
	particles.draw_passes = 1
	particles.lifetime = 0.45
	particles.local_coords = false
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
			kind = "droplet"
			base_size = 0.20
		"earth":
			kind = "shard"
			base_size = 0.24

	var quad := QuadMesh.new()
	quad.size = Vector2(base_size, base_size)
	quad.material = _particle_material(kind, Color(tint.r, tint.g, tint.b, 0.85))
	particles.draw_pass_1 = quad

	var process := ParticleProcessMaterial.new()
	match visual:
		"fire":
			particles.amount = 30
			particles.lifetime = 0.55
			process.direction = Vector3(0.0, 1.0, 0.0)
			process.spread = 35.0
			process.initial_velocity_min = 0.4
			process.initial_velocity_max = 1.2
			process.gravity = Vector3(0.0, 1.5, 0.0)
		"wind":
			particles.amount = 22
			particles.lifetime = 0.28
			process.direction = Vector3(0.0, 0.0, 1.0)
			process.spread = 18.0
			process.initial_velocity_min = 0.8
			process.initial_velocity_max = 1.8
			process.gravity = Vector3.ZERO
		"water":
			particles.amount = 26
			process.direction = Vector3(0.0, 0.0, 1.0)
			process.spread = 28.0
			process.initial_velocity_min = 0.5
			process.initial_velocity_max = 1.1
			process.gravity = Vector3(0.0, -1.0, 0.0)
		"earth":
			particles.amount = 24
			particles.lifetime = 0.7
			process.direction = Vector3(0.0, 0.3, 1.0)
			process.spread = 45.0
			process.initial_velocity_min = 0.2
			process.initial_velocity_max = 0.7
			process.gravity = Vector3(0.0, -2.0, 0.0)
	process.scale_min = 0.55
	process.scale_max = 1.35
	process.color_ramp = _fade_ramp(0.85)
	process.scale_curve = _scale_curve(1.0, 1.2 if visual == "water" else 0.3)
	if visual == "fire" or visual == "wind":
		process.turbulence_enabled = true
		process.turbulence_noise_strength = 0.35 if visual == "fire" else 0.5
		process.turbulence_noise_scale = 1.2
		process.turbulence_noise_speed = Vector3(0.8, 0.8, 0.8)
	particles.process_material = process
	particles.emitting = true
	return particles

## Дым за огненным снарядом: крупные тёмные частицы всплывают и расходятся.
func _make_smoke() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "SpellSmoke"
	particles.amount = 12
	particles.lifetime = 0.65
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-1.0, -1.0, -1.0), Vector3(2.0, 2.0, 2.0))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.36, 0.36)
	quad.material = _particle_material("soft", Color(0.18, 0.16, 0.15, 0.20))
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
	process.scale_curve = _scale_curve(0.6, 1.8)
	particles.process_material = process
	particles.emitting = true
	return particles

# --- Полёт -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_time += delta
	var from := global_position
	var motion := direction * speed * delta
	match visual:
		"fire":
			motion += Vector3(sin(_time * 9.0) * 0.35, 0.45, 0.0) * delta
			if _mesh != null:
				_mesh.rotation.z += 2.2 * delta
			# Пламя не горит ровно: свет дрожит на двух частотах.
			if _light != null:
				_light.light_energy = 0.8 + 0.22 * sin(_time * 21.0) + 0.13 * sin(_time * 33.0)
		"wind":
			motion += Vector3(sin(_time * 16.0) * 1.1, cos(_time * 13.0) * 0.45, 0.0) * delta
			if _mesh != null:
				_mesh.rotation.z = sin(_time * 8.0) * 0.5
		"water":
			motion *= 0.92 + 0.16 * sin(_time * 18.0)
			if _mesh != null:
				_mesh.rotation.z += 0.5 * delta
		"earth":
			motion += Vector3(0.0, -1.6, 0.0) * delta
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
		queue_free()

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
	queue_free()

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
	var ring_life := 0.4
	var ring_scale := 2.8
	var flash_energy := 2.5
	match visual:
		"fire":
			ring_life = 0.45
			ring_scale = 2.4
			flash_energy = 4.5
			fx.add_child(_make_burst(26, Color(1.0, 0.55, 0.15, 0.9), 0.5, 1.4,
				0.55, 0.16, Vector3(0.0, 1.8, 0.0), 40.0, "spark"))
		"wind":
			ring_color = Color(0.80, 0.95, 1.0)
			ring_life = 0.28
			ring_scale = 4.2
			flash_energy = 2.0
			fx.add_child(_make_burst(30, Color(0.85, 0.96, 1.0, 0.7), 1.2, 2.6,
				0.35, 0.22, Vector3.ZERO, 180.0, "streak"))
		"water":
			ring_color = Color(0.35, 0.65, 1.0)
			ring_life = 0.35
			ring_scale = 2.6
			flash_energy = 2.8
			fx.add_child(_make_burst(28, Color(0.45, 0.72, 1.0, 0.85), 0.6, 1.6,
				0.5, 0.16, Vector3(0.0, -2.0, 0.0), 70.0, "droplet"))
			var burn: Variant = body.get("burn_timer") if body != null else null
			if burn != null and float(burn) > 0.0:
				fx.add_child(_make_burst(22, Color(0.92, 0.96, 1.0, 0.45), 0.3, 0.9,
					0.7, 0.22, Vector3(0.0, 1.2, 0.0), 60.0, "soft"))
		"earth":
			ring_color = Color(0.62, 0.52, 0.40)
			ring_life = 0.5
			ring_scale = 2.0
			flash_energy = 1.2
			fx.add_child(_make_burst(32, Color(0.53, 0.44, 0.33, 0.85), 0.3, 1.0,
				0.75, 0.24, Vector3(0.0, -2.5, 0.0), 80.0, "shard"))

	# Вспышка света в точке удара: коридор реагирует на попадание.
	var flash := OmniLight3D.new()
	flash.name = "ImpactFlash"
	flash.light_color = ring_color
	flash.light_energy = flash_energy
	flash.omni_range = 5.0
	fx.add_child(flash)

	if visual == "earth":
		_heavy_hitstop()

	# Звук удара в цвет школы.
	SpellAudio.play_at(fx, Vector3.ZERO, SpellAudio.impact_stream(visual), -6.0, "ImpactAudio")

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

	var torus := TorusMesh.new()
	torus.inner_radius = 0.11
	torus.outer_radius = 0.17
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(ring_color.r, ring_color.g, ring_color.b, 0.8)
	ring_mat.emission_enabled = true
	ring_mat.emission = ring_color
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	torus.material = ring_mat
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.basis = _ring_basis(n)
	fx.add_child(ring)

	var tween := fx.create_tween()
	tween.tween_property(ring, "scale", Vector3(ring_scale, ring_scale, ring_scale), ring_life)
	tween.parallel().tween_property(ring_mat, "albedo_color",
		Color(ring_color.r, ring_color.g, ring_color.b, 0.0), ring_life)
	tween.parallel().tween_property(flash, "light_energy", 0.0, ring_life * 1.1)
	get_tree().create_timer(0.9, true, false, true).timeout.connect(fx.queue_free)

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
	quad.material = _particle_material(kind, color)
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

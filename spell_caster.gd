class_name SpellCaster
extends Node

## Безмолвное колдовство: ни слов, ни жестов — только намерение.
## F/Q и 1–4 на клавиатуре или назначения геймпада из InputMap.

signal spell_cast(spell_id: String)
signal selected_changed(spell_id: String)

const M := MagicBook.School

## Антиципация перед вылетом снаряда: короткий «сбор» энергии и отдача камеры.
const CAST_WINDUP := 0.12

## Заклинания. noise — шум для стелса (магия безмолвна, поэтому по умолчанию почти 0).
const SPELLS: Dictionary = {
	"fire_bolt": {"name": "Огненный сгусток", "school": M.FIRE, "mana": 15.0, "cooldown": 0.6,
		"damage": 20.0, "speed": 22.0, "knockback": 0.0, "effect": "ignite", "visual": "fire",
		"color": Color(1.0, 0.45, 0.1), "noise": 0.05},
	"wind_gust": {"name": "Порыв ветра", "school": M.WIND, "mana": 10.0, "cooldown": 0.5,
		"damage": 2.0, "speed": 30.0, "knockback": 12.0, "effect": "push", "visual": "wind",
		"color": Color(0.8, 0.95, 1.0), "noise": 0.0},
	"water_jet": {"name": "Водяная струя", "school": M.WATER, "mana": 10.0, "cooldown": 0.4,
		"damage": 8.0, "speed": 26.0, "knockback": 3.0, "effect": "extinguish", "visual": "water",
		"color": Color(0.2, 0.5, 1.0), "noise": 0.05},
	"stone_shard": {"name": "Каменный осколок", "school": M.EARTH, "mana": 20.0, "cooldown": 0.9,
		"damage": 25.0, "speed": 16.0, "knockback": 6.0, "effect": "", "visual": "earth",
		"color": Color(0.5, 0.4, 0.3), "noise": 0.15},
}

@onready var player: Player = get_parent() as Player

var cooldown_timer: float = 0.0
var selected_index: int = 0
## Множитель скорости снарядов: меняется в режиме отладки (F3 в HUD).
var speed_multiplier: float = 1.0
## Шум от последнего колдовства, затухает; учитывается в Player.get_noise_level().
var magic_noise: float = 0.0

func _ready() -> void:
	# Даёт выбрать школу клавишами 1–4, пока мир стоит на паузе.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_add_actions()

func _add_actions() -> void:
	var keys := {"cast_spell": KEY_F, "next_spell": KEY_Q,
		"pick_school_1": KEY_1, "pick_school_2": KEY_2,
		"pick_school_3": KEY_3, "pick_school_4": KEY_4}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			var ev := InputEventKey.new()
			ev.physical_keycode = keys[action]
			InputMap.action_add_event(action, ev)

	var joypad_events := {
		"cast_spell": _joy_axis_event(JOY_AXIS_TRIGGER_RIGHT, 1.0),
		"next_spell": _joy_button_event(JOY_BUTTON_RIGHT_SHOULDER),
		"pick_school_1": _joy_button_event(JOY_BUTTON_DPAD_UP),
		"pick_school_2": _joy_button_event(JOY_BUTTON_DPAD_RIGHT),
		"pick_school_3": _joy_button_event(JOY_BUTTON_DPAD_DOWN),
		"pick_school_4": _joy_button_event(JOY_BUTTON_DPAD_LEFT),
	}
	for action in joypad_events:
		var has_joypad := false
		for existing in InputMap.action_get_events(action):
			if existing is InputEventJoypadButton or existing is InputEventJoypadMotion:
				has_joypad = true
				break
		if not has_joypad:
			InputMap.action_add_event(action, joypad_events[action])

func _joy_axis_event(axis: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event

func _joy_button_event(button: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event

## Доступные игроку заклинания (по изученным школам).
func available_spells() -> Array[String]:
	var result: Array[String] = []
	if player == null or player.magic_book == null:
		return result
	for id in SPELLS:
		if player.magic_book.has_school(SPELLS[id]["school"]):
			result.append(id)
	return result

func selected_spell() -> String:
	var list := available_spells()
	if list.is_empty():
		return ""
	return list[selected_index % list.size()]

func _process(delta: float) -> void:
	if player == null or player.is_dead:
		return

	var book := player.magic_book
	if book.primary_school == -1:
		# Выбор школы идёт на паузе, поэтому обрабатывается до проверки паузы.
		for i in 4:
			if Input.is_action_just_pressed("pick_school_%d" % (i + 1)):
				book.choose_primary(MagicBook.BASE_SCHOOLS[i])
		return

	# Мир на паузе (меню, экран смерти): не тикаем кулдаун и не принимаем
	# управление, иначе F в меню тратит ману и стреляет после снятия паузы.
	if get_tree().paused:
		return

	cooldown_timer = maxf(cooldown_timer - delta, 0.0)
	magic_noise = move_toward(magic_noise, 0.0, delta * 0.5)

	if Input.is_action_just_pressed("next_spell"):
		var n := available_spells().size()
		if n > 0:
			selected_index = (selected_index + 1) % n
			selected_changed.emit(selected_spell())
	if Input.is_action_just_pressed("cast_spell"):
		cast(selected_spell())

func cast(id: String) -> bool:
	if id == "" or cooldown_timer > 0.0 or not SPELLS.has(id):
		return false
	var data: Dictionary = SPELLS[id]
	# Активное заклинание тратит ману (в отличие от пассивных навыков)
	if not player.spend_mana(data["mana"]):
		return false
	cooldown_timer = data["cooldown"]
	magic_noise = maxf(magic_noise, data["noise"])

	var cam := player.camera
	_spawn_cast_fx(cam, data["color"])
	SpellAudio.play_at(player, Vector3.ZERO,
		SpellAudio.cast_stream(str(data.get("visual", ""))), -8.0, "CastAudio")
	player.apply_cast_recoil(2.5, 0.03)
	# Снаряд вылетает после короткой антиципации, а не мгновенно.
	get_tree().create_timer(CAST_WINDUP).timeout.connect(_launch.bind(id))
	return true

## Вылет снаряда после антиципации. Направление пересчитывается в момент
## вылета: игрок мог повернуть камеру за доли секунды «сбора».
func _launch(id: String) -> void:
	if player == null or not is_instance_valid(player) or player.is_dead:
		return
	if not SPELLS.has(id):
		return
	var data: Dictionary = SPELLS[id]
	var cam := player.camera
	if cam == null:
		return
	var proj := SpellProjectile.new()
	proj.caster = player
	proj.direction = -cam.global_transform.basis.z
	proj.speed = data["speed"] * speed_multiplier
	proj.damage = data["damage"]
	proj.knockback = data["knockback"]
	proj.effect = data["effect"]
	proj.visual = str(data.get("visual", ""))
	proj.tint = data["color"]
	proj.configure()
	var parent: Node = player.get_tree().current_scene
	if parent == null:
		parent = player.get_parent()
	parent.add_child(proj)
	proj.global_position = cam.global_position + proj.direction * 0.8
	spell_cast.emit(id)

## «Сбор» энергии у камеры: искры сжимаются и гаснут, вспышка света.
func _spawn_cast_fx(cam: Camera3D, tint: Color) -> void:
	if cam == null:
		return
	var parent: Node = get_tree().current_scene
	if parent == null:
		parent = player.get_parent()
	if parent == null:
		return
	var fx := Node3D.new()
	fx.name = "CastGather"
	parent.add_child(fx)
	fx.global_position = cam.global_position - cam.global_transform.basis.z * 0.7

	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 1.6
	light.omni_range = 2.5
	fx.add_child(light)

	var particles := GPUParticles3D.new()
	particles.amount = 14
	particles.lifetime = CAST_WINDUP + 0.05
	particles.one_shot = true
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-1.0, -1.0, -1.0), Vector3(2.0, 2.0, 2.0))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = SpellProjectile._particle_texture("shard")
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.9)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.alpha_scissor_threshold = 0.5
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	particles.draw_pass_1 = quad
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.35
	process.direction = Vector3.ZERO
	process.spread = 180.0
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.2
	process.gravity = Vector3.ZERO
	process.scale_min = 0.6
	process.scale_max = 1.2
	process.color_ramp = SpellProjectile._fade_ramp(0.85)
	# Частицы сжимаются в точку — читается как «втягивание» энергии.
	process.scale_curve = SpellProjectile._scale_curve(1.0, 0.1)
	particles.process_material = process
	particles.emitting = true
	fx.add_child(particles)

	var tween := fx.create_tween()
	tween.tween_property(light, "light_energy", 0.0, CAST_WINDUP + 0.08)
	get_tree().create_timer(0.5).timeout.connect(fx.queue_free)

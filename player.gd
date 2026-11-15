class_name Player
extends CharacterBody3D

signal stance_changed(stance: Stance)
signal landed

signal died
signal health_changed(current: float, maximum: float)
signal air_jumped
signal passive_unlocked(skill: Passive)

enum Stance { STANDING, CROUCHING, SPRINTING }
enum Passive { DOUBLE_JUMP }

@export_group("Пассивные навыки")
## Список открытых пассивных навыков (по умолчанию двойной прыжок открыт).
@export var unlocked_passives: Array[Passive] = [Passive.DOUBLE_JUMP]
## Сила второго прыжка относительно обычного.
@export_range(0.3, 1.5, 0.05) var double_jump_power: float = 0.9
var air_jumps_used: int = 0

@export_group("Движение")
@export var walk_speed: float = 4.5
@export var sprint_speed: float = 7.5
@export var crouch_speed: float = 2.2
@export var ground_accel: float = 40.0
@export var ground_friction: float = 35.0
@export var air_accel: float = 12.0
@export var air_friction: float = 3.0

@export_group("Подъём на ступеньки")
@export_range(0.1, 1.0, 0.05) var step_height: float = 0.65

@export_group("Прыжок и гравитация")
@export var jump_height: float = 1.1
@export var coyote_time: float = 0.1
@export var jump_buffer_time: float = 0.1

@export_group("Приседание")
@export var standing_height: float = 1.8
@export var crouching_height: float = 1.1
@export var standing_head_y: float = 1.6
@export var crouching_head_y: float = 0.9
@export var crouch_transition_speed: float = 12.0

@export_group("Обзор мышью")
@export var mouse_sensitivity: float = 0.0025

@export_group("Покачивание камеры (Head Bob)")
@export var bob_enabled: bool = true
@export var bob_freq: float = 12.0
@export var bob_amp: float = 0.04

@export_group("Динамический FOV")
@export var fov_change: bool = true
@export var default_fov: float = 75.0
@export var sprint_fov_boost: float = 8.0
@export var fov_transition_speed: float = 8.0

@export_group("Здоровье")
@export var health_max: float = 100.0
## Скорость падения (м/с), ниже которой урона нет.
@export var fall_damage_threshold: float = 12.0
@export var fall_damage_per_speed: float = 8.0

@export_group("Мана")
@export var mana_max: float = 100.0
@export var mana_regen: float = 8.0
@export var mana_regen_delay: float = 1.5

@export_group("Выносливость")
@export var stamina_max: float = 100.0
@export var stamina_drain: float = 25.0
@export var stamina_regen: float = 40.0
@export var stamina_regen_delay: float = 0.5

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/CameraBoom/Camera3D
@onready var interact_ray: RayCast3D = $Head/CameraBoom/Camera3D/InteractRay
@onready var camera_boom: SpringArm3D = $Head/CameraBoom
@onready var ceiling_check: ShapeCast3D = $CeilingCheck
@onready var footstep_audio: AudioStreamPlayer3D = $FootstepAudio

var current_stance: Stance = Stance.STANDING
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var jump_velocity: float = 0.0

var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var was_on_floor: bool = false
var bob_phase: float = 0.0
var capsule: CapsuleShape3D = null

var health: float = 100.0
var is_dead: bool = false
var mana: float = 100.0
var mana_regen_timer: float = 0.0
var magic_book: MagicBook = null
var spell_caster: SpellCaster = null

var stamina: float = 100.0
var stamina_regen_timer: float = 0.0
var exhausted: bool = false
var land_offset: float = 0.0
var step_offset: float = 0.0
var land_vel: float = 0.0
var land_pitch: float = 0.0
var bob_y: float = 0.0
var fall_speed: float = 0.0
var _interact_target: Object = null
var sprint_blend: float = 0.0
var current_speed_limit: float = 4.5
@export_group("Ощущение камеры")
@export var tilt_max_deg: float = 1.5
@export var land_dip_amount: float = 0.12
@export var land_pitch_deg: float = 2.5
@export var land_spring: float = 400.0
@export var land_damping: float = 22.0
@export var sprint_lean_deg: float = 1.5
@export var sprint_blend_speed: float = 3.0
@export var speed_ramp: float = 8.0
var footstep_timer: float = 0.0
var step_streams: Dictionary = {}
var land_stream: AudioStreamWAV = null

func _ready() -> void:

	# Initialize input actions once
	_setup_input_actions()

	add_to_group("player")
	health = health_max
	mana = mana_max
	magic_book = MagicBook.new()
	magic_book.name = "MagicBook"
	add_child(magic_book)
	spell_caster = SpellCaster.new()
	spell_caster.name = "SpellCaster"
	add_child(spell_caster)

	if collision_shape and collision_shape.shape:
		collision_shape.shape = collision_shape.shape.duplicate()
		capsule = collision_shape.shape as CapsuleShape3D
	
	if camera_boom:
		camera_boom.spring_length = 0.6
	
	if ceiling_check:
		ceiling_check.add_exception(self)
		ceiling_check.enabled = true

	# Камера и луч не должны сталкиваться с телом самого игрока
	if camera_boom:
		camera_boom.add_excluded_object(get_rid())
	if interact_ray:
		interact_ray.add_exception(self)
		interact_ray.collision_mask = 4 # Layer 3: interactable
		interact_ray.collide_with_bodies = true

	# Прилипание к поверхности при спуске по ступенькам и небольшим уклонам
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)

	jump_velocity = sqrt(max(2.0 * gravity * jump_height, 0.001))

	if footstep_audio:
		step_streams = {
			Stance.STANDING: _generate_footstep_wav(300.0, 0.08, 50.0, 0.5, 0.0),
			Stance.CROUCHING: _generate_footstep_wav(200.0, 0.10, 40.0, 0.4, 0.8),
			Stance.SPRINTING: _generate_footstep_wav(380.0, 0.07, 60.0, 0.6, 0.0),
		}
		land_stream = _generate_footstep_wav(90.0, 0.22, 18.0, 0.5, 0.85)
		footstep_audio.stream = step_streams[Stance.STANDING]

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	# Пауза и ESC обрабатываются в pause_menu.gd
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))

func _physics_process(delta: float) -> void:
	if is_dead:
		velocity.x = move_toward(velocity.x, 0.0, ground_friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, ground_friction * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return
	_update_timers(delta)
	_handle_mana(delta)
	_handle_gravity(delta)
	_handle_stamina(delta)
	_handle_stance()
	_handle_jump()
	_handle_movement(delta)
	_apply_crouch_transition(delta)
	_apply_head_bob(delta)
	_apply_fov_change(delta)
	_apply_camera_feel(delta)
	_handle_footsteps(delta)
	_process_interaction()
	fall_speed = velocity.y
	_try_step_up(delta)
	move_and_slide()
	_check_landing()

func _update_timers(delta: float) -> void:
	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer = maxf(coyote_timer - delta, 0.0)

	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)

func _handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

# --- Здоровье ---
func take_damage(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, health_max)
	if health <= 0.0:
		is_dead = true
		died.emit()

func heal(amount: float) -> void:
	if is_dead or amount <= 0.0 or health >= health_max:
		return
	var previous_health := health
	health = clampf(health + amount, 0.0, health_max)
	if not is_equal_approx(health, previous_health):
		health_changed.emit(health, health_max)

## Простое возрождение: перезапуск текущей сцены.
func respawn() -> void:
	get_tree().reload_current_scene()

# --- Мана (тратят только активные заклинания, пассивные навыки её не трогают) ---
func has_mana(amount: float) -> bool:
	return mana >= amount

func spend_mana(amount: float) -> bool:
	if is_dead or mana < amount:
		return false
	mana -= amount
	mana_regen_timer = mana_regen_delay
	return true

func _handle_mana(delta: float) -> void:
	if mana_regen_timer > 0.0:
		mana_regen_timer -= delta
	else:
		mana = minf(mana + mana_regen * delta, mana_max)

func _handle_stamina(delta: float) -> void:
	if current_stance == Stance.SPRINTING and is_on_floor():
		stamina = maxf(stamina - stamina_drain * delta, 0.0)
		stamina_regen_timer = stamina_regen_delay
	else:
		if stamina_regen_timer > 0.0:
			stamina_regen_timer -= delta
		else:
			stamina = minf(stamina + stamina_regen * delta, stamina_max)

func _handle_stance() -> void:
	var wants_crouch: bool = Input.is_action_pressed("crouch")
	var has_ceiling: bool = ceiling_check and ceiling_check.is_colliding()
	var wants_sprint: bool = Input.is_action_pressed("sprint")
	var is_moving: bool = Input.get_vector("move_left", "move_right", "move_forward", "move_back").length_squared() > 0.01

	# После полного истощения бег доступен снова только при запасе выносливости 20%
	if stamina <= 0.0:
		exhausted = true
	elif stamina >= stamina_max * 0.2:
		exhausted = false
	var can_sprint: bool = wants_sprint and not exhausted

	var next_stance: Stance = Stance.STANDING
	if wants_crouch or has_ceiling:
		next_stance = Stance.CROUCHING
	elif can_sprint and is_moving and is_on_floor():
		next_stance = Stance.SPRINTING
	else:
		next_stance = Stance.STANDING

	if next_stance != current_stance:
		current_stance = next_stance
		stance_changed.emit(current_stance)

func _handle_jump() -> void:
	if is_on_floor():
		air_jumps_used = 0

	if jump_buffer_timer <= 0.0 or current_stance == Stance.CROUCHING:
		return

	if coyote_timer > 0.0:
		velocity.y = jump_velocity
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
	elif has_passive(Passive.DOUBLE_JUMP) and air_jumps_used < 1:
		# Пассивный навык: не тратит ни выносливость, ни магию
		air_jumps_used += 1
		velocity.y = jump_velocity * double_jump_power
		jump_buffer_timer = 0.0
		air_jumped.emit()

# --- Пассивные навыки ---
# Работают постоянно и не расходуют ресурсы (ни магию, ни выносливость).
func has_passive(skill: Passive) -> bool:
	return unlocked_passives.has(skill)

func unlock_passive(skill: Passive) -> void:
	if not unlocked_passives.has(skill):
		unlocked_passives.append(skill)
		passive_unlocked.emit(skill)

func lock_passive(skill: Passive) -> void:
	unlocked_passives.erase(skill)

func _handle_movement(delta: float) -> void:
	var input_2d := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var input_vector := Vector3(input_2d.x, 0.0, input_2d.y)
	var move_dir := Vector3.ZERO
	if input_vector.length_squared() > 0.0:
		move_dir = (transform.basis * input_vector).normalized()

	var target_speed: float = walk_speed
	match current_stance:
		Stance.CROUCHING:
			target_speed = crouch_speed
		Stance.SPRINTING:
			target_speed = sprint_speed
		Stance.STANDING:
			target_speed = walk_speed

	# Плавный переход между скоростями (ходьба / бег / присед)
	var ramp := speed_ramp if target_speed > current_speed_limit else speed_ramp * 1.5
	current_speed_limit = move_toward(current_speed_limit, target_speed, ramp * delta)
	# Степень «бега» 0..1 для камеры
	sprint_blend = move_toward(sprint_blend, 1.0 if current_stance == Stance.SPRINTING else 0.0, sprint_blend_speed * delta)

	var target_vel_x := move_dir.x * current_speed_limit
	var target_vel_z := move_dir.z * current_speed_limit
	var accel := ground_accel if is_on_floor() else air_accel
	var friction := ground_friction if is_on_floor() else air_friction

	if move_dir.length_squared() > 0.001:
		velocity.x = move_toward(velocity.x, target_vel_x, accel * delta)
		velocity.z = move_toward(velocity.z, target_vel_z, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)

func _apply_crouch_transition(delta: float) -> void:

	# Safety check: ensure capsule is initialized before use
	if not capsule:
		return
	var target_h: float = crouching_height if current_stance == Stance.CROUCHING else standing_height
	var target_head_y: float = crouching_head_y if current_stance == Stance.CROUCHING else standing_head_y

	if capsule:
		# Экспоненциальное сглаживание: быстрый старт, мягкое замедление в конце
		var k := 1.0 - exp(-crouch_transition_speed * 0.5 * delta)
		capsule.height = lerpf(capsule.height, target_h, k)
		if absf(capsule.height - target_h) < 0.002:
			capsule.height = target_h
		if collision_shape:
			collision_shape.position.y = capsule.height * 0.5

	var kh := 1.0 - exp(-crouch_transition_speed * 0.5 * delta)
	head.position.y = lerpf(head.position.y, target_head_y, kh)

func has_interact_target() -> bool:
	if interact_ray == null or not interact_ray.enabled:
		return false
	# The HUD samples in _process while the ray normally updates in the physics
	# tick. Force a fresh query so the prompt tracks the current camera aim.
	interact_ray.force_raycast_update()
	if not interact_ray.is_colliding():
		return false
	var obj := interact_ray.get_collider()
	return obj != null and obj.has_method("interact")

func _update_interact_target(target: Object) -> void:
	if target == _interact_target:
		return
	if is_instance_valid(_interact_target) and _interact_target.has_method("set_targeted"):
		_interact_target.call("set_targeted", false)
	_interact_target = target
	if is_instance_valid(_interact_target) and _interact_target.has_method("set_targeted"):
		_interact_target.call("set_targeted", true)

func _process_interaction() -> void:
	var target: Object = null
	if interact_ray != null and interact_ray.enabled:
		interact_ray.force_raycast_update()
		if interact_ray.is_colliding():
			var hit := interact_ray.get_collider()
			if hit != null and hit.has_method("interact"):
				target = hit
	_update_interact_target(target)
	if Input.is_action_just_pressed("interact") and target != null:
		target.call("interact")

func _apply_head_bob(delta: float) -> void:
	# SpringArm3D сам задаёт позицию камеры, поэтому покачиваем сам CameraBoom
	var bob_node: Node3D = camera_boom
	if not bob_enabled:
		bob_node.position = Vector3.ZERO
		return

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horizontal_speed > 0.5:
		var speed_factor := horizontal_speed / walk_speed
		bob_phase += delta * bob_freq * speed_factor
		var amp := bob_amp * lerpf(1.0, 1.7, sprint_blend)
		var bob_offset_y := sin(bob_phase) * amp
		var bob_offset_x := cos(bob_phase * 0.5) * (amp * 0.6)
		bob_y = lerpf(bob_y, bob_offset_y, delta * 12.0)
		bob_node.position.x = lerpf(bob_node.position.x, bob_offset_x, delta * 12.0)
	else:
		bob_phase = 0.0
		bob_y = lerpf(bob_y, 0.0, delta * 10.0)
		bob_node.position.x = lerpf(bob_node.position.x, 0.0, delta * 10.0)
	bob_node.position.y = bob_y + land_offset + step_offset

# Подъём на ступеньки: приподнимаем тело, если препятствие ниже step_height
func _try_step_up(delta: float) -> void:
	if not is_on_floor() or velocity.y > 0.1:
		return
	var h := Vector3(velocity.x, 0.0, velocity.z)
	if h.length() < 0.1:
		return
	# Проба вперёд минимум 0.1 м, чтобы заметить ступеньку заранее
	var motion := h.normalized() * maxf(h.length() * delta, 0.1)
	var xf := global_transform
	if not test_move(xf, motion):
		return
	var up := Vector3.UP * step_height
	if test_move(xf, up):
		return
	var raised := xf.translated(up)
	if test_move(raised, motion):
		return
	var col := KinematicCollision3D.new()
	if not test_move(raised.translated(motion), -up, col):
		return
	if col.get_normal().angle_to(Vector3.UP) > floor_max_angle:
		return
	var gained := step_height + col.get_travel().y
	if gained < 0.01:
		return
	global_position.y += gained
	step_offset -= gained

func _apply_camera_feel(delta: float) -> void:
	step_offset = lerpf(step_offset, 0.0, delta * 12.0)
	# Пружина приземления: резкий толчок вниз с затухающим отскоком
	land_vel += (-land_spring * land_offset - land_damping * land_vel) * delta
	land_offset += land_vel * delta
	land_pitch = lerpf(land_pitch, 0.0, delta * 7.0)

	# Наклон камеры при движении вбок (strafe tilt)
	var local_vel := global_transform.basis.inverse() * velocity
	var target_roll := -local_vel.x / sprint_speed * deg_to_rad(tilt_max_deg)
	camera.rotation.z = lerpf(camera.rotation.z, target_roll, delta * 8.0)

	# Лёгкий наклон головы вверх при прыжке/падении
	# + наклон вперёд при беге + толчок при приземлении
	var target_pitch := clampf(velocity.y * 0.004, -0.04, 0.04) - sprint_blend * deg_to_rad(sprint_lean_deg) + land_pitch
	camera.rotation.x = lerpf(camera.rotation.x, target_pitch, delta * 10.0)

func _apply_fov_change(delta: float) -> void:
	if not fov_change:
		return

	# FOV следует за плавным sprint_blend, а не за переключением состояния
	var target_fov: float = default_fov + sprint_fov_boost * smoothstep(0.0, 1.0, sprint_blend)
	camera.fov = lerpf(camera.fov, target_fov, delta * fov_transition_speed)

func _handle_footsteps(delta: float) -> void:
	if not footstep_audio or not is_on_floor():
		footstep_timer = 0.0
		return

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed < 0.2:
		footstep_timer = 0.0
		if footstep_audio.playing:
			footstep_audio.stop()
		return

	var step_interval: float = 0.45
	match current_stance:
		Stance.CROUCHING:
			step_interval = 0.7
		Stance.SPRINTING:
			step_interval = 0.3
		Stance.STANDING:
			step_interval = 0.45

	footstep_timer += delta
	if footstep_timer >= step_interval:
		footstep_timer = 0.0
		_play_footstep()

func _play_footstep() -> void:
	if not footstep_audio:
		return
	if step_streams.has(current_stance):
		footstep_audio.stream = step_streams[current_stance]
	footstep_audio.pitch_scale = randf_range(0.9, 1.1)
	var volume: float = 0.0
	match current_stance:
		Stance.CROUCHING:
			volume = -15.0
		Stance.STANDING:
			volume = -8.0
		Stance.SPRINTING:
			volume = -3.0
	footstep_audio.volume_db = volume
	footstep_audio.play()

func _check_landing() -> void:
	if not was_on_floor and is_on_floor():
		landed.emit()
		if -fall_speed > fall_damage_threshold:
			take_damage((-fall_speed - fall_damage_threshold) * fall_damage_per_speed)
		var impact := clampf(-fall_speed / jump_velocity, 0.0, 2.5)
		if impact > 0.15:
			land_vel = -impact * land_dip_amount * 12.0
			land_pitch = impact * deg_to_rad(land_pitch_deg)
		if footstep_audio:
			if land_stream:
				footstep_audio.stream = land_stream
			footstep_audio.pitch_scale = randf_range(0.9, 1.1)
			footstep_audio.volume_db = -9.0 + impact * 6.0
			footstep_audio.play()
	was_on_floor = is_on_floor()

## Заметность для зрения врагов, 0..1. Присед и неподвижность уменьшают её.
## Освещённость добавится позже.
func get_visibility() -> float:
	var moving := Vector2(velocity.x, velocity.z).length() > 0.3
	var v := 1.0
	if current_stance == Stance.CROUCHING:
		v = 0.5 if moving else 0.35
	elif not moving:
		v = 0.8
	return v

func get_noise_level() -> float:
	var magic := spell_caster.magic_noise if spell_caster else 0.0
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed < 0.1:
		return magic
	match current_stance:
		Stance.CROUCHING:
			return maxf(0.2, magic)
		Stance.STANDING:
			return maxf(0.6, magic)
		Stance.SPRINTING:
			return maxf(1.0, magic)
	return magic

func _setup_input_actions() -> void:
	var default_keys: Dictionary = {
		"move_forward": KEY_W,
		"move_back": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"jump": KEY_SPACE,
		"sprint": KEY_SHIFT,
		"crouch": KEY_CTRL,
		"interact": KEY_E,
		}
	for action in default_keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			var ev := InputEventKey.new()
			ev.physical_keycode = default_keys[action]
			InputMap.action_add_event(action, ev)

	var joypad_events := {
		"move_left": _joy_axis_event(JOY_AXIS_LEFT_X, -1.0),
		"move_right": _joy_axis_event(JOY_AXIS_LEFT_X, 1.0),
		"move_forward": _joy_axis_event(JOY_AXIS_LEFT_Y, -1.0),
		"move_back": _joy_axis_event(JOY_AXIS_LEFT_Y, 1.0),
		"jump": _joy_button_event(JOY_BUTTON_A),
		"sprint": _joy_button_event(JOY_BUTTON_LEFT_STICK),
		"crouch": _joy_button_event(JOY_BUTTON_B),
		"interact": _joy_button_event(JOY_BUTTON_X),
	}
	for action in joypad_events:
		_add_joypad_event_if_missing(action, joypad_events[action])

func _joy_axis_event(axis: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event

func _joy_button_event(button: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event

func _add_joypad_event_if_missing(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventJoypadButton or existing is InputEventJoypadMotion:
			return
	InputMap.action_add_event(action, event)

# Генерация короткого звука шага (белый шум с затуханием)
func _generate_footstep_wav(tone_hz: float = 300.0, duration: float = 0.08, decay: float = 50.0, noise_amount: float = 0.5, smooth: float = 0.0) -> AudioStreamWAV:
	var sample_rate: int = 22050
	var length: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(length * 2)
	var prev_noise: float = 0.0
	for i in range(length):
		var t := float(i) / float(sample_rate)
		var env := exp(-t * decay)
		# smooth > 0 даёт простой ФНЧ: приглушённый звук (присед, мягкая посадка)
		var raw_noise := randf() * 2.0 - 1.0
		prev_noise = lerpf(raw_noise, prev_noise, smooth)
		var sample := sin(t * tone_hz * TAU) * env * 0.3 + prev_noise * env * noise_amount
		var val := clampi(int(sample * 16384.0), -32768, 32767)
		data.encode_s16(i * 2, val)
	var wav := AudioStreamWAV.new()
	wav.data = data
	wav.mix_rate = sample_rate
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	return wav

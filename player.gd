class_name Player
extends CharacterBody3D

signal stance_changed(stance: Stance)
signal landed

enum Stance { STANDING, CROUCHING, SPRINTING }

@export_group("Движение")
@export var walk_speed: float = 4.5
@export var sprint_speed: float = 7.5
@export var crouch_speed: float = 2.2
@export var ground_accel: float = 40.0
@export var ground_friction: float = 35.0
@export var air_accel: float = 12.0
@export var air_friction: float = 3.0

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

var stamina: float = 100.0
var stamina_regen_timer: float = 0.0
var exhausted: bool = false
var land_offset: float = 0.0
var fall_speed: float = 0.0
@export_group("Ощущение камеры")
@export var tilt_max_deg: float = 1.5
@export var land_dip_amount: float = 0.08
var footstep_timer: float = 0.0

func _ready() -> void:

	# Initialize input actions once
	_setup_input_actions()

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

	jump_velocity = sqrt(max(2.0 * gravity * jump_height, 0.001))

	if footstep_audio and not footstep_audio.stream:
		footstep_audio.stream = _generate_footstep_wav()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))

func _physics_process(delta: float) -> void:
	_update_timers(delta)
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
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0 and current_stance != Stance.CROUCHING:
		velocity.y = jump_velocity
		jump_buffer_timer = 0.0
		coyote_timer = 0.0

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

	var target_vel_x := move_dir.x * target_speed
	var target_vel_z := move_dir.z * target_speed
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
		capsule.height = move_toward(capsule.height, target_h, crouch_transition_speed * delta)
		if collision_shape:
			collision_shape.position.y = capsule.height * 0.5

	head.position.y = move_toward(head.position.y, target_head_y, crouch_transition_speed * delta)

func has_interact_target() -> bool:
	if interact_ray == null or not interact_ray.is_colliding():
		return false
	var obj := interact_ray.get_collider()
	return obj != null and obj.has_method("interact")

func _process_interaction() -> void:
	if Input.is_action_just_pressed("interact"):
		if interact_ray and interact_ray.is_colliding() and interact_ray.get_collider():
			var obj = interact_ray.get_collider()
			if obj and obj.has_method("interact"):
				obj.call("interact")

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
		var bob_offset_y := sin(bob_phase) * bob_amp
		var bob_offset_x := cos(bob_phase * 0.5) * (bob_amp * 0.6)
		bob_node.position.y = lerpf(bob_node.position.y, bob_offset_y + land_offset, delta * 12.0)
		bob_node.position.x = lerpf(bob_node.position.x, bob_offset_x, delta * 12.0)
	else:
		bob_phase = 0.0
		bob_node.position = bob_node.position.lerp(Vector3(0.0, land_offset, 0.0), delta * 10.0)

func _apply_camera_feel(delta: float) -> void:
	# Затухание «просадки» камеры после приземления
	land_offset = lerpf(land_offset, 0.0, delta * 8.0)

	# Наклон камеры при движении вбок (strafe tilt)
	var local_vel := global_transform.basis.inverse() * velocity
	var target_roll := -local_vel.x / sprint_speed * deg_to_rad(tilt_max_deg)
	camera.rotation.z = lerpf(camera.rotation.z, target_roll, delta * 8.0)

	# Лёгкий наклон головы вверх при прыжке/падении
	var target_pitch := clampf(velocity.y * 0.004, -0.04, 0.04)
	camera.rotation.x = lerpf(camera.rotation.x, target_pitch, delta * 6.0)

func _apply_fov_change(delta: float) -> void:
	if not fov_change:
		return

	var target_fov: float = default_fov
	if current_stance == Stance.SPRINTING and is_on_floor() and velocity.length() > walk_speed:
		target_fov = default_fov + sprint_fov_boost

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
		var impact := clampf(-fall_speed / jump_velocity, 0.0, 2.0)
		land_offset = -impact * land_dip_amount
		if footstep_audio:
			footstep_audio.pitch_scale = randf_range(0.75, 0.9)
			footstep_audio.volume_db = -9.0 + impact * 6.0
			footstep_audio.play()
	was_on_floor = is_on_floor()

func get_noise_level() -> float:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed < 0.1:
		return 0.0
	match current_stance:
		Stance.CROUCHING:
			return 0.2
		Stance.STANDING:
			return 0.6
		Stance.SPRINTING:
			return 1.0
	return 0.0

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

# Генерация короткого звука шага (белый шум с затуханием)
func _generate_footstep_wav() -> AudioStreamWAV:
	var sample_rate: int = 22050
	var duration: float = 0.08
	var length: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(length * 2)
	for i in range(length):
		var t := float(i) / float(sample_rate)
		var env := exp(-t * 50.0)
		var sample := sin(t * 300.0 * TAU) * env * 0.3 + (randf() * 2.0 - 1.0) * env * 0.5
		var val := clampi(int(sample * 16384.0), -32768, 32767)
		data.encode_s16(i * 2, val)
	var wav := AudioStreamWAV.new()
	wav.data = data
	wav.mix_rate = sample_rate
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	return wav
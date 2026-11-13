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

# Ссылки на узлы
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var ceiling_check: ShapeCast3D = $CeilingCheck

var current_stance: Stance = Stance.STANDING
var gravity: float = 9.8
var jump_velocity: float = 0.0

var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var was_on_floor: bool = false
var bob_phase: float = 0.0
var capsule: CapsuleShape3D

func _ready() -> void:
	_setup_input_actions()

	# Получение гравитации из настроек проекта с безопасным значением по умолчанию
	gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

	# Делаем копию формы, чтобы изменение высоты не затрагивало другие экземпляры
	if collision_shape and collision_shape.shape:
		collision_shape.shape = collision_shape.shape.duplicate()
		capsule = collision_shape.shape as CapsuleShape3D

	# Исключаем персонажа из проверки потолка
	if ceiling_check:
		ceiling_check.add_exception(self)

	# Расчет скорости прыжка по высоте: v = sqrt(2 * g * h)
	jump_velocity = sqrt(2.0 * gravity * jump_height)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	# Переключение курсора по Esc
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Захват мыши по клику внутри окна
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Вращение камеры
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))

func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_handle_gravity(delta)
	_handle_stance()
	_handle_jump()
	_handle_movement(delta)
	_apply_crouch_transition(delta)
	_apply_head_bob(delta)
	_apply_fov_change(delta)

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

func _handle_stance() -> void:
	var wants_crouch: bool = Input.is_action_pressed("crouch")
	var has_ceiling: bool = ceiling_check.is_colliding() if ceiling_check else false
	var wants_sprint: bool = Input.is_action_pressed("sprint")
	var is_moving: bool = Input.get_vector("move_left", "move_right", "move_forward", "move_back").length_squared() > 0.01

	var next_stance: Stance = Stance.STANDING

	# Если игрок жмет присед или над головой препятствие — стоим/идем в приседе
	if wants_crouch or has_ceiling:
		next_stance = Stance.CROUCHING
	elif wants_sprint and is_moving and is_on_floor():
		next_stance = Stance.SPRINTING
	else:
		next_stance = Stance.STANDING

	if next_stance != current_stance:
		current_stance = next_stance
		stance_changed.emit(current_stance)

func _handle_jump() -> void:
	# Прыжок доступен, если есть буфер, койот-тайм и мы не зажаты низким потолком
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0 and current_stance != Stance.CROUCHING:
		velocity.y = jump_velocity
		jump_buffer_timer = 0.0
		coyote_timer = 0.0

func _handle_movement(delta: float) -> void:
	var input_2d := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Направление ввода относительно ориентации тела игрока
	var move_dir := (transform.basis * Vector3(input_2d.x, 0.0, input_2d.y)).normalized()

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

	# Плавный разгон или торможение
	if move_dir.length_squared() > 0.001:
		velocity.x = move_toward(velocity.x, target_vel_x, accel * delta)
		velocity.z = move_toward(velocity.z, target_vel_z, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)

func _apply_crouch_transition(delta: float) -> void:
	var target_h: float = crouching_height if current_stance == Stance.CROUCHING else standing_height
	var target_head_y: float = crouching_head_y if current_stance == Stance.CROUCHING else standing_head_y

	# Плавно меняем высоту капсулы
	if capsule:
		capsule.height = move_toward(capsule.height, target_h, crouch_transition_speed * delta)
		collision_shape.position.y = capsule.height * 0.5

	# Плавно перемещаем базовую высоту головы
	head.position.y = move_toward(head.position.y, target_head_y, crouch_transition_speed * delta)

func _apply_head_bob(delta: float) -> void:
	if not bob_enabled:
		camera.position = Vector3.ZERO
		return

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()

	if is_on_floor() and horizontal_speed > 0.5:
		var speed_factor := horizontal_speed / walk_speed
		bob_phase += delta * bob_freq * speed_factor

		var bob_offset_y := sin(bob_phase) * bob_amp
		var bob_offset_x := cos(bob_phase * 0.5) * (bob_amp * 0.6)

		camera.position.y = lerp(camera.position.y, bob_offset_y, delta * 12.0)
		camera.position.x = lerp(camera.position.x, bob_offset_x, delta * 12.0)
	else:
		bob_phase = 0.0
		camera.position = lerp(camera.position, Vector3.ZERO, delta * 10.0)

func _apply_fov_change(delta: float) -> void:
	if not fov_change:
		return

	var target_fov: float = default_fov
	if current_stance == Stance.SPRINTING and is_on_floor() and velocity.length() > walk_speed:
		target_fov = default_fov + sprint_fov_boost

	camera.fov = lerp(camera.fov, target_fov, delta * fov_transition_speed)

func _check_landing() -> void:
	if not was_on_floor and is_on_floor():
		landed.emit()
	was_on_floor = is_on_floor()

## Уровень создаваемого шума: 0.0 (покой), 0.2 (присед), 0.6 (шаг), 1.0 (бег)
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

## Регистрация действий ввода в InputMap, если они не заданы в проекте
func _setup_input_actions() -> void:
	var default_keys: Dictionary = {
		"move_forward": KEY_W,
		"move_back": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"jump": KEY_SPACE,
		"sprint": KEY_SHIFT,
		"crouch": KEY_CTRL,
	}
	for action in default_keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			var ev := InputEventKey.new()
			ev.physical_keycode = default_keys[action]
			InputMap.action_add_event(action, ev)

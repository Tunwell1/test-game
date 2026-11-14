class_name Enemy
extends CharacterBody3D

## Враг с ИИ: патруль -> подозрение -> погоня -> бой -> поиск.
## Видит конусом зрения (с учётом заметности игрока) и слышит шум.
## Визуал и коллизия создаются кодом, достаточно повесить скрипт на CharacterBody3D (слой 8).

signal died
signal state_changed(state: State)

enum State { PATROL, SUSPICIOUS, CHASE, SEARCH, DEAD }

@export_group("Характеристики")
@export var health_max: float = 60.0
@export var patrol_speed: float = 1.8
@export var chase_speed: float = 4.2
@export var turn_speed: float = 6.0

@export_group("Чувства")
@export var view_distance: float = 14.0
@export var view_angle_deg: float = 70.0
## Радиус слуха при уровне шума 1.0 (бег). Меньший шум слышен ближе.
@export var hearing_radius: float = 12.0
## Скорость роста подозрения при полном обнаружении (1/сек).
@export var detect_rate: float = 1.2
@export var awareness_decay: float = 0.25
@export var search_time: float = 6.0

@export_group("Бой")
@export var attack_range: float = 1.6
@export var attack_damage: float = 12.0
@export var attack_cooldown: float = 1.0

@export_group("Патруль")
## Точки патруля относительно стартовой позиции врага.
@export var patrol_offsets: Array[Vector3] = [Vector3(0, 0, 0), Vector3(4, 0, 0)]
@export var patrol_wait: float = 1.5

const GRAVITY := 9.8

var health: float = 0.0
var state: State = State.PATROL
## 0..1: шкала подозрения. >=0.35 подозрение, >=1 погоня.
var awareness: float = 0.0
var player: Player = null
var last_known_pos: Vector3 = Vector3.ZERO
var patrol_points: Array[Vector3] = []
var patrol_index: int = 0
var wait_timer: float = 0.0
var search_timer: float = 0.0
var attack_timer: float = 0.0
var burn_timer: float = 0.0
var knock: Vector3 = Vector3.ZERO
var _mat: StandardMaterial3D
var _indicator: Label3D

func _ready() -> void:
	health = health_max
	collision_layer = 8
	collision_mask = 1 | 2
	add_to_group("enemies")

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)

	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = 1.8
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.6, 0.2, 0.2)
	cm.material = _mat
	mi.mesh = cm
	mi.position.y = 0.9
	add_child(mi)

	# Метка-«глаза», показывающая, куда смотрит враг
	var nose := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.2, 0.1, 0.3)
	nose.mesh = box
	nose.position = Vector3(0, 1.55, -0.35)
	add_child(nose)

	_indicator = Label3D.new()
	_indicator.position.y = 2.2
	_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_indicator.no_depth_test = true
	_indicator.font_size = 64
	add_child(_indicator)

	for off in patrol_offsets:
		patrol_points.append(global_position + off)

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Player
		if player == null:
			player = _find_player()
	attack_timer = maxf(attack_timer - delta, 0.0)

	_tick_burn(delta)
	_perceive(delta)
	_update_state(delta)
	_move(delta)
	_update_indicator()

func _find_player() -> Player:
	return get_tree().current_scene.find_child("Player", true, false) as Player

# --- Восприятие ---

func _eye_pos() -> Vector3:
	return global_position + Vector3(0, 1.6, 0)

func _can_see_player() -> float:
	## Возвращает силу обнаружения 0..1 (0 — не видит).
	if player == null or player.is_dead:
		return 0.0
	var target := player.global_position + Vector3(0, 1.0, 0)
	var to_p := target - _eye_pos()
	var dist := to_p.length()
	var vis := player.get_visibility()
	var max_dist := view_distance * vis
	if dist > max_dist:
		return 0.0
	var fwd := -global_transform.basis.z
	var flat := Vector3(to_p.x, 0, to_p.z).normalized()
	if rad_to_deg(fwd.angle_to(flat)) > view_angle_deg:
		return 0.0
	var q := PhysicsRayQueryParameters3D.create(_eye_pos(), target, 1, [get_rid()])
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return 0.0
	# Чем ближе и заметнее игрок, тем быстрее обнаружение
	return clampf(1.0 - dist / max_dist, 0.0, 1.0) * 0.7 + 0.3 * vis

func _hear_player() -> bool:
	if player == null or player.is_dead:
		return false
	var noise := player.get_noise_level()
	if noise <= 0.0:
		return false
	return global_position.distance_to(player.global_position) <= hearing_radius * noise

func _perceive(delta: float) -> void:
	var seen := _can_see_player()
	var heard := _hear_player()
	if seen > 0.0:
		awareness = minf(awareness + detect_rate * seen * delta * (3.0 if state == State.CHASE else 1.0), 1.0)
		last_known_pos = player.global_position
	elif heard:
		awareness = minf(awareness + detect_rate * 0.6 * delta, 1.0)
		last_known_pos = player.global_position
	elif state != State.CHASE:
		awareness = maxf(awareness - awareness_decay * delta, 0.0)

# --- Состояния ---

func _set_state(s: State) -> void:
	if s == state:
		return
	state = s
	if s == State.SEARCH:
		search_timer = search_time
	state_changed.emit(s)

func _update_state(delta: float) -> void:
	match state:
		State.PATROL:
			if awareness >= 1.0:
				_set_state(State.CHASE)
			elif awareness >= 0.35:
				_set_state(State.SUSPICIOUS)
		State.SUSPICIOUS:
			if awareness >= 1.0:
				_set_state(State.CHASE)
			elif awareness < 0.1:
				_set_state(State.PATROL)
		State.CHASE:
			if _can_see_player() <= 0.0 and not _hear_player():
				_set_state(State.SEARCH)
		State.SEARCH:
			if awareness >= 1.0:
				_set_state(State.CHASE)
			else:
				search_timer -= delta
				if search_timer <= 0.0:
					awareness = 0.0
					_set_state(State.PATROL)

func _move(delta: float) -> void:
	var desired := Vector3.ZERO
	var face_target: Variant = null

	match state:
		State.PATROL:
			if not patrol_points.is_empty():
				var tgt := patrol_points[patrol_index]
				var d := Vector3(tgt.x - global_position.x, 0, tgt.z - global_position.z)
				if d.length() < 0.4:
					wait_timer += delta
					if wait_timer >= patrol_wait:
						wait_timer = 0.0
						patrol_index = (patrol_index + 1) % patrol_points.size()
				else:
					desired = d.normalized() * patrol_speed
					face_target = tgt
		State.SUSPICIOUS:
			# Замирает и смотрит на источник подозрения
			face_target = last_known_pos
		State.CHASE:
			if player and not player.is_dead:
				var d := Vector3(player.global_position.x - global_position.x, 0, player.global_position.z - global_position.z)
				face_target = player.global_position
				if d.length() > attack_range * 0.8:
					desired = d.normalized() * chase_speed
				if d.length() <= attack_range:
					_try_attack()
		State.SEARCH:
			var d := Vector3(last_known_pos.x - global_position.x, 0, last_known_pos.z - global_position.z)
			if d.length() > 0.6:
				desired = d.normalized() * patrol_speed * 1.4
			face_target = last_known_pos

	if face_target != null:
		var ft: Vector3 = face_target
		var dir := Vector3(ft.x - global_position.x, 0, ft.z - global_position.z)
		if dir.length() > 0.05:
			var target_yaw := atan2(-dir.x, -dir.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))

	velocity.x = desired.x + knock.x
	velocity.z = desired.z + knock.z
	knock = knock.move_toward(Vector3.ZERO, 25.0 * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	move_and_slide()

func _try_attack() -> void:
	if attack_timer > 0.0:
		return
	attack_timer = attack_cooldown
	if player:
		player.take_damage(attack_damage)

# --- Получение урона и эффектов ---

func take_damage(amount: float) -> void:
	if state == State.DEAD:
		return
	health -= amount
	# Удар мгновенно выдаёт игрока
	awareness = 1.0
	if player:
		last_known_pos = player.global_position
	if state != State.CHASE:
		_set_state(State.CHASE)
	_flash()
	if health <= 0.0:
		_die()

func apply_knockback(impulse: Vector3) -> void:
	knock += Vector3(impulse.x, 0, impulse.z) * 0.5

func on_spell_effect(effect: String) -> void:
	match effect:
		"ignite":
			burn_timer = 3.0
		"extinguish":
			burn_timer = 0.0

func _tick_burn(delta: float) -> void:
	if burn_timer > 0.0:
		burn_timer -= delta
		take_damage(6.0 * delta)

func _flash() -> void:
	if _mat == null:
		return
	_mat.albedo_color = Color(1, 1, 1)
	var tw := create_tween()
	tw.tween_property(_mat, "albedo_color", Color(0.6, 0.2, 0.2), 0.15)

func _die() -> void:
	state = State.DEAD
	died.emit()
	_indicator.text = ""
	collision_layer = 0
	var tw := create_tween()
	tw.tween_property(self, "rotation:x", deg_to_rad(-90), 0.4)
	tw.tween_interval(3.0)
	tw.tween_callback(queue_free)

func _update_indicator() -> void:
	match state:
		State.PATROL:
			_indicator.text = ""
		State.SUSPICIOUS:
			_indicator.text = "?"
			_indicator.modulate = Color(1, 0.9, 0.2)
		State.CHASE:
			_indicator.text = "!"
			_indicator.modulate = Color(1, 0.2, 0.2)
		State.SEARCH:
			_indicator.text = "?"
			_indicator.modulate = Color(1, 0.6, 0.2)

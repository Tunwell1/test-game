class_name EnemyHealthOverlay
extends CanvasLayer

## Экранные полосы HP врагов. Пиксельный размер не зависит от расстояния до камеры.

const ANCHOR_OFFSET := Vector3(0.0, 2.5, 0.0)
const BAR_SIZE := Vector2(46.0, 8.0)
const LINGER_TIME := 4.0
const FADE_SPEED := 2.0
const DEATH_FADE_TIME := 0.3
const MAX_DISTANCE := 28.0
const NEAR_DISTANCE := 6.0
const FAR_DISTANCE := 20.0
const SCREEN_MARGIN := 60.0

var _root: Control
var _player: Player
var _camera: Camera3D
var _entries: Dictionary = {}


func _ready() -> void:
	layer = 4
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_resolve_player()


func _process(delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		_resolve_player()
		if _camera == null:
			return

	var used: Dictionary = {}
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or not is_instance_valid(enemy):
			continue
		var id := enemy.get_instance_id()
		var entry := _get_or_create_entry(enemy, id)
		_update_entry(enemy, entry, delta)
		used[id] = true
	_forget_unused(used)


func _get_or_create_entry(enemy: Enemy, id: int) -> Dictionary:
	if _entries.has(id):
		return _entries[id]
	var entry := {
		"enemy": enemy,
		"bar": _make_bar(enemy.health, enemy.health_max),
		"alpha": 0.0,
		"linger": 0.0,
		"dying": false,
		"last_pos": Vector2.ZERO,
	}
	enemy.health_changed.connect(_on_enemy_health_changed.bind(id))
	enemy.died.connect(_on_enemy_died.bind(id))
	_entries[id] = entry
	return entry


func _make_bar(current: float, maximum: float) -> StatBar:
	var bar := StatBar.new()
	bar.color = UiTheme.HEALTH
	bar.thickness = 4.0
	bar.show_text = false
	bar.pulse_when_low = true
	bar.set_values(current, maximum)
	bar.snap()
	bar.visible = false
	_root.add_child(bar)
	return bar


func _on_enemy_health_changed(current: float, maximum: float, id: int) -> void:
	if not _entries.has(id):
		return
	var entry: Dictionary = _entries[id]
	entry["linger"] = LINGER_TIME
	entry["alpha"] = 1.0
	var bar := entry["bar"] as StatBar
	bar.set_values(current, maximum)
	bar.visible = true
	bar.modulate.a = 1.0


func _on_enemy_died(id: int) -> void:
	if _entries.has(id):
		_entries[id]["dying"] = true


func _update_entry(enemy: Enemy, entry: Dictionary, delta: float) -> void:
	var bar := entry["bar"] as StatBar
	if entry["dying"] or enemy.state == Enemy.State.DEAD:
		entry["alpha"] = move_toward(entry["alpha"], 0.0, delta / DEATH_FADE_TIME)
		bar.modulate.a = entry["alpha"]
		bar.visible = entry["alpha"] > 0.01
		return

	entry["linger"] = maxf(entry["linger"] - delta, 0.0)
	if entry["linger"] <= 0.0:
		entry["alpha"] = move_toward(entry["alpha"], 0.0, FADE_SPEED * delta)
	if entry["alpha"] <= 0.01:
		bar.visible = false
		return

	var anchor := enemy.global_position + ANCHOR_OFFSET
	if _camera.is_position_behind(anchor):
		bar.visible = false
		return
	var screen := _camera.unproject_position(anchor)
	if (
		screen.x < -SCREEN_MARGIN
		or screen.y < -SCREEN_MARGIN
		or screen.x > _root.size.x + SCREEN_MARGIN
		or screen.y > _root.size.y + SCREEN_MARGIN
	):
		bar.visible = false
		return

	var distance := _camera.global_position.distance_to(anchor)
	if distance > MAX_DISTANCE:
		bar.visible = false
		return
	var width_scale := clampf(remap(distance, NEAR_DISTANCE, FAR_DISTANCE, 1.0, 0.55), 0.55, 1.0)
	bar.set_values(enemy.health, enemy.health_max)
	bar.size = Vector2(BAR_SIZE.x * width_scale, BAR_SIZE.y)
	bar.position = screen - bar.size * 0.5
	bar.visible = true
	bar.modulate.a = entry["alpha"]
	entry["last_pos"] = bar.position


func _forget_unused(used: Dictionary) -> void:
	for id in _entries.keys():
		if used.has(id):
			continue
		var entry: Dictionary = _entries[id]
		var bar := entry["bar"] as StatBar
		if is_instance_valid(bar):
			bar.queue_free()
		_entries.erase(id)


func _resolve_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null and get_tree().current_scene != null:
		_player = get_tree().current_scene.find_child("Player", true, false) as Player
	_camera = _player.camera if _player != null else null

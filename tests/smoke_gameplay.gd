extends SceneTree

## Смоук-тест основной сцены. В main.tscn намеренно нет врагов: это арена
## для отладки движения, стен и интерактивных объектов. Поэтому проверки,
## которым нужен живой враг, явно пропускаются, а не считаются провалом.
## Проверки игрока и целостности сцены выполняются всегда.

## StaticBody3D с парой MeshInstance3D + CollisionShape3D: у них должен быть
## одинаковый локальный transform, иначе визуал уезжает от коллизии.
const VISUAL_BODIES := [
	"Floor", "BoxLeft", "BoxRight", "LowCeiling", "Stair1", "Stair2", "Stair3"
]

var _failures: Array[String] = []
var _skipped: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_check(packed != null, "main.tscn loads")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var player := scene.find_child("Player", true, false)
	if player != null:
		var magic_book = player.get("magic_book")
		if magic_book != null and int(magic_book.get("primary_school")) == -1:
			magic_book.call("choose_primary", 0)
		await process_frame
		await physics_frame
	_check(player != null, "player exists in main scene")

	var enemies := get_nodes_in_group("enemies")
	print("INFO: main scene registers %d enemies" % enemies.size())
	_check(scene.find_child("EnemyHealthOverlay", true, false) != null, "health overlay is present")
	var has_controller_move := false
	for event in InputMap.action_get_events("move_forward"):
		if event is InputEventJoypadMotion:
			has_controller_move = true
	_check(has_controller_move, "controller movement has a default binding")
	_check(_visuals_match_colliders(scene), "visual meshes match their collision shapes")
	_check(_lining_uses_procedural_shader(scene),
		"all 12 wall-lining meshes use the procedural ShaderMaterial")

	if player == null:
		_finish()
		return

	var health_before: float = player.get("health")
	player.call("take_damage", 25.0)
	_check(
		is_equal_approx(float(player.get("health")), health_before - 25.0),
		"player takes positive damage"
	)
	var after_damage: float = player.get("health")
	player.call("heal", -100.0)
	_check(
		is_equal_approx(float(player.get("health")), after_damage), "negative healing is ignored"
	)
	player.call("heal", 10.0)
	_check(
		is_equal_approx(float(player.get("health")), after_damage + 10.0), "positive healing works"
	)

	if enemies.is_empty():
		_skip("enemy damage, health_changed and overlay tracking (no enemies in main.tscn)")
	else:
		var enemy = enemies[0]
		var enemy_health_before: float = enemy.get("health")
		var health_events: Array[float] = []
		enemy.connect(
			"health_changed",
			func(current: float, _maximum: float) -> void: health_events.append(current)
		)
		enemy.call("take_damage", -10.0)
		_check(
			is_equal_approx(float(enemy.get("health")), enemy_health_before),
			"negative enemy damage is ignored"
		)
		enemy.call("take_damage", 20.0)
		_check(
			is_equal_approx(float(enemy.get("health")), enemy_health_before - 20.0),
			"enemy takes positive damage"
		)
		_check(not health_events.is_empty(), "enemy health_changed emits after damage")

		await process_frame
		var overlay := scene.find_child("EnemyHealthOverlay", true, false)
		if overlay != null:
			var entries: Dictionary = overlay.get("_entries")
			var enemy_id := enemy.get_instance_id()
			_check(entries.has(enemy_id), "damaged enemy is tracked by health overlay")
			if entries.has(enemy_id):
				var enemy_bar = entries[enemy_id]["bar"]
				_check(
					is_equal_approx(float(enemy_bar.get("value")), float(enemy.get("health"))),
					"enemy bar reflects current health"
				)

	player.call("take_damage", 10000.0)
	_check(bool(player.get("is_dead")), "player death state is set at zero health")
	_check(float(player.get("health")) == 0.0, "player health is clamped at zero")

	_finish()


func _visuals_match_colliders(scene: Node) -> bool:
	var checked := 0
	for body_name in VISUAL_BODIES:
		var body := scene.find_child(body_name, true, false)
		if body == null:
			push_error("Missing static body: %s" % body_name)
			return false
		var mesh := body.get_node_or_null("MeshInstance3D") as Node3D
		var shape := body.get_node_or_null("CollisionShape3D") as Node3D
		if mesh == null or shape == null:
			# Декоративные дети могут быть удалены из сцены — сравнивать нечего.
			continue
		checked += 1
		if not mesh.transform.is_equal_approx(shape.transform):
			push_error("Mesh/collider offset on %s" % body_name)
			return false
	return checked >= 4


func _lining_uses_procedural_shader(scene: Node) -> bool:
	var found := 0
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and String(node.name).begins_with("Wall_Lining"):
			var material: Material = (node as MeshInstance3D).material_override
			if material is ShaderMaterial and (material as ShaderMaterial).shader != null \
					and String((material as ShaderMaterial).shader.resource_path).ends_with("wall_wood.gdshader"):
				found += 1
		for child in node.get_children():
			stack.append(child)
	return found == 12


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		_failures.append(label)
		push_error("FAIL: " + label)


func _skip(label: String) -> void:
	_skipped.append(label)
	print("SKIP: ", label)


func _finish() -> void:
	if _failures.is_empty():
		print("All gameplay smoke checks passed (%d skipped)." % _skipped.size())
		quit(0)
	else:
		push_error("%d gameplay smoke check(s) failed." % _failures.size())
		quit(1)

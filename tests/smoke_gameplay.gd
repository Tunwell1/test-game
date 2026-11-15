extends SceneTree

var _failures: Array[String] = []


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
	_check(enemies.size() == 2, "main scene registers two enemies")
	_check(scene.find_child("EnemyHealthOverlay", true, false) != null, "health overlay is present")
	var has_controller_move := false
	for event in InputMap.action_get_events("move_forward"):
		if event is InputEventJoypadMotion:
			has_controller_move = true
	_check(has_controller_move, "controller movement has a default binding")
	if player == null or enemies.is_empty():
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


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		_failures.append(label)
		push_error("FAIL: " + label)


func _finish() -> void:
	if _failures.is_empty():
		print("All gameplay smoke checks passed.")
		quit(0)
	else:
		push_error("%d gameplay smoke check(s) failed." % _failures.size())
		quit(1)

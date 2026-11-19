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

## Снаряды больше не лежат в корне сцены: они живут в пуле (`SpellPool`).
## Помощник собирает все живые и не спящие снаряды пула.
func _live_projectiles() -> Array:
	var found: Array = []
	var pools := get_nodes_in_group("spell_pool")
	for pool in pools:
		for child in pool.get_children():
			if child is SpellProjectile and child.visible \
					and not child.is_queued_for_deletion():
				found.append(child)
	return found


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
	var hud := scene.find_child("HUD", true, false)
	if hud != null:
		var school_layer = hud.get("school_screen")
		_check(school_layer != null and school_layer.mouse_filter == Control.MOUSE_FILTER_STOP,
			"school choice accepts mouse input")
	if player != null and hud != null:
		_check(_debug_controls_work(hud, player),
			"slow motion and spell speed debug controls")
	if player != null:
		var magic_book = player.get("magic_book")
		if magic_book != null and int(magic_book.get("primary_school")) == -1:
			magic_book.call("choose_primary", 0)
		await process_frame
		await physics_frame
	_check(player != null, "player exists in main scene")
	_check(_ambient_vfx_ready(player), "warm light and dust motes are attached to the player")
	_check(_first_person_camera_ready(player), "camera sits at eye level with no spring arm")
	if player != null:
		_check(await _spell_projectiles_distinct(scene, player),
			"four schools create distinct projectiles with trails")
		_check(await _pool_reuses_projectile(scene, player),
			"projectile pool reuses objects instead of allocating per cast")

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


func _first_person_camera_ready(player: Node) -> bool:
	if player == null:
		return false
	var cam := player.find_child("Camera3D", true, false) as Camera3D
	var head := player.find_child("Head", true, false) as Node3D
	if cam == null or head == null or cam.get_parent() != head:
		return false
	for node in player.find_children("*", "SpringArm3D", true, false):
		return false
	var ray := cam.get_node_or_null("InteractRay") as RayCast3D
	return ray != null and absf(cam.position.x) < 0.2 and absf(cam.position.z) < 0.2


func _debug_controls_work(hud: Node, player: Node) -> bool:
	var caster = player.get("spell_caster")
	if caster == null:
		return false
	var f3 := InputEventKey.new()
	f3.physical_keycode = KEY_F3
	f3.pressed = true
	hud.call("_unhandled_input", f3)
	var opened := Engine.time_scale < 1.0

	# F3 по умолчанию: время 1.0, скорость магии 0.1 (замедленный полёт).
	var defaults_ok := is_equal_approx(Engine.time_scale, 1.0) \
		and is_equal_approx(float(caster.get("speed_multiplier")), 0.1)
	var minus := InputEventKey.new()
	minus.physical_keycode = KEY_MINUS
	minus.pressed = true
	hud.call("_unhandled_input", minus)
	var bracket := InputEventKey.new()
	bracket.physical_keycode = KEY_BRACKETRIGHT
	bracket.pressed = true
	hud.call("_unhandled_input", bracket)
	# Шаг свободный: время ушло ниже 1, магия выросла выше 0.1.
	var tuned := Engine.time_scale < 1.0 and float(caster.get("speed_multiplier")) > 0.1
	# Ограничений нет: много нажатий «=» выводит за пределы старых ступеней.
	var plus := InputEventKey.new()
	plus.physical_keycode = KEY_EQUAL
	plus.pressed = true
	for i in 14:
		hud.call("_unhandled_input", plus)
	var unbounded := Engine.time_scale > 0.5

	hud.call("_unhandled_input", f3)
	var restored := is_equal_approx(Engine.time_scale, 1.0) \
		and is_equal_approx(float(caster.get("speed_multiplier")), 1.0)
	return opened and defaults_ok and tuned and unbounded and restored


func _spell_projectiles_distinct(scene: Node, player: Node) -> bool:
	var caster = player.get("spell_caster")
	if caster == null:
		return false
	player.set("mana", 999.0)
	var expected := {
		"fire_bolt": "fire", "wind_gust": "wind",
		"water_jet": "water", "stone_shard": "earth",
	}
	var ok := true
	# Код шейдера по школам: четыре разные материи не могут жить в одном шейдере.
	var school_shaders := {}
	for id in expected:
		caster.set("cooldown_timer", 0.0)
		caster.call("cast", id)
		# Антиципация: сначала эффект «сбора», снаряд вылетает после CAST_WINDUP.
		if scene.find_child("CastGather", true, false) == null:
			ok = false
		# Каст озвучен процедурным сэмплом школы.
		if player.find_child("CastAudio", true, false) == null:
			ok = false
		await create_timer(0.25).timeout
		var found := false
		for child in _live_projectiles():
			if str(child.get("visual")) == str(expected[id]):
				var mesh_node = child.get("_mesh")
				var trail := child.find_child("SpellTrail", true, false)
				var flight_audio := child.find_child("SpellFlightAudio", true, false)
				var smoke := child.find_child("SpellSmoke", true, false)
				# Материал тела тоже обязан быть своим: у школ разные шейдеры,
				# а не один с другим цветом.
				var body_mat = child.get("_mesh_mat")
				var shader_ok := body_mat is ShaderMaterial and body_mat.shader != null
				if shader_ok:
					school_shaders[str(expected[id])] = body_mat.shader.code
				if mesh_node != null and mesh_node.mesh != null and trail != null \
						and flight_audio != null and shader_ok \
						and (str(expected[id]) != "fire" or smoke != null):
					found = true
				# Возвращаем снаряд в пул, иначе он переиспользуется раньше
				# времени и следующий каст возьмёт «занятый» объект.
				child.call("_recycle")
		if not found:
			ok = false
	# Все четыре школы обязаны получить разные шейдеры и все четыре — в кэше.
	if school_shaders.size() != 4:
		ok = false
	else:
		var unique := {}
		for key in school_shaders:
			unique[school_shaders[key]] = true
		if unique.size() != 4:
			ok = false

	# Попадание должно создавать отдельный эффект со вспышкой света,
	# звуком и декалью следа, а не просто исчезать.
	var dummy := Node3D.new()
	scene.add_child(dummy)
	caster.set("cooldown_timer", 0.0)
	caster.call("cast", "fire_bolt")
	await create_timer(0.25).timeout
	var impact_ok := false
	for child in _live_projectiles():
		child.call("_apply_hit", dummy, Vector3.UP)
		if scene.find_child("SpellImpact", true, false) != null \
				and scene.find_child("ImpactFlash", true, false) != null \
				and scene.find_child("ImpactAudio", true, false) != null \
				and scene.find_child("SpellDecal", true, false) != null:
			impact_ok = true
		break
	if not impact_ok:
		ok = false
	dummy.queue_free()

	# Тяжёлый камень даёт короткий hitstop и возвращает время обратно.
	caster.set("cooldown_timer", 0.0)
	caster.call("cast", "stone_shard")
	await create_timer(0.25).timeout
	var earth_proj: Node = null
	for child in _live_projectiles():
		if str(child.get("visual")) == "earth":
			earth_proj = child
			break
	if earth_proj == null:
		return false
	# Сам снаряд за 0.25 с уже мог врезаться в стену — проверяем сам hitstop,
	# чтобы тест не зависел от геометрии арены.
	earth_proj.call("_heavy_hitstop")
	var slowed := Engine.time_scale < 1.0
	await create_timer(0.1, true, false, true).timeout
	var restored := is_equal_approx(Engine.time_scale, 1.0)
	if not slowed or not restored:
		ok = false
	earth_proj.call("_recycle")
	return ok


## Пул: повторный каст не должен создавать новый узел снаряда.
func _pool_reuses_projectile(scene: Node, player: Node) -> bool:
	var caster = player.get("spell_caster")
	if caster == null:
		return false
	player.set("mana", 999.0)
	var pools := get_nodes_in_group("spell_pool")
	if pools.is_empty():
		return false
	var pool: Node = pools[0]
	var before := pool.get_child_count()
	for i in 3:
		caster.set("cooldown_timer", 0.0)
		caster.call("cast", "fire_bolt")
		await create_timer(0.25).timeout
		for child in _live_projectiles():
			child.call("_recycle")
	var after := pool.get_child_count()
	var stats: Dictionary = pool.call("stats")
	# Один-два объекта на школу, а не по одному на каждый из трёх кастов.
	return after == before and int(stats["total"]) <= 4


func _ambient_vfx_ready(player: Node) -> bool:
	if player == null:
		return false
	var light := player.find_child("WarmLight", true, false) as OmniLight3D
	var dust := player.find_child("DustMotes", true, false) as GPUParticles3D
	if light == null or dust == null:
		return false
	if light.shadow_enabled or light.omni_range < 1.0:
		return false
	return dust.amount >= 8 and dust.draw_pass_1 != null and dust.process_material != null


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

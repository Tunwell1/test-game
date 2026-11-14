class_name SpellProjectile
extends Area3D

## Снаряд заклинания. Создаётся кодом из SpellCaster.

var direction: Vector3 = Vector3.FORWARD
var speed: float = 20.0
var damage: float = 10.0
var knockback: float = 0.0
var effect: String = ""
var lifetime: float = 4.0
var caster: Node3D = null
var _spent: bool = false

func _ready() -> void:
	# Мир (1), интерактивные объекты (4), враги (8)
	collision_layer = 0
	collision_mask = 1 | 4 | 8
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + direction * speed * delta
	# Area3D overlap-сигналы сами по себе могут пропустить тонкое препятствие,
	# если снаряд за тик переместился дальше его толщины. Проверяем весь сегмент.
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.position
		var body := hit.collider as Node3D
		if body != null:
			_apply_hit(body)
			return
	global_position = to
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	_apply_hit(body)

func _apply_hit(body: Node3D) -> void:
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
	queue_free()

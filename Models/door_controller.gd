extends AnimatableBody3D

@export_range(0.0, 180.0, 1.0) var open_angle_degrees: float = 100.0
@export var open_duration: float = 0.7
## Change to 1.0 if the leaf should swing to the opposite side.
@export var open_direction: float = -1.0
## glTF node identity for the moving leaf.
@export_range(0, 20, 1) var door_mesh_index: int = 2

var _is_open: bool = false
var _motion: Tween
var _door_mesh: MeshInstance3D
var _outline_mesh: MeshInstance3D
var _initialized: bool = false
var _closed_rotation: Vector3


func _ready() -> void:
	# Enforce the interaction layer even if a parent scene overrides it.
	collision_layer = 4
	collision_mask = 0
	call_deferred("_setup_door")


func _setup_door() -> void:
	if _initialized:
		return
	# This body is an interaction target, not part of the static wall collision.
	collision_layer = 4
	collision_mask = 0
	var imported_model: Node = get_parent().get_node_or_null("ImportedModel")
	if imported_model == null:
		push_warning("Door controller: ImportedModel was not found.")
		return

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(imported_model, meshes)
	if meshes.is_empty():
		push_warning("Door controller: ImportedModel contains no MeshInstance3D nodes.")
		return

	# Prefer the known glTF identity, but fall back to its stable third-mesh order.
	for mesh_instance in meshes:
		if _is_door_mesh(mesh_instance):
			_door_mesh = mesh_instance
			break
	if _door_mesh == null and door_mesh_index < meshes.size():
		_door_mesh = meshes[door_mesh_index]
	if _door_mesh == null or _door_mesh.mesh == null:
		push_warning("Door controller: door mesh not found. Meshes: %s" % _describe_meshes(meshes))
		return

	# Keep the imported leaf exactly where it is when closed, and place this
	# body origin at its node origin—the x=0 (hinge) edge of the mesh.
	var mesh_global_transform: Transform3D = _door_mesh.global_transform
	var hinge_global_transform := Transform3D(mesh_global_transform.basis, mesh_global_transform.origin)
	_door_mesh.reparent(self, false)
	global_transform = hinge_global_transform
	_door_mesh.transform = Transform3D.IDENTITY
	_closed_rotation = rotation

	# The leaf mesh is a thin, high-poly slab. A box from its local mesh bounds
	# is more reliable in Jolt than a convex hull built from every face vertex.
	var mesh_bounds: AABB = _door_mesh.mesh.get_aabb()
	if mesh_bounds.size.length_squared() <= 0.0001:
		push_warning("Door controller: door mesh has empty bounds.")
		return
	var shape := BoxShape3D.new()
	shape.size = mesh_bounds.size
	var collision := CollisionShape3D.new()
	collision.name = "DoorCollision"
	collision.shape = shape
	collision.position = mesh_bounds.position + mesh_bounds.size * 0.5
	add_child(collision)
	_create_outline()
	_initialized = true
	print("Door initialized from mesh '%s' / '%s'. Press E to toggle." % [_door_mesh.name, _door_mesh.mesh.resource_name])


func _create_outline() -> void:
	# Load at runtime so a shader import/compile issue can never disable door interaction.
	var outline_shader := load("res://Models/door_outline.gdshader") as Shader
	if outline_shader == null:
		push_warning("Door outline shader could not be loaded; interaction remains available.")
		return
	_outline_mesh = MeshInstance3D.new()
	_outline_mesh.name = "DoorOutline"
	_outline_mesh.mesh = _door_mesh.mesh
	_outline_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var outline_material := ShaderMaterial.new()
	outline_material.shader = outline_shader
	outline_material.render_priority = 1
	_outline_mesh.material_override = outline_material
	_outline_mesh.visible = false
	_door_mesh.add_child(_outline_mesh)


func set_targeted(targeted: bool) -> void:
	if is_instance_valid(_outline_mesh):
		_outline_mesh.visible = targeted


func interact() -> void:
	if not _initialized:
		_setup_door()
	if not _initialized:
		return
	if _motion and _motion.is_running():
		_motion.kill()

	_is_open = not _is_open
	var target_angle := deg_to_rad(open_angle_degrees * open_direction if _is_open else 0.0)
	var target_rotation := _closed_rotation + Vector3(0.0, target_angle, 0.0)
	_motion = create_tween()
	_motion.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(self, "rotation", target_rotation, open_duration)


func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh != null:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, result)


func _is_door_mesh(node: MeshInstance3D) -> bool:
	var node_name := String(node.name).replace("_", ".")
	var mesh_name := String(node.mesh.resource_name).replace("_", ".") if node.mesh else ""
	return node_name.begins_with("Cube.016") or mesh_name.begins_with("Cube.015")


func _describe_meshes(meshes: Array[MeshInstance3D]) -> String:
	var descriptions: PackedStringArray = []
	for index in range(meshes.size()):
		descriptions.append("%d:%s/%s" % [index, meshes[index].name, meshes[index].mesh.resource_name])
	return ", ".join(descriptions)

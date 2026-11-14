extends StaticBody3D

const STONE_ALBEDO: Texture2D = preload("res://Models/Wall/Default_wall/albedo.png")
const WOOD_ALBEDO: Texture2D = preload("res://Models/Wall/Wall_door/door.png")

## Applies the source colors/textures and builds concave colliders from the
## imported meshes, preserving the door and window openings.
func _ready() -> void:
	var mesh_instances: Array[MeshInstance3D] = []
	_collect_mesh_instances(self, mesh_instances)

	var body_inverse := global_transform.affine_inverse()
	for mesh_instance in mesh_instances:
		if mesh_instance.mesh == null:
			continue

		_apply_wall_materials(mesh_instance)

		var shape := mesh_instance.mesh.create_trimesh_shape()
		if shape == null:
			continue

		var collision := CollisionShape3D.new()
		collision.name = "%s_Collision" % mesh_instance.name
		collision.shape = shape
		collision.transform = body_inverse * mesh_instance.global_transform
		add_child(collision)


func _apply_wall_materials(mesh_instance: MeshInstance3D) -> void:
	for surface_index in range(mesh_instance.mesh.get_surface_count()):
		var source := mesh_instance.mesh.surface_get_material(surface_index)
		if source == null:
			continue

		var material := StandardMaterial3D.new()
		if source is StandardMaterial3D:
			material = (source as StandardMaterial3D).duplicate() as StandardMaterial3D
		if material == null:
			material = StandardMaterial3D.new()

		var material_name := source.resource_name.to_lower()
		var original_color := Color.WHITE
		if source is BaseMaterial3D:
			original_color = (source as BaseMaterial3D).albedo_color

		if material_name.begins_with("glass"):
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color = Color(0.64, 0.79, 0.88, 0.32)
			material.roughness = 0.16
		elif _is_wood(original_color):
			material.albedo_texture = WOOD_ALBEDO
			material.albedo_color = Color.WHITE
			material.roughness = 0.78
		else:
			# The FBX files contain very dark flat material factors and no texture
			# links. Use the project's stone albedo instead of rendering near-black.
			material.albedo_texture = STONE_ALBEDO
			material.albedo_color = _stone_tint(original_color)
			material.roughness = 0.95

		mesh_instance.set_surface_override_material(surface_index, material)


func _is_wood(color: Color) -> bool:
	return color.r > color.g * 1.35 and color.g > color.b * 1.25 and color.r > 0.12


func _stone_tint(color: Color) -> Color:
	return Color(
		maxf(0.68, _linear_to_srgb(color.r)),
		maxf(0.70, _linear_to_srgb(color.g)),
		maxf(0.73, _linear_to_srgb(color.b)),
		1.0
	)


func _linear_to_srgb(channel: float) -> float:
	if channel <= 0.0031308:
		return channel * 12.92
	return 1.055 * pow(channel, 1.0 / 2.4) - 0.055


func _collect_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			result.append(child)
		_collect_mesh_instances(child, result)

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
		var material := StandardMaterial3D.new()
		if source is StandardMaterial3D:
			material = (source as StandardMaterial3D).duplicate() as StandardMaterial3D
		if material == null:
			material = StandardMaterial3D.new()

		var material_name := mesh_instance.mesh.surface_get_name(surface_index).to_lower()
		if source != null:
			material_name += " " + source.resource_name.to_lower()
		var original_color := Color.WHITE
		var has_source_color := false
		var source_is_transparent := false
		if source is BaseMaterial3D:
			var source_material := source as BaseMaterial3D
			original_color = source_material.albedo_color
			has_source_color = true
			source_is_transparent = source_material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED

		# FBX importers do not always retain the material name, so also use its
		# source transparency and pale-blue albedo to recognize window panes.
		if "glass" in material_name or source_is_transparent or (has_source_color and _is_glass(original_color)):
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material.albedo_color = Color(0.64, 0.79, 0.88, 0.18)
			material.roughness = 0.16
		elif _is_wood(original_color):
			material.albedo_texture = WOOD_ALBEDO
			material.albedo_color = Color.WHITE
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material.roughness = 0.78
		else:
			# The FBX files contain very dark flat material factors and no texture
			# links. Use the project's stone albedo instead of rendering near-black.
			material.albedo_texture = STONE_ALBEDO
			material.albedo_color = _stone_tint(original_color)
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			# The panels face outward; render both sides so their backs are not black
			# or invisible when viewed from inside the room.
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material.roughness = 0.95

		mesh_instance.set_surface_override_material(surface_index, material)


func _is_glass(color: Color) -> bool:
	return color.a < 0.98 or (
		color.r > 0.7
		and color.g > color.r * 1.01
		and color.b > color.r * 1.04
		and color.b > 0.85
	)


func _is_wood(color: Color) -> bool:
	return color.r > color.g * 1.35 and color.g > color.b * 1.25 and color.r > 0.12


func _stone_tint(color: Color) -> Color:
	return Color(
		maxf(0.88, _linear_to_srgb(color.r)),
		maxf(0.90, _linear_to_srgb(color.g)),
		maxf(0.93, _linear_to_srgb(color.b)),
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

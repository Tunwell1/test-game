extends StaticBody3D

const STONE_ALBEDO: Texture2D = preload("res://Models/Wall/Default_wall/albedo.png")

## Applies a readable stone material and builds concave static colliders from the
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

		var is_stone := material_name.begins_with("color_") or _is_blue_stone(original_color)
		if is_stone:
			material.albedo_texture = STONE_ALBEDO
			material.albedo_color = Color.WHITE
			material.roughness = 0.95
		elif material_name.begins_with("glass"):
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color = Color(0.64, 0.79, 0.88, 0.32)
			material.roughness = 0.16
		elif maxf(original_color.r, maxf(original_color.g, original_color.b)) < 0.18:
			material.albedo_color = Color(0.38, 0.37, 0.35, 1.0)

		mesh_instance.set_surface_override_material(surface_index, material)


func _is_blue_stone(color: Color) -> bool:
	return (
		color.r < 0.22
		and color.g > color.r * 1.15
		and color.b > color.r * 1.3
		and color.b < 0.35
	)


func _collect_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			result.append(child)
		_collect_mesh_instances(child, result)

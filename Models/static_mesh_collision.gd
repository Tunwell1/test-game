extends StaticBody3D

## Builds static triangle-mesh colliders for imported architectural meshes.
func _ready() -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes($ImportedModel, meshes)
	for index in range(meshes.size()):
		var mesh_instance := meshes[index]
		# Door leaf is Cube.016 / Cube.015. Its stable glTF order is third.
		if _is_door_mesh(mesh_instance) or (meshes.size() >= 3 and index == 2):
			continue
		var shape: ConcavePolygonShape3D = mesh_instance.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var collision := CollisionShape3D.new()
		collision.shape = shape
		var collider_transform: Transform3D = global_transform.affine_inverse() * mesh_instance.global_transform
		add_child(collision)
		collision.transform = collider_transform


func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh != null:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, result)


func _is_door_mesh(node: MeshInstance3D) -> bool:
	var node_name := String(node.name).replace("_", ".")
	var mesh_name := String(node.mesh.resource_name).replace("_", ".") if node.mesh else ""
	return node_name.begins_with("Cube.016") or mesh_name.begins_with("Cube.015")

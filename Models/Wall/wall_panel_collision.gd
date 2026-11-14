extends StaticBody3D

## Builds a concave static collider from the imported wall meshes at runtime.
## This preserves the door and window openings instead of filling them with a box.
func _ready() -> void:
	var mesh_instances: Array[MeshInstance3D] = []
	_collect_mesh_instances(self, mesh_instances)

	var body_inverse := global_transform.affine_inverse()
	for mesh_instance in mesh_instances:
		if mesh_instance.mesh == null:
			continue

		var shape := mesh_instance.mesh.create_trimesh_shape()
		if shape == null:
			continue

		var collision := CollisionShape3D.new()
		collision.name = "%s_Collision" % mesh_instance.name
		collision.shape = shape
		collision.transform = body_inverse * mesh_instance.global_transform
		add_child(collision)


func _collect_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			result.append(child)
		_collect_mesh_instances(child, result)

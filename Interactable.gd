extends StaticBody3D

## Простой интерактивный объект.
## Подключите этот скрипт к StaticBody3D (с дочерним MeshInstance3D),
## чтобы нажатие E меняло цвет и выводило сообщение в консоль.

func interact() -> void:
	print("Interacted with: ", name)
	var mesh_node := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_node and mesh_node.mesh:
		var mat := mesh_node.get_surface_override_material(0) as StandardMaterial3D
		if not mat:
			mat = StandardMaterial3D.new()
			mesh_node.set_surface_override_material(0, mat)
		mat.albedo_color = Color(randf(), randf(), randf())

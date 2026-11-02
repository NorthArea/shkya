extends SceneTree

func _initialize() -> void:
	for path: String in ["res://assets/models/characters/ilyusha/ilyusha.glb", "res://assets/animations/ilyusha/quaternius_in_place.glb"]:
		var scene := load(path) as PackedScene
		if scene == null:
			push_error("Missing imported scene: " + path)
			continue
		var node := scene.instantiate()
		root.add_child(node)
		print(path)
		for child: Node in node.find_children("*", "Skeleton3D", true, false):
			var sk := child as Skeleton3D
			print("SKELETON ", node.get_path_to(sk), " bones=", sk.get_bone_count(), " motion_scale=", sk.motion_scale)
			for i in sk.get_bone_count():
				print(i, " ", sk.get_bone_name(i), " ", sk.get_bone_rest(i))
		for child: Node in node.find_children("*", "MeshInstance3D", true, false):
			var mesh := child as MeshInstance3D
			print("MESH ", node.get_path_to(mesh), " surfaces=", mesh.mesh.get_surface_count(), " bounds=", mesh.mesh.get_aabb(), " transform=", mesh.transform, " skeleton=", mesh.skeleton, " skin=", mesh.skin.get_bind_count() if mesh.skin else 0)
		for child: Node in node.find_children("*", "AnimationPlayer", true, false):
			print("ANIMATIONS ", child.get_animation_list())
		node.free()
	quit()

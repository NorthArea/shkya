extends SceneTree

func _initialize() -> void:
	for class_name_: String in ["TwoBoneIK3D", "IKModifier3D", "Skeleton3D", "SkeletonModifier3D"]:
		if not ClassDB.class_exists(class_name_):
			print(class_name_, " MISSING")
			continue
		print(class_name_)
		for method: Dictionary in ClassDB.class_get_method_list(class_name_, true):
			print(method.name, " ", method.args)
		for property: Dictionary in ClassDB.class_get_property_list(class_name_, true):
			print("PROP ", property.name, " ", property.hint_string)
	quit()

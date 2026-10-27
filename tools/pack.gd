extends SceneTree

func _initialize() -> void:
	var packer := PCKPacker.new()
	DirAccess.make_dir_recursive_absolute("res://builds")
	var result := packer.pck_start("res://builds/ShkyaNovosibirsk.pck")
	if result == OK:
		result = packer.add_file("res://project.godot", "res://project.godot")
	if result == OK:
		result = _pack_dir(packer, "res://game")
	if result == OK:
		result = _pack_dir(packer, "res://assets")
	if result == OK:
		result = packer.flush()
	if result != OK:
		push_error("Packaging failed: " + error_string(result))
		quit(1)
	else:
		print("PACK: builds/ShkyaNovosibirsk.pck")
		quit()

func _pack_dir(packer: PCKPacker, path: String) -> Error:
	for file in DirAccess.get_files_at(path):
		if file.get_extension() not in ["gd", "gdshader", "tscn", "uid", "png", "wav", "mp3", "ogg", "import", "txt"]:
			continue
		var filename := path.path_join(file)
		var result := packer.add_file(filename, filename)
		if result != OK:
			return result
		if file.ends_with(".png.import"):
			var config := ConfigFile.new()
			result = config.load(filename)
			if result != OK:
				return result
			for key in config.get_section_keys("remap"):
				if not key.begins_with("path"):
					continue
				var imported: String = config.get_value("remap", key)
				result = packer.add_file(imported, imported)
				if result != OK:
					return result
	for directory in DirAccess.get_directories_at(path):
		var result := _pack_dir(packer, path.path_join(directory))
		if result != OK:
			return result
	return OK

extends SceneTree
## Лист предпросмотра рисунков ART-01: все SVG из assets/art/characters/ на сером фоне
## -> builds/screenshots/art01/sheet.png. Запуск: ./tools/run.command --headless --script tools/preview_characters.gd

const DIR := "res://assets/art/characters/"
const CELL := Vector2i(200, 300)
const COLUMNS := 8

func _init() -> void:
	var names: Array[String] = []
	for file in DirAccess.get_files_at(DIR):
		if file.ends_with(".svg"):
			names.append(file)
	names.sort()
	var rows := int(ceil(names.size() / float(COLUMNS)))
	var sheet := Image.create(CELL.x * COLUMNS, CELL.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.42, 0.45, 0.50))
	for i in names.size():
		var image := Image.new()
		var error := image.load_svg_from_string(FileAccess.get_file_as_string(DIR + names[i]), 0.25)
		if error != OK:
			push_error("SVG failed: " + names[i])
			continue
		image.convert(Image.FORMAT_RGBA8)
		var at := Vector2i(i % COLUMNS * CELL.x, i / COLUMNS * CELL.y)
		sheet.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)
		print("SHEET %d: %s" % [i, names[i]])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/screenshots/art01"))
	sheet.save_png("res://builds/screenshots/art01/sheet.png")
	quit()

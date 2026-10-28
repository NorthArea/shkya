extends SceneTree
## Лист предпросмотра рисунков ART-01: все SVG из assets/art/characters/ на сером фоне
## -> builds/screenshots/art01/sheet.png. Запуск: ./tools/run.command --headless --script tools/preview_characters.gd
## Крупно и выборочно: ... -- --only=babka,vendor --scale=0.6 --out=sheet_babka
## --only сравнивает префикс имени до ракурса: resident — все жители, resident_man — один (PEOPLE-01);
## --columns=3 — по ракурсу в колонке, --dir=PEOPLE-01/a — подкаталог builds/screenshots/ (по умолчанию art01).

const DIR := "res://assets/art/characters/"
const COLUMNS := 8

func _init() -> void:
	var only: PackedStringArray = []
	var scale := 0.25
	var out := "sheet"
	var columns_max := COLUMNS
	var dir := "art01"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			only = argument.trim_prefix("--only=").split(",")
		elif argument.begins_with("--scale="):
			scale = float(argument.trim_prefix("--scale="))
		elif argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
		elif argument.begins_with("--columns="):
			columns_max = int(argument.trim_prefix("--columns="))
		elif argument.begins_with("--dir="):
			dir = argument.trim_prefix("--dir=")
	var CELL := Vector2i(int(800 * scale), int(1200 * scale))
	var names: Array[String] = []
	for file in DirAccess.get_files_at(DIR):
		if file.ends_with(".svg") and (only.is_empty() or _matches(file, only)):
			names.append(file)
	names.sort()
	var columns := mini(columns_max, names.size())
	var rows := int(ceil(names.size() / float(columns)))
	var sheet := Image.create(CELL.x * columns, CELL.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.42, 0.45, 0.50))
	for i in names.size():
		var image := Image.new()
		var error := image.load_svg_from_string(FileAccess.get_file_as_string(DIR + names[i]), scale)
		if error != OK:
			push_error("SVG failed: " + names[i])
			continue
		image.convert(Image.FORMAT_RGBA8)
		var at := Vector2i(i % columns * CELL.x, i / columns * CELL.y)
		sheet.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)
		print("SHEET %d: %s" % [i, names[i]])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/screenshots/" + dir))
	sheet.save_png("res://builds/screenshots/%s/%s.png" % [dir, out])
	quit()

## Префикс до ракурса: «resident» совпадает со всеми resident_*, «resident_man» — только с resident_man_*;
## полное имя без .svg («ilyusha_front_idle») — один файл.
func _matches(file: String, only: PackedStringArray) -> bool:
	for prefix in only:
		if file.begins_with(prefix + "_") or file.get_basename() == prefix:
			return true
	return false

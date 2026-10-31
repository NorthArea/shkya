extends Node
## The Main-owned local collection outlives worlds. A toast is emitted only after commit.

signal achievement_unlocked(id: StringName)

const Catalog = preload("res://game/progression/achievements.gd")
const DEFAULT_PATH := "user://achievements.json"
const VERSION := 1
var save_path := DEFAULT_PATH
var last_error: Error = OK
var _unlocked: Dictionary = {}

func _init() -> void:
	name = "Achievements"
	add_to_group(&"achievements_store")

func setup(path: String = DEFAULT_PATH) -> Error:
	save_path = path
	_unlocked.clear()
	var primary := _read_snapshot(save_path)
	if primary["error"] == OK:
		_unlocked = primary["unlocked"]
		last_error = OK
		return OK
	var backup := _read_snapshot(save_path + ".bak")
	if backup["error"] == OK:
		_unlocked = backup["unlocked"]
		last_error = _write_atomic(save_path, _payload(_unlocked))
		return last_error
	last_error = OK if primary["error"] == ERR_FILE_NOT_FOUND and backup["error"] == ERR_FILE_NOT_FOUND else ERR_PARSE_ERROR
	return last_error

func unlocked(id: StringName) -> bool:
	return _unlocked.has(String(id))

func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source: Dictionary in Catalog.ALL:
		var entry := source.duplicate()
		entry["unlocked"] = unlocked(entry["id"])
		entry["icon"] = Catalog.icon_path(entry["id"])
		result.append(entry)
	return result

func unlock(id: StringName) -> bool:
	if Catalog.definition(id).is_empty() or unlocked(id):
		return false
	var next := _unlocked.duplicate()
	next[String(id)] = maxi(1, int(Time.get_unix_time_from_system()))
	var payload := _payload(next)
	last_error = _write_atomic(save_path, payload)
	if last_error != OK:
		push_warning("Не удалось сохранить достижение: %s" % error_string(last_error))
		return false
	_unlocked = next
	# The backup mirrors the latest committed set, including the first unlock.
	var backup_error := _write_atomic(save_path + ".bak", payload)
	if backup_error != OK:
		push_warning("Не удалось сохранить резерв достижений: %s" % error_string(backup_error))
	achievement_unlocked.emit(id)
	return true

func _payload(values: Dictionary) -> String:
	return JSON.stringify({"version": VERSION, "unlocked": values})

func _read_snapshot(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": ERR_FILE_NOT_FOUND}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": FileAccess.get_open_error()}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return {"error": ERR_PARSE_ERROR}
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return {"error": ERR_PARSE_ERROR}
	var version: Variant = parsed.get("version")
	if not (version is int or version is float):
		return {"error": ERR_PARSE_ERROR}
	if not is_finite(float(version)) or float(version) != float(VERSION) or not parsed.get("unlocked") is Dictionary:
		return {"error": ERR_PARSE_ERROR}
	var values: Dictionary = parsed["unlocked"]
	for id: Variant in values:
		var timestamp: Variant = values[id]
		if not id is String or Catalog.definition(StringName(id)).is_empty():
			return {"error": ERR_PARSE_ERROR}
		if not (timestamp is int or timestamp is float) or not is_finite(float(timestamp)) or float(timestamp) < 1.0:
			return {"error": ERR_PARSE_ERROR}
	return {"error": OK, "unlocked": values}

func _write_atomic(path: String, payload: String) -> Error:
	var absolute := ProjectSettings.globalize_path(path)
	var dir_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if dir_error != OK:
		return dir_error
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(payload)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return error
	# On the target Mac this rename replaces the destination as one filesystem operation.
	return DirAccess.rename_absolute(temporary, absolute)

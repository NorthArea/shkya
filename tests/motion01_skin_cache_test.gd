extends SceneTree
## Immutable mesh reads may be cached; replacing/editing the mesh must remain visible.

const Imported = preload("res://game/characters/imported_hero_visual.gd")
const Catalog = preload("res://game/characters/character_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var hero := Imported.new()
	hero.configure(Catalog.ILYUSHA_VISIBLE_HEIGHT_M, Color.WHITE)
	root.add_child(hero)
	hero.set_process(false)
	if not check(hero.has_method("_skin_surface_arrays"), "mesh skinning retains immutable arrays instead of GPU reads each frame"):
		hero.free()
		_finish()
		return
	var surface: int = hero._sole_surfaces[0]
	var first: Array = hero.call("_skin_surface_arrays", surface)
	var second: Array = hero.call("_skin_surface_arrays", surface)
	check(is_same(first, second), "repeat reads reuse the same array snapshot")
	var original: Array = hero.uniform_mesh.mesh.surface_get_arrays(surface)
	check(first[Mesh.ARRAY_VERTEX] == original[Mesh.ARRAY_VERTEX], "cached vertices exactly match the real sole")
	check(first[Mesh.ARRAY_BONES] == original[Mesh.ARRAY_BONES] and first[Mesh.ARRAY_WEIGHTS] == original[Mesh.ARRAY_WEIGHTS], "weights and bone bindings are unchanged")
	var replacement := ArrayMesh.new()
	var vertices: PackedVector3Array = original[Mesh.ARRAY_VERTEX].duplicate()
	vertices[0].x += 0.01
	original[Mesh.ARRAY_VERTEX] = vertices
	replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, original)
	hero.uniform_mesh.mesh = replacement
	var replaced: Array = hero.call("_skin_surface_arrays", 0)
	check(replaced[Mesh.ARRAY_VERTEX][0] == vertices[0], "a replacement mesh cannot use the former model's cached vertices")
	check(not is_same(replaced, first), "replacement has an independent snapshot")
	vertices[0].y += 0.02
	original[Mesh.ARRAY_VERTEX] = vertices
	replacement.clear_surfaces()
	replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, original)
	var edited: Array = hero.call("_skin_surface_arrays", 0)
	check(edited[Mesh.ARRAY_VERTEX][0] == vertices[0], "an in-place ArrayMesh edit invalidates its cached surface")
	hero.free()
	_finish()

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok

func _finish() -> void:
	print("MOTION01_SKIN_CACHE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

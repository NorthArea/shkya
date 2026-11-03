extends SceneTree
## Geometry observations must follow a replaced or edited source mesh on the same node.
const Uniform = preload("res://game/characters/uniform_visual.gd")
var failures: Array[String] = []
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:failures.append(label);push_error(label)
func _run() -> void:
	var visual := Uniform.new()
	visual.configure("ilyusha",1.765,Color.WHITE)
	root.add_child(visual)
	await process_frame
	var hero: Node3D=visual.imported_hero
	hero.set_process(false);hero.animation_tree.active=false
	var before: PackedVector3Array=hero._posed_surface_vertices(0)
	var original: ArrayMesh=hero.uniform_mesh.mesh
	var replacement:=_altered(original,.05)
	hero.uniform_mesh.mesh=replacement
	var replaced: PackedVector3Array=hero._posed_surface_vertices(0)
	check(replaced[0].distance_to(before[0])>.03,"source geometry reader follows same-node mesh replacement")
	var changed:=_altered(original,.10)
	var arrays:=changed.surface_get_arrays(0)
	replacement.clear_surfaces()
	replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},changed.surface_get_format(0)&Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	var edited: PackedVector3Array=hero._posed_surface_vertices(0)
	check(edited[0].distance_to(replaced[0])>.03,"source geometry reader follows ArrayMesh.changed after in-place edit")
	visual.free()
	print("READY_HERO_CACHE 2 checks/",failures.size()," failures")
	quit(0 if failures.is_empty()else 1)
func _altered(source: ArrayMesh, dy: float) -> ArrayMesh:
	var result:=ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays:=source.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX].duplicate()
		vertices[0]+=Vector3.UP*dy
		arrays[Mesh.ARRAY_VERTEX]=vertices
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},source.surface_get_format(surface)&Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	return result

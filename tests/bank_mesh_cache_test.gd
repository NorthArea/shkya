extends SceneTree
const Cached = preload("res://game/world/environment_dress.gd")
const Snow = preload("res://game/world/snow_field.gd")
const Cache = preload("res://game/world/bank_mesh_cache.gd")
const OUT := "res://builds/checks/MOTION-01/bank-mesh-cache-regression/"
var checks := 0
var failures := 0
var vertex_count := 0
var index_count := 0
var serialized_bytes := 0
var keys: Array = []

func _initialize() -> void:
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	_run.call_deferred()

func frames(count: int) -> void:
	for _frame in count:
		await process_frame

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func mesh_bytes(mesh: ArrayMesh) -> PackedByteArray:
	var bytes := PackedByteArray()
	for surface in mesh.get_surface_count():
		bytes.append_array(var_to_bytes(mesh.surface_get_arrays(surface)))
	return bytes

func verify_resource_values(entries: Dictionary) -> void:
	for value in entries.values():
		verify(value is ArrayMesh, "cache values contain ArrayMesh resources only")

func compare_key(key: PackedByteArray, mesh: ArrayMesh, ordinal: int) -> void:
	var length := key.decode_double(0)
	var width := key.decode_double(8)
	var height := key.decode_double(16)
	var seed := key.decode_s64(24)
	var toward := key.decode_double(32)
	verify(key.decode_double(40) == Snow.CLOD and key.decode_double(48) == Snow.RAG and key.decode_double(56) == Snow.MARGIN and key.decode_double(64) == Snow.STEP_U and key.decode_double(72) == Snow.STEP_V, "all external geometry constants included")
	verify(key.slice(80).get_string_from_utf8() == Cached.BANK_GEOMETRY_SOURCE_ID, "source helper revision included without reducing parameter key to hash")
	var baseline: ArrayMesh = Cached._bank_mesh_uncached(length,width,height,seed,toward)
	verify(mesh != baseline, "cached mesh is independent of uncached reference resource")
	var before := mesh_bytes(mesh)
	var baseline_before := mesh_bytes(baseline)
	var hit: ArrayMesh = Cached.bank_mesh(length,width,height,seed,toward)
	verify(hit == mesh, "same exact key returns same immutable mesh")
	verify(mesh_bytes(mesh) == before and mesh_bytes(baseline) == baseline_before, "lookup does not mutate cached or reference geometry")
	verify(mesh.get_surface_count() == baseline.get_surface_count(), "surface count matches")
	verify(mesh.get_blend_shape_count() == baseline.get_blend_shape_count(), "blend-shape format matches")
	verify(mesh.get_aabb() == baseline.get_aabb(), "AABB matches")
	verify(mesh.get_meta_list().is_empty(), "cached mesh carries no scene metadata")
	for surface in mesh.get_surface_count():
		verify(mesh.surface_get_format(surface) == baseline.surface_get_format(surface), "surface format exact")
		verify(mesh.surface_get_primitive_type(surface) == baseline.surface_get_primitive_type(surface), "primitive format exact")
		verify(mesh.surface_get_material(surface) == null and baseline.surface_get_material(surface) == null, "no material state stored in mesh")
		var arrays: Array = mesh.surface_get_arrays(surface)
		var reference: Array = baseline.surface_get_arrays(surface)
		verify(arrays.size() == reference.size(), "array slot counts exact")
		for slot in arrays.size():
			verify(typeof(arrays[slot]) == typeof(reference[slot]) and var_to_bytes(arrays[slot]) == var_to_bytes(reference[slot]), "key %d slot %d exact bytes (vertices/normals/colors/UV/index and unused channels)" % [ordinal,slot])
		vertex_count += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		index_count += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		serialized_bytes += var_to_bytes(arrays).size()
	if ordinal == 0:
		var a := MeshInstance3D.new()
		var b := MeshInstance3D.new()
		a.mesh = mesh
		b.mesh = mesh
		a.material_override = StandardMaterial3D.new()
		b.material_override = StandardMaterial3D.new()
		a.position = Vector3(1,2,3)
		b.rotation.y = 1.0
		verify(a.material_override != b.material_override and mesh_bytes(mesh) == before, "per-instance material and transform do not mutate shared geometry")
		var owner_a: WeakRef = weakref(a)
		a.free()
		b.free()
		verify(owner_a.get_ref() == null, "cache retains no mesh instance")
	var altered := [length,width,height,seed,toward]
	for index in 5:
		var modified := altered.duplicate()
		modified[index] = int(modified[index]) + 1 if index == 3 else float(modified[index]) + 0.000000000001
		var other: PackedByteArray = Cached.bank_mesh_cache_key(modified[0],modified[1],modified[2],modified[3],modified[4])
		verify(other != key, "each exact parameter affects full binary key, including sub-float32 changes")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var main: Node = load("res://game/main.tscn").instantiate()
	var stem := OUT + "exact-%d-" % OS.get_process_id()
	main.achievement_path = stem + "achievements.json"
	main.display_settings_path = stem + "display.cfg"
	main.audio_settings_path = stem + "audio.cfg"
	root.add_child(main)
	await frames(8)
	var entries: Dictionary = Cache.entries()
	keys = entries.keys()
	verify(keys.size() == 58 and Cache.stats().entries == 58, "actual normal menu produces all 58 canonical exact keys")
	var retained: WeakRef = weakref(entries[keys[0]])
	for ordinal in keys.size():
		compare_key(keys[ordinal], entries[keys[ordinal]], ordinal)
	verify_resource_values(entries)
	entries.clear()
	for kind: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for player: Node in main.find_children("*", kind, true, false):
			player.stop()
	main.queue_free()
	await frames(10)
	OS.delay_msec(100)
	await process_frame
	main = null
	verify(Cache.stats().entries == 0 and not root.has_meta(Cache.META), "final Main release removes resource-cache metadata")
	verify(retained.get_ref() == null, "final Main release frees cached mesh after all scene owners leave")
	for ordinal in 65:
		Cached.bank_mesh(9.0,1.4,0.9,10000+ordinal,1.0)
	verify(Cache.stats().entries == Cache.CAPACITY and Cache.stats().bypassed == 1, "65 real small geometries remain bounded at 64 entries")
	Cache.clear()
	verify(Cache.stats().entries == 0 and not root.has_meta(Cache.META), "explicit cache clear removes all entries")
	var result := {"checks":checks,"failures":failures,"canonical_keys":keys.size(),"vertices":vertex_count,"indices":index_count,"serialized_array_bytes":serialized_bytes,"limits":["Exact serialized CPU arrays compared in headless; not a native image or GPU equivalence check.","ArrayMesh is shared by read-only contract; callers can still mutate Godot resources if they violate that contract."]}
	var file := FileAccess.open(OUT + "exact-geometry.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  ")+"\n")
	file.close()
	print("BANK_MESH_CACHE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

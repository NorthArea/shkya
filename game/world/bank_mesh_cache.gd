extends RefCounted
## Shared immutable snow-bank meshes for Main's lifetime; no scene or material state.
const META := &"immutable_bank_mesh_cache"
const CAPACITY := 64

static func _data(create := false) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return {}
	if not tree.root.has_meta(META):
		if not create:
			return {}
		tree.root.set_meta(META, {"meshes": {}, "hits": 0, "misses": 0, "bypassed": 0, "lookup_us": 0, "store_us": 0})
	return tree.root.get_meta(META)

static func get_mesh(key: PackedByteArray) -> ArrayMesh:
	var data := _data(true)
	if data.is_empty():
		return null
	var mesh: ArrayMesh = data.meshes.get(key)
	if mesh != null:
		data.hits += 1
	else:
		data.misses += 1
	return mesh

static func store_mesh(key: PackedByteArray, mesh: ArrayMesh) -> void:
	var started := Time.get_ticks_usec()
	var data := _data(true)
	if data.is_empty():
		return
	if data.meshes.size() < CAPACITY:
		data.meshes[key] = mesh
	else:
		data.bypassed += 1
	data.store_us += Time.get_ticks_usec() - started

static func record_lookup(elapsed_us: int) -> void:
	var data := _data(false)
	if not data.is_empty():
		data.lookup_us += elapsed_us

static func stats() -> Dictionary:
	var data := _data(false)
	if data.is_empty():
		return {"entries": 0, "hits": 0, "misses": 0, "bypassed": 0, "lookup_us": 0, "store_us": 0}
	return {"entries": data.meshes.size(), "hits": data.hits, "misses": data.misses, "bypassed": data.bypassed, "lookup_us": data.lookup_us, "store_us": data.store_us}

static func entries() -> Dictionary:
	var data := _data(false)
	return data.meshes.duplicate() if not data.is_empty() else {}

static func clear() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null and tree.root.has_meta(META):
		(tree.root.get_meta(META).meshes as Dictionary).clear()
		tree.root.remove_meta(META)

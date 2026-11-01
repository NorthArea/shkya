extends SceneTree
## Approved SVG palette/width guards on the author mesh, not the gait adapter.
## These guards never establish exact likeness.
const Models = preload("res://game/characters/models/civilian_model.gd")
const Residents = preload("res://game/characters/models/legacy_resident_models.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("IP01_LIKENESS: " + message)
func _run() -> void:
	for drawing: String in ["ilyusha", "babka", "vendor"]:
		_check(not Residents.handles(drawing), drawing + " cannot be routed to a similarly named passer-by")
	_check(Residents.handles("resident_babka"), "walking granny has a separate drawing from the quest grandmother")
	for spec: Array in [["ilyusha", Color("a2f03a"), Color("f4b3cd"), 0.33], ["babka", Color("b6ba78"), Color("fffde2"), 0.23], ["vendor", Color("4e3b2d"), Color("ebd198"), 0.27]]:
		var model := Models.new().build_model(spec[0])
		var mesh := model.get_node("Skeleton3D/UniformMesh").mesh as ArrayMesh
		var colors := []
		var left := INF
		var right := -INF
		for surface in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
			var tint: PackedColorArray = a[Mesh.ARRAY_COLOR]
			for index in vertices.size():
				if bones[index * 4] == 3:
					left = minf(left, vertices[index].x)
					right = maxf(right, vertices[index].x)
				if tint[index] not in colors: colors.append(tint[index])
		_check(right - left >= spec[3], spec[0] + " retains the previous broad head silhouette")
		for wanted: Color in [spec[1], spec[2]]:
			var found := false
			for c: Color in colors:
				if Vector3(c.r - wanted.r, c.g - wanted.g, c.b - wanted.b).length() < 0.015: found = true
			_check(found, spec[0] + " previous SVG palette " + wanted.to_html(false))
		model.free()
	print("IP01_LIKENESS: %d checks, %d failures; approved SVG palette/width and quest-character routing; likeness requires visual review" % [checks, failures])
	quit(0 if failures == 0 else 1)

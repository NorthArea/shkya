extends RefCounted
## Pure inventory/bounds oracle. Perimeter membership comes from canonical
## records, never from a body-name prefix. Visible/contact checks stay WORLD-02.

static func expected_inventory(gameplay: Array, perimeter: Array, bare_names: int, extras: Array[Dictionary]) -> Array[Dictionary]:
	var expected: Array[Dictionary] = []
	var specs: Array = gameplay+perimeter
	for index in specs.size():
		var spec: Array = specs[index]
		var xz: Vector2 = spec[2]
		var size: Vector3 = spec[3]
		expected.append({"name":str(spec[0]) if index < bare_names else "%s_%d" % [spec[0],index], "category":"gameplay" if index < gameplay.size() else "perimeter", "position":Vector3(xz.x,size.y*0.5,xz.y), "size":size})
	for extra: Dictionary in extras:
		var record := extra.duplicate(true)
		record["category"] = "gameplay"
		expected.append(record)
	return expected

static func snapshot(level: Node) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for body in level.get_children():
		# Preserve GREY's existing ground/insurance-wall scope. No perimeter
		# names are excluded: every canonical perimeter collider is inventoried.
		if not body is StaticBody3D or body.name.begins_with("Bound_") or body.name == "Ground":
			continue
		var shapes: Array[CollisionShape3D] = []
		for child in body.get_children():
			if child is CollisionShape3D:
				shapes.append(child)
		var shape: CollisionShape3D = shapes[0] if not shapes.is_empty() else null
		var box: bool = shape != null and shape.shape is BoxShape3D
		rows.append({"name":str(body.name), "position":body.position, "size":shape.shape.size if box else Vector3.ZERO, "is_box":box, "shape_count":shapes.size(), "rotation":body.rotation, "scale":body.scale, "shape_position":shape.position if shape != null else Vector3.ZERO, "shape_rotation":shape.rotation if shape != null else Vector3.ZERO, "shape_scale":shape.scale if shape != null else Vector3.ONE, "layer":body.collision_layer, "disabled":shape.disabled if shape != null else true})
	return rows

static func validate(rows: Array[Dictionary], expected: Array[Dictionary], bounds: Rect2) -> Array[String]:
	var errors: Array[String] = []
	var canonical := {}
	var counts := {}
	for record: Dictionary in expected:
		if canonical.has(record.name):
			errors.append("duplicate canonical record: "+record.name)
		canonical[record.name] = record
	for row: Dictionary in rows:
		var name: String = row.name
		counts[name] = int(counts.get(name,0))+1
		if not canonical.has(name):
			errors.append("unrepresented runtime solid: "+name)
			continue
		var record: Dictionary = canonical[name]
		var position: Vector3 = row.position
		var size: Vector3 = row.size
		if not position.is_finite() or not size.is_finite() or size.x <= 0 or size.y <= 0 or size.z <= 0:
			errors.append(name+": invalid box dimensions/position")
			continue
		if not row.is_box or row.shape_count != 1 or position != record.position or size != record.size:
			errors.append(name+": runtime box differs from canonical record")
		if row.rotation != Vector3.ZERO or row.scale != Vector3.ONE or row.shape_position != Vector3.ZERO or row.shape_rotation != Vector3.ZERO or row.shape_scale != Vector3.ONE:
			errors.append(name+": canonical box must remain axis-aligned and unscaled")
		var lo := position-size*0.5
		var hi := position+size*0.5
		if record.category == "perimeter":
			if absf(lo.y) > 0.001 or row.layer != 1 or row.disabled:
				errors.append(name+": perimeter must stand on ground with active World collision")
		else:
			if lo.x < bounds.position.x or hi.x > bounds.end.x or lo.z < bounds.position.y or hi.z > bounds.end.y or lo.y < -0.001:
				errors.append(name+": gameplay solid outside unchanged bounds/ground")
	for name: String in canonical:
		if int(counts.get(name,0)) != 1:
			errors.append("canonical solid %s expected once, found %d" % [name,int(counts.get(name,0))])
	return errors

extends Node3D

const Layout = preload("res://game/world/layout.gd")
const GrimeShader = preload("res://game/world/shaders/winter_grime.gdshader")
const TEMPERATURE_C := -10
const SEED := 3010
const PATCH_SPACING := 9.0
const ICE_HEIGHT := 0.032
const SLUSH_HEIGHT := 0.038

func _ready() -> void:
	name = "WinterGrime"
	var patches := road_patches()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	_batch("FrozenRuts", plane, patches[&"ice"], _surface_material(true))
	_batch("SaltedSlush", plane, patches[&"slush"], _surface_material(false))
	var clod := SphereMesh.new()
	clod.radius = 0.5
	clod.height = 1.0
	clod.radial_segments = 5
	clod.rings = 2
	_batch("FrozenGrit", clod, patches[&"grit"], _plain(Color(0.31, 0.29, 0.25), 0.95))
	_litter(rng)

static func road_patches() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var ice: Array[Transform3D] = []
	var slush: Array[Transform3D] = []
	var grit: Array[Transform3D] = []
	for surface in Layout.SURFACES:
		if surface[1] != "road": continue
		var center: Vector2 = surface[2]
		var size: Vector2 = surface[3]
		var along_x := size.x > size.y
		var length_m := maxf(size.x, size.y)
		var width_m := minf(size.x, size.y)
		var along := -length_m * 0.5 + 5.0
		while along < length_m * 0.5 - 5.0:
			for side: float in [-1.0, 1.0]:
				var longitudinal := along + rng.randf_range(-1.0, 1.0)
				var rut := side * width_m * 0.25 + rng.randf_range(-0.35, 0.35)
				ice.append(_patch(center, along_x, longitudinal, rut, rng.randf_range(2.0, 4.8), rng.randf_range(0.5, 0.85), ICE_HEIGHT))
				var edge := side * (width_m * 0.5 - 0.85)
				var strip := _patch(center, along_x, longitudinal, edge, rng.randf_range(3.0, 5.8), rng.randf_range(0.7, 1.1), SLUSH_HEIGHT)
				slush.append(strip)
				for k in 3:
					var p := strip.origin + Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4))
					p.y = 0.045
					grit.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3(rng.randf_range(0.07, 0.16), rng.randf_range(0.035, 0.08), rng.randf_range(0.06, 0.13))), p))
			along += PATCH_SPACING + rng.randf_range(-1.5, 1.5)
	return {&"ice": ice, &"slush": slush, &"grit": grit}

static func _patch(center: Vector2, along_x: bool, along: float, across: float, length_m: float, width_m: float, height_m: float) -> Transform3D:
	var p := center + (Vector2(along, across) if along_x else Vector2(across, along))
	var size := Vector3(length_m, 1, width_m) if along_x else Vector3(width_m, 1, length_m)
	return Transform3D(Basis.from_scale(size), Vector3(p.x, height_m, p.y))

func _surface_material(ice: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GrimeShader
	material.set_shader_parameter("frozen", ice)
	return material

func _batch(label: String, mesh: Mesh, transforms: Array[Transform3D], material: Material) -> void:
	var batch := MultiMeshInstance3D.new()
	batch.name = label
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.mesh = mesh
	batch.multimesh.instance_count = transforms.size()
	for i in transforms.size():
		batch.multimesh.set_instance_transform(i, transforms[i])
	batch.material_override = material
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(batch)

func _plain(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _litter(rng: RandomNumberGenerator) -> void:
	var paper: Array[Transform3D] = []
	var cans: Array[Transform3D] = []
	for point in Layout.WINTER_LITTER:
		for i in 2:
			var at := point + Vector3(rng.randf_range(-0.45, 0.45), 0, rng.randf_range(-0.45, 0.45))
			at.y = 0.035
			paper.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3(0.14, 0.025, 0.2)), at))
		cans.append(Transform3D(Basis.from_euler(Vector3(0.1, rng.randf_range(0, TAU), PI * 0.5)), point + Vector3(0.25, 0.055, 0.1)))
	var scrap := BoxMesh.new()
	scrap.size = Vector3.ONE
	_batch("PaperInSnow", scrap, paper, _plain(Color(0.53, 0.49, 0.39), 1.0))
	var can := CylinderMesh.new()
	can.top_radius = 0.035
	can.bottom_radius = 0.035
	can.height = 0.12
	can.radial_segments = 6
	_batch("CrushedCans", can, cans, _plain(Color(0.24, 0.29, 0.27), 0.65))

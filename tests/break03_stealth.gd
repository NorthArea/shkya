extends "res://tests/stealth_test.gd"
## BREAK-03: тот же C7 oracle, но с разрушенным влияющим окружением у киоска.
## _free_residents вызывается после каждого из семи start_game исходного полного набора.
## Сценарии, ожидания, ввод, фазы и число кадров целиком принадлежат stealth_test.gd.

const ENV_INFLUENCE_MARGIN := 16.0
var _fixture_objects: Array = []
var _fixture_worlds := 0
var _fixture_exited := 0
var _fixture_finishing := false

func _free_residents() -> void:
	var live_people = world.get_node_or_null("LevelGeometry/Residents")
	check(live_people != null and live_people.residents.size() == 64, "destroyed C7 world starts with all 64 residents before the inherited director-only isolation")
	super._free_residents()
	var geometry := world.get_node("LevelGeometry")
	var owner := geometry.get_node_or_null("Breakables")
	if not check(owner != null, "destroyed C7 fixture: actual environment controller is present"):
		return
	var selected: Array = []
	var ids: Array = []
	var kinds := {}
	var area: Rect2 = Layout.KIOSK_SQUARE.grow(ENV_INFLUENCE_MARGIN)
	var initial_state := true
	var registry_present := true
	var before_coins: int = owner.coins_dropped
	for entry in Layout.env_breakables():
		var center: Vector2 = entry[2]
		var size: Vector3 = entry[3]
		var footprint := Rect2(center - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z))
		if not footprint.intersects(area): continue
		var b = owner.get_by_id(entry[0])
		if not check(b != null, "destroyed C7 fixture: selected id %s resolves in the real world" % entry[0]): continue
		initial_state = initial_state and b.is_intact()
		registry_present = registry_present and geometry.break_visuals.has(b.id)
		b.smash(&"test", Vector3.RIGHT)
		b.restore_left = 1.0e9
		selected.append(b)
		ids.append(b.id)
		kinds[b.kind] = true
	check(not selected.is_empty(), "destroyed C7 fixture: the influencing environment selection is nonempty")
	check(initial_state and registry_present, "destroyed C7 fixture: real intact objects and visuals were connected before damage")
	var all_solids = Layout.all_solids()
	for source in all_solids.size():
		var solid = all_solids[source]
		if solid[0] in ["KioskPavilion", "KioskBins"] or solid[1] in ["panel", "panel_low", "garage", "kiosk", "snow", "snow_bank"]:
			check(owner.env_at_index(source) == null, "destroyed C7 fixture preserves %s as an immutable blocker" % solid[0])
	check(owner.coins_dropped == before_coins, "destroyed C7 fixture: preparation awards no coins")
	_verify_fixture(selected, "prepared")
	_fixture_worlds += 1
	_fixture_objects = selected
	world.tree_exiting.connect(func():
		if not _fixture_finishing:
			_verify_fixture(selected, "before world exit")
		_fixture_exited += 1)
	print("INFO: BREAK03 destroyed C7 world %d: %d objects, kinds %s; ids %s" % [_fixture_worlds, selected.size(), kinds.keys(), ids])

func _verify_fixture(objects: Array, boundary: String) -> void:
	var remains_broken := not objects.is_empty()
	var collision_consistent := not objects.is_empty()
	for b in objects:
		if not is_instance_valid(b):
			remains_broken = false
			collision_consistent = false
			continue
		remains_broken = remains_broken and b.state == &"broken" and b.restore_left > 0.0
		collision_consistent = collision_consistent and (b.blocks() if b.mode == &"dent" else not b.blocks())
	check(remains_broken, "destroyed C7 fixture %s: every selected object remains broken with restoration disabled" % boundary)
	check(collision_consistent, "destroyed C7 fixture %s: only crushed dent bodies can remain solid" % boundary)

func _finish(code := -1) -> void:
	if not _fixture_finishing:
		_fixture_finishing = true
		_verify_fixture(_fixture_objects, "before final result")
		check(_fixture_worlds > 0 and _fixture_exited + 1 == _fixture_worlds,
			"destroyed C7 fixture: every previous world was checked before replacement (%d prepared, %d exited)" % [_fixture_worlds, _fixture_exited])
		print("INFO: BREAK03 destroyed C7 fixture applied to %d worlds; all oracle scenarios and phase rules inherited" % _fixture_worlds)
	super._finish(code)

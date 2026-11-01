extends SceneTree
## Developer integration: real active bones and CPU-skinned hand surfaces.
## Main/Life/state producers and artistic/GPU acceptance are separate checks.
const Visual = preload("res://game/characters/character_sprite.gd")
const Uniform = preload("res://game/characters/uniform_visual.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CHARACTER05_ACTION_INTEGRATION: " + message)

func _poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bone in skeleton.get_bone_count(): result.append(skeleton.get_bone_pose(bone))
	return result

func _same_pose(a: Array[Transform3D], b: Array[Transform3D]) -> bool:
	if a.size() != b.size(): return false
	for bone in a.size():
		if not a[bone].is_equal_approx(b[bone]): return false
	return true

func _rest(skeleton: Skeleton3D) -> bool:
	for bone in skeleton.get_bone_count():
		if not skeleton.get_bone_pose(bone).is_equal_approx(skeleton.get_bone_rest(bone)): return false
	return true

func _fingerprint(mesh: Mesh, skin: Skin) -> int:
	var contents: Array = []
	for surface in mesh.get_surface_count(): contents.append(mesh.surface_get_arrays(surface))
	for bind in skin.get_bind_count(): contents.append([skin.get_bind_bone(bind), skin.get_bind_pose(bind)])
	return hash(contents)

func _hand_gap(visual: Node, suffix: String, target: Vector3) -> float:
	var instance: MeshInstance3D = visual.uniform_mesh
	var skeleton: Skeleton3D = visual.skeleton
	var hand := skeleton.find_bone("hand" + suffix)
	var nearest := INF
	for surface in instance.mesh.get_surface_count():
		if "skin" not in instance.mesh.surface_get_name(surface): continue
		var arrays := instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for vertex in vertices.size():
			var point := Vector3.ZERO
			var is_hand := false
			for influence in 4:
				var slot := vertex * 4 + influence
				if weights[slot] <= 0.0: continue
				var bind := bones[slot]
				var bone := instance.skin.get_bind_bone(bind)
				point += (skeleton.get_bone_global_pose(bone) * instance.skin.get_bind_pose(bind) * vertices[vertex]) * weights[slot]
				is_hand = is_hand or (bone == hand and weights[slot] >= 0.99)
			if is_hand: nearest = minf(nearest, (instance.global_transform * point).distance_to(target))
	return nearest

func _run() -> void:
	var actor := Node3D.new()
	root.add_child(actor)
	var appearance := Node3D.new()
	actor.add_child(appearance)
	var look := Visual.new()
	look.character = "ilyusha"
	appearance.add_child(look)
	look.set_physics_process(false)
	var visual: Node = look.uniform_visual
	check(visual.skeleton.get_bone_count() == 16 and visual.author_skeleton.get_bone_count() == 14, "action consumer uses the active adapter while keeping artist14")
	var spare: Node = Uniform.new()
	spare.configure("ilyusha", visual.visible_height, Color.WHITE)
	actor.add_child(spare)
	spare.prepare_locomotion()
	var mesh: Mesh = visual.uniform_mesh.mesh
	var skin: Skin = visual.uniform_mesh.skin
	var before_resources := _fingerprint(mesh, skin)
	var actor_transform := actor.global_transform
	var request := {"kind": &"chat", "phase": 0.3, "speaker": true}
	look.submit_locomotion(Vector3.ZERO, true)
	look.submit_action(request)
	request.phase = 0.9
	look._physics_process(1.0 / 60.0)
	check(visual.last_action_kind == &"chat" and not _rest(visual.skeleton), "submitted snapshot reaches real bones")
	var chat_pose := _poses(visual.skeleton)
	for frame in 20: look._physics_process(1.0 / 60.0)
	check(_same_pose(chat_pose, _poses(visual.skeleton)), "repeating the same phase does not accumulate offsets")
	check(actor.global_transform.is_equal_approx(actor_transform), "bone action never changes actor/root transform")
	check(_rest(spare.skeleton) and spare.skeleton != visual.skeleton, "shared sibling keeps independent bones")
	check(mesh == spare.uniform_mesh.mesh and skin == spare.uniform_mesh.skin and before_resources == _fingerprint(mesh, skin), "actions preserve shared mesh, Skin and all geometry arrays")
	check(look.find_children("*", "CollisionObject3D", true, false).is_empty(), "action consumer adds no gameplay collision")
	look.submit_action({"kind": &"none"})
	look._physics_process(1.0 / 60.0)
	check(_rest(visual.skeleton), "none releases all conversation bones to fresh base")
	for kind: StringName in [&"flail", &"down", &"getup"]:
		look.submit_locomotion(Vector3.ZERO, true, &"knock")
		look.submit_action({"kind": kind, "phase": 0.3})
		look._physics_process(1.0 / 60.0)
		check(visual.last_action_kind == kind and not _rest(visual.skeleton), String(kind) + " operates on active recovery bones")
	look.submit_action({"kind": &"flail", "phase": 0.0})
	look._physics_process(1.0 / 60.0)
	var rehit := _poses(visual.skeleton)
	look.submit_action({"kind": &"getup", "phase": 0.8})
	look._physics_process(1.0 / 60.0)
	look.submit_action({"kind": &"flail", "phase": 0.0})
	look._physics_process(1.0 / 60.0)
	check(_same_pose(rehit, _poses(visual.skeleton)), "getup to repeated flail carries no stale recovery pose")
	look.submit_action({"kind": &"chat", "phase": 0.3})
	look._physics_process(1.0 / 60.0)
	check(visual.last_action_kind == &"none" and _rest(visual.skeleton), "knock priority suppresses a stale activity")
	look.submit_locomotion(Vector3.ZERO, true)
	look.submit_action({"kind": &"chat", "phase": 0.3})
	look._physics_process(1.0 / 60.0)
	look.visible = false
	look._physics_process(1.0 / 60.0)
	look.visible = true
	look._physics_process(1.0 / 60.0)
	check(visual.last_action_kind == &"none" and _rest(visual.skeleton), "hidden clears both cached snapshots before reappearance")
	look.submit_action({"kind": &"chat", "phase": 0.3})
	actor.position.x += 5.0
	look._physics_process(1.0 / 60.0)
	look._physics_process(1.0 / 60.0)
	check(visual.last_action_kind == &"none" and _rest(visual.skeleton), "teleport clears cached action without restarting it next tick")
	for kind: StringName in [&"jump_kick", &"stomp_antic", &"stomp_air", &"stomp_land"]:
		look.submit_locomotion(Vector3.ZERO, kind == &"stomp_land")
		look.submit_action({"kind": kind, "phase": 0.5})
		look._physics_process(1.0 / 60.0)
		check(visual.last_action_valid and visual.last_action_kind == kind, String(kind) + " owner phase reaches the pose consumer")
	var paused := _poses(visual.skeleton)
	visual.submit_action({"kind": &"chat", "phase": 0.5})
	visual.update_locomotion(Vector3.ZERO, true, &"locomotion", 0.0)
	check(_same_pose(paused, _poses(visual.skeleton)), "zero delta does not reapply offsets or advance a pose")
	look.submit_locomotion(Vector3.ZERO, true)
	look.reset_pose()
	look._physics_process(1.0 / 60.0)
	check(visual.last_action_kind == &"none" and _rest(visual.skeleton), "consumer reset clears both action caches and contact state")
	_check_grips("ilyusha")
	_check_grips("resident_tourist")
	var occupant: Node = Uniform.new()
	occupant.configure("ilyusha", 1.5, Color.WHITE)
	actor.add_child(occupant)
	occupant.prepare_locomotion()
	occupant.submit_action({"kind": &"chat", "phase": 0.3})
	occupant.update_locomotion(Vector3.ZERO, true, &"locomotion", 1.0 / 60.0)
	occupant.set_occupant_pose(&"lada")
	var seat := _poses(occupant.skeleton)
	occupant.submit_action({"kind": &"flail", "phase": 0.5})
	occupant.update_locomotion(Vector3.ZERO, true, &"knock", 1.0 / 60.0)
	check(occupant.skeleton == occupant.author_skeleton and occupant.skeleton.get_bone_count() == 14 and occupant.last_action_kind == &"none" and _same_pose(seat, _poses(occupant.skeleton)), "occupant author rig and seat override stale action submissions")
	actor.free()
	print("CHARACTER05_ACTION_INTEGRATION: %d checks, %d failures; actual Resident/Life/air producers, tool contact, cabin regression and GPU require separate acceptance" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check_grips(drawing: String) -> void:
	var frame := Node3D.new()
	root.add_child(frame)
	frame.transform = Transform3D(Basis.from_euler(Vector3(0.08, 0.7, -0.04)).scaled(Vector3.ONE * 1.15), Vector3(4, 0.2, -6))
	var visual: Node = Uniform.new()
	visual.configure(drawing, 2.0, Color.WHITE)
	frame.add_child(visual)
	visual.prepare_locomotion()
	var skeleton: Skeleton3D = visual.skeleton
	var grips := {}
	for suffix: String in ["_l", "_r"]:
		var side := 1.0 if suffix == "_l" else -1.0
		var upper := skeleton.find_bone("upper_arm" + suffix)
		var lower := skeleton.find_bone("lower_arm" + suffix)
		var hand := skeleton.find_bone("hand" + suffix)
		var length := skeleton.get_bone_rest(lower).origin.length() + skeleton.get_bone_rest(hand).origin.length()
		var target := skeleton.get_bone_global_rest(upper).origin + Vector3(-side * length * 0.10, -length * 0.60, -length * 0.45)
		grips[suffix] = Transform3D(skeleton.global_basis.orthonormalized(), skeleton.to_global(target))
	var saved := grips.duplicate(true)
	visual.submit_action({"kind": &"dig", "stroke": 0.6, "grips": grips})
	visual.update_locomotion(Vector3.ZERO, true, &"activity", 1.0 / 60.0)
	check(visual.last_action_valid and visual.last_action_kind == &"dig", drawing + " applies work pose with leaned spine")
	for suffix: String in ["_l", "_r"]:
		var target: Transform3D = grips[suffix]
		var gap := _hand_gap(visual, suffix, target.origin)
		check(gap < 0.012, "%s %s actual skinned hand reaches world grip under rotated/scaled parent, gap=%.6f" % [drawing, suffix, gap])
		var contact: Transform3D = visual.hand_contact_transform(suffix)
		check(contact.basis.orthonormalized().is_equal_approx(target.basis), drawing + " hand orientation follows world grip: " + suffix)
	check(grips == saved, drawing + " action IK leaves tool/world grip trajectory unchanged")
	frame.free()

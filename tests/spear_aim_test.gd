extends Node
## Change aim during the thrust: pose, trail and damage must follow the visible lane.
## Run with test_runner.tscn -- --test=res://tests/spear_aim_test.gd --class=spearman

const TARGET := preload("res://scenes/training/training_target.tscn")
var failures := 0


func _check(ok: bool, message: String) -> void:
	printerr(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures += 1


func _ready() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await get_tree().create_timer(0.5).timeout
	get_tree().current_scene.find_child("TrainingButton", true, false).pressed.emit()
	await get_tree().create_timer(2.0).timeout
	var main := get_tree().current_scene
	var player: Player = main.local_player
	main.set_physics_process(false)
	player.set_physics_process(false)
	player.global_position = Vector3(-8.0, 0.0, 10.0)
	player.crit_chance = 0.0
	var targets: Array[TrainingTarget] = []
	for offset in [Vector3(1.3, 0, 0), Vector3(0, 0, -1.3), Vector3(1.3, 0, -1.3)]:
		var target := TARGET.instantiate() as TrainingTarget
		main.world.add_child(target)
		target.global_position = player.global_position + offset
		targets.append(target)
	player.set_melee_aim(Vector3.RIGHT)
	player.attack_melee_toward(Vector3.RIGHT)
	await get_tree().create_timer(player.attack_hit_delay / player.anim_speed * 0.65).timeout
	player.set_melee_aim(Vector3.FORWARD)
	# Keep the model facing the old way to exercise aim changes before body rotation catches up.
	player.face_now(Vector3.RIGHT)
	await get_tree().create_timer(player.attack_hit_delay / player.anim_speed * 0.2).timeout
	var spear := player._weapon_items.spear as Node3D
	var shaft := spear.global_basis.y.normalized()
	_check(shaft.dot(Vector3.FORWARD) > 0.9, "spear pose follows the new decal direction during wind-up")
	var trail: MeshInstance3D
	for child in player.get_children():
		if child is MeshInstance3D and child.mesh is ImmediateMesh:
			trail = child
	_check(trail != null and trail.global_basis.z.dot(Vector3.FORWARD) > 0.99,
			"thrust streak follows the new direction instead of its starting direction")
	_check(is_equal_approx(player._melee_indicator.rotation.y, PI), "decal uses the same live direction")
	var query := player._melee_query(Vector3.FORWARD)
	var points := (query.shape as ConvexPolygonShape3D).points
	var back := INF
	for point in points:
		back = minf(back, point.z)
	_check(is_equal_approx(back, 0.25), "damage prism begins at the visible decal edge")
	await get_tree().create_timer(0.2).timeout
	_check(targets[0].total_damage() == 0.0, "old attack direction deals no damage")
	_check(targets[1].total_damage() > 0.0, "target inside the new decal takes damage")
	_check(targets[2].total_damage() == 0.0, "target outside the decal takes no damage")
	printerr("DONE failures=", failures)
	get_tree().quit(1 if failures else 0)

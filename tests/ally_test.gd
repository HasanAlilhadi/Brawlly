extends Node
## Soldiers (allies) on an open field (town scenery collision off), against orcs held still unless noted:
## - spear soldiers stab (melee only: no projectile, the spear points straight ahead mid-stab);
## - archers shoot from half their hero's bow range, step back from an orc next to them, walk around a wall
##   that blocks their line of fire, and line up behind the hero;
## - teamwork: three swordsmen spread over three orcs; an orc hitting the hero is attacked first;
## - following: a soldier cut off by a cup-shaped wall walks the hero's path out and catches up.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/ally_test.gd
## --shots=<dir> also saves frames of a spear stab (needs a window: --position -4000,-4000, no --headless).

var failures := 0
var shots := ""
var main: Node
var player: Player
var _arrows: Array[Dictionary] = []  # {time, from} of each arrow spawned
var _walls: Array[Node] = []


func _check(ok: bool, message: String) -> void:
	printerr(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures += 1


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots = arg.substr(8)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	while get_tree().current_scene == null or get_tree().current_scene.name != "Main" \
			or get_tree().get_nodes_in_group(&"players").is_empty():
		await get_tree().process_frame
	await _wait(1.0)
	main = get_tree().current_scene
	player = get_tree().get_nodes_in_group(&"players")[0]
	player.max_health = 100000.0
	player.health = 100000.0
	_clear_scenery()
	main.set_physics_process(false)  # the hero walks by joystick_vector here, not by the keyboard / HUD
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is ArrowProjectile:
			_arrows.append({"time": Time.get_ticks_msec(), "node": node}))
	await _spear()
	await _archer_range()
	await _archer_keep_away()
	await _archer_line_of_fire()
	await _archers_behind()
	await _spread()
	await _defend()
	await _follow_around_wall()
	printerr("%s ally: done (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures else 0)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Physics frames until `done` returns true, at most `seconds` of game time; returns the game seconds taken.
func _until(done: Callable, seconds: float) -> float:
	var frames := 0
	var limit := roundi(seconds * Engine.physics_ticks_per_second)
	while not done.call() and frames < limit:
		await get_tree().physics_frame
		frames += 1
	return float(frames) / Engine.physics_ticks_per_second


func _reset(at: Vector3 = Vector3.ZERO) -> void:
	for node in get_tree().get_nodes_in_group(&"units"):
		if node != player:
			node.queue_free()
	for wall in _walls:
		wall.queue_free()
	_walls.clear()
	player.global_position = at
	player.army_order = Player.Order.FOLLOW
	player.trail = PackedVector3Array()
	player.joystick_vector = Vector2.ZERO
	await _wait(0.1)
	_arrows.clear()


func _clear_scenery() -> void:
	for node in main.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		if not body is Unit and body.collision_layer & (GameConfig.LAYER_WORLD | GameConfig.LAYER_FENCE):
			body.collision_layer = 0


func _ally(weapon: String, at: Vector3) -> Ally:
	var ally := NetSpawn.unit(&"ally", at, {"team": player.team_id, "owner": player.peer_id, "weapon": weapon}) as Ally
	ally.max_health = 100000.0
	ally.health = 100000.0
	return ally


func _orc(at: Vector3, still: bool = true) -> Enemy:
	var orc := NetSpawn.unit(&"enemy", at, {"scene": "res://scenes/characters/enemy.tscn", "strength": 1.0,
			"coins": 1.0}) as Enemy
	orc.add_to_group(&"active_enemies")
	orc.max_health = 5000.0
	orc.health = 5000.0
	orc.set_physics_process(not still)
	return orc


## A wall (tree / house layer) centered at `at`, `size` = (x, z) extent.
func _wall(at: Vector3, size: Vector2) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = GameConfig.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, 2.0, size.y)
	shape.shape = box
	body.add_child(shape)
	var look := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	look.mesh = mesh
	body.add_child(look)
	main.world.add_child(body)
	body.global_position = at + Vector3(0, 1.0, 0)
	_walls.append(body)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _spear() -> void:
	await _reset()
	if shots != "":
		main.camera.offset *= 0.5
	var ally := _ally("spear", Vector3(1.5, 0, 0))
	var orc := _orc(Vector3(3.2, 0, 0))
	var best_level := -1.0
	var shot_index := 0
	for i in 240:
		await get_tree().physics_frame
		if ally._stab_phase > 0.4 and ally._stab_phase < 0.7 and ally._right_item:
			best_level = maxf(best_level, ally._right_item.global_basis.y.normalized().dot(ally.facing()))
		if shots != "" and i % 3 == 0 and shot_index < 36:
			get_viewport().get_texture().get_image().save_png("%s/spear_%02d.png" % [shots, shot_index])
			shot_index += 1
	_check(orc.health < orc.max_health, "spear soldier hits in melee (%.0f damage)" % (orc.max_health - orc.health))
	_check(_arrows.is_empty(), "spear soldier never throws (%d projectiles)" % _arrows.size())
	_check(_flat(ally.global_position, orc.global_position) < 2.4, "it fights up close (%.1f m)" % _flat(ally.global_position, orc.global_position))
	_check(best_level > 0.9, "mid-stab the spear points straight ahead (%.2f)" % best_level)
	if shots != "":
		main.camera.offset *= 2.0


func _archer_range() -> void:
	await _reset()
	var ally := _ally("bow", Vector3(0, 0, -1.5))
	await _wait(1.5)  # settles in its spot behind the hero
	var expected := player.aim_range * Ally.ARCHER_RANGE_SHARE
	_check(is_equal_approx(ally.shoot_range, expected), "archers shoot from half the hero's bow range (%.1f m)" % ally.shoot_range)
	# An orc ahead of the hero, a little past the archers' range from it: they walk up and shoot from range.
	var orc := _orc(Vector3(0, 0, expected + 2.0))
	var took := await _until(func() -> bool: return not _arrows.is_empty(), 6.0)
	printerr("  first arrow after %.1f s" % took)
	var gap := _flat(ally.global_position, orc.global_position) - orc.radius
	_check(not _arrows.is_empty() and gap > expected - 1.5 and gap <= expected + 0.3,
			"the first arrow leaves from range (%.1f m from the orc)" % gap)
	await _wait(2.0)
	_check(orc.health < orc.max_health, "its arrows hit (%.0f damage)" % (orc.max_health - orc.health))
	_check(_flat(ally.global_position, orc.global_position) > expected - 1.5, "it keeps its distance (%.1f m)" % _flat(ally.global_position, orc.global_position))


func _archer_keep_away() -> void:
	await _reset()
	var ally := _ally("bow", Vector3(0, 0, 2.0))
	var orc := _orc(Vector3(0, 0, 3.2))
	await _wait(2.5)
	var gap := _flat(ally.global_position, orc.global_position)
	_check(gap > Ally.ARCHER_KEEP_AWAY - 0.3, "an archer steps back from an orc next to it (%.1f m)" % gap)
	_check(orc.health < orc.max_health, "and keeps shooting it (%.0f damage)" % (orc.max_health - orc.health))


func _archer_line_of_fire() -> void:
	await _reset()
	var ally := _ally("bow", Vector3(0, 0, 1.5))
	_wall(Vector3(0, 0, 4.0), Vector2(3.0, 0.6))
	var orc := _orc(Vector3(0, 0, 6.5))
	await _wait(0.3)
	_check(not ally._clear_shot(orc), "the wall blocks the line of fire")
	var took := await _until(func() -> bool: return orc.health < orc.max_health, 9.0)
	_check(orc.health < orc.max_health, "the archer moves until it has a clear shot and hits (%.1f s)" % took)


func _archers_behind() -> void:
	await _reset()
	var archers: Array[Ally] = []
	for i in 3:
		archers.append(_ally("bow", Vector3(-1.0 + i, 0, 1.0)))
	# Walk the hero +X for a while.
	player.joystick_vector = Vector2(1, 0)
	await _wait(3.0)
	player.joystick_vector = Vector2.ZERO
	await _wait(1.5)
	var behind := 0
	for archer in archers:
		if archer.global_position.x < player.global_position.x - 0.8:
			behind += 1
	_check(behind == 3, "archers line up behind the walking hero (%d of 3)" % behind)


func _spread() -> void:
	await _reset()
	var orcs: Array[Enemy] = [_orc(Vector3(-3, 0, 4)), _orc(Vector3(0, 0, 4.5)), _orc(Vector3(3, 0, 4))]
	var soldiers: Array[Ally] = []
	for i in 3:
		soldiers.append(_ally("sword", Vector3(-0.6 + i * 0.6, 0, 1.2)))
	await _wait(3.0)
	var targets := {}
	for soldier in soldiers:
		if soldier.target:
			targets[soldier.target] = true
	_check(targets.size() >= 2, "three swordsmen spread over the orcs (%d different targets)" % targets.size())
	var hit := orcs.filter(func(o: Enemy) -> bool: return o.health < o.max_health).size()
	_check(hit >= 2, "%d of 3 orcs under attack" % hit)


func _defend() -> void:
	await _reset()
	var soldier := _ally("sword", Vector3(0, 0, 1.0))
	var near := _orc(Vector3(1.2, 0, 3.0))  # closer to the soldier, minding its own business
	var attacker := _orc(Vector3(-2.5, 0, -0.5))  # going for the hero
	attacker.target = player
	await _wait(0.6)
	_check(soldier.target == attacker, "a soldier goes for the orc attacking the hero first (%s)" % (soldier.target.name if soldier.target else "none"))
	near.queue_free()


## `no_trail`: the control run — without the hero's trail the soldier stays stuck in the cup.
func _follow_around_wall(no_trail: bool = false) -> void:
	await _reset(Vector3(0, 0, -4.5))
	# A deep cup open toward -Z: back wall at z = 3, sides at x = +-2.2 from z = -3 to 3.
	_wall(Vector3(0, 0, 3.0), Vector2(4.9, 0.5))
	_wall(Vector3(-2.2, 0, 0.0), Vector2(0.5, 6.5))
	_wall(Vector3(2.2, 0, 0.0), Vector2(0.5, 6.5))
	# The soldier is busy with an orc at the bottom of the cup while the hero walks round to behind it.
	var soldier := _ally("sword", Vector3(0, 0, 0.5))
	var orc := _orc(Vector3(0, 0, 2.2))
	await _wait(0.5)
	var path: Array[Vector3] = [Vector3(3.8, 0, -4.5), Vector3(3.8, 0, 6.0), Vector3(0, 0, 6.0)]
	for point in path:
		while _flat(player.global_position, point) > 0.15:
			var step := point - player.global_position
			step.y = 0.0
			player.global_position += step.normalized() * minf(step.length(), 0.08)
			await get_tree().physics_frame
	orc.queue_free()
	if no_trail:
		player.set_physics_process(false)
		player.trail = PackedVector3Array()
	# Out of the cup (past its back wall or round its sides) and next to the hero.
	var out := func() -> bool:
		var at := soldier.global_position
		return (at.z > 3.4 or absf(at.x) > 2.6) and _flat(at, player.global_position) <= 3.0
	var took := await _until(out, 15.0)
	var gap := _flat(soldier.global_position, player.global_position)
	if no_trail:
		printerr("  control (no trail): out and caught up = %s (%.1f m, at %s, %.1f s)" % [out.call(), gap, soldier.global_position, took])
		player.set_physics_process(true)
		return
	_check(out.call(), "a soldier cut off in a cup of walls walks the hero's way out and catches up (%.1f m, %.1f s)" % [gap, took])

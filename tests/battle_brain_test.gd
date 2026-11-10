extends Node
## The commanders' mind (BattleBrain / BrainJob): it picks, soldiers and monsters carry out.
## - the picks themselves, on a hand-made snapshot (no scene): an army's swordsmen spread over the foes, a foe
##   hitting the hero comes first, shooters go for the wounded and get a second choice, monsters get the nearest
##   hero / soldier (the weak-hunters the most wounded, wave monsters the nearest hero however far), orcs and
##   animals ignore each other, a healer gets the most wounded friend (its hero first);
## - in the game: a soldier and a monster take their target from the brain's orders, and with the brain switched
##   off neither picks a fight by itself (nothing scans the battlefield on its own any more);
## - steering: straight ahead and three other ways, no more; a soldier still walks around a wall to its target,
##   and one walled in on every side just stands (no endless probing).
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/battle_brain_test.gd

const SOLDIER := BrainJob.ALLY | BrainJob.FRIENDLY | BrainJob.ASKS
const MONSTER := BrainJob.ENEMY | BrainJob.ASKS
const HERO := BrainJob.HERO | BrainJob.FRIENDLY
const ARMY := 7

var failures := 0
var main: Node
var player: Player
var brain: BattleBrain
var _walls: Array[Node] = []


func _check(ok: bool, message: String) -> void:
	printerr(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures += 1


func _ready() -> void:
	_picks()
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	while get_tree().current_scene == null or get_tree().current_scene.name != "Main" \
			or get_tree().get_nodes_in_group(&"players").is_empty():
		await get_tree().process_frame
	await _wait(1.0)
	main = get_tree().current_scene
	player = get_tree().get_nodes_in_group(&"players")[0]
	player.max_health = 100000.0
	player.health = 100000.0
	brain = main.battle_brain
	for node in main.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		if not body is Unit and body.collision_layer & (GameConfig.LAYER_WORLD | GameConfig.LAYER_FENCE):
			body.collision_layer = 0  # an open field
	main.set_physics_process(false)
	await _orders()
	await _steering()
	printerr("%s battle brain: done (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures else 0)


# --- The picks (BrainJob on its own) ------------------------------------------------------------------------------

func _job() -> BrainJob:
	var job := BrainJob.new()
	job.add(1, Vector3.ZERO, 0, HERO, 0.0, ARMY, 0)  # row 0: the hero
	return job


func _soldier(job: BrainJob, id: int, at: Vector3, extra: int = 0, after: int = 0, hurt: float = 0.0) -> void:
	job.add(id, at, 0, SOLDIER | extra, hurt, ARMY, after, Vector3.INF, 10.0, 0.0, 4.6 if extra & BrainJob.RANGED else 0.0)


func _monster(job: BrainJob, id: int, at: Vector3, extra: int = 0, after: int = 0, hurt: float = 0.0) -> void:
	job.add(id, at, GameConfig.ORC_TEAM, MONSTER | extra, hurt, 0, after, Vector3.INF, 6.5, 0.0, 7.6)


func _picks() -> void:
	# An army's swordsmen spread over the foes instead of piling on the nearest.
	var job := _job()
	for i in 3:
		_soldier(job, 11 + i, Vector3(i * 0.4, 0, 1))
	for i in 3:
		_monster(job, 21 + i, Vector3(i - 1.0, 0, 4))
	job.run()
	var taken := {}
	for row in [1, 2, 3]:
		taken[job.best[row]] = true
	_check(taken.size() == 3 and not taken.has(-1), "three swordsmen are sent at three different orcs (%s)" % [taken.keys()])
	_check(job.near[4] >= 0 and job.flags[job.near[4]] & BrainJob.FRIENDLY != 0, "an orc is told who is nearest to it")

	# The orc hitting the hero comes first, though another is closer.
	job = _job()
	_soldier(job, 11, Vector3(0, 0, 0.5))
	_monster(job, 21, Vector3(0, 0, 3.5))
	_monster(job, 22, Vector3(0, 0, 6.5), 0, 1)  # after the hero
	job.run()
	_check(job.best[1] == 3, "a soldier is sent at the orc that is hitting its hero (row %d)" % job.best[1])

	# Shooters: the wounded one, and a second choice.
	job = _job()
	_soldier(job, 11, Vector3(0, 0, 0.5), BrainJob.RANGED)
	_monster(job, 21, Vector3(0, 0, 6.0))
	_monster(job, 22, Vector3(0, 0, 5.0), 0, 0, 0.9)  # row 3: 4.5 m away, nearly dead
	_monster(job, 23, Vector3(3.0, 0, 0.5))  # row 4: the closest, whole
	job.run()
	_check(job.best[1] == 3 and job.alt[1] >= 0 and job.alt[1] != 3,
			"an archer is sent at the wounded orc, with a second choice (best %d, alt %d)" % [job.best[1], job.alt[1]])
	_check(job.near[1] == 4, "an archer is told which orc is next to it (row %d)" % job.near[1])

	# Monsters: the nearest, the weakest for those that hunt the weak, the nearest hero for wave monsters; an orc
	# doesn't see an angry animal, a soldier does.
	job = _job()
	_soldier(job, 11, Vector3(0, 0, 5.0), 0, 0, 0.8)  # row 1: a wounded soldier
	_monster(job, 21, Vector3(0, 0, 3.0))  # row 2: 3 m from the hero, 2 m from the soldier
	_monster(job, 22, Vector3(0, 0, -3.0), BrainJob.WEAK)  # row 3
	_monster(job, 23, Vector3(200.0, 0, 0), BrainJob.WAVE)  # row 4
	job.add(31, Vector3(0, 0, 4.2), GameConfig.ANIMAL_TEAM, 0, 0.0, 0, 0)  # row 5: an angry hog between orc and soldier
	job.run()
	_check(job.near[2] == 1, "an orc is told about the nearest of hero and soldiers (row %d)" % job.near[2])
	_check(job.near[3] == 0 and job.best[3] == 0, "a weak-hunter with only the hero in reach gets the hero (%d / %d)" % [
			job.near[3], job.best[3]])
	_check(job.near[4] == 0, "a wave monster is sent at the hero from 200 m away (row %d)" % job.near[4])
	_check(job.best[1] == 5, "a soldier is sent at the angry hog next to it, the orcs ignore it (row %d)" % job.best[1])
	job = _job()
	_soldier(job, 11, Vector3(0, 0, 5.0), 0, 0, 0.8)
	_monster(job, 22, Vector3(0, 0, 2.0), BrainJob.WEAK)
	job.run()
	_check(job.near[2] == 0 and job.best[2] == 1, "a weak-hunter is sent at the wounded soldier, not the nearer hero (%d / %d)" % [
			job.near[2], job.best[2]])

	# A healer: the most wounded friend in sight, its hero first; no foe for itself.
	job = _job()
	job.hurt[0] = 0.45
	_soldier(job, 11, Vector3(1, 0, 0), BrainJob.RANGED | BrainJob.HEALER)
	_soldier(job, 12, Vector3(2, 0, 0), 0, 0, 0.5)
	_soldier(job, 13, Vector3(30, 0, 0), 0, 0, 0.9)  # out of sight
	_monster(job, 21, Vector3(1, 0, 3))
	job.run()
	_check(job.patient[1] == 0 and job.best[1] == -1, "a healer is sent to its wounded hero first and at no foe (%d / %d)" % [
			job.patient[1], job.best[1]])
	job.hurt[0] = 0.0
	job.run()
	_check(job.patient[1] == 2, "then to the wounded soldier in sight (row %d)" % job.patient[1])


# --- In the game ---------------------------------------------------------------------------------------------------

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(done: Callable, seconds: float) -> float:
	var frames := 0
	var limit := roundi(seconds * Engine.physics_ticks_per_second)
	while not done.call() and frames < limit:
		await get_tree().physics_frame
		frames += 1
	return float(frames) / Engine.physics_ticks_per_second


func _reset() -> void:
	for node in get_tree().get_nodes_in_group(&"units"):
		if node != player:
			node.queue_free()
	for wall in _walls:
		wall.queue_free()
	_walls.clear()
	player.global_position = Vector3.ZERO
	player.army_order = Player.Order.FOLLOW
	player.joystick_vector = Vector2.ZERO
	await _wait(0.3)


func _ally(at: Vector3) -> Ally:
	var ally := NetSpawn.unit(&"ally", at, {"team": player.team_id, "owner": player.peer_id, "weapon": "sword"}) as Ally
	ally.max_health = 100000.0
	ally.health = 100000.0
	return ally


func _orc(at: Vector3, still: bool = true) -> Enemy:
	var orc := NetSpawn.unit(&"enemy", at, {"scene": "res://scenes/characters/enemies/orc_grunt.tscn", "strength": 1.0,
			"coins": 1.0}) as Enemy
	orc.add_to_group(&"active_enemies")
	orc.max_health = 100000.0
	orc.health = 100000.0
	orc.set_physics_process(not still)
	return orc


func _wall(at: Vector3, size: Vector2) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, 2.0, size.y)
	shape.shape = box
	shape.position.y = 1.0
	body.add_child(shape)
	main.add_child(body)
	body.global_position = at
	_walls.append(body)


func _orders() -> void:
	_check(brain != null and BattleBrain.current == brain, "the match has its commanders' mind")
	await _reset()
	var before := brain.cycle
	var orc := _orc(Vector3(0, 0, 4.0))
	var ally := _ally(Vector3(0.5, 0, 1.0))
	var took := await _until(func() -> bool: return ally.target == orc, 2.0)
	_check(ally.target == orc and ally.brain_best == orc.get_instance_id() and brain.cycle > before,
			"a soldier takes the orc its commander picked (%.2f s, cycle %d)" % [took, ally.brain_cycle])
	_check(brain.last_asking >= 2 and brain.last_rows >= 3, "the snapshot holds hero, soldier and orc (%d rows, %d take orders)" % [
			brain.last_rows, brain.last_asking])

	# The brain off: a soldier and an orc next to their foes do nothing by themselves.
	await _reset()
	brain.enabled = false
	await _wait(0.3)  # (a cycle in flight still hands out)
	orc = _orc(Vector3(0, 0, 3.0), false)
	ally = _ally(Vector3(0.5, 0, 1.0))
	await _wait(1.5)
	_check(ally.target == null and ally.brain_cycle < 0, "with no orders the soldier picks no fight by itself")
	_check(GameConfig.is_gone(orc.target), "with no orders the orc spots nobody by itself")
	brain.enabled = true
	took = await _until(func() -> bool: return ally.target == orc and not GameConfig.is_gone(orc.target), 2.0)
	_check(ally.target == orc and not GameConfig.is_gone(orc.target),
			"orders back: the soldier goes for the orc, the orc for somebody (%.2f s)" % took)

	# A hit can't wait for a cycle: the orc turns on its attacker at once.
	await _reset()
	brain.enabled = false
	await _wait(0.3)
	orc = _orc(Vector3(0, 0, 3.0), false)
	await _wait(0.2)
	orc.take_damage(5.0, player)
	_check(orc.target == player, "a hit provokes the orc at once, brain or no brain")
	brain.enabled = true


func _steering() -> void:
	_check(Unit.STEER_TRIES.size() == 3 and Unit.UNSTICK_TRIES.size() == 3, "a blocked unit tries three other ways, no more")
	# Around a wall to its target.
	await _reset()
	var orc := _orc(Vector3(0, 0, 7.0))
	_wall(Vector3(0, 0, 4.0), Vector2(5.0, 0.6))
	var ally := _ally(Vector3(0, 0, 1.5))
	player.command_army(Player.Order.KILL, orc.global_position)
	var took := await _until(func() -> bool: return ally.flat_distance_to(orc) < 1.6, 9.0)
	_check(ally.flat_distance_to(orc) < 1.6, "a soldier walks around a wall to the orc it is sent at (%.1f s, %.1f m away)" % [
			took, ally.flat_distance_to(orc)])

	# Walled in on every side: it stays put, and looking for a way costs four casts a look at most.
	await _reset()
	orc = _orc(Vector3(0, 0, 9.0))
	for side: Vector3 in [Vector3(0, 0, 1.1), Vector3(0, 0, -1.1), Vector3(1.1, 0, 0), Vector3(-1.1, 0, 0)]:
		_wall(Vector3(0, 0, 3.0) + side, Vector2(2.8, 0.6) if side.x == 0.0 else Vector2(0.6, 2.8))
	ally = _ally(Vector3(0, 0, 3.0))
	player.global_position = Vector3(0, 0, -6.0)
	player.command_army(Player.Order.KILL, orc.global_position)
	var worst := 0.0
	for i in 180:
		var t0 := Time.get_ticks_usec()
		ally.steer(Vector3.BACK, 1.0)  # (delta 1: a fresh look every call)
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
		await get_tree().physics_frame
	_check(Vector2(ally.global_position.x, ally.global_position.z - 3.0).length() < 1.0,
			"a soldier walled in on every side stays inside (%.1f m from the middle)" % Vector2(ally.global_position.x, ally.global_position.z - 3.0).length())
	_check(worst < 2.0, "and looking for a way out stays cheap (worst look %.2f ms)" % worst)

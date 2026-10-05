extends Node
## Balance bench for the class passed with --class: measures real damage in the game (cooldowns, hit frames,
## hit areas) against still orcs with lots of health, crits off, and prints one table row per scenario:
## single target (DPS), a crowd of 6 (total DPS), a line of 4 (pierce), the special ability (damage per use on
## one target and on the crowd), the extra weapons / moves (javelin, knife, dash, wave), all again with the
## damage + rate upgrades maxed. Also the camera: how far ahead the screen shows at each zoom.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/balance_test.gd --class=bowman

const BENCH_TIME: float = 8.0
const AHEAD := Vector3(0, 0, 1)

var main: Node
var player: Player
var _orcs: Array[Enemy] = []
var _rows: Array[String] = []


func _ready() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	while get_tree().current_scene == null or get_tree().current_scene.name != "Main" \
			or get_tree().get_nodes_in_group(&"players").is_empty():
		await get_tree().process_frame
	await _wait(1.0)
	main = get_tree().current_scene
	main.set_physics_process(false)
	HitFx.hit_stop_enabled = false  # online matches have none; it would stall the fast headless clock
	player = get_tree().get_nodes_in_group(&"players")[0]
	player.max_health = 1000000.0
	player.health = 1000000.0
	player.crit_chance = 0.0
	player.coins = 1000000
	_clear_scenery()
	var id := String(player.class_def.id)
	_row("class", "%s  speed %.1f  shield %s  health %.0f" % [id, player.move_speed,
			"%.0f" % player.class_def.shield_health if player.class_def.shield else "-", player.max_health])
	await _camera()
	await _soldier()
	await _bench("base")
	for upgrade in [&"_damage", &"_rate"]:
		var def_id := StringName({"swordsman": "sword", "spearman": "spear", "bowman": "bow"}[id] + upgrade)
		for i in 5:
			player.grant_upgrade(def_id)
	await _bench("maxed")
	await _extras()
	await _camera()
	printerr("\n".join(_rows))
	get_tree().quit(0)


func _row(label: String, text: String) -> void:
	_rows.append("BAL %-26s %s" % [label, text])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _clear_scenery() -> void:
	for node in main.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		if not body is Unit and body.collision_layer & (GameConfig.LAYER_WORLD | GameConfig.LAYER_FENCE):
			body.collision_layer = 0


func _reset() -> void:
	for node in get_tree().get_nodes_in_group(&"units"):
		if node != player:
			node.queue_free()
	_orcs.clear()
	player.global_position = Vector3.ZERO
	player.face_now(AHEAD)
	player._melee_timer = 0.0
	player._shoot_timer = 0.0
	await _wait(0.2)


func _orc(at: Vector3) -> Enemy:
	var orc := NetSpawn.unit(&"enemy", at, {"scene": "res://scenes/characters/enemies/orc_grunt.tscn", "strength": 1.0,
			"coins": 1.0}) as Enemy
	orc.add_to_group(&"active_enemies")
	orc.max_health = 1000000.0
	orc.health = 1000000.0
	orc.set_physics_process(false)
	_orcs.append(orc)
	return orc


func _damage() -> float:
	var total := 0.0
	for orc in _orcs:
		if is_instance_valid(orc):
			total += orc.max_health - orc.health
	return total


## Attack with the weapon in hand toward `point` every frame for `seconds`; returns the damage dealt.
func _attack(point: Vector3, seconds: float, how: String = "main") -> float:
	var frames := roundi(seconds * Engine.physics_ticks_per_second)
	for i in frames:
		var to := point - player.global_position
		to.y = 0.0
		match how:
			"knife":
				player.knife_attack(to)
			"dash":
				player.dash(to)
			_:
				if player.holds_melee():
					player.attack_melee_toward(to)
				else:
					player.shoot(to)
		await get_tree().physics_frame
	await _wait(1.0)  # arrows / spears in flight land
	return _damage()


## The distance a weapon is used from: melee just inside its reach, ranged well inside its range.
func _distance() -> float:
	if player.holds_melee():
		return player.melee_reach() * 0.75
	return 8.0


func _bench(label: String) -> void:
	var d := _distance()
	# One target.
	await _reset()
	_orc(AHEAD * d)
	var single := await _attack(AHEAD * d, BENCH_TIME) / BENCH_TIME
	# A crowd of 6 (two rows of three, 0.9 m apart).
	await _reset()
	for row in 2:
		for col in 3:
			_orc(AHEAD * (d + row * 0.9) + Vector3((col - 1) * 0.9, 0, 0))
	var crowd := await _attack(AHEAD * (d + 0.45), BENCH_TIME) / BENCH_TIME
	# A line of 4 straight ahead.
	await _reset()
	for i in 4:
		_orc(AHEAD * (d + i * 0.8))
	var line := await _attack(AHEAD * d, BENCH_TIME) / BENCH_TIME
	_row("%s %s" % [label, player.current_weapon()], "single %5.1f dps   crowd6 %6.1f dps   line4 %6.1f dps   (dmg %.1f, cd %.2f s, from %.1f m)" % [
			single, crowd, line, player.arrow_damage if player.current_weapon() == "bow" else (player.spear_damage if player.class_def.id == &"spearman" else player.melee_damage),
			player.melee_cooldown if player.holds_melee() else player.shoot_cooldown, d])
	await _ability(label)


## One use of the special ability against one orc and against a crowd of 6.
func _ability(label: String) -> void:
	var results: Array[float] = []
	for crowd in [false, true]:
		await _reset()
		player.training_mode = true
		var center := AHEAD * 3.0
		match player.class_def.ability:
			&"whirlwind":
				center = Vector3.ZERO
				if crowd:
					for i in 6:
						_orc(Vector3(cos(i * TAU / 6.0), 0, sin(i * TAU / 6.0)) * 1.2)
				else:
					_orc(AHEAD * 1.2)
				player.use_ability()
			&"bull_rush":
				if crowd:
					for row in 2:
						for col in 3:
							_orc(AHEAD * (2.5 + row * 1.2) + Vector3((col - 1) * 0.7, 0, 0))
				else:
					_orc(AHEAD * 3.0)
				player.use_ability()
			&"bow_rain":
				center = AHEAD * 8.0
				if crowd:
					for row in 2:
						for col in 3:
							_orc(center + Vector3((col - 1) * 1.4, 0, (row - 0.5) * 1.4))
				else:
					_orc(center)
				player.use_bow_rain(center)
		await _wait(player.class_def.ability_duration + 1.5)
		player.training_mode = false
		results.append(_damage())
	_row("%s ability %s" % [label, player.class_def.ability], "one target %6.0f   crowd6 %6.0f total (%.0f each)   %.1f s" % [
			results[0], results[1], results[1] / 6.0, player.class_def.ability_duration])


func _extras() -> void:
	match player.class_def.id:
		&"swordsman":
			player.grant_upgrade(&"sword_dash")
			await _reset()
			for i in 3:
				_orc(AHEAD * (1.5 + i * 1.2))
			var dash := await _attack(AHEAD * 10.0, 0.1, "dash")
			_row("maxed dash", "%.0f per enemy crossed, every %.1f s" % [dash / 3.0, Player.DASH_COOLDOWN])
			player.grant_upgrade(&"sword_wave")
			await _reset()
			for i in 4:
				_orc(AHEAD * (1.2 + i * 1.0))
			var wave := await _attack(AHEAD * 1.2, BENCH_TIME) / BENCH_TIME
			_row("maxed sword + wave", "line4 %.1f dps" % wave)
		&"spearman":
			player.grant_upgrade(&"spear_throw")
			player.switch_weapon()
			await _reset()
			_orc(AHEAD * 8.0)
			var single := await _attack(AHEAD * 8.0, BENCH_TIME) / BENCH_TIME
			_row("maxed javelin", "single %.1f dps from 8 m (dmg %.1f, cd %.2f s)" % [single, player.spear_damage, player.spear_cooldown])
			player.switch_weapon()
		&"bowman":
			player.grant_upgrade(&"knife")
			await _reset()
			_orc(AHEAD * 0.8)
			var knife := await _attack(AHEAD * 0.8, BENCH_TIME, "knife") / BENCH_TIME
			_row("knife", "single %.1f dps (dmg %.0f, cd %.2f s)" % [knife, player.knife_damage, Player.KNIFE_COOLDOWN])
			for i in 3:
				player.grant_upgrade(&"bow_range")
			for i in 2:
				player.grant_upgrade(&"bow_pierce")
			await _reset()
			for i in 4:
				_orc(AHEAD * (8.0 + i * 0.8))
			var line := await _attack(AHEAD * 8.0, BENCH_TIME) / BENCH_TIME
			_row("maxed bow + pierce 2", "line4 %.1f dps, range %.1f m" % [line, player.aim_range])


## One soldier of the class's weapon against a still orc: its damage per second.
func _soldier() -> void:
	await _reset()
	var ally := NetSpawn.unit(&"ally", AHEAD * 1.5, {"team": player.team_id, "owner": player.peer_id,
			"weapon": player.class_def.ally_weapon}) as Ally
	ally.max_health = 1000000.0
	ally.health = 1000000.0
	_orc(AHEAD * 4.0)
	await _wait(1.5)  # walks up
	var before := _damage()
	await _wait(BENCH_TIME)
	_row("soldier %s" % ally.weapon, "%.1f dps, %.0f hp (from %.1f m)" % [(_damage() - before) / BENCH_TIME, ally._base_max_health if "_base_max_health" in ally else ally.max_health,
			ally.global_position.distance_to(_orcs[0].global_position)])
	ally.queue_free()


## How far ahead (screen up, the short side) and to the side the screen shows at the current zoom.
func _camera() -> void:
	await _reset()
	main.set_physics_process(true)
	await _wait(0.5)
	var camera: Camera3D = main.camera
	var size := get_viewport().get_visible_rect().size
	var reach := func(direction: Vector3) -> float:
		var d := 0.5
		while d < 60.0:
			var p := camera.unproject_position(player.global_position + direction * d)
			if p.x < 0.0 or p.y < 0.0 or p.x > size.x or p.y > size.y:
				return d
			d += 0.25
		return d
	var up: Vector3 = main._screen_to_world(Vector2(0, -1))
	var down: Vector3 = main._screen_to_world(Vector2(0, 1))
	var side: Vector3 = main._screen_to_world(Vector2(1, 0))
	_row("camera", "zoom %.2f: %.1f m up, %.1f m down, %.1f m to the side (aim range %.1f m)" % [
			camera.zoom, reach.call(up), reach.call(down), reach.call(side), player.aim_range])
	main.set_physics_process(false)

extends Node
## AI behaviour (solo):
## 0. Going down next to a warband: its members keep running (a downed player still keeps it awake).
## 1. Target stickiness: while the player shoots a warband from range and their soldiers brawl with it, its
##    members must not keep flipping between the player and the soldiers.
## 2. Obstacles: the Warlord walks around a wall that stands between it and the player, and never stays stuck.
## 3. Point-blank arrows hit an orc / a big brute touching the player; an arrow aimed beside an orc flies past.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/ai_test.gd

const WATCH_TIME := 10.0
const GRUNT := "res://scenes/characters/enemies/orc_grunt.tscn"
const BRUTE := "res://scenes/characters/enemies/orc_brute.tscn"

var t := 0.0
var phase := 0
var pt := 0.0
var main: Node
var player: Player
var band: Warband
var warlord: Enemy
var shot_timer := 0.0
var last_targets: Dictionary = {}  # enemy -> target
var switches: Dictionary = {}  # enemy -> count
var start_dist := 0.0
var last_pos := Vector3.ZERO
var still_time := 0.0
var max_still := 0.0
var failures := 0


func _ready() -> void:
	Net.profile["class"] = &"bowman"  # the point-blank arrow checks
	Net.open_offline_lobby()
	Net.settings.seed = 12345
	Net.set_setting("events", false)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _log(msg: String) -> void:
	printerr("[%.1fs] %s" % [t, msg])


func _check(ok: bool, what: String) -> void:
	_log(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


func _next() -> void:
	phase += 1
	pt = 0.0


func _clear() -> void:
	for node in get_tree().get_nodes_in_group(&"units"):
		if node != player:
			node.queue_free()


func _spawn(scene: String, at: Vector3) -> Enemy:
	var enemy := NetSpawn.unit(&"enemy", at, {"scene": scene, "strength": 1.0, "coins": 1.0}) as Enemy
	enemy.add_to_group(&"active_enemies")
	enemy.set_physics_process(false)
	return enemy


func _process(delta: float) -> void:
	t += delta
	pt += delta
	main = get_tree().current_scene
	if main == null or main.name != "Main" or main.get("local_player") == null:
		return
	player = main.local_player
	match phase:
		0:
			if pt < 1.0:
				return
			player.max_health = 1e6
			player.health = 1e6
			# A mid-size band near the start (an orc one: no skeletons lying around between fights).
			var best_dist := INF
			for node in get_tree().get_nodes_in_group(&"warbands"):
				var b := node as Warband
				var d := b.global_position.length()
				if b.size >= 5 and b.faction == &"orc" and d < best_dist:
					best_dist = d
					band = b
			player.global_position = band.global_position + Vector3(0, 0, 7.0)
			band.alert(player)
			phase = 8
			pt = 0.0
		8:
			if pt > 1.0 and not player.is_downed:
				GameConfig.downed_enabled = true
				player.take_damage(player.health * 2.0, band.leader)
			if pt < 4.0:
				return
			var paused := 0
			var members := band.members()
			for enemy in members:
				if enemy.process_mode == Node.PROCESS_MODE_DISABLED:
					paused += 1
			_check(player.is_downed and members.size() > 0 and paused == 0, "a band next to a downed player keeps running (%d of %d paused)" % [paused, members.size()])
			GameConfig.downed_enabled = false
			player.revive(player.global_position)
			player.health = player.max_health
			for i in 10:
				NetSpawn.unit(&"ally", player.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-1, 1)),
						{"team": player.team_id, "owner": player.peer_id, "color": player.unit_color})
			phase = 1
			pt = 0.0
		1:
			# The player keeps shooting the band from range while the soldiers brawl with it.
			shot_timer -= delta
			var members := band.members()
			if shot_timer <= 0.0 and not members.is_empty():
				shot_timer = 0.6
				(members.pick_random() as Enemy).take_damage(1.0, player, false)
			for enemy in members:
				var current: Node3D = enemy.target if is_instance_valid(enemy.target) else null
				if last_targets.has(enemy) and last_targets[enemy] != current and current != null and last_targets[enemy] != null:
					switches[enemy] = switches.get(enemy, 0) + 1
				last_targets[enemy] = current
			if pt > WATCH_TIME:
				var total := 0
				var most := 0
				for enemy in last_targets:
					total += switches.get(enemy, 0)
					most = maxi(most, switches.get(enemy, 0))
				var average := float(total) / maxf(last_targets.size(), 1.0)
				_check(average <= 1.5 and most <= 4, "enemies stick to their targets: %.1f switches each in %ds (max %d, %d enemies)" % [average, WATCH_TIME, most, last_targets.size()])
				_next()
		2:
			# Clear the fight, then put a wall between the Warlord and the player.
			_clear()
			player.global_position = Vector3(0, 0, 5.0)
			var wall := StaticBody3D.new()
			wall.collision_layer = GameConfig.LAYER_WORLD
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(6.0, 2.0, 1.0)
			shape.shape = box
			shape.position.y = 1.0
			wall.add_child(shape)
			main.get_node("World").add_child(wall)
			wall.global_position = Vector3.ZERO
			warlord = main.world_events.spawn_warlord(player)
			for enemy in main.world_events.warlord_band.members():
				if enemy != warlord:
					enemy.queue_free()
			warlord.global_position = Vector3(0, 0, -6.0)
			main.world_events.warlord_band.global_position = warlord.global_position
			start_dist = warlord.global_position.distance_to(player.global_position)
			last_pos = warlord.global_position
			_next()
		3:
			var moved := warlord.global_position.distance_to(last_pos)
			last_pos = warlord.global_position
			var dist := warlord.global_position.distance_to(player.global_position)
			if moved < 0.5 * delta and dist > 4.0:
				still_time += delta
				max_still = maxf(max_still, still_time)
			else:
				still_time = 0.0
			if dist < 3.5 or pt > 20.0:
				_check(dist < 3.5, "Warlord got around the wall to the player (%.1f -> %.1f m in %.1fs)" % [start_dist, dist, pt])
				_check(max_still < 1.5, "Warlord never stuck (longest stop %.1fs)" % max_still)
				_next()
		4:
			# Point-blank arrows: an orc right in front of the player, then a big brute.
			_clear()
			player.global_position = Vector3(20, 0, 20)
			var orc := _spawn(GRUNT, player.global_position + Vector3(0.45, 0, 0))
			set_meta(&"orc", orc)
			set_meta(&"orc_health", orc.max_health)
			player._shoot_timer = 0.0
			player.shoot(Vector3(1, 0, 0))
			_next()
		5:
			if pt > 0.3:
				var orc: Enemy = get_meta(&"orc")
				_check(is_instance_valid(orc) and orc.health < float(get_meta(&"orc_health")),
						"point-blank arrow hits an orc touching the player")
				if is_instance_valid(orc):
					orc.queue_free()
				var brute := _spawn(BRUTE, player.global_position + Vector3(0, 0, -0.9))
				set_meta(&"orc", brute)
				set_meta(&"orc_health", brute.max_health)
				player._shoot_timer = 0.0
				player.shoot(Vector3(0, 0, -1))
				_next()
		6:
			if pt > 0.3:
				var brute: Enemy = get_meta(&"orc")
				_check(is_instance_valid(brute) and brute.health < float(get_meta(&"orc_health")),
						"point-blank arrow hits a brute touching the player")
				if is_instance_valid(brute):
					brute.queue_free()
				# No aim snapping: an arrow aimed 6° beside an orc 8 m away flies past it.
				var orc := _spawn(GRUNT, player.global_position + Vector3(8, 0, 0))
				set_meta(&"orc", orc)
				set_meta(&"orc_health", orc.max_health)
				player._shoot_timer = 0.0
				player.shoot(Vector3(cos(deg_to_rad(6.0)), 0, sin(deg_to_rad(6.0))))
				phase = 9  # (8 is the downed check that runs first)
				pt = 0.0
		9:
			if pt > 1.0:
				var orc: Enemy = get_meta(&"orc")
				_check(is_instance_valid(orc) and is_equal_approx(orc.health, float(get_meta(&"orc_health"))),
						"an arrow aimed beside an orc flies where aimed (no snapping)")
				_log("DONE failures=%d" % failures)
				get_tree().quit(1 if failures > 0 else 0)

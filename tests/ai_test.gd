extends Node
## AI behaviour (solo):
## 1. Target stickiness: while the player and their soldiers fight a camp together, orcs must not keep
##    flipping between the player and the soldiers.
## 2. Obstacles: the Warlord walks around a camp house that stands between it and the player, and
##    never stays stuck.
## 3. Small squads live in tents, big ones in houses.
## 0. First, going down next to that camp: its orcs keep running (a downed player still keeps it awake).
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/ai_test.gd

const WATCH_TIME := 10.0

var t := 0.0
var phase := 0
var pt := 0.0
var main: Node
var player: Player
var camp: Camp
var warlord: Warlord
var shot_timer := 0.0
var last_targets: Dictionary = {}  # orc -> target
var switches: Dictionary = {}  # orc -> count
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
			# A mid-size camp near the start.
			var best_dist := INF
			for node in get_tree().get_nodes_in_group(&"camps"):
				var c := node as Camp
				var d := c.global_position.length()
				if c.squad_size >= 5 and d < best_dist:
					best_dist = d
					camp = c
			player.global_position = camp.global_position + Vector3(0, 0, camp.radius + 7.0)
			phase = 8
			pt = 0.0
		8:
			if pt > 1.0 and not player.is_downed:
				GameConfig.downed_enabled = true
				player.take_damage(player.health * 2.0, camp)
			if pt < 4.0:
				return
			var paused := 0
			var orcs := 0
			for orc in camp._squad:
				if orc and is_instance_valid(orc) and not orc.is_dead:
					orcs += 1
					if orc.process_mode == Node.PROCESS_MODE_DISABLED:
						paused += 1
			_check(player.is_downed and orcs > 0 and paused == 0, "orcs next to a downed player keep running (%d of %d paused)" % [paused, orcs])
			GameConfig.downed_enabled = false
			player.revive(player.global_position)
			player.health = player.max_health
			for i in 10:
				NetSpawn.unit(&"ally", player.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-1, 1)),
						{"team": player.team_id, "owner": player.peer_id, "color": player.unit_color})
			phase = 1
			pt = 0.0
		1:
			# The player keeps shooting the camp from range while the soldiers brawl with the squad.
			shot_timer -= delta
			if shot_timer <= 0.0:
				shot_timer = 0.6
				camp.take_damage(1.0, player, false)
			for node in get_tree().get_nodes_in_group(&"enemies"):
				var orc := node as Enemy
				if orc.camp != camp or orc.is_dead:
					continue
				var current: Node3D = orc.target if is_instance_valid(orc.target) else null
				if last_targets.has(orc) and last_targets[orc] != current and current != null and last_targets[orc] != null:
					switches[orc] = switches.get(orc, 0) + 1
				last_targets[orc] = current
			if pt > WATCH_TIME:
				var total := 0
				var most := 0
				for orc in last_targets:
					total += switches.get(orc, 0)
					most = maxi(most, switches.get(orc, 0))
				var average := float(total) / maxf(last_targets.size(), 1.0)
				_check(average <= 1.5 and most <= 4, "orcs stick to their targets: %.1f switches per orc in %ds (max %d, %d orcs)" % [average, WATCH_TIME, most, last_targets.size()])
				_next()
		2:
			# Clear the fight, then put a camp house between the Warlord and the player.
			for node in get_tree().get_nodes_in_group(&"units"):
				if node != player:
					node.queue_free()
			camp.respawn_delay = 1e6
			player.global_position = camp.global_position + Vector3(0, 0, camp.radius + 5.0)
			warlord = main.world_events.spawn_warlord(player)
			for orc in warlord._band:
				orc.queue_free()
			warlord.global_position = camp.global_position - Vector3(0, 0, camp.radius + 9.0)
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
				_check(dist < 3.5, "Warlord got around the house to the player (%.1f -> %.1f m in %.1fs)" % [start_dist, dist, pt])
				_check(max_still < 1.5, "Warlord never stuck (longest stop %.1fs)" % max_still)
				_next()
		4:
			var wrong := 0
			var tents := 0
			for node in get_tree().get_nodes_in_group(&"camps"):
				var c := node as Camp
				var tent := (c.get_node("Tent") as Node3D).visible or c.is_dead
				if tent != (c.squad_size <= c.tent_max_squad) and not c.is_dead:
					wrong += 1
				if c.squad_size <= c.tent_max_squad:
					tents += 1
			_check(wrong == 0 and tents > 0, "small squads in tents (%d tents, %d wrong)" % [tents, wrong])
			_next()
		5:
			# Point-blank arrows: an orc right in front of the player, then a camp wall.
			for node in get_tree().get_nodes_in_group(&"units"):
				if node != player:
					node.queue_free()
			player.global_position = Vector3(0, 0, 0)
			var orc := NetSpawn.unit(&"enemy", player.global_position + Vector3(0.45, 0, 0), {
				"scene": "res://scenes/characters/enemy.tscn", "strength": 1.0, "coins": 1.0}) as Enemy
			orc.add_to_group(&"active_enemies")
			orc.set_physics_process(false)
			set_meta(&"orc", orc)
			set_meta(&"orc_health", orc.max_health)
			player._shoot_timer = 0.0
			player.shoot(Vector3(1, 0, 0))
			_next()
		6:
			if pt > 0.3:
				var orc: Enemy = get_meta(&"orc")
				_check(is_instance_valid(orc) and orc.health < float(get_meta(&"orc_health")),
						"point-blank arrow hits an orc touching the player")
				if is_instance_valid(orc):
					orc.queue_free()
				camp.respawn_delay = 1e6
				player.global_position = camp.global_position + Vector3(0, 0, camp.radius + 0.05)  # touching the wall
				set_meta(&"camp_health", camp.health)
				player._shoot_timer = 0.0
				player.shoot(Vector3(0, 0, -1))
				_next()
		7:
			if pt > 0.3:
				_check(camp.health < float(get_meta(&"camp_health")), "point-blank arrow hits the camp wall (%.0f -> %.0f)" % [get_meta(&"camp_health"), camp.health])
				# No aim snapping: an arrow aimed 6° beside an orc 8 m away flies past it.
				player.global_position = Vector3(0, 0, 0)
				var orc := NetSpawn.unit(&"enemy", Vector3(8, 0, 0), {
					"scene": "res://scenes/characters/enemy.tscn", "strength": 1.0, "coins": 1.0}) as Enemy
				orc.add_to_group(&"active_enemies")
				orc.set_physics_process(false)
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

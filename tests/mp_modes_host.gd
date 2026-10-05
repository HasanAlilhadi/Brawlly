extends Node
## Plays King of the Hill on Crown Ruins with the client, checking the team spawn areas (the map's bases, free of
## warbands) and the hill score on the server; then a supply drop lands for both.
var t := 0.0
var step := 0
var st := 0.0
var modes := [Net.Mode.KING_OF_THE_HILL]
var round_i := 0
func _ready() -> void:
	Net.profile.name = "Hosty"; Net.host()
func _log(m: String) -> void:
	printerr("HOST [%.1f] %s" % [t, m])
func _p(peer_is_host: bool) -> Player:
	for p in get_tree().get_nodes_in_group(&"players"):
		if (p.peer_id == 1) == peer_is_host: return p
	return null
func _gm() -> GameMode:
	var main := get_tree().current_scene
	return main.game_mode if main and main.name == "Main" else null
func _process(delta: float) -> void:
	t += delta; st += delta
	match step:
		0: # lobby: configure next mode
			if Net.players.size() >= 2 and st > 1.0:
				Net.set_setting("mode", modes[round_i]); Net.set_setting("map", "crown_ruins"); Net.set_setting("band_count", 4); Net.set_setting("score_limit", 5)
				var client_peer: int = Net.players.keys().filter(func(k): return k != 1)[0]
				Net.set_team(client_peer, 1); Net.set_team(1, 0)
				Net.start_game(); step = 1; st = 0
		1:
			if _p(true) and _p(false) and st > 2.5:
				var h := _p(true); var c := _p(false)
				_log("== %s: host team %d, client team %d" % [Net.MODE_NAMES[modes[round_i]], h.team_id, c.team_id])
				# One spawn area per team, far apart, with no warband near either.
				var bases: Array[Vector3] = _gm().world_spawn_points()
				var near_camp := INF
				for camp: Node3D in get_tree().get_nodes_in_group(&"warbands"):
					for base in bases:
						near_camp = minf(near_camp, camp.global_position.distance_to(base))
				var host_base := _gm().spawn_point_for(h.peer_id)
				var client_base := _gm().spawn_point_for(c.peer_id)
				if bases.size() != 2 or host_base.distance_to(client_base) < 30.0 or near_camp < 24.0 \
						or get_tree().get_node_count_in_group(&"shop_stations") > 0:
					printerr("FAILED team spawn areas in %s (bases %d, %.1f m apart, nearest warband %.1f m)" % [
							Net.MODE_NAMES[modes[round_i]], bases.size(), host_base.distance_to(client_base), near_camp])
				else:
					_log("team spawn areas: %d bases %.1f m apart, nearest warband %.1f m" % [bases.size(),
							host_base.distance_to(client_base), near_camp])
				h.max_health = 1e6; h.health = 1e6
				step = 2; st = 0
		2:
			var h := _p(true); var c := _p(false); var gm := _gm()
			if gm == null: return
			# host holds the hill alone; the client waits at its team base
			h.global_position = Vector3(0.5, 0, 0.5)
			c.global_position = gm.team_bases[1]
			if st > 2.0 and not has_meta("dropped"):
				set_meta("dropped", true)
				get_tree().current_scene.world_events.drop_supplies(Vector3(6, 0, 6), 1.0)
				_log("supply drop sent")
			if gm.is_over or st > 25:
				_log("scores=%s over=%s time_left=%.0f" % [gm.scores, gm.is_over, gm.time_left])
				step = 3; st = 0
		3:
			if st > 3.0:
				round_i += 1
				if round_i >= modes.size():
					_log("done"); get_tree().quit(); return
				get_tree().current_scene._restart(); step = 0; st = -1.0

extends Node
## Plays King of the Hill with the client, checking team base access and the hill score on the server.
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
func _shop_near(point: Vector3) -> ShopStation:
	var best: ShopStation
	var distance := INF
	for node in get_tree().get_nodes_in_group(&"shop_stations"):
		var shop := node as ShopStation
		if shop.stall_id == &"blacksmith" and shop.global_position.distance_to(point) < distance:
			best = shop; distance = shop.global_position.distance_to(point)
	return best
func _process(delta: float) -> void:
	t += delta; st += delta
	match step:
		0: # lobby: configure next mode
			if Net.players.size() >= 2 and st > 1.0:
				Net.set_setting("mode", modes[round_i]); Net.set_setting("camp_count", 4); Net.set_setting("score_limit", 5)
				var client_peer: int = Net.players.keys().filter(func(k): return k != 1)[0]
				Net.set_team(client_peer, 1); Net.set_team(1, 0)
				Net.start_game(); step = 1; st = 0
		1:
			if _p(true) and _p(false) and st > 2.5:
				var h := _p(true); var c := _p(false)
				_log("== %s: host team %d, client team %d" % [Net.MODE_NAMES[modes[round_i]], h.team_id, c.team_id])
				var host_shop := _shop_near(_gm().spawn_point_for(h.peer_id))
				var client_shop := _shop_near(_gm().spawn_point_for(c.peer_id))
				if host_shop == null or client_shop == null or host_shop == client_shop \
						or not host_shop.can_access(h) or host_shop.can_access(c) \
						or not client_shop.can_access(c) or client_shop.can_access(h):
					printerr("FAILED town access in %s" % Net.MODE_NAMES[modes[round_i]])
				h.max_health = 1e6; h.health = 1e6
				step = 2; st = 0
		2:
			var h := _p(true); var c := _p(false); var gm := _gm()
			if gm == null: return
			# host holds the hill alone; the client waits at its team base
			h.global_position = Vector3(0.5, 0, 0.5)
			c.global_position = gm.team_bases[1]
			if gm.is_over or st > 25:
				_log("scores=%s over=%s time_left=%.0f" % [gm.scores, gm.is_over, gm.time_left])
				step = 3; st = 0
		3:
			if st > 3.0:
				round_i += 1
				if round_i >= modes.size():
					_log("done"); get_tree().quit(); return
				get_tree().current_scene._restart(); step = 0; st = -1.0

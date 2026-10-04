extends Node
var t := 0.0
var phase := 0
var pt := 0.0
func _ready() -> void:
	Net.profile.name = "Hosty"; Net.host()
func _log(m: String) -> void:
	printerr("HOST [%.1f] %s" % [t, m])
func _process(delta: float) -> void:
	t += delta; pt += delta
	match phase:
		0:
			if Net.players.size() >= 2:
				Net.set_setting("camp_count", 8); Net.start_game(); phase = 1; pt = 0
		1:
			var camps := get_tree().get_nodes_in_group(&"camps")
			if get_tree().get_nodes_in_group(&"players").size() >= 2 and pt > 3:
				camps.sort_custom(func(a, b): return a.name < b.name)
				var sig := ""
				for c in camps: sig += "%s@%d,%d " % [c.name, int(c.global_position.x), int(c.global_position.z)]
				_log("camps: " + sig)
				_log("trees=%d chests=%d seed=%d" % [get_tree().get_nodes_in_group(&"choppable").size(), get_tree().current_scene.get_node("World").get_children().filter(func(n): return n is Chest).size(), Net.settings.seed])
				var host_player: Player = get_tree().get_nodes_in_group(&"players").filter(func(p): return p.peer_id == 1)[0]
				camps[0].take_damage(camps[0].health * 0.5, host_player)
				phase = 2; pt = 0
		2:
			if pt > 1.5:
				var camps := get_tree().get_nodes_in_group(&"camps")
				camps.sort_custom(func(a, b): return a.name < b.name)
				var host_player: Player = get_tree().get_nodes_in_group(&"players").filter(func(p): return p.peer_id == 1)[0]
				camps[0].take_damage(1e6, host_player)
				_log("destroyed %s (is_dead=%s)" % [camps[0].name, camps[0].is_dead])
				phase = 3; pt = 0
		3:
			# Soldiers over the network: the client recruits one (anywhere), it trains here and joins the client.
			if pt > 2:
				var guest: Player = get_tree().get_nodes_in_group(&"players").filter(func(p): return p.peer_id != 1)[0]
				guest.coins = 120
				_log("client has %d coins to recruit" % guest.coins)
				phase = 4; pt = 0
		4:
			if pt > 18:
				var guest: Player = get_tree().get_nodes_in_group(&"players").filter(func(p): return p.peer_id != 1)[0]
				_log("client army: following %d, training %d, coins %d" % [guest.followers().size(), guest.soldiers_training, guest.coins])
				get_tree().current_scene.world_events.start_wave(0.1)
				phase = 5; pt = 0
		5:
			if pt > 2:
				_log("wave enemies replicated: %d" % get_tree().get_nodes_in_group(&"wave_enemies").size())
				_log("done"); get_tree().quit()

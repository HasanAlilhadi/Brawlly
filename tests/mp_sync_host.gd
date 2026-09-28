extends Node
var t := 0.0
var phase := 0
var pt := 0.0
func _ready() -> void:
	Net.set_profile("Hosty", 0); Net.host()
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
			if pt > 6: _log("done"); get_tree().quit()

extends Node
var t := 0.0
var started := false
func _ready() -> void:
	Net.profile.name = "Hosty"; Net.host()
func _process(delta: float) -> void:
	t += delta
	if not started and Net.players.size() >= 2:
		started = true; Net.set_setting("camp_count", 8); Net.start_game()
	if t > 14.0:
		for p in get_tree().get_nodes_in_group(&"players"):
			if p.peer_id != 1: printerr("HOST client player on server x=%.3f" % p.global_position.x)
		get_tree().quit()

extends Node
## Downed + revive over the network (run with mp_revive_client.gd):
## the client's archer goes down instead of dying, the host revives them by standing close,
## orcs can't finish a downed archer, left alone they bleed out and respawn; pings reach teammates.
## Dying keeps the class weapons and the coins (nothing drops).
var t := 0.0
var step := 0
var st := 0.0
var failures := 0
var host_arrows := 0


func _ready() -> void:
	Net.set_profile("Hosty", 0)
	Net.host()


func _log(m: String) -> void:
	printerr("HOST [%.1f] %s" % [t, m])


func _check(ok: bool, what: String) -> void:
	_log(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


func _p(host: bool) -> Player:
	for p in get_tree().get_nodes_in_group(&"players"):
		if (p.peer_id == 1) == host:
			return p
	return null


func _pickups(kind: Pickup.Kind) -> Array:
	return get_tree().current_scene.get_node("World/Items").get_children().filter(
			func(n: Node) -> bool: return n is Pickup and n.kind == kind)


func _process(delta: float) -> void:
	t += delta
	st += delta
	var h := _p(true)
	var c := _p(false)
	match step:
		0:
			if Net.players.size() >= 2 and st > 1.0:
				Net.set_setting("camp_count", 4)
				Net.set_setting("events", false)
				Net.start_game()
				step = 1
				st = 0
		1:
			if h and c and st > 2.5:
				h.max_health = 1e6
				h.health = 1e6
				h.global_position = Vector3(20, 0, 20)
				c.take_damage(1e6)
				step = 2
				st = 0
		2:
			if st > 0.3:
				_check(c.is_downed and not c.is_dead, "client went down instead of dying")
				c.take_damage(1e6, get_tree().get_nodes_in_group(&"enemies")[0])
				_check(c.is_downed and not c.is_dead, "an orc can't finish a downed archer")
				_check(get_tree().get_nodes_in_group(&"pings").size() > 0, "the automatic Help! ping reached the host")
				step = 3
				st = 0
		3:
			if st > 1.0:
				h.global_position = c.global_position + Vector3(0.8, 0, 0)
			if st > 5.0:
				_check(not c.is_downed and not c.is_dead and absf(c.health - c.max_health * Player.REVIVE_HEALTH) < 1.0,
						"host revived the client (health %.0f/%.0f)" % [c.health, c.max_health])
				_check(get_tree().current_scene.match_stats.stat(1, &"revives") == 1.0, "revive counted for the host")
				h.global_position = Vector3(20, 0, 20)
				c.coins = 100
				c.take_damage(1e6)
				step = 4
				st = 0
		4:
			if st > Player.BLEED_TIME + 1.0:
				_check(c.is_dead, "left alone, the client bled out")
				_check(c.weapons == c.class_def.weapons and c.coins == 100,
						"dying kept the class weapons and the coins (%s, %d coins)" % [c.weapons, c.coins])
				step = 5
				st = 0
		5:
			if st > get_tree().current_scene.game_mode.respawn_time() + 1.0:
				_check(not c.is_dead and not c.is_downed, "client respawned")
				_log("DONE failures=%d" % failures)
				get_tree().quit(1 if failures > 0 else 0)

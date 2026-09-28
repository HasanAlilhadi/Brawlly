extends Node
## World events + army orders + pings + awards (solo):
## treasure goblin flees / drops coins / gets caught, soldiers hold / charge / follow, the Warlord
## marches in with its warband which joins the player when it falls, a ping shows, awards at the end.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/events_test.gd

var t := 0.0
var phase := 0
var pt := 0.0
var main: Node
var player: Player
var goblin: TreasureGoblin
var warlord: Warlord
var start_dist := 0.0
var coins_before := 0
var point := Vector3.ZERO
var failures := 0


func _ready() -> void:
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


func _army_center() -> Vector3:
	var sum := Vector3.ZERO
	var list := player.followers()
	for ally in list:
		sum += (ally as Node3D).global_position
	return sum / maxf(list.size(), 1.0)


func _army_debug() -> String:
	var parts := PackedStringArray()
	for ally in player.followers():
		var target: Node = ally.target
		parts.append("%s@%.1f" % [target.get_class() + ":" + str(target.name) if target else "-", (ally as Node3D).global_position.distance_to(player.global_position)])
	return ", ".join(parts)


func _coin_piles() -> int:
	return main.get_node("World/Items").get_children().filter(func(n: Node) -> bool: return n is Pickup and n.kind == Pickup.Kind.COIN).size()


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
			goblin = main.world_events.spawn_goblin(player)
			_check(goblin != null and goblin.is_in_group(&"tracked"), "goblin spawned + tracked")
			start_dist = goblin.global_position.distance_to(player.global_position)
			_next()
		1:
			# Chase it: it should keep its distance.
			var to := goblin.global_position - player.global_position
			main.hud.joystick.output = Vector2(to.x, to.z).normalized()
			if pt > 3.0:
				main.hud.joystick.output = Vector2.ZERO
				var dist := goblin.global_position.distance_to(player.global_position)
				_check(dist > 4.0, "goblin runs away (%.1f -> %.1f m)" % [start_dist, dist])
				coins_before = _coin_piles()
				goblin.take_damage(20.0, player)
				_next()
		2:
			if pt > 0.3:
				_check(_coin_piles() > coins_before, "a hit spills coins (%d -> %d piles)" % [coins_before, _coin_piles()])
				goblin.take_damage(1e6, player)
				_next()
		3:
			if pt > 0.5:
				_check(main.match_stats.stat(1, &"goblin_kills") == 1.0, "goblin catch counted")
				# Orders are checked in the (camp-free) spawn area, away from orcs the chase may have woken.
				player.global_position = main.game_mode.spawn_point_for(1)
				for orc in get_tree().get_nodes_in_group(&"active_enemies"):
					if (orc as Node3D).global_position.distance_to(player.global_position) < 25.0:
						orc.queue_free()
				player.reserve_soldiers = 6
				_next()
		4:
			if player.followers().size() >= 6 and pt > 2.0:
				point = player.global_position + Vector3(8, 0, 0)
				main._command_army(Player.Order.HOLD, point)
				_next()
			elif pt > 10.0:
				_check(false, "soldiers arrived (%d)" % player.followers().size())
				_next()
		5:
			if pt > 5.0:
				var d := _army_center().distance_to(point)
				_check(player.army_order == Player.Order.HOLD and d < 3.0, "HOLD: soldiers guard the point (%.1f m)" % d)
				point = player.global_position + Vector3(-9, 0, 4)
				start_dist = _army_center().distance_to(point)
				main._command_army(Player.Order.CHARGE, point)
				_next()
		6:
			if pt > 5.0:
				# They fight whatever is there, so they end up around the point, not on it.
				var d := _army_center().distance_to(point)
				_log("army: " + _army_debug())
				_check(d < 6.0 and d < start_dist * 0.5, "CHARGE: soldiers run to the point (%.1f -> %.1f m)" % [start_dist, d])
				main._command_army(Player.Order.FOLLOW)
				_next()
		7:
			if pt > 5.0:
				var d := _army_center().distance_to(player.global_position)
				_log("army: " + _army_debug())
				_check(player.army_order == Player.Order.FOLLOW and d < 4.0, "FOLLOW: back in formation (%.1f m)" % d)
				main._ping(player.global_position + Vector3(2, 0, 0))
				_next()
		8:
			if pt > 0.2:
				_check(get_tree().get_nodes_in_group(&"pings").size() > 0, "ping marker shown")
				warlord = main.world_events.spawn_warlord(player)
				_check(warlord != null, "warlord spawned")
				start_dist = warlord.global_position.distance_to(player.global_position)
				_next()
		9:
			if pt > 6.0:
				_check(warlord._band.size() >= 7, "warband raised (%d orcs)" % warlord._band.size())
				var dist := warlord.global_position.distance_to(player.global_position)
				_check(dist < start_dist - 5.0, "warlord marches on the player (%.1f -> %.1f m)" % [start_dist, dist])
				start_dist = player.followers().size() + player.reserve_soldiers
				warlord.take_damage(1e7, player)
				_next()
		10:
			if pt > 1.0:
				var army := player.followers().size() + player.reserve_soldiers
				_check(army > start_dist, "warband joins the player (%d -> %d soldiers)" % [start_dist, army])
				_check(main.match_stats.stat(1, &"warlord_kills") == 1.0, "warlord kill counted")
				main.game_mode.finish("Test over", "")
				_next()
		11:
			if pt > 0.5:
				var awards: Array = main.match_stats.compute_awards(main.game_mode.player_names())
				_log("awards: %s" % [awards.map(func(a: Dictionary) -> String: return "%s (%s)" % [a.title, a.detail])])
				_check(main.hud._awards_box.get_child_count() > 0, "awards shown on the end screen")
				_log("DONE failures=%d" % failures)
				get_tree().quit(1 if failures > 0 else 0)

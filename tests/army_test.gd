extends Node
## Army orders (solo): soldiers in a fight drop it at once for HOLD / FOLLOW, the KILL order (key 4 on the
## orc under the cursor, and the HUD Kill button + a click) sends everyone at that orc and turns into a
## CHARGE once it falls, a KILL that misses becomes a CHARGE to the clicked spot, and soldiers after an orc
## behind a wall of other orcs go around them (never fighting the ones in the way).
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/army_test.gd

var t := 0.0
var phase := 0
var pt := 0.0
var main: Node
var player: Player
var orcs: Array[Enemy] = []
var prey: Enemy
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


func _fighting() -> int:
	return player.followers().filter(func(a: Node) -> bool: return a.target is Enemy).size()


func _all_target(node: Node3D) -> bool:
	return player.followers().all(func(a: Node) -> bool: return a.target == node)


## Moves the mouse over a world point (the cursor pick reads the viewport's mouse position).
func _hover(at: Vector3) -> Vector2:
	# Viewport pixels → window pixels (the headless window is tiny and stretched).
	var screen: Vector2 = main.get_viewport().get_screen_transform() * main.camera.unproject_position(at + Vector3(0, 0.6, 0))
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	Input.parse_input_event(motion)
	return screen


func _click(screen: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = screen
		e.global_position = screen
		Input.parse_input_event(e)


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
			# Open ground south of the spawn area.
			player.global_position = main.game_mode.spawn_point_for(1) + Vector3(0, 0, 26)
			for node in get_tree().get_nodes_in_group(&"enemies"):
				if (node as Node3D).global_position.distance_to(player.global_position) < 30.0:
					node.queue_free()
			for node in get_tree().get_nodes_in_group(&"choppable"):
				if (node as Node3D).global_position.distance_to(player.global_position) < 22.0:
					node.queue_free()
			for i in 6:
				NetSpawn.unit(&"ally", player.global_position + Vector3(cos(i), 0, sin(i)) * 2.0,
						{"team": player.team_id, "owner": player.peer_id, "color": player.unit_color})
			# Three harmless, tough orcs right next to the army: the soldiers pile in.
			for i in 3:
				var orc := NetSpawn.unit(&"enemy", player.global_position + Vector3(4.5, 0, i * 1.5 - 1.5), {
					"scene": "res://scenes/characters/enemy.tscn", "strength": 1.0, "coins": 1.0}) as Enemy
				orc.add_to_group(&"active_enemies")
				orc.max_health = 1e6
				orc.health = 1e6
				orc.melee_damage = 0.0
				orcs.append(orc)
			_next()
		1:
			if _fighting() >= 4:
				_check(true, "soldiers fight the orcs (%d of %d)" % [_fighting(), player.followers().size()])
				point = player.global_position + Vector3(-10, 0, 0)
				main._command_army(Player.Order.HOLD, point)
				_next()
			elif pt > 8.0:
				_check(false, "soldiers fight the orcs (%d)" % _fighting())
				get_tree().quit(1)
		2:
			if pt < 0.05:
				return
			if pt < 0.2:
				_check(_fighting() == 0, "HOLD: every soldier drops the fight at once (%d still fighting)" % _fighting())
				set_meta(&"reached", {})
				pt = 0.2
			# Each soldier gets to the held spot (then they may fight the orcs that followed, so no snapshot).
			var held: Dictionary = get_meta(&"reached", {})
			for ally in player.followers():
				if (ally as Node3D).global_position.distance_to(point) < 3.5:
					held[ally] = true
			if pt > 4.0:
				var missing := player.followers().filter(func(a: Node) -> bool: return not held.has(a)).size()
				_check(missing == 0, "HOLD: every soldier walks to the new spot mid-fight (%d didn't)" % missing)
				# Back into the fight, then FOLLOW while the player walks away.
				main._command_army(Player.Order.CHARGE, orcs[1].global_position)
				_next()
		3:
			if pt > 4.0:
				_check(_fighting() >= 4, "CHARGE: back in the fight (%d)" % _fighting())
				player.global_position += Vector3(0, 0, 12)
				main._command_army(Player.Order.FOLLOW)
				_next()
		4:
			if pt > 0.05 and pt < 0.3:
				_check(_fighting() == 0, "FOLLOW: every soldier drops the fight at once (%d still fighting)" % _fighting())
				set_meta(&"reached", {})
				pt = 0.3
			# Obeying = each soldier gets to the player (its formation spot). Afterwards they may fight the
			# orcs that chased them a few meters out, so a snapshot of distances would be flaky.
			if has_meta(&"reached"):
				var reached: Dictionary = get_meta(&"reached")
				for ally in player.followers():
					if (ally as Node3D).global_position.distance_to(player.global_position) < 3.5:
						reached[ally] = true
			if pt > 4.5:
				var reached: Dictionary = get_meta(&"reached")
				var missing := player.followers().filter(func(a: Node) -> bool: return not reached.has(a))
				var parts := PackedStringArray()
				for ally in missing:
					parts.append("%.1f" % (ally as Node3D).global_position.distance_to(player.global_position))
				_check(missing.is_empty(), "FOLLOW: every soldier comes to the player mid-fight (%d/%d; missing at %s m)" % [
						player.followers().size() - missing.size(), player.followers().size(), ", ".join(parts)])
				# KILL (key 4) on the orc under the cursor: walk back so the orcs are on screen.
				prey = orcs[0]
				player.global_position = prey.global_position + Vector3(-6, 0, 0)
				_next()
		5:
			if pt > 1.5 and not has_meta(&"hovered"):
				set_meta(&"hovered", true)
				_hover(prey.global_position)
			elif pt > 1.6:
				var key := InputEventKey.new()
				key.physical_keycode = KEY_4
				key.keycode = KEY_4
				key.pressed = true
				Input.parse_input_event(key)
				key = key.duplicate()
				key.pressed = false
				Input.parse_input_event(key)
				_next()
		6:
			if pt < 0.1:
				return
			if pt < 0.3:
				prey.health = 50.0  # killable now (not earlier: the fight going on would finish it first)
				_check(player.army_order == Player.Order.KILL and player.army_target == prey, "4 on an orc: a KILL order on it")
				_check(_all_target(prey), "KILL: every soldier goes for that orc")
				_check(main._kill_mark != null and main._kill_mark.visible, "a target mark shows over it")
				pt = 0.3
			if prey.is_dead or not is_instance_valid(prey):
				_check(true, "KILL: the orc is killed (%.1f s)" % pt)
				_next()
			elif pt > 10.0:
				_check(false, "KILL: the orc is killed (health %.0f)" % prey.health)
				_next()
		7:
			if pt > 0.2:
				_check(player.army_order == Player.Order.CHARGE, "after the kill they charge where it fell (order %d)" % player.army_order)
				_check(main._kill_mark == null or not main._kill_mark.visible, "the target mark is gone")
				# HUD Kill button with the mouse: the next click picks the target.
				prey = orcs[2]
				main._on_army_button(Player.Order.KILL)
				_check(main._kill_picking and main.hud._army_buttons[Player.Order.KILL].button_pressed, "the Kill button waits for a click")
				_next()
		8:
			if pt > 0.1:
				var swings_before: String = player.action_token
				_click(_hover(prey.global_position))
				set_meta(&"swings", swings_before)
				_next()
		9:
			if pt > 0.2:
				_check(player.army_order == Player.Order.KILL and player.army_target == prey, "click on an orc: KILL on that one")
				_check(not main._kill_picking, "picking ends after the click")
				_check(player.action_token == get_meta(&"swings"), "the click didn't swing the sword")
				# A kill that misses: charge to the clicked spot.
				point = player.global_position + Vector3(-6, 0, 3)
				_hover(point - Vector3(0, 0.6, 0))
				_next()
		10:
			if pt > 0.1:
				main._command_army(Player.Order.KILL, main._cursor_point())
				_next()
		11:
			if pt > 0.2:
				_check(player.army_order == Player.Order.CHARGE and player.army_point.distance_to(point) < 1.0,
						"KILL on empty ground: CHARGE there (%.1f m off)" % player.army_point.distance_to(point))
				# Next: an orc behind a wall of other orcs. Clear the field and regroup first.
				for orc in orcs:
					if is_instance_valid(orc):
						orc.queue_free()
				orcs.clear()
				main._command_army(Player.Order.FOLLOW)
				_next()
		12:
			if pt > 3.0:
				# Seven harmless orcs shoulder to shoulder across the way (no gaps), the target 4 m behind them.
				var ahead := Vector3(1, 0, 0)
				for i in 7:
					orcs.append(_still_orc(player.global_position + ahead * 4.5 + Vector3(0, 0, i * 0.75 - 2.25), 1e6))
				prey = _still_orc(player.global_position + ahead * 8.5, 150.0)
				player.command_army(Player.Order.KILL, prey.global_position)
				set_meta(&"distracted", 0)
				_next()
		13:
			if not GameConfig.is_gone(prey):
				for ally in player.followers():
					if ally.target != null and ally.target != prey:
						set_meta(&"distracted", get_meta(&"distracted") + 1)
			if GameConfig.is_gone(prey):
				var hurt := orcs.filter(func(o: Enemy) -> bool: return o.health < 1e6).size()
				_check(true, "KILL behind a wall of orcs: the target falls (%.1f s)" % pt)
				_check(hurt == 0, "no orc in the way was hit (%d hurt)" % hurt)
				_check(get_meta(&"distracted") == 0, "no soldier went for an orc in the way (%d soldier-frames)" % get_meta(&"distracted"))
				_log("DONE failures=%d" % failures)
				get_tree().quit(1 if failures > 0 else 0)
			elif pt > 15.0:
				_check(false, "KILL behind a wall of orcs: the target falls (health %.0f, %s)" % [prey.health,
						", ".join(player.followers().map(func(a: Node) -> String: return "%.1f" % (a as Node3D).global_position.distance_to(prey.global_position)))])
				_log("DONE failures=%d" % failures)
				get_tree().quit(1)


## A harmless orc that stands still (physics off: it neither walks nor fights).
func _still_orc(at: Vector3, health: float) -> Enemy:
	var orc := NetSpawn.unit(&"enemy", at, {"scene": "res://scenes/characters/enemy.tscn", "strength": 1.0, "coins": 1.0}) as Enemy
	orc.add_to_group(&"active_enemies")
	orc.max_health = health
	orc.health = health
	orc.melee_damage = 0.0
	orc.set_physics_process(false)
	orc.health_changed.connect(func(current: float, _max: float) -> void:
		if orc != prey and current < health:
			var parts := PackedStringArray()
			for ally in player.followers():
				parts.append("%s d_orc=%.2f tgt=%s" % [ally.name, (ally as Node3D).global_position.distance_to(orc.global_position),
						ally.target.name if ally.target else "-"])
			_log("note: an orc in the way (%s) was hit at %s (prey %s gone=%s): %s" % [orc.name, orc.global_position, prey.name if prey else "-",
					GameConfig.is_gone(prey), "; ".join(parts)]))
	return orc

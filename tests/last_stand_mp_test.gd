extends Node
## Last Stand online (host + client on 127.0.0.1, Gravemoor): both build the same world (a signature of the circles,
## gold veins and landmarks is printed by both: compare the SIG lines), the circle state reaches the client, a circle
## needing two heroes only counts with both inside, a downed hero nobody revives is gone for good (no respawn) and
## spectates the other, the next circle needs only the one left, and the last hero falling ends the match (Defeat)
## on both screens.
##   "$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/last_stand_mp_test.gd --role=host --port=24715 &
##   "$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/last_stand_mp_test.gd --role=client --port=24715

var host := true
var t := 0.0
var pt := 0.0
var phase := 0
var failures := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--role=client":
			host = false
	if host:
		Net.profile.name = "Hosty"
		Net.host()
	else:
		Net.profile.name = "Guest"
		await get_tree().create_timer(1.0).timeout
		Net.join("127.0.0.1", Net.port)


func _log(msg: String) -> void:
	printerr("%s [%.1f] %s" % ["HOST" if host else "CLIENT", t, msg])


func _check(ok: bool, what: String) -> void:
	_log(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


func _next() -> void:
	phase += 1
	pt = 0.0


func _finish() -> void:
	_log("done: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _players() -> Array:
	return get_tree().get_nodes_in_group(&"players")


func _player(peer_is_host: bool) -> Player:
	for p in _players():
		if ((p as Player).peer_id == 1) == peer_is_host:
			return p
	return null


func _put(player: Player, at: Vector3) -> void:
	player.global_position = at
	player.net_position = at


func _signature(main: Node) -> String:
	var parts := PackedStringArray()
	for c in main.game_mode.circles:
		parts.append("%d,%d" % [roundi(c.x), roundi(c.z)])
	var veins := 0.0
	for v in get_tree().get_nodes_in_group(&"gold_veins"):
		veins += (v as Node3D).global_position.x * 0.37 + (v as Node3D).global_position.z
	var solids := 0
	for node in main.world.get_children():
		if node is StaticBody3D and str(node.name).begins_with("Solid_"):
			solids += 1
	return "circles %s veins %.2f solids %d trees %d" % [" ".join(parts), veins, solids, get_tree().get_nodes_in_group(&"choppable").size()]


func _process(delta: float) -> void:
	t += delta
	pt += delta
	if t > 150.0:
		_check(false, "finished in time (phase %d)" % phase)
		_finish()
		return
	if host and phase == 7:
		if pt > 3.0:
			_finish()  # the client has seen the end (it may already have left)
		return
	if host and phase == 0:
		if Net.players.size() >= 2 and pt > 0.5:
			Net.set_setting("mode", Net.Mode.LAST_STAND)
			Net.set_setting("map", 1)
			Net.set_setting("camp_count", 8)
			Net.set_setting("events", false)
			Net.start_game(false)
			_next()
		return
	var main := get_tree().current_scene
	if main == null or main.name != "Main" or _players().size() < 2 or main.get("local_player") == null:
		if not host and phase > 0 and Net.players.is_empty():
			_finish()  # the host quit
		return
	if not host:
		_client(main)
		return
	var me := _player(true)
	var guest := _player(false)
	var mode: GameMode = main.game_mode
	match phase:
		1:
			if pt < 2.0:
				return
			_log("SIG " + _signature(main))
			me.max_health = 1e6
			me.health = 1e6
			mode.circle_seconds = 3.0
			mode._base_required = 2  # this circle needs both heroes
			_put(me, mode.circles[0])
			_put(guest, mode.circles[0] + Vector3(HoldCircle.RADIUS + 6.0, 0, 0))
			_next()
		2:
			if pt < 1.5:
				return
			_check(mode.circle_required == 2 and mode.circle_inside == 1 and mode.circle_time < 0.05,
					"one of two heroes inside: the clock waits (%d / %d, %.2f)" % [mode.circle_inside, mode.circle_required, mode.circle_time])
			_put(guest, mode.circles[0] + Vector3(2.0, 0, 0))
			_next()
		3:
			if mode.circle_index == 1:
				_check(true, "both inside: circle 1 held")
				# The guest goes down far from the host; nobody revives them → gone for good.
				_put(guest, mode.circles[1] + Vector3(HoldCircle.RADIUS + 25.0, 0, 0))
				guest.take_damage(1e5)
				_next()
			elif pt > 8.0:
				_check(false, "circle 1 held with both inside (%.2f)" % mode.circle_time)
				_next()
		4:
			if pt < 0.5:
				return
			_check(guest.is_downed, "the guest is down")
			guest.die()  # bled out
			_next()
		5:
			if pt < GameMode.COOP_RESPAWN + 1.0:
				return
			_check(guest.is_dead, "no respawn in Last Stand")
			_check(mode.living_players().size() == 1 and mode.circle_required == 1, "the circle needs only the hero left (%d)" % mode.circle_required)
			me.max_health = 100.0
			me.health = 100.0
			me.take_damage(1e5)
			_next()
		6:
			if pt < 0.5:
				return
			if me.is_downed:
				_check(false, "the last hero standing goes down and nobody can help: gone at once")
			_check(mode.is_over and main.hud.end_title.text == "Defeat", "defeat when the last hero falls (%s)" % main.hud.end_title.text)
			_next()


func _client(main: Node) -> void:
	var me: Player = main.local_player
	var mode: GameMode = main.game_mode
	match phase:
		0:
			if pt < 2.0:
				return
			_log("SIG " + _signature(main))
			_check(mode.hold_circle != null and mode.hold_circle.position.distance_to(mode.circles[0]) < 0.1, "the circle shows here")
			_check((MapCatalog.get_map(1).sky as Color).is_equal_approx((main.get_node("WorldEnvironment") as WorldEnvironment).environment.background_color), "Gravemoor here too")
			_next()
		1:
			if mode.circle_index == 1:
				_check(mode.hold_circle.position.distance_to(mode.circles[1]) < 0.1, "circle 2 reached the client")
				_next()
		2:
			if me.is_dead:
				_next()
		3:
			if pt < 1.0:
				return
			var watched: Player = main.get("_spectating")
			_check(watched != null and watched.peer_id == 1, "spectating the host")
			_check(main.camera.target == watched, "the camera follows them")
			_check(main.hud.get("_spectate_label").visible, "the spectating line shows")
			_next()
		4:
			if mode.is_over:
				_check(main.hud.end_title.text == "Defeat", "defeat here too")
				_next()
		5:
			if pt > 1.0:
				_finish()

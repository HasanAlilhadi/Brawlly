extends Node
## Host/client pair for class upgrades over the network. The client (a Swordsman) buys from the sheet through the
## server, dashes (predicted at once on the client, confirmed by the server); the host (a Bowman) buys Fire Range
## and the client sees the host's new aim range (stats follow the replicated levels on every peer).
##   "$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/class_upgrades_mp_test.gd --role=host --class=bowman --port=24705 &
##   "$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/class_upgrades_mp_test.gd --role=client --class=swordsman --port=24705

var role := "host"
var failures := 0
var finished := false


func _check(ok: bool, message: String) -> void:
	printerr(("PASS " if ok else "FAIL ") + role + ": " + message)
	if not ok:
		failures += 1


func _ready() -> void:
	name = "ClassUpgradesMpTest"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.substr(7)
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		if not finished:
			printerr("FAIL %s: timed out" % role)
			get_tree().quit(1))
	Net.profile.name = role.capitalize()
	if role == "host":
		_check(Net.host() == OK, "host starts")
		while Net.players.size() < 2:
			await get_tree().process_frame
		Net.settings.camp_count = 0
		Net.settings.events = false
		Net.start_game(false)
	else:
		_check(Net.join("127.0.0.1", Net.port) == OK, "client connects")
	while get_tree().current_scene == null or get_tree().current_scene.name != "Main" \
			or get_tree().get_nodes_in_group(&"players").size() < 2:
		await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout
	if role == "host":
		await _host()
	else:
		await _client()
	finished = true
	printerr("%s %s: done (%d failures)" % ["PASS" if failures == 0 else "FAIL", role, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _players() -> Dictionary:
	var result := {}
	for player: Player in get_tree().get_nodes_in_group(&"players"):
		result[&"me" if player.is_local() else &"other"] = player
	return result


func _def(id: StringName) -> UpgradeDef:
	for def in Player.CATALOG.upgrades:
		if def.id == id:
			return def
	return null


func _host() -> void:
	var me: Player = _players().me
	var client: Player = _players().other
	client.coins = 1000
	me.coins = 1000
	me.global_position = Vector3(0, 0, -6)
	client.global_position = Vector3(0, 0, -3)
	# Wait for the client's purchases.
	var end := Time.get_ticks_msec() + 10000
	while client.upgrade_level(&"sword_dash") == 0 and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	_check(client.upgrade_level(&"sword_dash") == 1 and client.coins == 1000 - _def(&"sword_dash").cost_at(0),
			"the client's Dash Attack purchase reached the server (coins %d)" % client.coins)
	me.request_buy(_def(&"bow_range"))
	_check(is_equal_approx(me.aim_range, 14.5), "host Bowman: Fire Range on the server (%.1f m)" % me.aim_range)
	await get_tree().create_timer(16.0).timeout


func _client() -> void:
	var me: Player = _players().me
	var host: Player = _players().other
	var hud: Hud = get_tree().current_scene.get_node("HUD")
	var end := Time.get_ticks_msec() + 5000
	while me.coins < 1000 and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	hud.toggle_upgrades()
	await get_tree().create_timer(0.4).timeout
	var buy := hud.upgrade_sheet.find_child("Buy_sword_dash", true, false) as Button
	_check(buy != null and not buy.disabled, "the sheet offers Dash Attack (%s)" % (buy.text if buy else "missing"))
	buy.pressed.emit()
	end = Time.get_ticks_msec() + 3000
	while not me.has_dash() and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	_check(me.has_dash(), "the bought upgrade replicated back: the client can dash")
	_check(buy.disabled and buy.text == "Owned", "its card says Owned")
	hud.toggle_upgrades()
	await get_tree().create_timer(0.5).timeout
	var start := me.global_position
	me.request_dash(Vector3.BACK)
	await get_tree().create_timer(0.1).timeout
	_check(me.global_position.distance_to(start) > 1.0, "the dash moves the client right away (predicted, %.2f m)" % me.global_position.distance_to(start))
	await get_tree().create_timer(0.6).timeout
	var server_moved := me.net_position.distance_to(start)
	_check(server_moved > 3.0, "the server dashed too (%.2f m)" % server_moved)
	_check(me.global_position.distance_to(me.net_position) < 0.8, "client and server agree on where the dash ended")
	end = Time.get_ticks_msec() + 5000
	while not is_equal_approx(host.aim_range, 14.5) and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	_check(is_equal_approx(host.aim_range, 14.5), "the host Bowman's Fire Range shows on the client too (%.1f m)" % host.aim_range)
	# Army tab: a soldier recruited away from the barracks joins the client 10 s later.
	var joined := [false]
	me.soldier_ready.connect(func(at_barracks: bool) -> void: joined[0] = not at_barracks)
	me.request_buy(_def(&"recruit"))
	end = Time.get_ticks_msec() + 13000
	while me.followers().is_empty() and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	_check(me.followers().size() == 1 and joined[0], "a recruited soldier joins the client after 10 s")

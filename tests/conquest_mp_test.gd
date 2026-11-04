extends Node
## Conquest online (host + client on 127.0.0.1, both in the first faction): the host makes a squad of 4 trained
## archers for the client's hero from their Citadel's barracks; the client sees it (members, leader with its banner,
## out of its army but counted, its card on the M map), then — as the Citadel's lord — picks wizards for the barracks
## and orders the squad to
## hold a point — both reach the server and come back to the client. Then the client buys a bow (Conquest heroes
## start Unarmed): the server swaps its hero, the client binds the new one (HUD, prediction) and the squad stays its.
## The supplies panel's flows reach the client too.
##   "$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/conquest_mp_test.gd --role=host --port=24725 &
##   "$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/conquest_mp_test.gd --role=client --port=24725

var host := true
var t := 0.0
var pt := 0.0
var phase := 0
var failures := 0
var squad := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--role=client":
			host = false
	if host:
		Net.profile.name = "Hosty"
		Net.conquest_section = true
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


func _player(peer_is_host: bool) -> Player:
	for p in get_tree().get_nodes_in_group(&"players"):
		if ((p as Player).peer_id == 1) == peer_is_host:
			return p
	return null


## A zone 1 place without walls (the same on both peers: the plan comes from the seed).
func _lone(mode: ConquestMode) -> TerritoryNode:
	return mode.territories.filter(func(n: TerritoryNode) -> bool: return n.zone == 1 and n.gate == null)[0]


func _mode() -> ConquestMode:
	var main := get_tree().current_scene
	return main.game_mode as ConquestMode if main and main.name == "Main" else null


func _process(delta: float) -> void:
	t += delta
	pt += delta
	if t > 150.0:
		_check(false, "finished in time (phase %d)" % phase)
		_finish()
		return
	if host:
		_host()
	else:
		_client()


func _host() -> void:
	match phase:
		0:
			if Net.players.size() < 2 or pt < 1.0:
				return
			_check(Net.mode() == Net.Mode.CONQUEST, "a Conquest lobby")
			var guest: int = Net.players.keys().filter(func(k: int) -> bool: return k != 1)[0]
			Net.set_team(1, 0)
			Net.set_team(guest, 0)
			Net.start_game()
			_next()
		1:
			var mode := _mode()
			var guest := _player(false)
			if mode == null or mode.logistics == null or guest == null or _player(true) == null or pt < 4.0:
				return
			var home := mode.territories[0]
			_check(home.kind == TerritoryNode.Kind.CITADEL and home.owner_team == 0, "our Citadel")
			home.armed[1] = 4
			home.drill[1] = Ally.DRILL_SECONDS[2]
			home.store[&"food"] = 50
			home.lord = guest.peer_id  # the guest lords it: its orders for the place count
			guest.coins = 100  # to buy a weapon (heroes start Unarmed)
			home._send_state()
			mode.logistics.tick()
			_check(mode.logistics.muster_from(guest, home, 1, 4) == 4, "a squad of 4 archers for the guest")
			var ids := mode.squads.of_player(guest.peer_id)
			squad = ids[0] if not ids.is_empty() else 0
			var lone := _lone(mode)
			lone._guards_spawned = true
			lone._captured_by(0)  # nobody of ours stands in it: its countdown starts
			_next()
		2:
			var mode := _mode()
			var home := mode.territories[0]
			var held := int(mode.squads.squad(squad).get("place", 0)) == -1
			if (home.train_kind != 2 or not held) and pt < 60.0:
				return
			_check(home.train_kind == 2, "the guest's Train order reached the server (wizards)")
			_check(held and int(mode.squads.squad(squad).order) == ConquestSquads.Order.HOLD, "the guest's squad order reached the server")
			_next()
		3:
			var guest := _player(false)
			if (guest == null or guest.class_def.id != &"bowman") and pt < 40.0:
				return
			_check(guest != null and guest.class_def.id == &"bowman" and guest.coins == 70, "the guest's hero was swapped for a bowman")
			_check(guest != null and _mode().squads.of_player(guest.peer_id).size() == 1, "its squad is still its")
			_next()
		4:
			if pt > 6.0:
				_finish()


func _client() -> void:
	var mode := _mode()
	if mode == null or mode.squads == null:
		return
	var me := _player(false)
	if me == null:
		return
	var home := mode.territories[0]
	match phase:
		0:
			var ids := mode.squads.of_player(me.peer_id)
			var all: Array = mode.squads.members(ids[0]) if not ids.is_empty() else []
			if all.size() < 4 and pt < 60.0:
				return
			_check(ids.size() == 1 and all.size() == 4, "the squad reached the client (%d soldiers)" % all.size())
			if ids.is_empty():
				_finish()
				return
			squad = ids[0]
			var heads := all.filter(func(a: Ally) -> bool: return a.squad_leader)
			_check(heads.size() == 1 and heads[0]._banner != null and heads[0]._banner.visible, "one leads it, with a banner")
			_check(all.all(func(a: Ally) -> bool: return a.weapon == "bow" and a.rank == 2), "trained archers (rank %d)" % all[0].rank)
			_check(me.followers().is_empty() and me.army_size() >= 4, "out of my army, counted in its size")
			_check(mode.squads.order_text(squad) == "Holding " + home.display_name, "it holds the Citadel: " + mode.squads.order_text(squad))
			var map: ConquestMap = get_tree().current_scene.conquest_map
			map.toggle()
			map._squad = squad
			map._update_panel()
			_check("Squad" in map._title.text and map._buttons[&"squad_hold"].visible, "its card on my M map, with orders")
			map.toggle()
			me.request_place_action(home.index, &"train", 2)
			me.request_squad_action(squad, &"hold", -1, home.global_position + Vector3(20.0, 0.0, 0.0))
			_next()
		1:
			var lone := _lone(mode)
			var done := home.train_kind == 2 and mode.squads.order_text(squad) == "Holding a point" 					and lone.unguarded_left > 0.0
			if not done and pt < 30.0:
				return
			_check(lone.state == TerritoryNode.State.OWNED and lone.unguarded_left > 0.0
					and lone.unguarded_left <= TerritoryNode.ZONE_UNGUARDED[1] and "UNGUARDED" in lone._label_text(),
					"an unguarded place of ours counts down here too (%.0f s)" % lone.unguarded_left)
			_check(home.train_kind == 2, "the barracks now arm wizards (seen here)")
			_check(mode.squads.order_text(squad) == "Holding a point", "the squad holds the point (seen here)")
			_check(me.class_def.id == Player.START_CLASS and me.classless, "my hero starts Unarmed")
			for def in Player.CATALOG.upgrades:
				if def.id == &"arm_bow":
					me.request_buy(def)
			_next()
		2:
			var now: Player = get_tree().current_scene.local_player
			var swapped := now != null and is_instance_valid(now) and now.class_def.id == &"bowman"
			if not swapped and pt < 20.0:
				return
			_check(swapped, "my new hero (a bowman) is bound here")
			if not swapped:
				_finish()
				return
			var main := get_tree().current_scene
			_check(main.hud._player == now and main.camera.target == now and now.is_predicted, "the HUD, camera and prediction follow it")
			_check(now.weapons == PackedStringArray(["bow"]) and now.hero_level == 0, "a bow, level 0")
			_check(mode.squads.of_player(now.peer_id).size() == 1, "my squad is still mine")
			var flow: Dictionary = mode.logistics.stock_of(now.team_id).get(&"flow", {})
			_check(not flow.is_empty() and main.conquest_panel != null, "the supplies flows reach me: %s" % [flow.keys()])
			_finish()

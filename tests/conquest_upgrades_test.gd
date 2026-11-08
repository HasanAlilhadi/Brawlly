extends Node
## Conquest place upgrades (offline): the commander buys Walls / Workshops / Barracks / Storehouse levels on a place
## with its own treasury (ConquestMode.place_action "upgrade"): each does what it says (gate health, output, barracks
## room and arming, store), costs more each level and more on bigger places, stops at UPGRADE_MAX, is refused
## without the gold or where it doesn't fit (a Village has no walls), goes to every peer with the places' numbers
## and stays with the place when another faction takes it.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/conquest_upgrades_test.gd

var t := 0.0
var failures := 0
var done := false


func _ready() -> void:
	Net.open_offline_lobby()
	Net.settings.mode = Net.Mode.CONQUEST
	Net.settings.seed = 31
	Net.settings.events = []
	TerritoryNode.unguarded_falls = false
	ConquestDemons.campaigns_on = false
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _check(ok: bool, what: String) -> void:
	printerr(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


func _process(delta: float) -> void:
	t += delta
	if done:
		return
	if t > 40.0:
		_check(false, "finished in time")
		_finish()
		return
	var main := get_tree().current_scene
	if main == null or main.name != "Main" or main.get("local_player") == null or t < 1.5:
		return
	done = true
	var mode := main.game_mode as ConquestMode
	var hero: Player = main.local_player
	var home := mode.territories[hero.team_id]
	home.lord = hero.peer_id
	home.treasury = 3000
	var W := TerritoryNode.UP_WALLS
	# Walls: +50% gate health a level, the added health given at once.
	var gate_top := home.gate.max_health
	var cost := home.upgrade_cost(W)
	_check(mode.place_action(hero, home.index, &"upgrade", W), "the lord upgrades the Walls")
	_check(home.upgrades[W] == 1 and is_equal_approx(home.gate.max_health, gate_top * 1.5)
			and is_equal_approx(home.gate.health, home.gate.max_health), "the gate gets +50%% (%.0f -> %.0f)" % [gate_top, home.gate.max_health])
	_check(home.treasury == 3000 - cost and cost == roundi(TerritoryNode.UPGRADE_COST[0] * TerritoryNode.UPGRADE_KIND_COST[home.kind]),
			"paid from its treasury (%d)" % cost)
	_check(home.upgrade_cost(W) > cost, "the next level costs more (%d)" % home.upgrade_cost(W))
	mode.place_action(hero, home.index, &"upgrade", W)
	mode.place_action(hero, home.index, &"upgrade", W)
	_check(home.upgrades[W] == TerritoryNode.UPGRADE_MAX and not mode.place_action(hero, home.index, &"upgrade", W),
			"three levels at most")
	# Workshops: more of everything.
	var before: Dictionary = home.output()
	mode.place_action(hero, home.index, &"upgrade", TerritoryNode.UP_WORKSHOPS)
	var after: Dictionary = home.output()
	_check(after[&"food"] + after[&"equipment"] + after[&"gold"] > before[&"food"] + before[&"equipment"] + before[&"gold"],
			"Workshops: more output (%s -> %s)" % [before, after])
	# Barracks: room, arming.
	var room := home.barracks_cap()
	mode.place_action(hero, home.index, &"upgrade", TerritoryNode.UP_BARRACKS)
	_check(home.barracks_cap() == roundi(room * 1.5) and home.arm_per_tick() == LogisticsManager.ARM_PER_TICK + 1,
			"Barracks: room %d -> %d, %d armed a tick" % [room, home.barracks_cap(), home.arm_per_tick()])
	# Storehouse: a bigger store, and production fills it past the old top.
	mode.place_action(hero, home.index, &"upgrade", TerritoryNode.UP_STOREHOUSE)
	_check(home.store_cap() == roundi(TerritoryNode.STORE_CAP * 1.5), "Storehouse: holds %d" % home.store_cap())
	home.store[&"food"] = TerritoryNode.STORE_CAP
	mode.logistics.tick()
	_check(int(home.store[&"food"]) > TerritoryNode.STORE_CAP or home.output()[&"food"] == 0,
			"its store fills past the old top (%d)" % home.store[&"food"])
	# Refused: no gold; doesn't fit.
	home.treasury = 0
	_check(not mode.place_action(hero, home.index, &"upgrade", TerritoryNode.UP_WORKSHOPS), "no gold in its treasury: refused")
	var village: TerritoryNode = null
	for place in mode.territories:
		if place.kind == TerritoryNode.Kind.VILLAGE:
			village = place
			break
	village._captured_by(hero.team_id)
	village.treasury = 1000
	_check(not village.can_upgrade(W) and not mode.place_action(hero, village.index, &"upgrade", W), "a Village has no walls to upgrade")
	_check(mode.place_action(hero, village.index, &"upgrade", TerritoryNode.UP_WORKSHOPS)
			and village.upgrade_cost(TerritoryNode.UP_WORKSHOPS) < home.upgrade_cost(TerritoryNode.UP_STOREHOUSE),
			"a Village upgrades for less")
	# Every peer gets the levels with the places' numbers.
	var packed: PackedInt32Array = mode.logistics._places()
	var at := home.index * LogisticsManager.PLACE_FIELDS + LogisticsManager.PLACE_UPGRADES
	_check(packed.size() == LogisticsManager.PLACE_FIELDS * mode.territories.size()
			and packed[at + W] == 3 and packed[at + TerritoryNode.UP_STOREHOUSE] == 1, "the levels go out with the places")
	# The M map closes with M, Esc and its Close button.
	var map: ConquestMap = main.conquest_map
	for way in ["M", "Esc", "button"]:
		map.toggle()
		var opened := map.visible
		if way == "button":
			(map.find_child("CloseMap", true, false) as Button).pressed.emit()
		else:
			var key := InputEventKey.new()
			key.physical_keycode = KEY_M if way == "M" else KEY_ESCAPE
			key.keycode = key.physical_keycode
			key.pressed = true
			Input.parse_input_event(key)
			Input.flush_buffered_events()
			var up := key.duplicate() as InputEventKey
			up.pressed = false
			Input.parse_input_event(up)
			Input.flush_buffered_events()
		_check(opened and not map.visible, "the map closes with %s" % way)
	# Conquest: a bought soldier is there at once (no training).
	var recruit: UpgradeDef = null
	for def in hero.sheet_items(&"army"):
		if def.id == &"recruit":
			recruit = def
	hero.coins += 100
	var army_before := hero.soldiers().size()
	_check(recruit != null and hero.buy_upgrade(recruit), "buy a recruit")
	_check(hero.soldiers().size() == army_before + 1 and hero.soldiers_training == 0,
			"the soldier is there at once, no training wait (%d -> %d)" % [army_before, hero.soldiers().size()])
	# The army cap from held places goes up to +100 (150 with Command).
	_check(LogisticsManager.CAP_BONUS_MAX == 100, "places can raise the army cap by up to 100")
	# They stay with the place.
	village._captured_by((hero.team_id + 1) % ConquestMode.FACTIONS)
	_check(village.upgrades[TerritoryNode.UP_WORKSHOPS] == 1, "a taken place keeps its upgrades")
	_finish()


func _finish() -> void:
	printerr("%s upgrades: done (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures else 0)

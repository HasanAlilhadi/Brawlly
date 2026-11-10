extends Node
## Conquest: what an army and a place need, place sizes and the lands (offline).
## - a broken weapon (WEAPON_LIFE battles) makes a soldier useless: every blow, shot or heal deals 1;
## - the stock entry's "armies" row counts this hero's soldiers, their rations, the battles their weapons still
##   last, the worn and the broken ones; the HUD's Army row / card show how long the food lasts (first / last to
##   starve) and the weapons left;
## - the M map's place card: the store against its room, who eats there and how long that food lasts, what arming
##   the people waiting takes;
## - every place has a size: small / medium / large all exist, Citadels and the Lair stay medium, a large place has
##   a wider ring, more garrison, output, store room and barracks than a small one of its kind;
## - the lands differ: Ashen Wastes plans more Outposts and bigger places than Frostmere, Frostmere more Villages.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/conquest_needs_test.gd

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


func _soldier(hero: Player, weapon: String, at: Vector3) -> Ally:
	return NetSpawn.unit(&"ally", at, {"owner": hero.peer_id, "team": hero.team_id, "weapon": weapon}) as Ally


func _process(delta: float) -> void:
	t += delta
	if done:
		return
	if t > 60.0:
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
	var logistics := mode.logistics

	# --- A broken weapon: 1 damage -------------------------------------------------------------------------------
	var sword := _soldier(hero, "sword", hero.global_position + Vector3(1.5, 0, 0))
	var bow := _soldier(hero, "bow", hero.global_position + Vector3(-1.5, 0, 0))
	var healer := _soldier(hero, "healer", hero.global_position + Vector3(0, 0, 1.5))
	logistics.tick()  # they join the upkeep: rations, weapons that wear
	var whole: float = sword._roll_melee_damage()[0]
	sword.weapon_uses = Ally.WEAR_STEP
	var worn: float = sword._roll_melee_damage()[0]
	sword.weapon_uses = Ally.WEAPON_LIFE
	_check(worn < whole and worn > 1.0, "a worn sword hits weaker (%.1f -> %.1f)" % [whole, worn])
	_check(sword.weapon_broken() and sword._roll_melee_damage()[0] == 1.0 and sword.weapon_left() == 0,
			"a broken sword deals 1 damage (was %.1f)" % whole)
	bow.weapon_uses = Ally.WEAPON_LIFE
	healer.weapon_uses = Ally.WEAPON_LIFE
	_check(bow.hit_damage(bow.melee_damage) == 1.0 and healer.hit_damage(8.0) == 1.0, "so do a broken bow and a broken healer's staff")
	bow.weapon_uses = 3

	# --- The army in numbers ---------------------------------------------------------------------------------------
	sword.rations = 0
	bow.rations = 1
	healer.rations = 2
	hero.global_position = home.position + (Vector3.ZERO - home.position).normalized() * 150.0  # beyond every supply point
	for ally: Ally in [sword, bow, healer]:
		ally.global_position = hero.global_position + Vector3(randf(), 0, randf())
	logistics.tick()
	var stock: Dictionary = logistics.stock_of(hero.team_id)
	var army: PackedInt32Array = stock[&"armies"].get(hero.peer_id, PackedInt32Array())
	_check(army.size() == LogisticsManager.ARMY_FIELDS and army[LogisticsManager.ARMY_SOLDIERS] == 3,
			"the stock counts this hero's army (%s)" % [army])
	_check(army[LogisticsManager.ARMY_RATIONS] == 1 and army[LogisticsManager.ARMY_RATIONS + 1] == 1
			and army[LogisticsManager.ARMY_RATIONS + 2] == 1, "one soldier each with 0, 1 and 2 rations")
	_check(army[LogisticsManager.ARMY_WEAPON_LEFT] == 0 + (Ally.WEAPON_LIFE - 3) + 0 and army[LogisticsManager.ARMY_BROKEN] == 2
			and army[LogisticsManager.ARMY_WORN] == 3, "weapons: %d battles left, 3 worn of which 2 broken" % army[LogisticsManager.ARMY_WEAPON_LEFT])
	var panel := main.find_child("ConquestPanel", true, false) as ConquestPanel
	_check(panel != null, "the HUD has the Conquest panel")
	if panel:
		var meal_in := int(stock[&"meal_in"])
		var times: Dictionary = panel._starve_times(army, meal_in)
		_check(times.first == meal_in and times.count == 1 and times.last == meal_in + 2 * LogisticsManager.MEAL_SECONDS,
				"no more food: the first starves at the next meal (%s), the last two meals later (%s)" % [
				ConquestPanel._clock(times.first), ConquestPanel._clock(times.last)])
		panel._hover(ConquestPanel.ARMY)
		var row: Dictionary = panel._rows[ConquestPanel.ARMY]
		_check((row.total as Label).text == "Army  3" and (row.flow as Label).text.begins_with("food ")
				and (row.flow as Label).text.contains("weapons"), "the Army row: \"%s\" / \"%s\"" % [(row.total as Label).text, (row.flow as Label).text])
		_check(panel._detail.visible and panel._detail_title.text == "Your army: 3 soldiers"
				and panel._detail_net.text.contains("starve"), "its card warns: \"%s\"" % panel._detail_net.text)
		panel._hover(&"")

	# --- A place's card ----------------------------------------------------------------------------------------------
	for ally: Ally in [sword, bow, healer]:
		ally.global_position = home.position + Vector3(2.0 + randf(), 0, 2.0)
	home.store[&"food"] = 30
	home.store[&"equipment"] = 4
	home.people = 10
	home.train_kind = 0
	var map := main.conquest_map as ConquestMap
	_check(map != null, "the match has the M map")
	if map:
		map.toggle()
		map._selected = home
		map._update_panel()
		var text := map._info.text
		_check(text.contains("Food 30/%d" % home.store_cap()) and text.contains("Weapons 4/%d" % home.store_cap()),
				"the card shows the store against its room")
		_check(text.contains("3 soldiers eat 3 a meal · lasts %s" % ConquestPanel._clock(10 * LogisticsManager.MEAL_SECONDS)),
				"who eats there and how long the food lasts")
		_check(map._people.text.contains("all 10 need 10 weapons (4 here, 6 SHORT) · 0:25"),
				"what arming the people waiting takes: \"%s\"" % map._people.text.get_slice("\n", 1))
		map.toggle()

	# --- Place sizes -------------------------------------------------------------------------------------------------
	var by_size := [0, 0, 0]
	for place in mode.territories:
		by_size[place.place_size] += 1
	_check(by_size[0] > 0 and by_size[1] > 0 and by_size[2] > 0, "small, medium and large places (%s)" % [by_size])
	_check(mode.territories.all(func(p: TerritoryNode) -> bool:
		return p.place_size == TerritoryNode.Size.MEDIUM or (p.kind != TerritoryNode.Kind.CITADEL and p.kind != TerritoryNode.Kind.THRONE)),
			"Citadels and the Lair stay medium")
	var small: TerritoryNode = null
	var large: TerritoryNode = null
	for place in mode.territories:
		if place.kind == TerritoryNode.Kind.CITY and place.place_size == TerritoryNode.Size.SMALL and small == null:
			small = place
		if place.kind == TerritoryNode.Kind.CITY and place.place_size == TerritoryNode.Size.LARGE and large == null:
			large = place
	_check(small != null and large != null, "a small and a large City on this land")
	if small and large:
		_check(large.radius() > small.radius() and large.info().guards > small.info().guards
				and large.store_cap() > small.store_cap() and large.barracks_cap() > small.barracks_cap()
				and large.info().cap > small.info().cap, "the large one: wider ring (%.1f / %.1f m), more garrison, store and barracks" % [
				large.radius(), small.radius()])
		small.specialty = large.specialty
		small.zone = large.zone
		_check(large.output()[&"gold"] > small.output()[&"gold"], "and more output (%s / %s)" % [large.output(), small.output()])
		_check(large.full_name().begins_with("Large ") and small.full_name().begins_with("Small "),
				"named by size (%s, %s)" % [large.full_name(), small.full_name()])

	# --- The lands -----------------------------------------------------------------------------------------------------
	var ash := _plan_of(&"ashlands")
	var frost := _plan_of(&"frostmere")
	_check(ash.outposts > frost.outposts and frost.villages > ash.villages,
			"Ashen Wastes: more Outposts (%d / %d); Frostmere: more Villages (%d / %d)" % [ash.outposts, frost.outposts,
			frost.villages, ash.villages])
	_check(ash.large > frost.large and frost.small > ash.small, "Ashen Wastes' places are bigger (large %d / %d, small %d / %d)" % [
			ash.large, frost.large, ash.small, frost.small])
	_finish()


## What Conquest plans on a land: how many Outposts / Villages, small / large places.
func _plan_of(id: StringName) -> Dictionary:
	var mode := ConquestMode.new()
	var settings := Net.settings.duplicate()
	mode.setup(settings, Net.players, MapCatalog.find(id))
	var counts := {"outposts": 0, "villages": 0, "small": 0, "large": 0}
	for planned: Dictionary in mode._plan:
		if planned.kind == TerritoryNode.Kind.OUTPOST:
			counts.outposts += 1
		elif planned.kind == TerritoryNode.Kind.VILLAGE:
			counts.villages += 1
		if int(planned.get("size", 1)) == TerritoryNode.Size.SMALL:
			counts.small += 1
		elif int(planned.get("size", 1)) == TerritoryNode.Size.LARGE:
			counts.large += 1
	mode.free()
	return counts


func _finish() -> void:
	printerr("%s conquest needs: done (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	TerritoryNode.unguarded_falls = true
	ConquestDemons.campaigns_on = true
	get_tree().quit(1 if failures else 0)

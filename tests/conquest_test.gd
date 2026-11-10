extends Node
## Conquest (solo, offline), the big map: four factions in the corners, the Demon's Lair in the middle (zones 0..6), Cities of
## every specialty; garrisons appear only when a hero comes near; liberating and raising a banner; production into
## each place's own store (by specialty), rations from the nearest supply point, a meal every 200 s (no ration: dead); army cap
## from Cities; barracks fill and the General musters soldiers who walk to them; soldiers rank up from kills;
## caravans carry goods to a cut-off army and rivals loot them; MARCH along the navigation mesh; walls, gates and
## siege engines; holding the Throne long enough wins.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/conquest_test.gd

var t := 0.0
var phase := 0
var squad_id := 0
var squad_goal: TerritoryNode
var pt := 0.0
var failures := 0
var step := 0
var main: Node
var player: Player
var mode: ConquestMode
var logistics: LogisticsManager
var village: TerritoryNode
var cities: Dictionary = {}  # Specialty -> a City of it
var hungry: Ally
var mustered: Array[Ally] = []
var homebound: CaravanUnit
var gate_before := 0.0
var barred: TerritoryNode
var raided: TerritoryNode
var courier: CaravanUnit


func _ready() -> void:
	Net.open_offline_lobby()
	Net.settings.mode = Net.Mode.CONQUEST
	Net.settings.seed = 777
	Net.settings.score_limit = 100000  # the Lair decides this test, not the score
	Net.settings.events = []
	TerritoryNode.unguarded_falls = false  # places the test leaves alone stay held; phase 13 checks the countdown
	ConquestMode.sizes_on = false  # the numbers checked here are the kinds' own (sizes: conquest_needs_test)
	ConquestDemons.campaigns_on = false  # no demon campaigns on them either (conquest_zones_test checks those)
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
	step = 0


func _put(at: Vector3) -> void:
	player.global_position = at
	player.net_position = at


func _done() -> void:
	_log("done: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _def(id: StringName) -> UpgradeDef:
	for def in Player.CATALOG.upgrades:
		if def.id == id:
			return def
	return null


func _live_caravan() -> CaravanUnit:
	for node in get_tree().get_nodes_in_group(&"caravans"):
		if not (node as CaravanUnit).is_dead:
			return node
	return null


## A spot no held place of ours supplies (the middle of the map, beside the Throne's walls).
func _wilds() -> Vector3:
	return Vector3(0.0, 0.0, TerritoryNode.INFO[TerritoryNode.Kind.THRONE].radius + 25.0)


func _process(delta: float) -> void:
	t += delta
	pt += delta
	if t > 420.0:
		_check(false, "finished in time (phase %d)" % phase)
		_done()
		return
	main = get_tree().current_scene
	if main == null or main.name != "Main" or main.get("local_player") == null:
		return
	player = main.local_player
	mode = main.game_mode as ConquestMode
	logistics = mode.logistics
	player.health = player.max_health  # the hero survives the test's walk-ins
	match phase:
		0:
			if pt < 0.5:
				return
			logistics._timer = 100000.0  # only the test's own ticks
			mode._raid_timer.stop()  # raids only when the test sends one
			_check(Net.settings.team_count == ConquestMode.FACTIONS and ConquestMode.FACTIONS == 4, "four factions")
			_check(is_equal_approx(GameConfig.world_half, ConquestMode.WORLD_HALF), "the big map (%.0f m across)" % (GameConfig.world_half * 2.0))
			var corners := true
			for team in 4:
				var citadel := mode.territories[team]
				corners = corners and citadel.kind == TerritoryNode.Kind.CITADEL and citadel.owner_team == team \
						and absf(citadel.position.x) > GameConfig.world_half * 0.7 and absf(citadel.position.z) > GameConfig.world_half * 0.7
			_check(corners, "a Citadel per faction in each corner")
			var seat := mode.throne()
			_check(seat.kind == TerritoryNode.Kind.THRONE and seat.position.length() < 1.0 and seat.state == TerritoryNode.State.INFESTED and seat.zone == 0, "the Demon's Lair in the middle (zone 0), held by demons")
			_check(mode.territories.slice(0, 4).all(func(n: TerritoryNode) -> bool: return n.zone == 6), "the Citadels stand in zone 6")
			var zones := {}
			for node in mode.territories:
				zones[node.zone] = zones.get(node.zone, 0) + 1
			_check(range(1, 7).all(func(z: int) -> bool: return zones.get(z, 0) >= 3), "places in every zone (%s)" % str(zones))
			var plain := mode.territories.filter(func(n: TerritoryNode) -> bool: return n.zone == 1 and n.kind == TerritoryNode.Kind.CITY)
			_check(not plain.is_empty() and plain.all(func(n: TerritoryNode) -> bool: return n.gate == null and n.has_node("Houses")), "zone 1 Cities have no walls, only houses")
			var outer := mode.territories.filter(func(n: TerritoryNode) -> bool: return n.zone >= 5 and n.kind == TerritoryNode.Kind.CITY)
			var inner := mode.territories.filter(func(n: TerritoryNode) -> bool: return n.zone == 2 and n.kind == TerritoryNode.Kind.CITY)
			_check(not outer.is_empty() and not inner.is_empty() and outer[0].gate.max_health > inner[0].gate.max_health, "outer walls are stronger (%.0f vs %.0f)" % [outer[0].gate.max_health if outer else 0.0, inner[0].gate.max_health if inner else 0.0])
			var rich: int = outer[0].output().values().reduce(func(a, b): return a + b, 0) if outer else 0
			var poor: int = plain[0].output().values().reduce(func(a, b): return a + b, 0) if plain else 0
			_check(rich > poor, "outer Cities make more (%d vs %d a tick)" % [rich, poor])
			var counts := {}
			for node in mode.territories:
				if node.kind == TerritoryNode.Kind.CITY:
					counts[node.specialty] = counts.get(node.specialty, 0) + 1
					if node.gate:
						cities[node.specialty] = cities.get(node.specialty, node)  # walled ones: the gate checks below
			_check(counts.size() == 3 and counts.values().min() >= 5, "Iron, Lumber and Farm Cities (%s)" % str(counts))
			_check(mode.territories.size() > 80, "many places (%d)" % mode.territories.size())
			_check(player.global_position.distance_to(mode.territories[0].position) < 6.0, "hero spawns at its Citadel")
			var far_guards := mode.territories.filter(func(n: TerritoryNode) -> bool:
					return n._guards_spawned and n.position.distance_to(player.global_position) > TerritoryNode.GARRISON_RANGE + 1.0)
			_check(far_guards.is_empty(), "no garrison far from every hero")
			for node in mode.territories:
				if node.kind == TerritoryNode.Kind.VILLAGE and (village == null or
						node.position.distance_to(player.global_position) < village.position.distance_to(player.global_position)):
					village = node
			_put(village.position + Vector3(TerritoryNode.GARRISON_RANGE - 10.0, 0.0, 0.0).limit_length(
					village.position.distance_to(player.global_position)))
			_next()
		1:
			if not village._guards_spawned:
				_put(village.position + Vector3(20.0, 0.0, 0.0))
				if pt < 5.0:
					return
			if step == 0:
				if not village._spawn_queue.is_empty() and pt < 5.0:
					return  # the garrison rises one a frame
				_check(village._guards_spawned and village._guards.size() == roundi(TerritoryNode.INFO[TerritoryNode.Kind.VILLAGE].guards * TerritoryNode.ZONE_GUARDS[village.zone]), "a hero nearby wakes the garrison (%d)" % village._guards.size())
				for guard in village._guards:
					(guard as Unit).die()
				step = 1
				pt = 0.0
				return
			if step == 1:
				if pt < 1.0:
					return
				_check(village.state == TerritoryNode.State.NEUTRAL, "garrison dead → liberated")
				step = 2
				pt = 0.0
			_put(village.position + Vector3(1.0, 0.0, 1.0))
			if village.state != TerritoryNode.State.OWNED and pt < 15.0:
				return
			_check(village.owner_team == 0, "standing in it raises our banner")
			_check(village.lord == player.peer_id, "the hero who took it is its lord")
			_next()
		2:
			# Production goes into each place's own store; soldiers eat where they stand; the unfed die.
			var food_before: int = village.store[&"food"]
			var gold_before := village.treasury
			logistics.tick()
			_check(village.treasury == gold_before + int(village.output()[&"gold"]) and village.output()[&"gold"] > 0, "gold goes into its treasury (%d)" % village.treasury)
			var coins_before := player.coins
			var taken := mode.withdraw(player)
			_check(taken > 0 and player.coins == coins_before + taken and village.treasury == 0, "its lord takes the treasury (%d gold)" % taken)
			village.treasury = 5
			_put(village.position + Vector3(village.radius() + 5.0, 0.0, 0.0))
			_check(mode.withdraw(player) == 0 and village.treasury == 5, "only standing in it")
			_put(village.position + Vector3(1.0, 0.0, 1.0))
			village.lord = 9999  # a lord who left the game
			village._update_lord()
			_check(village.lord == player.peer_id, "an unguarded place goes to the faction's hero who walks in")
			_check(village.store[&"food"] == food_before + int(village.output()[&"food"]), "a Village grows food into its own store (%d → %d)" % [food_before, village.store[&"food"]])
			hungry = NetSpawn.unit(&"ally", village.position + Vector3(2.0, 0.0, 0.0), {"owner": player.peer_id, "team": 0, "weapon": "bow"}) as Ally
			step = 1
			_next()
		3:
			if pt < 0.3:
				return
			var food_before: int = village.store[&"food"]
			logistics.tick()
			_check(hungry.rations == LogisticsManager.MAX_RATIONS and village.store[&"food"] == food_before + int(village.output()[&"food"]) - 1, "a soldier by the Village takes a ration from its store (%d)" % hungry.rations)
			_check(hungry.weapon_uses == 0 and hungry.upkeep_damage == 1.0, "and joins the upkeep with a new weapon")
			# Weapons wear by battle: weaker every 2, broken after 8; a new one comes from a supply point.
			hungry._fight()
			hungry._wear_weapon(Ally.BATTLE_END + 0.1)
			_check(hungry.weapon_uses == 1 and hungry.upkeep_damage == 1.0, "a battle uses the weapon once (still whole)")
			hungry._fight()
			hungry._wear_weapon(Ally.BATTLE_END + 0.1)
			_check(hungry.weapon_uses == 2 and is_equal_approx(hungry.upkeep_damage, 1.0 - Ally.WEAR_LOSS), "two battles: weaker (%.2f)" % hungry.upkeep_damage)
			hungry.weapon_uses = Ally.WEAPON_LIFE
			_check(hungry.weapon_broken() and hungry.hit_damage(hungry.melee_damage) == Ally.BROKEN_DAMAGE and hungry._roll_melee_damage()[0] == 1.0,
					"eight battles: broken — every blow deals 1")
			var weapons_before: int = village.store[&"equipment"]
			village.store[&"equipment"] = weapons_before + 1
			logistics.tick()
			_check(hungry.weapon_uses == 0 and village.store[&"equipment"] == weapons_before + int(village.output()[&"equipment"]), "by a supply point it gets a new weapon for one weapons supply")
			hungry.global_position = _wilds()
			_check(not logistics.is_supplied(hungry, 0), "the wilds are beyond every supply point")
			var fed := NetSpawn.unit(&"ally", _wilds() + Vector3(1.0, 0.0, 0.0), {"owner": player.peer_id, "team": 0, "weapon": "sword", "rations": 1}) as Ally
			hungry.rations = 0
			logistics._ticks = 1
			logistics.tick()
			_check(hungry.upkeep_speed < 1.0 and not hungry.is_dead, "no ration left: slower, alive until the meal")
			_check(logistics.stock_of(0)[&"starving"] >= 1, "the HUD counts those without food (%d)" % logistics.stock_of(0)[&"starving"])
			_check(int(logistics.stock_of(0)[&"meal_in"]) > 0, "and shows the next meal")
			hungry.global_position = _wilds()
			fed.global_position = _wilds() + Vector3(1.0, 0.0, 0.0)
			logistics._ticks = LogisticsManager.MEAL_TICKS - 1  # the next tick is a meal (every 200 s)
			logistics.tick()
			_check(hungry.is_dead, "at the meal, a soldier without a ration dies of hunger")
			_check(not fed.is_dead and fed.rations == 0, "one with a ration eats it and lives")
			fed.die()
			_next()
		4:
			# Specialized production and army cap.
			var cap_before := player.follower_cap
			var before := {}
			for specialty in cities:
				var city: TerritoryNode = cities[specialty]
				city._captured_by(0)
				city.gate.health = city.gate.max_health  # a half-rebuilt gate would spend the new weapons on itself
				before[specialty] = city.store.duplicate()
			logistics.tick()
			var iron: TerritoryNode = cities[TerritoryNode.Specialty.IRON]
			var lumber: TerritoryNode = cities[TerritoryNode.Specialty.LUMBER]
			var farm: TerritoryNode = cities[TerritoryNode.Specialty.FARM]
			_check(iron.store[&"equipment"] - before[TerritoryNode.Specialty.IRON][&"equipment"] == roundi(6 * TerritoryNode.ZONE_OUTPUT[iron.zone]), "an Iron City makes weapons (zone %d)" % iron.zone)
			_check(lumber.store[&"equipment"] - before[TerritoryNode.Specialty.LUMBER][&"equipment"] == roundi(6 * TerritoryNode.ZONE_OUTPUT[lumber.zone]), "a Lumber City makes weapons (bows: no arrows) (zone %d)" % lumber.zone)
			_check(not iron.store.has(&"ammo"), "there are no arrows to store")
			_check(farm.store[&"food"] - before[TerritoryNode.Specialty.FARM][&"food"] == roundi(10 * TerritoryNode.ZONE_OUTPUT[farm.zone]), "a Farm City makes food (zone %d)" % farm.zone)
			_check(iron.store[&"food"] == 0 and farm.store[&"equipment"] == before[TerritoryNode.Specialty.FARM][&"equipment"], "each only its own goods")
			_check(player.follower_cap == cap_before + 3 * TerritoryNode.INFO[TerritoryNode.Kind.CITY].cap, "Cities raise the army cap (%d → %d)" % [cap_before, player.follower_cap])
			_next()
		5:
			# Barracks fill over time; the General musters soldiers, who walk to them.
			var lumber: TerritoryNode = cities[TerritoryNode.Specialty.LUMBER]
			if step == 0:
				var pool_before := lumber.people + lumber.growth
				logistics.tick()
				logistics.tick()
				var grown := lumber.people + lumber.growth - pool_before
				_check(is_equal_approx(grown, TerritoryNode.ZONE_PEOPLE[lumber.zone]), "a City's barracks get people (%.2f per 10 s in zone %d)" % [grown, lumber.zone])
				_check(mode.territories.all(func(t: TerritoryNode) -> bool: return t.has_barracks()), "every place has a barracks, villages too")
				_check(TerritoryNode.ZONE_PEOPLE[6] > TerritoryNode.ZONE_PEOPLE[1], "more people out toward the corners")
				_check(lumber.armed.all(func(n: int) -> bool: return n == 0) and lumber.drill[0] == 0.0, "people without a class stay unarmed and untrained")
				for node in mode.territories:
					node.clear_barracks()
				lumber.people = 14
				lumber.store[&"food"] = 50
				lumber.store[&"equipment"] = 50
				_check(logistics.general_of(0) == player.peer_id, "our only hero is the General")
				_put(lumber.position + Vector3(45.0, 0.0, 0.0))
				var muster := _def(&"muster")
				_check(player.sheet_items(&"army").has(muster) and player.can_buy(muster), "the General can muster (Army tab)")
				_check(player.buy_upgrade(muster), "muster")
				for node in player.followers():
					if (node as Ally).mustering:
						mustered.append(node)
				_check(mustered.size() == LogisticsManager.MUSTER_BATCH and lumber.barracks == 4, "10 leave the barracks (%d, %d left)" % [mustered.size(), lumber.barracks])
				_check(lumber.store[&"food"] == 40 and lumber.store[&"equipment"] == 40, "each takes a ration and a weapon from its store")
				lumber.people = 5
				lumber.store[&"food"] = 2
				_check(logistics.can_muster(player) <= 2, "a barracks sends no more than its store feeds (%d)" % logistics.can_muster(player))
				lumber.people = 4
				lumber.store[&"food"] = 40
				_check(mustered.all(func(a: Ally) -> bool: return a.weapon == "bow"), "Lumber City barracks send archers")
				step = 1
				pt = 0.0
				return
			_put(lumber.position + Vector3(45.0, 0.0, 0.0))
			var walking := mustered.filter(func(a: Ally) -> bool: return is_instance_valid(a) and a.mustering)
			if not walking.is_empty() and pt < 60.0:
				return
			_check(walking.is_empty(), "they march to the General and join (%.0fs)" % pt)
			_next()
		6:
			# Ranks from kills.
			var veteran := mustered[0]
			var health_before := veteran.max_health
			veteran.credit_kill(null)
			veteran.credit_kill(null)
			_check(veteran.rank == 1 and is_equal_approx(veteran.max_health, health_before * (1.0 + Ally.RANK_BONUS)), "two kills: rank I (%s), +15 percent" % Ally.RANK_NAMES[veteran.rank])
			for i in 18:
				veteran.credit_kill(null)
			_check(veteran.rank == 4 and veteran._rank_label != null and veteran._rank_label.text == "IV", "twenty kills: Champion (IV)")
			# Soldiers waiting in a barracks train: they leave with the rank their drill earned.
			var drilled: TerritoryNode = cities[TerritoryNode.Specialty.IRON]
			for node in mode.territories:
				node.clear_barracks()
			# A class picked: people get its weapon (from the store) and only they train. A Village: it makes no
			# weapons and has no gate to rebuild, so the store's weapons are only spent on arming.
			drilled = mode.territories.filter(func(t: TerritoryNode) -> bool: return t.kind == TerritoryNode.Kind.VILLAGE)[0]
			drilled._captured_by(0)
			_put(drilled.position)  # the army stands supplied: these ticks send no caravan
			for ally in player.followers():
				(ally as Ally).global_position = drilled.position + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
			var bow := TerritoryNode.SOLDIER_KINDS.find("bow")
			drilled.people = 6
			drilled.store[&"food"] = 10
			drilled.store[&"equipment"] = 3
			_check(mode.place_action(player, drilled.index, &"train", bow) and drilled.train_kind == bow, "pick archers for its barracks (map)")
			logistics.tick()
			_check(drilled.armed[bow] == LogisticsManager.ARM_PER_TICK and drilled.people == 6 - LogisticsManager.ARM_PER_TICK
					and drilled.store[&"equipment"] == 3 - LogisticsManager.ARM_PER_TICK, "two people a tick get bows from the store (%d armed)" % drilled.armed[bow])
			logistics.tick()
			_check(drilled.armed[bow] == 3 and drilled.store[&"equipment"] == 0, "no weapons left: no more are armed (%d)" % drilled.armed[bow])
			_check(drilled.drill[bow] > 0.0 and drilled.drill[TerritoryNode.SOLDIER_KINDS.find("sword")] == 0.0, "the armed ones train (%.0f s)" % drilled.drill[bow])
			drilled.drill[bow] = Ally.DRILL_SECONDS[3]
			var known := player.soldiers()
			_check(mode.place_action(player, drilled.index, &"muster", bow), "take archers on the map")
			var fresh := player.soldiers().filter(func(a: Node) -> bool: return not known.has(a))
			_check(fresh.size() == 3 and fresh.all(func(a: Ally) -> bool: return a.weapon == "bow" and a.rank == 3),
					"trained archers leave as Elites (%d)" % fresh.size())
			# Unarmed people taken as a class get its weapon now (from the store) and no training.
			drilled.store[&"equipment"] = 1
			var wizard := TerritoryNode.SOLDIER_KINDS.find("wizard")
			known = player.soldiers()
			_check(mode.place_action(player, drilled.index, &"muster", wizard), "take wizards from the people")
			fresh = player.soldiers().filter(func(a: Node) -> bool: return not known.has(a))
			_check(fresh.size() == 1 and (fresh[0] as Ally).weapon == "wizard" and (fresh[0] as Ally).rank == 0
					and drilled.store[&"equipment"] == 0, "one weapon in store: one raw wizard (%d)" % fresh.size())
			for node in mode.territories:
				if node != drilled:
					node.clear_barracks()  # people came in elsewhere during the ticks
			drilled.armed[0] = 1
			drilled.drill[0] = Ally.DRILL_SECONDS[3]
			drilled.store[&"food"] = 10  # the army standing here ate its food
			known = player.followers()
			logistics.muster(player)
			fresh = player.followers().filter(func(a: Node) -> bool: return not known.has(a))
			_check(fresh.size() == 1 and (fresh[0] as Ally).rank == 3 and (fresh[0] as Ally).weapon == "sword",
					"the General musters the trained swordsman first, as an Elite (%d, room %d)" % [fresh.size(), player.follower_cap - player.army_size()])
			drilled.clear_barracks()
			_next()
		7:
			# A cut-off army gets a caravan from the depot with the most goods; a rival loots it.
			var farm: TerritoryNode = cities[TerritoryNode.Specialty.FARM]
			farm.store[&"food"] = 200
			farm.store[&"equipment"] = 50
			var field := farm.position + Vector3(0.0, 0.0, 60.0)
			_put(field)
			for ally in player.followers():
				(ally as Ally).global_position = field + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
			var food_before: int = farm.store[&"food"]
			logistics.tick()
			var caravan := _live_caravan()
			_check(caravan != null and caravan.owner_peer == player.peer_id, "a caravan is sent after the cut-off army")
			if caravan == null:
				_done()
				return
			_check(farm.store[&"food"] <= food_before + 10 - int(CaravanUnit.CARGO[&"food"]), "loaded at the Farm City (food %d → %d)" % [food_before, farm.store[&"food"]])
			caravan.global_position = field
			mustered[1].global_position = field
			mustered[1].weapon_uses = Ally.WEAPON_LIFE
			mustered[1].rations = 0
			logistics.tick()
			_check(mustered[1].weapon_uses == 0 and mustered[1].rations > 0, "the army eats and rearms from it")
			Net.players[2] = {"name": "Rival", "team": 1, "class": &"swordsman", "ready": false}
			var rival_home := mode.territories[1]
			var rival_food: int = rival_home.store[&"food"]
			var loot: int = caravan.cargo[&"food"]
			caravan.global_position = rival_home.position + Vector3(0.0, 0.0, 20.0)
			caravan.last_attacker_peer = 2
			caravan.die()
			_check(rival_home.store[&"food"] == mini(rival_food + loot, TerritoryNode.STORE_CAP), "a rival loots its cargo into their nearest store (+%d food)" % loot)
			Net.players.erase(2)
			_next()
		8:
			# MARCH to a far held City along the navigation mesh.
			var iron: TerritoryNode = cities[TerritoryNode.Specialty.IRON]
			if step == 0:
				if not mode.navigation_ready and pt < 60.0:
					return
				_check(mode.navigation_ready, "the navigation mesh is baked (%.0fs)" % t)
				player.command_army(Player.Order.MARCH, iron.position)
				_check(player.army_point.is_equal_approx(iron.position), "MARCH targets the City")
				step = 1
				pt = 0.0
				return
			var soldiers := player.followers()
			var there := soldiers.filter(func(a: Node) -> bool:
					return Ally._flat((a as Node3D).global_position - iron.position).length() < Ally.MARCH_ARRIVE + 1.0)
			if there.size() < soldiers.size() * 0.8 and pt < 120.0:
				return
			_check(there.size() >= soldiers.size() * 0.8, "the army marches to the City (%d / %d in %.0fs)" % [there.size(), soldiers.size(), pt])
			player.command_army(Player.Order.FOLLOW, player.global_position)
			_next()
		9:
			# Walls, gates and siege engines on the Red Citadel.
			var target_gate := mode.territories[1].gate
			var outside := target_gate.global_position + target_gate.global_basis.z.normalized() * 16.0
			outside.y = 0.0
			if step == 0:
				_check(get_tree().get_nodes_in_group(&"conquest_walls").size() > 4 + 1 + 15, "Cities, Citadels and the Throne are walled")
				_check(target_gate.shut, "an enemy gate is shut")
				var home_gate := mode.territories[0].gate
				_put(home_gate.global_position - home_gate.global_basis.z.normalized() * 2.0)
				step = 1
				pt = 0.0
				return
			if step == 1:
				if pt < 1.0:
					return
				_check(not mode.territories[0].gate.shut, "our own gate opens for us")
				_put(outside)
				player.coins = 1000
				_check(player.buy_upgrade(_def(&"siege_catapult")) and player.buy_upgrade(_def(&"siege_ram")), "buy a catapult and a ram")
				step = 2
				pt = 0.0
				return
			if step == 2:
				_put(outside)
				if not target_gate.is_broken() and pt < 90.0:
					return
				_check(target_gate.is_broken(), "siege engines break the Citadel gate (%.0fs)" % pt)
				# A demon-held City: its gate is barred too, and an army order sends the engines at it from beyond `seek`.
				barred = _infested_city()
				_check(barred != null and barred.gate.shut, "the demons bar a City's gate")
				var front := barred.gate.global_position + barred.gate.global_basis.z.normalized() * 45.0
				front.y = 0.0
				_put(barred.gate.global_position + barred.gate.global_basis.z.normalized() * 20.0)
				for node in get_tree().get_nodes_in_group(&"siege"):
					var engine := node as SiegeEngine
					engine.global_position = front + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
					engine.max_health = 100000.0
					engine.health = 100000.0
				player.command_army(Player.Order.CHARGE, barred.global_position)
				step = 3
				pt = 0.0
				return
			_put(barred.gate.global_position + barred.gate.global_basis.z.normalized() * 20.0)
			if not barred.gate.is_broken() and pt < 120.0:
				return
			_check(barred.gate.is_broken(), "ordered at it, the engines break the demons' gate (%.0fs)" % pt)
			player.command_army(Player.Order.FOLLOW, player.global_position)
			_next()
		10:
			# Raids: demons march on a held plain place in zone 1 and take it back when nobody defends it.
			if step == 0:
				raided = mode.territories.filter(func(n: TerritoryNode) -> bool: return n.zone == 1 and n.gate == null)[0]
				raided._guards_spawned = true  # no garrison: we hold it from the start
				raided._captured_by(0)
				_put(raided.position + Vector3(-raided.position.normalized() * 120.0))
				var raiders := mode.raid_place(raided)
				_check(raiders.size() == ConquestMode.RAID_BASE + ConquestMode.RAID_STEP * 4, "a zone 1 raid brings %d demons" % raiders.size())
				step = 1
				pt = 0.0
				return
			_put(raided.position + Vector3(-raided.position.normalized() * 120.0))
			if raided.state == TerritoryNode.State.OWNED and pt < 60.0:
				return
			_check(raided.state == TerritoryNode.State.INFESTED and raided.owner_team == -1, "undefended, the demons take it back (%.0fs)" % pt)
			_next()
		11:
			# Couriers and the map: a route carries goods to another place and the courier comes home; buy a courier,
			# take soldiers and gold from the map's card.
			var farm: TerritoryNode = cities[TerritoryNode.Specialty.FARM]
			var iron: TerritoryNode = cities[TerritoryNode.Specialty.IRON]
			if step == 0:
				for node in get_tree().get_nodes_in_group(&"caravans"):
					(node as CaravanUnit)._retired = true
					(node as Unit).die()
				farm.couriers = 1
				farm.courier_total = 1
				farm.store[&"food"] = 200
				iron.store[&"food"] = 0
				farm.lord = player.peer_id
				_check(mode.place_action(player, farm.index, &"route", iron.index) and farm.route == iron.index, "the map sets a route: Farm → Iron City")
				logistics.tick()
				courier = null
				for node in get_tree().get_nodes_in_group(&"caravans"):
					if (node as CaravanUnit).dest == iron.index:
						courier = node
				_check(courier != null and farm.couriers == 0 and int(courier.cargo[&"food"]) == CaravanUnit.CARGO[&"food"], "its courier sets out with a load")
				mode.place_action(player, farm.index, &"route", TerritoryNode.ROUTE_NONE)
				if courier:
					var toward := (iron.position - courier.global_position)
					toward.y = 0.0
					courier.global_position = iron.position - toward.normalized() * (iron.radius() + 6.0)
				step = 1
				pt = 0.0
				return
			if step == 1:
				if is_instance_valid(courier) and not courier._going_home and pt < 40.0:
					return
				_check(int(iron.store[&"food"]) >= CaravanUnit.CARGO[&"food"], "it unloads at the Iron City (%d food)" % iron.store[&"food"])
				if is_instance_valid(courier):
					courier.global_position = farm.position + Vector3(farm.radius() + 4.0, 0.0, 0.0)
				step = 2
				pt = 0.0
				return
			if step == 2:
				if farm.couriers == 0 and pt < 40.0:
					return
				_check(farm.couriers == 1, "and walks home: the Farm has its courier back")
				player.coins = 100
				_check(mode.place_action(player, farm.index, &"courier", 0) and farm.courier_total == 2 and player.coins == 100 - LogisticsManager.COURIER_COST, "buy a courier on the map")
				farm.people = 3
				farm.store[&"equipment"] = 10
				var known := player.followers()
				var room := player.follower_cap - player.army_size()
				_check(mode.place_action(player, farm.index, &"muster", -1) == (room > 0), "take soldiers from its barracks")
				var fresh := player.followers().filter(func(a: Node) -> bool: return not known.has(a))
				_check(room <= 0 or fresh.all(func(a: Ally) -> bool: return a.weapon == "healer"), "a Farm arms its people as healers (%d)" % fresh.size())
				farm.treasury = 30
				var coins_before := player.coins
				_check(mode.place_action(player, farm.index, &"withdraw", 0) and player.coins == coins_before + 30, "its lord takes its gold from anywhere")
				var map: ConquestMap = main.conquest_map
				_check(map != null and not map.is_open(), "the M map exists, closed")
				if map:
					map.toggle()
					map._selected = farm
					map._update_panel()
					_check(map.is_open() and map._buttons[&"courier"].visible and "Farm" in map._info.text, "the map's card shows the place and its orders")
					_check(map._barracks_box.visible and map._class_rows.size() == 4 and (map._class_rows[0].train as Button).visible,
							"and its barracks: a row per class with Train / Take")
					map.toggle()
				_next()
		12:
			# Squads: taken on the map as a squad of 8 with a leader, sent to a place, holding a point, a new
			# leader when it falls, then joining the hero's army.
			var squads := mode.squads
			var base: TerritoryNode = cities[TerritoryNode.Specialty.IRON]
			if step == 0:
				for id in squads.of_player(player.peer_id):
					squads._join(id)  # the squads taken earlier go back to the army
				base.clear_barracks()
				base.armed[0] = 8
				base.drill[0] = Ally.DRILL_SECONDS[2]
				base.store[&"food"] = 20
				player.follower_cap = player.army_size() + 20
				var before := player.followers().size()
				_check(mode.place_action(player, base.index, &"muster", 0 + 10 * 1), "take a squad of 8 swordsmen on the map")
				var ids := squads.of_player(player.peer_id)
				_check(ids.size() == 1, "one squad (%d)" % ids.size())
				if ids.is_empty():
					_done()
					return
				squad_id = ids[0]
				var all := squads.members(squad_id)
				var heads := all.filter(func(a: Ally) -> bool: return a.squad_leader)
				_check(all.size() == 8 and heads.size() == 1 and heads[0]._banner != null and heads[0]._banner.visible,
						"8 soldiers, one leads it with a banner (%d, %d)" % [all.size(), heads.size()])
				_check(player.followers().size() == before and player.army_size() >= all.size(), "out of the hero's army, still counted in its size")
				_check(squads.order_text(squad_id) == "Holding " + base.display_name, "it holds its barracks' place: " + squads.order_text(squad_id))
				_check(all.all(func(a: Ally) -> bool: return a.rank == 2), "with the rank they trained")
				var far: TerritoryNode = null
				for node in mode.territories:
					var d := node.position.distance_to(base.position)
					if node != base and d > 25.0 and (far == null or d < far.position.distance_to(base.position)):
						far = node
				squad_goal = far
				_check(mode.squads.command(player, squad_id, &"go", far.index, Vector3.ZERO) and squads.order_text(squad_id) == "Going to " + far.display_name,
						"send it to %s (%.0f m)" % [far.display_name, far.position.distance_to(base.position)])
				var map: ConquestMap = main.conquest_map
				map.toggle()
				map._squad = squad_id
				map._update_panel()
				_check("Squad" in map._title.text and map._buttons[&"squad_go"].visible and not map._buttons[&"courier"].visible,
						"the map shows the squad's card and orders")
				map.toggle()
				step = 1
				pt = 0.0
				return
			if step == 1:
				var head := squads.leader_of(squad_id)
				var arrived := head != null and Ally._flat(head.global_position - squad_goal.position).length() < ConquestSquads.GUARD
				if not arrived and pt < 80.0:
					return
				_check(arrived, "the leader leads it there (%.0fs)" % pt)
				if pt < 6.0:
					return
				var near := squads.members(squad_id).filter(func(a: Ally) -> bool:
					return Ally._flat(a.global_position - squad_goal.position).length() < ConquestSquads.GUARD + 6.0)
				_check(near.size() >= 6, "the squad follows it (%d of %d there)" % [near.size(), squads.members(squad_id).size()])
				squads._check()
				_check(int(squads.squad(squad_id).order) == ConquestSquads.Order.HOLD, "and holds the place")
				var point := squad_goal.position + Vector3(8.0, 0.0, 0.0)
				_check(squads.command(player, squad_id, &"hold", -1, point) and squads.order_text(squad_id) == "Holding a point", "hold a point")
				var old := squads.leader_of(squad_id)
				old.die()
				squads._check()
				var next := squads.leader_of(squad_id)
				_check(next != null and next != old and next.squad_leader, "its leader falls: another leads")
				var count := squads.members(squad_id).size()
				var before := player.followers().size()
				_check(squads.command(player, squad_id, &"join", -1, Vector3.ZERO) and not squads.squads.has(squad_id), "join my army: the squad breaks up")
				_check(player.followers().size() == before + count, "its soldiers follow the hero again (%d)" % count)
				_next()
		13:
			# Raids hit guarded places too: raiders batter a standing gate. Unguarded places fall to the demons.
			_check(ConquestMode.ZONE_RAID[1] > ConquestMode.ZONE_RAID[4] and ConquestMode.ZONE_RAID[4] > ConquestMode.ZONE_RAID[6]
					and ConquestMode.ZONE_RAID[6] > 0.0, "raids everywhere, more the nearer the Lair")
			var walled: TerritoryNode = null
			for node in mode.territories:
				if node.gate and node.kind != TerritoryNode.Kind.CITADEL and node.kind != TerritoryNode.Kind.THRONE:
					walled = node
					break
			walled._guards_spawned = true
			walled._captured_by(0)
			walled.gate.health = walled.gate.max_health
			var raiders := mode.raid_place(walled)
			var at_gate := raiders.all(func(d: Enemy) -> bool:
				return Ally._flat(d.home - walled.gate.outside_point(1.0)).length() < 4.0)
			_check(at_gate, "raiders on a walled place head for its gate")
			for d in raiders:
				(d as Enemy).global_position = walled.gate.outside_point(1.0)
				(d as Enemy).target = null
			var dealt := mode._batter()
			_check(dealt > 0.0 and walled.gate.health < walled.gate.max_health, "and batter it (%.0f a second)" % dealt)
			for d in raiders:
				(d as Unit).die()
			# The countdown: zone 1 the shortest, 120 s by the corners, never a Citadel.
			TerritoryNode.unguarded_falls = true
			_check(TerritoryNode.ZONE_UNGUARDED[1] == 20.0 and TerritoryNode.ZONE_UNGUARDED[6] == 120.0, "unguarded: 20 s in zone 1 up to 120 s in zone 6")
			var lone: TerritoryNode = mode.territories.filter(func(n: TerritoryNode) -> bool:
				return n.zone == 1 and n.gate == null and n.state != TerritoryNode.State.OWNED)[0]
			lone._guards_spawned = true
			lone._captured_by(0)
			_put(lone.position + Vector3(-lone.position.normalized() * 120.0))
			for ally in player.soldiers():
				(ally as Ally).global_position = player.global_position
			_check(lone._update_guard(1.0) and is_equal_approx(lone.unguarded_left, 20.0), "nobody in it: demons take it in 20 s")
			var guard := player.soldiers()[0] as Ally
			guard.global_position = lone.position
			_check(lone._update_guard(1.0) and lone.unguarded_left < 0.0, "a soldier standing in it guards it")
			guard.global_position = player.global_position
			lone._update_guard(1.0)
			for i in 19:
				lone._update_guard(1.0)
			_check(lone.state == TerritoryNode.State.OWNED and lone.unguarded_left <= 1.0, "still ours with a second left")
			lone._update_guard(1.0)
			_check(lone.state == TerritoryNode.State.INFESTED and lone.owner_team == -1 and not lone._guards_spawned,
					"left unguarded, the demons take it (their garrison comes when a hero does)")
			var citadel := mode.territories[0]
			_check(not citadel._update_guard(1.0) and citadel.unguarded_left < 0.0, "a Citadel never falls that way")
			TerritoryNode.unguarded_falls = false
			_next()
		14:
			# The Lair: held long enough, it wins.
			var seat := mode.throne()
			seat._spawn_guards()
			while not seat._spawn_queue.is_empty():
				seat._spawn_some()  # all of it now (the game raises one a frame)
			var lord := seat._guards[0] as Enemy
			_check(lord.scene_file_path.ends_with("malakor.tscn") and lord.scale.x > 1.5 and lord.power > 3.0,
					"Malakor holds the Lair (x%.1f size, x%.1f power)" % [lord.scale.x, lord.power])
			_check(seat._guards.size() > TerritoryNode.INFO[TerritoryNode.Kind.THRONE].guards, "with the biggest garrison (%d)" % seat._guards.size())
			for guard in seat._guards:
				(guard as Unit).die()
			seat._captured_by(0)
			_check(seat.owner_team == 0, "we take the Demon's Lair")
			for i in ConquestMode.THRONE_WIN_TICKS - 1:
				mode.on_logistics_tick()
			_check(not mode.is_over, "not yet: held %d ticks" % mode.throne_ticks)
			mode.on_logistics_tick()
			_next()
		15:
			if pt < 0.3:
				return
			_check(mode.is_over, "holding the Lair %d minutes wins" % (ConquestMode.THRONE_WIN_TICKS * int(LogisticsManager.TICK) / 60))
			_done()


## The infested walled City nearest the hero.
func _infested_city() -> TerritoryNode:
	var best: TerritoryNode = null
	for node in mode.territories:
		var place := node as TerritoryNode
		if place.kind != TerritoryNode.Kind.CITY or place.state != TerritoryNode.State.INFESTED or place.gate == null:
			continue
		if best == null or place.position.distance_to(player.global_position) < best.position.distance_to(player.global_position):
			best = place
	return best

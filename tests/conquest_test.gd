extends Node
## Conquest (solo, offline): three citadels owned by the three factions, everything else infested; killing a
## village's guards liberates it, standing in it raises our banner; the logistics tick pays income + points, feeds
## soldiers (starving slows them), wears / repairs weapons and refills quivers only within supply range; an enemy
## citadel's gate shrugs off our own side, takes HAND_SHARE from a hero, and once broken the citadel can be taken;
## holding every citadel wins. Caravans follow cut-off armies, supply them, get looted or go home; MARCH sends the
## army to a far territory along the navigation mesh, where it patrols.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/conquest_test.gd

var t := 0.0
var phase := 0
var pt := 0.0
var failures := 0
var main: Node
var player: Player
var mode: ConquestMode
var village: TerritoryNode
var archer: Ally
var score_before := 0
var field := Vector3.ZERO
var homebound: CaravanUnit
var homebound_cargo := 0
var home_food := 0
var patrol_from := Vector3.ZERO
var marched := false


func _ready() -> void:
	Net.open_offline_lobby()
	Net.settings.mode = Net.Mode.CONQUEST
	Net.settings.seed = 777
	Net.settings.score_limit = 1000  # the citadels decide this test, not the score
	Net.settings.events = []
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


func _put(at: Vector3) -> void:
	player.global_position = at
	player.net_position = at


func _done() -> void:
	_log("done: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _live_caravan() -> CaravanUnit:
	for node in get_tree().get_nodes_in_group(&"caravans"):
		if not (node as CaravanUnit).is_dead:
			return node
	return null


func _process(delta: float) -> void:
	t += delta
	pt += delta
	if t > 240.0:
		_check(false, "finished in time (phase %d)" % phase)
		_done()
		return
	main = get_tree().current_scene
	if main == null or main.name != "Main" or main.get("local_player") == null:
		return
	player = main.local_player
	mode = main.game_mode as ConquestMode
	player.health = player.max_health  # the hero survives the test's walk-ins
	match phase:
		0:
			if pt < 0.5:
				return
			_check(mode != null and mode.logistics != null, "Conquest mode + logistics")
			_check(Net.settings.team_count == ConquestMode.FACTIONS, "three factions")
			var owners := [mode.territories[0].owner_team, mode.territories[1].owner_team, mode.territories[2].owner_team]
			_check(owners == [0, 1, 2], "citadels belong to their factions %s" % str(owners))
			var infested := mode.territories.slice(3).all(func(n: TerritoryNode) -> bool:
					return n.state == TerritoryNode.State.INFESTED)
			_check(infested, "every other place starts infested (%d)" % (mode.territories.size() - 3))
			_check(player.global_position.distance_to(mode.territories[0].position) < 6.0, "hero spawns at its citadel")
			for node in mode.territories:
				if node.kind == TerritoryNode.Kind.VILLAGE and (village == null or
						node.position.distance_to(player.global_position) < village.position.distance_to(player.global_position)):
					village = node
			_next()
		1:
			if pt < 0.3:
				return
			_check(village._guards.size() == TerritoryNode.INFO[TerritoryNode.Kind.VILLAGE].guards, "village guards spawned (%d)" % village._guards.size())
			for guard in village._guards:
				(guard as Unit).die()
			_next()
		2:
			if pt < 1.0:
				return
			_check(village.state == TerritoryNode.State.NEUTRAL, "guards dead → liberated")
			_put(village.position + Vector3(1.0, 0.0, 1.0))
			_next()
		3:
			_put(village.position + Vector3(1.0, 0.0, 1.0))
			if village.state != TerritoryNode.State.OWNED and pt < 15.0:
				return
			_check(village.owner_team == 0, "standing in it raises our banner (%.1fs)" % pt)
			archer = NetSpawn.unit(&"ally", village.position + Vector3(2.0, 0.0, 0.0),
					{"owner": player.peer_id, "team": 0, "weapon": "bow"}) as Ally
			# More mouths than the citadel + village food income (4 + 6) feeds.
			for i in 12:
				NetSpawn.unit(&"ally", mode.territories[0].position + Vector3(i % 4, 0.0, 3.0 + i / 4),
						{"owner": player.peer_id, "team": 0, "weapon": "sword"})
			_next()
		4:
			if pt < 0.3:
				return
			mode.logistics._timer = 1000.0  # only the test's own ticks from here on
			var stock := mode.logistics.stock_of(0)
			stock[&"food"] = 0
			score_before = mode.scores.get(0, 0)
			mode.logistics.tick()
			_check(archer.durability == LogisticsManager.FULL_DURABILITY and archer.ammo == LogisticsManager.QUIVER, "soldier joins the upkeep (durability %.0f, ammo %d)" % [archer.durability, archer.ammo])
			_check(stock[&"starving"] and archer.upkeep_speed < 1.0, "no food → starving, slower")
			_check(mode.scores.get(0, 0) > score_before, "held places score points (%d)" % mode.scores.get(0, 0))
			stock[&"food"] = 100
			stock[&"ammo"] = 40
			stock[&"equipment"] = 40
			archer.ammo = 0
			archer.durability = 0.0
			_check(not archer.shoots(), "empty quiver → no shooting")
			archer.global_position = mode.territories[1].position  # far from any of our supply points
			mode.logistics.tick()
			_check(archer.ammo == 0 and archer.upkeep_damage == LogisticsManager.BROKEN_DAMAGE, "out of supply range: no refill, weapon broken")
			_check(not stock[&"starving"] and archer.upkeep_speed == 1.0, "fed again → full speed")
			archer.global_position = village.position
			mode.logistics.tick()
			_check(archer.ammo == LogisticsManager.QUIVER and archer.durability == LogisticsManager.FULL_DURABILITY and archer.upkeep_damage == 1.0, "in supply range: quiver refilled, weapon repaired")
			# Phase 2: a held City raises the army cap, trains free recruits and rebuilds its gate.
			var city := mode.territories[3]
			city._captured_by(0)
			var cap_before := player.follower_cap
			var gate_before := city.gate.health
			mode.logistics.tick()
			var city_cap: int = TerritoryNode.INFO[TerritoryNode.Kind.CITY].cap
			_check(player.follower_cap == cap_before + city_cap, "a City raises the army cap (%d → %d)" % [cap_before, player.follower_cap])
			_check(city.gate.health > gate_before, "equipment rebuilds the City gate (%.0f → %.0f)" % [gate_before, city.gate.health])
			mode.logistics.tick()
			_check(player.follower_cap == cap_before + city_cap, "the cap bonus is given once")
			var training_before := player.soldiers_training
			mode.logistics.tick()
			while mode.logistics._ticks % LogisticsManager.RECRUIT_EVERY != 0:
				mode.logistics.tick()
			var recruits := 1 + 1 + 2  # citadel + village + city
			_check(player.soldiers_training == training_before + recruits, "held places train free recruits (%d)" % (player.soldiers_training - training_before))
			_next()
		5:
			# Phase 3: the army marches out beyond every supply point → a caravan is sent after it.
			if pt < 0.2:
				return
			field = mode.territories[2].position + Vector3(14.0, 0.0, 0.0)
			_put(field)
			for ally in player.followers():
				(ally as Ally).global_position = field + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
			_check(not mode.logistics.is_supplied(archer, 0), "the army is out of supply range")
			var stock := mode.logistics.stock_of(0)
			var food_before: int = stock[&"food"]
			mode.logistics.tick()
			var caravans := get_tree().get_nodes_in_group(&"caravans")
			_check(caravans.size() == 1, "a caravan is sent after the cut-off army (%d)" % caravans.size())
			if caravans.is_empty():
				_done()
				return
			var caravan := caravans[0] as CaravanUnit
			_check(caravan.owner_peer == player.peer_id and caravan.team_id == 0 and caravan.cargo_left() > 0, "it follows our hero with cargo %s" % str(caravan.cargo))
			_check(stock[&"food"] < food_before + 20, "its cargo came out of the stockpile")
			# By the army: soldiers eat, repair and refill from its cargo.
			caravan.global_position = field
			archer.global_position = field
			archer.durability = 0.0
			archer.ammo = 0
			var cargo_before: Dictionary = caravan.cargo.duplicate()
			mode.logistics.tick()
			_check(mode.logistics.is_supplied(archer, 0), "the caravan is a supply point")
			_check(archer.durability == LogisticsManager.FULL_DURABILITY and archer.ammo == LogisticsManager.QUIVER, "soldiers repaired and resupplied in the field")
			_check(caravan.cargo[&"equipment"] < cargo_before[&"equipment"] and caravan.cargo[&"ammo"] < cargo_before[&"ammo"] and caravan.cargo[&"food"] < cargo_before[&"food"], "from the caravan's cargo %s → %s" % [str(cargo_before), str(caravan.cargo)])
			_check(get_tree().get_nodes_in_group(&"caravans").size() == 1, "one caravan per hero")
			# Ambushed by a rival faction: its cargo is theirs.
			Net.players[2] = {"name": "Rival", "team": 1, "class": &"swordsman", "ready": false}
			var rival_food: int = mode.logistics.stock_of(1)[&"food"]
			var loot: int = caravan.cargo[&"food"]
			caravan.last_attacker_peer = 2
			caravan.die()
			_check(mode.logistics.stock_of(1)[&"food"] == mini(rival_food + loot, LogisticsManager.STOCK_CAP), "a rival faction loots the cargo (+%d food)" % loot)
			Net.players.erase(2)
			# Destroyed by monsters: the cargo is lost.
			mode.logistics.tick()
			var second := _live_caravan()
			_check(second != null, "another caravan is sent")
			if second:
				var stocks := [mode.logistics.stock_of(0)[&"food"], mode.logistics.stock_of(1)[&"food"]]
				second.last_attacker_peer = 0
				second.die()
				_check([mode.logistics.stock_of(0)[&"food"], mode.logistics.stock_of(1)[&"food"]] == stocks, "monsters destroy the cargo")
			# No hero to follow: it walks home and hands back what is left.
			mode.logistics.tick()
			homebound = _live_caravan()
			_check(homebound != null, "a third caravan is sent")
			if homebound:
				homebound_cargo = homebound.cargo[&"food"]
				home_food = mode.logistics.stock_of(0)[&"food"]
				homebound.owner_peer = 99
			_next()
		6:
			if is_instance_valid(homebound) and not homebound.is_dead and pt < 60.0:
				return
			_check(not is_instance_valid(homebound) or homebound.is_dead, "a caravan with nobody to follow goes home (%.1fs)" % pt)
			_check(mode.logistics.stock_of(0)[&"food"] == mini(home_food + homebound_cargo, LogisticsManager.STOCK_CAP), "and hands back its cargo (+%d food)" % homebound_cargo)
			_put(mode.territories[0].position)
			_next()
		7:
			# Phase 4: MARCH sends the army to a territory however far, along the navigation mesh, to patrol it.
			var city := mode.territories[3]
			if not marched:
				marched = true
				_check(mode.navigation_ready, "the navigation mesh is baked")
				var far := city.position.distance_to(player.followers()[0].global_position)
				_check(far > Player.MAX_ORDER_DISTANCE, "the army is far from the City (%.0f m)" % far)
				player.command_army(Player.Order.MARCH, city.position + Vector3(3.0, 0.0, 2.0))
				_check(player.army_order == Player.Order.MARCH and player.army_point.is_equal_approx(city.position), "MARCH targets the territory nearest the point")
				return
			var soldiers := player.followers()
			var there := soldiers.filter(func(a: Node) -> bool:
					return Ally._flat((a as Node3D).global_position - city.position).length() < Ally.MARCH_ARRIVE + 1.0)
			if there.size() < soldiers.size() * 0.8 and pt < 90.0:
				return
			_check(there.size() >= soldiers.size() * 0.8, "the army reaches the City (%d / %d in %.0fs)" % [there.size(), soldiers.size(), pt])
			var pathed := soldiers.any(func(a: Node) -> bool: return (a as Ally)._nav != null)
			_check(pathed, "soldiers walk by the navigation agent")
			patrol_from = (soldiers[0] as Node3D).global_position
			_next()
		8:
			if pt < 6.0:
				return
			var soldier := player.followers()[0] as Node3D
			_check(soldier.global_position.distance_to(patrol_from) > 0.5, "they patrol the ring (moved %.1f m)" % soldier.global_position.distance_to(patrol_from))
			_check(Ally._flat(soldier.global_position - mode.territories[3].position).length() < Ally.MARCH_ARRIVE + 1.0, "and stay at the City")
			player.command_army(Player.Order.FOLLOW, player.global_position)
			_next()
		9:
			_next()
		10:
			var citadel := mode.territories[1]
			var own_gate := mode.territories[0].gate
			own_gate.take_damage(500.0, player)
			_check(own_gate.health == own_gate.max_health, "our own gate ignores us")
			citadel.gate.take_damage(100.0, player)
			_check(is_equal_approx(citadel.gate.health, citadel.gate.max_health - 100.0 * TerritoryGate.HAND_SHARE), "a hero only chips the gate (%.0f)" % citadel.gate.health)
			_put(citadel.position)
			_next()
		11:
			_put(mode.territories[1].position)
			if pt < 3.0:
				return
			_check(mode.territories[1].progress == 0.0, "gate standing → no capture")
			for i in [1, 2]:
				var gate := mode.territories[i].gate
				gate.take_damage(gate.max_health / TerritoryGate.HAND_SHARE + 1.0, player)
			_check(mode.territories[1].gate.is_broken(), "gate broken")
			_next()
		12:
			var target := mode.territories[1] if mode.territories[1].owner_team != 0 else mode.territories[2]
			_put(target.position)
			if mode.is_over or pt > 60.0:
				_check(mode.territories[1].owner_team == 0 and mode.territories[2].owner_team == 0, "both enemy citadels taken")
				_check(mode.is_over, "every citadel under one banner wins")
				_done()

extends Node
## Conquest (solo, offline): three citadels owned by the three factions, everything else infested; killing a
## village's guards liberates it, standing in it raises our banner; the logistics tick pays income + points, feeds
## soldiers (starving slows them), wears / repairs weapons and refills quivers only within supply range; an enemy
## citadel's gate shrugs off our own side, takes HAND_SHARE from a hero, and once broken the citadel can be taken;
## holding every citadel wins.
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
			var citadel := mode.territories[1]
			var own_gate := mode.territories[0].gate
			own_gate.take_damage(500.0, player)
			_check(own_gate.health == own_gate.max_health, "our own gate ignores us")
			citadel.gate.take_damage(100.0, player)
			_check(is_equal_approx(citadel.gate.health, citadel.gate.max_health - 100.0 * TerritoryGate.HAND_SHARE), "a hero only chips the gate (%.0f)" % citadel.gate.health)
			_put(citadel.position)
			_next()
		6:
			_put(mode.territories[1].position)
			if pt < 3.0:
				return
			_check(mode.territories[1].progress == 0.0, "gate standing → no capture")
			for i in [1, 2]:
				var gate := mode.territories[i].gate
				gate.take_damage(gate.max_health / TerritoryGate.HAND_SHARE + 1.0, player)
			_check(mode.territories[1].gate.is_broken(), "gate broken")
			_next()
		7:
			var target := mode.territories[1] if mode.territories[1].owner_team != 0 else mode.territories[2]
			_put(target.position)
			if mode.is_over or pt > 60.0:
				_check(mode.territories[1].owner_team == 0 and mode.territories[2].owner_team == 0, "both enemy citadels taken")
				_check(mode.is_over, "every citadel under one banner wins")
				_done()

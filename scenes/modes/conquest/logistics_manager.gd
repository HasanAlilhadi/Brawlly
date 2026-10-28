class_name LogisticsManager
extends Node
## Conquest: every faction's stockpile (food, equipment, ammo) and the army upkeep, one tick every TICK seconds.
## Server: owned territories pay their income in (`TerritoryNode.income`), every soldier eats, worn weapons are
## repaired and quivers refilled for soldiers inside a supply point's range (group `conquest_supply`: owned
## territories draw on the stockpile, CaravanUnits on their own cargo; `_dispatch` sends a caravan to a hero
## whose soldiers are cut off), then the effects are set on the soldiers (Ally.upkeep_speed / upkeep_damage /
## durability / ammo — they stay neutral in every other mode). Held places also raise every hero's army cap
## (`TerritoryNode.INFO.cap`, at most CAP_BONUS_MAX), train free recruits for the faction's heroes and spend
## equipment rebuilding their gates. Every peer gets the stockpiles via `_net_stock`.

signal stock_changed

const TICK: float = 5.0
const KEYS: Array[StringName] = [&"food", &"equipment", &"ammo"]
## What a faction starts with, and the most it can store of each.
const START_STOCK: int = 40
const STOCK_CAP: int = 600
## Food per soldier per tick. Short of it, the whole army starves: slower, and it loses STARVE_DRAIN of its
## health a tick (never below STARVE_FLOOR).
const FOOD_PER_SOLDIER: int = 1
const STARVE_SPEED: float = 0.75
const STARVE_DRAIN: float = 0.08
const STARVE_FLOOR: float = 0.3
## Weapon durability 0..100; one equipment repairs this much. Broken (0): damage × BROKEN_DAMAGE.
const FULL_DURABILITY: float = 100.0
const REPAIR_PER_EQUIPMENT: float = 20.0
const BROKEN_DAMAGE: float = 0.3
## Arrows an archer carries; one ammo refills this many.
const QUIVER: int = 30
const ARROWS_PER_AMMO: int = 5
## Army cap the held places add to each hero, at most (a host simulating many more soldiers gets slow).
const CAP_BONUS_MAX: int = 20
## Held places hand out their recruits every this many ticks (one at a time, to the hero with the smallest army).
const RECRUIT_EVERY: int = 6
## Gate rebuilding while nobody else stands in the ring: health per equipment, equipment per gate per tick.
const GATE_REPAIR_PER_EQUIPMENT: float = 50.0
const GATE_REPAIR_PARTS: int = 4
## A caravan goes out when at least this many of a hero's soldiers are beyond every supply point, and only with
## at least this much cargo in all.
const DISPATCH_MIN: int = 3
const DISPATCH_MIN_CARGO: int = 10

var mode: ConquestMode
## team -> {food, equipment, ammo, starving: bool, soldiers: int, food_need: int, income: Dictionary,
## cap_bonus: int, recruits: int (waiting for a hero with room)}
var stock: Dictionary = {}

var _timer: float = TICK
var _ticks: int = 0
## peer -> army cap bonus already added to that hero's follower_cap.
var _cap_given: Dictionary = {}


func _ready() -> void:
	name = "Logistics"
	add_to_group(&"logistics")
	for team in ConquestMode.FACTIONS:
		stock[team] = {&"food": START_STOCK, &"equipment": START_STOCK, &"ammo": START_STOCK,
				&"starving": false, &"soldiers": 0, &"food_need": 0, &"income": {}, &"cap_bonus": 0, &"recruits": 0}


func stock_of(team: int) -> Dictionary:
	return stock.get(team, {})


## Seconds until the next tick (HUD countdown).
func time_to_tick() -> float:
	return _timer


func _process(delta: float) -> void:
	if not multiplayer.is_server() or mode == null or mode.is_over:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = TICK
	tick()


## Server: one upkeep round for every faction (tests call it directly).
func tick() -> void:
	_ticks += 1
	var territories := mode.territories
	for team in ConquestMode.FACTIONS:
		var entry: Dictionary = stock[team]
		var income := {&"food": 0, &"equipment": 0, &"ammo": 0}
		var points := 0
		var cap := 0
		var recruits := 0
		var held: Array[TerritoryNode] = []
		for territory in territories:
			if territory.state == TerritoryNode.State.OWNED and territory.owner_team == team:
				var info := territory.info()
				for key in KEYS:
					income[key] += int(info[key])
				points += int(info.points)
				cap += int(info.cap)
				recruits += int(info.recruits)
				held.append(territory)
		for key in KEYS:
			entry[key] = mini(int(entry[key]) + int(income[key]), STOCK_CAP)
		entry[&"income"] = income
		_upkeep(team, entry)
		_dispatch(team, entry)
		_repair_gates(held, entry)
		entry[&"cap_bonus"] = mini(cap, CAP_BONUS_MAX)
		_give_cap(team, entry[&"cap_bonus"])
		if _ticks % RECRUIT_EVERY == 0:
			entry[&"recruits"] = int(entry[&"recruits"]) + recruits
		entry[&"recruits"] = _hand_out_recruits(team, int(entry[&"recruits"]))
		if points > 0:
			mode.add_score(team, points)
	_net_stock.rpc(stock)


func _heroes(team: int) -> Array[Player]:
	var result: Array[Player] = []
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if is_instance_valid(player) and player.team_id == team:
			result.append(player)
	return result


## Every hero of the faction gets the held places' army cap (follower_cap is replicated; only the change is added,
## so Command levels stay theirs).
func _give_cap(team: int, bonus: int) -> void:
	for player in _heroes(team):
		var given: int = _cap_given.get(player.peer_id, 0)
		if given != bonus:
			player.follower_cap += bonus - given
			_cap_given[player.peer_id] = bonus


## Free recruits from the held places, one at a time to the living hero with the smallest army and room for one;
## the rest wait. Returns how many still wait.
func _hand_out_recruits(team: int, waiting: int) -> int:
	while waiting > 0:
		var best: Player = null
		for player in _heroes(team):
			if player.is_dead or player.army_size() >= player.follower_cap:
				continue
			if best == null or player.army_size() < best.army_size():
				best = player
		if best == null:
			break
		best.soldiers_training += 1  # trains like a bought recruit, then joins (Player._finish_training)
		waiting -= 1
	return waiting


## Equipment rebuilds the gates of held places nobody else stands in.
func _repair_gates(held: Array[TerritoryNode], entry: Dictionary) -> void:
	for territory in held:
		var gate := territory.gate
		if gate == null or gate.health >= gate.max_health or territory.contested():
			continue
		var parts := mini(ceili((gate.max_health - gate.health) / GATE_REPAIR_PER_EQUIPMENT),
				mini(GATE_REPAIR_PARTS, int(entry[&"equipment"])))
		if parts <= 0:
			return
		gate.repair(parts * GATE_REPAIR_PER_EQUIPMENT)
		entry[&"equipment"] = int(entry[&"equipment"]) - parts


## Feed, repair and resupply one faction's soldiers, then set what they suffer from what's missing.
func _upkeep(team: int, entry: Dictionary) -> void:
	var soldiers: Array[Ally] = []
	for node in get_tree().get_nodes_in_group(&"allies"):
		var ally := node as Ally
		if ally and not GameConfig.is_gone(ally) and ally.team_id == team:
			soldiers.append(ally)
	entry[&"soldiers"] = soldiers.size()
	# Soldiers by a caravan with food eat from its cargo; everyone else from the stockpile.
	var food_need := 0
	for ally in soldiers:
		var caravan := _caravan_near(ally, team)
		if caravan and int(caravan.cargo.get(&"food", 0)) >= FOOD_PER_SOLDIER:
			caravan.cargo[&"food"] = int(caravan.cargo[&"food"]) - FOOD_PER_SOLDIER
		else:
			food_need += FOOD_PER_SOLDIER
	entry[&"food_need"] = food_need
	var starving := int(entry[&"food"]) < food_need
	entry[&"food"] = maxi(int(entry[&"food"]) - food_need, 0)
	entry[&"starving"] = starving and food_need > 0
	for ally in soldiers:
		if ally.durability < 0.0:
			ally.durability = FULL_DURABILITY  # joins the upkeep: from now on the weapon wears
		if ally.is_archer() and ally.ammo < 0:
			ally.ammo = QUIVER
		var source := supply_source(ally, team)
		if source:
			# An owned territory draws on the stockpile, a caravan on its own cargo.
			var supplies: Dictionary = (source as CaravanUnit).cargo if source is CaravanUnit else entry
			_repair(ally, supplies)
			_refill(ally, supplies)
		ally.upkeep_speed = STARVE_SPEED if starving else 1.0
		ally.upkeep_damage = BROKEN_DAMAGE if ally.durability <= 0.0 else 1.0
		if starving and ally.health > ally.max_health * STARVE_FLOOR:
			# Straight off the health (not a hit: no knockback, no stats; the hurt flash shows the hunger).
			ally.health = maxf(ally.health - ceilf(ally.max_health * STARVE_DRAIN), ally.max_health * STARVE_FLOOR)


func _repair(ally: Ally, entry: Dictionary) -> void:
	var missing := FULL_DURABILITY - ally.durability
	var parts := mini(ceili(missing / REPAIR_PER_EQUIPMENT), int(entry.get(&"equipment", 0)))
	if parts <= 0:
		return
	entry[&"equipment"] = int(entry[&"equipment"]) - parts
	ally.durability = minf(ally.durability + parts * REPAIR_PER_EQUIPMENT, FULL_DURABILITY)


func _refill(ally: Ally, entry: Dictionary) -> void:
	if not ally.is_archer():
		return
	var bundles := mini(ceili(float(QUIVER - ally.ammo) / ARROWS_PER_AMMO), int(entry.get(&"ammo", 0)))
	if bundles <= 0:
		return
	entry[&"ammo"] = int(entry[&"ammo"]) - bundles
	ally.ammo = mini(ally.ammo + bundles * ARROWS_PER_AMMO, QUIVER)


## Within range of one of its faction's supply points (an owned territory or a caravan).
func is_supplied(unit: Node3D, team: int) -> bool:
	return supply_source(unit, team) != null


## The supply point `unit` draws on: an owned territory in range first (the stockpile), else a caravan with
## cargo left, else null.
func supply_source(unit: Node3D, team: int) -> Node3D:
	var caravan: Node3D = null
	for node in get_tree().get_nodes_in_group(&"conquest_supply"):
		var point := node as Node3D
		if point == null or int(point.get("team_id")) != team:
			continue
		var reach: float = point.call("supply_range")
		var offset := point.global_position - unit.global_position
		offset.y = 0.0
		if reach <= 0.0 or offset.length() > reach:
			continue
		if not point is CaravanUnit:
			return point
		if caravan == null and (point as CaravanUnit).cargo_left() > 0:
			caravan = point
	return caravan


func _caravan_near(unit: Node3D, team: int) -> CaravanUnit:
	var source := supply_source(unit, team)
	return source as CaravanUnit


## Server: supplies come back to a faction's stockpile (a caravan home again, or loot from a rival's).
func store(team: int, supplies: Dictionary) -> void:
	if not stock.has(team):
		return
	for key in KEYS:
		stock[team][key] = mini(int(stock[team][key]) + int(supplies.get(key, 0)), STOCK_CAP)


## A hero whose soldiers march beyond every supply point (DISPATCH_MIN of them) and has no caravan yet gets one
## from the nearest held territory, loaded from the stockpile (CaravanUnit.CARGO at most of each).
func _dispatch(team: int, entry: Dictionary) -> void:
	for player in _heroes(team):
		if player.is_dead or _caravan_of(player) != null:
			continue
		var cut_off := 0
		for ally in player.followers():
			if not is_supplied(ally, team):
				cut_off += 1
		if cut_off < DISPATCH_MIN:
			continue
		var from := _nearest_held(team, player.global_position)
		if from == null:
			continue
		var cargo := {}
		var total := 0
		for key in KEYS:
			cargo[key] = mini(int(CaravanUnit.CARGO[key]), int(entry[key]))
			total += int(cargo[key])
		if total < DISPATCH_MIN_CARGO:
			continue
		for key in KEYS:
			entry[key] = int(entry[key]) - int(cargo[key])
		var at := GameConfig.clamp_to_world(from.global_position + Vector3(0.0, 0.0, from.radius() * 0.5))
		NetSpawn.unit(&"caravan", at, {"team": team, "owner": player.peer_id, "cargo": cargo})


func _caravan_of(player: Player) -> CaravanUnit:
	for node in get_tree().get_nodes_in_group(&"caravans"):
		var caravan := node as CaravanUnit
		if caravan.owner_peer == player.peer_id and not caravan.is_dead:
			return caravan
	return null


func _nearest_held(team: int, near: Vector3) -> TerritoryNode:
	var best: TerritoryNode = null
	for territory in mode.territories:
		if territory.state == TerritoryNode.State.OWNED and territory.owner_team == team and (best == null or
				territory.global_position.distance_to(near) < best.global_position.distance_to(near)):
			best = territory
	return best


@rpc("authority", "call_local", "reliable")
func _net_stock(new_stock: Dictionary) -> void:
	stock = new_stock
	stock_changed.emit()

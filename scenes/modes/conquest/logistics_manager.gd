class_name LogisticsManager
extends Node
## Conquest supplies, one tick every TICK seconds (server; every peer gets the totals via `_net_stock`).
## - Production: every held place adds its `output()` (food / weapons / gold, by kind and City specialty) to its
##   OWN store (`TerritoryNode.store`, capped). There is no shared stockpile: goods are where they were made.
## - Upkeep: soldiers carry rations (`Ally.rations`, at most MAX_RATIONS). Every MEAL_TICKS ticks (200 s) each one
##   eats a ration; a soldier with none left dies of hunger (10 soldiers, 8 rations among them: 2 die). Weapons
##   (bows and staffs too: there are no arrows) wear by battle (`Ally.weapon_uses`: weaker every 2, broken after
##   8); a soldier gets a new one for one weapons supply once it is worn (REARM_AT). Rations and new weapons come
##   only from the supply point a soldier stands near (group `conquest_supply`, `supply_source()`): a held place's
##   store, or a caravan's cargo — one ration per soldier per tick. Out of rations it marches slower
##   (STARVE_SPEED) as a warning.
## - Barracks (every place): people come in unarmed (`TerritoryNode.people`, INFO pool × ZONE_PEOPLE every
##   POOL_EVERY ticks, up to its pool_cap). With a class picked (`train_kind`) ARM_PER_TICK of them a tick get its
##   weapon (MUSTER_EQUIPMENT from the store each); only armed soldiers train (`drill`, per class).
## - Leaving a barracks costs its place MUSTER_FOOD food per soldier (its first ration), and an unarmed one also
##   MUSTER_EQUIPMENT weapons; armed ones go first, with the rank their drill earned (`_available`, `_send_soldiers`).
## - Convoys: a hero with DISPATCH_MIN soldiers beyond every supply point gets a caravan (CaravanUnit), loaded at
##   the held place within CONVOY_RANGE that has the most of what the army lacks (food first); rivals can loot it.
## - The faction's General musters from the nearest barracks (`muster()`, the Army tab); a place's commander takes
##   soldiers of one class from it on the map (`muster_from`). They walk from their barracks to that hero.
## - Held places raise every hero's army cap (`INFO.cap`, at most CAP_BONUS_MAX), score points, and rebuild their
##   gates from their own weapons store while nobody else stands in them.

signal stock_changed

const TICK: float = 5.0
const KEYS: Array[StringName] = [&"food", &"equipment"]
## Shown names of the supplies (keys stay food / equipment).
const KEY_NAMES: Dictionary = {&"food": "Food", &"equipment": "Weapons"}
## What a Citadel holds at the start (the rest start empty).
const START_STORE: int = 60
## Meals: every MEAL_TICKS ticks (200 s) a soldier eats one ration; it carries at most MAX_RATIONS (one food
## each), a recruit starts with START_RATIONS. Out of rations: STARVE_SPEED until fed (dead at the next meal).
const MEAL_TICKS: int = 40
const MAX_RATIONS: int = 2
const START_RATIONS: int = 1
const STARVE_SPEED: float = 0.75
## What one soldier leaving a barracks takes from its place's store.
const MUSTER_FOOD: int = 1
const MUSTER_EQUIPMENT: int = 1
## A soldier near a supply point swaps its weapon for a new one (one weapons supply) once it has this many
## battles behind it (Ally.WEAR_STEP: the first loss of damage).
const REARM_AT: int = Ally.WEAR_STEP
## Army cap the held places add to each hero, at most: base 30 + Command 20 + this = 80 (each soldier costs the
## host ~0.15 ms a frame, measured headless).
const CAP_BONUS_MAX: int = 100
## Barracks grow every this many ticks (10 s).
const POOL_EVERY: int = 2
## A muster brings at most this many soldiers at once; the map takes MAP_TAKE of one class.
const MUSTER_BATCH: int = 10
const MAP_TAKE: int = 4
## People a barracks arms with its class each tick (weapons allowing).
const ARM_PER_TICK: int = 2
## Gate rebuilding while nobody else stands in the ring: health per weapons supply, supplies per gate per tick.
const GATE_REPAIR_PER_EQUIPMENT: float = 50.0
const GATE_REPAIR_PARTS: int = 4
## A caravan goes out when at least this many of a hero's soldiers are beyond every supply point, from a held place
## within CONVOY_RANGE of the hero, and only with at least DISPATCH_MIN_CARGO in all.
const DISPATCH_MIN: int = 3
const DISPATCH_MIN_CARGO: int = 10
const CONVOY_RANGE: float = 220.0
## Coins for one more courier at a place (the map, up to TerritoryNode.COURIER_MAX).
const COURIER_COST: int = 40

var mode: ConquestMode
## team -> {food, equipment (totals over its places and caravans), income: {per key}, food_need, worn,
## starving: soldiers going hungry, soldiers, cap_bonus, barracks: total waiting, general: peer id}
var stock: Dictionary = {}

## Where each faction's goods came from and went over the last FLOW_TICKS ticks (a minute): `note(team, key, reason,
## amount)` (+ made or brought in, - spent or lost; moves between its own places and caravans are not noted).
## Keys: KEYS + &"gold" (treasuries) + &"people" (barracks). Every tick sums them into the stock entry's "flow"
## ({key: {"in": {reason: n}, "out": {reason: n}}}, per minute) for the HUD's supplies panel (ConquestPanel).
const FLOW_TICKS: int = 12
const FLOW_KEYS: Array[StringName] = [&"food", &"equipment", &"gold", &"people"]
var _flow: Dictionary = {}  # team -> Array of {key: {reason: signed amount}}, oldest first

var _timer: float = TICK
var _ticks: int = 0
## peer -> army cap bonus already added to that hero's follower_cap.
var _cap_given: Dictionary = {}


func _ready() -> void:
	name = "Logistics"
	add_to_group(&"logistics")
	for team in ConquestMode.FACTIONS:
		stock[team] = _empty_entry()
		_flow[team] = [{}]
	for territory in mode.territories:
		if territory.kind == TerritoryNode.Kind.CITADEL:
			for key in KEYS:
				territory.store[key] = START_STORE
			territory.people = TerritoryNode.START_PEOPLE
	for team in ConquestMode.FACTIONS:
		_total(team, stock[team])  # the host's HUD shows the starting stores at once (other peers: first tick)


func _empty_entry() -> Dictionary:
	return {&"food": 0, &"equipment": 0, &"income": {}, &"food_need": 0, &"starving": 0, &"meal_in": 0, &"worn": 0,
			&"soldiers": 0, &"cap_bonus": 0, &"barracks": 0, &"general": 0, &"flow": {}}


## Server: `amount` of `key` came in (+) or went out (-) for `team`, for `reason` (see FLOW_TICKS).
func note(team: int, key: StringName, reason: String, amount: int) -> void:
	if amount == 0 or not _flow.has(team):
		return
	var record: Dictionary = _flow[team].back()
	if not record.has(key):
		record[key] = {}
	record[key][reason] = int(record[key].get(reason, 0)) + amount


## The last minute of `team`'s notes, per minute: {key: {"in": {reason: n}, "out": {reason: n}}} (out as positive).
func _flow_sum(team: int) -> Dictionary:
	var records: Array = _flow.get(team, [])
	var scale := 60.0 / (maxf(records.size(), 1.0) * TICK)
	var sums := {}
	for record: Dictionary in records:
		for key in record:
			for reason in record[key]:
				var amount: int = record[key][reason]
				var side := "in" if amount > 0 else "out"
				if not sums.has(key):
					sums[key] = {"in": {}, "out": {}}
				sums[key][side][reason] = float(sums[key][side].get(reason, 0.0)) + absf(amount)
	for key in sums:
		for side in sums[key]:
			for reason in sums[key][side]:
				sums[key][side][reason] = roundi(sums[key][side][reason] * scale)
	return sums


## The source a place's goods are noted under ("Farm Cities", "Villages", …).
static func source_name(territory: TerritoryNode) -> String:
	var kind := territory.kind_name()
	if territory.kind == TerritoryNode.Kind.CITADEL or territory.kind == TerritoryNode.Kind.THRONE:
		return kind
	return kind.trim_suffix("City") + "Cities" if kind.ends_with("City") else kind + "s"


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


## Server: one round for every faction (tests call it directly).
func tick() -> void:
	_ticks += 1
	for team in ConquestMode.FACTIONS:
		var records: Array = _flow[team]
		records.append({})
		while records.size() > FLOW_TICKS:
			records.pop_front()
	for team in ConquestMode.FACTIONS:
		var entry: Dictionary = stock[team]
		var income := {&"food": 0, &"equipment": 0}
		var points := 0
		var cap := 0
		for territory in held(team):
			var made := territory.output()
			var source := source_name(territory)
			for key in KEYS:
				var before := int(territory.store[key])
				territory.store[key] = mini(before + int(made[key]), territory.store_cap())
				income[key] += int(made[key])
				note(team, key, source, int(territory.store[key]) - before)  # a full store wastes the rest
			_train(territory)
			var had := territory.treasury
			territory.treasury = mini(territory.treasury + int(made[&"gold"]), TerritoryNode.TREASURY_CAP)
			note(team, &"gold", source, territory.treasury - had)
			income[&"gold"] = int(income.get(&"gold", 0)) + int(made[&"gold"])
			points += int(territory.info().points)
			cap += int(territory.info().cap)
		entry[&"income"] = income
		_upkeep(team, entry)
		_run_routes(team)
		_dispatch(team)
		_repair_gates(team)
		entry[&"cap_bonus"] = mini(cap, CAP_BONUS_MAX)
		_give_cap(team, entry[&"cap_bonus"])
		entry[&"general"] = general_of(team)
		_total(team, entry)
		entry[&"flow"] = _flow_sum(team)
		if points > 0:
			mode.add_score(team, points)
	_net_stock.rpc(stock, _places())
	mode.on_logistics_tick()


## One place's barracks for a tick: armed soldiers train, people of its class get their weapons, more people come.
func _train(territory: TerritoryNode) -> void:
	for k in TerritoryNode.SOLDIER_KINDS.size():
		if territory.armed[k] > 0:
			territory.drill[k] += TICK
	var k := territory.train_kind
	if k >= 0 and k < TerritoryNode.SOLDIER_KINDS.size():
		var count := mini(mini(territory.arm_per_tick(), territory.people), int(territory.store[&"equipment"]) / MUSTER_EQUIPMENT)
		if count > 0:
			territory.people -= count
			territory.store[&"equipment"] = int(territory.store[&"equipment"]) - count * MUSTER_EQUIPMENT
			note(territory.owner_team, &"equipment", "Arming people in barracks", -count * MUSTER_EQUIPMENT)
			territory.drill[k] *= float(territory.armed[k]) / (territory.armed[k] + count)  # untrained newcomers
			territory.armed[k] += count
	if territory.has_barracks() and _ticks % POOL_EVERY == 0:
		territory.growth += float(territory.info().pool) * TerritoryNode.ZONE_PEOPLE[territory.zone] * territory.growth_boost()
		var whole := int(territory.growth)
		territory.growth -= whole
		var came := clampi(whole, 0, maxi(territory.barracks_cap() - territory.barracks, 0))
		territory.people += came
		note(territory.owner_team, &"people", source_name(territory), came)
	for i in TerritoryNode.SOLDIER_KINDS.size():
		territory.ranks[i] = Ally.rank_for_drill(territory.drill[i]) if territory.armed[i] > 0 else 0


## Per place, in plan order: people, armed and rank per class, its class, treasury, couriers at home / in all,
## route, then its store (KEYS order), then its upgrade levels — PLACE_FIELDS ints each.
const PLACE_BARRACKS: int = 1 + 4 + 4 + 1
const PLACE_UPGRADES: int = PLACE_BARRACKS + 4 + 2
const PLACE_FIELDS: int = PLACE_UPGRADES + 4


func _places() -> PackedInt32Array:
	var places := PackedInt32Array()
	for territory in mode.territories:
		places.append(territory.people)
		places.append_array(PackedInt32Array(territory.armed))
		places.append_array(PackedInt32Array(territory.ranks))
		places.append(territory.train_kind)
		places.append(territory.treasury)
		places.append(territory.couriers)
		places.append(territory.courier_total)
		places.append(territory.route)
		for key in KEYS:
			places.append(int(territory.store[key]))
		places.append_array(PackedInt32Array(territory.upgrades))
	return places


## Server: every peer gets the places' numbers now (a treasury emptied, goods moved).
func send_places() -> void:
	_net_stock.rpc(stock, _places())


## The places a faction holds.
func held(team: int) -> Array[TerritoryNode]:
	var result: Array[TerritoryNode] = []
	for territory in mode.territories:
		if territory.state == TerritoryNode.State.OWNED and territory.owner_team == team:
			result.append(territory)
	return result


## Totals for the HUD: every store of its places plus its caravans' cargo, and the soldiers waiting in barracks.
func _total(team: int, entry: Dictionary) -> void:
	for key in KEYS:
		entry[key] = 0
	entry[&"barracks"] = 0
	entry[&"gold"] = 0
	for territory in held(team):
		for key in KEYS:
			entry[key] += int(territory.store[key])
		entry[&"barracks"] += territory.barracks
		entry[&"gold"] += territory.treasury
	for node in get_tree().get_nodes_in_group(&"caravans"):
		var caravan := node as CaravanUnit
		if caravan.team_id == team and not caravan.is_dead:
			for key in KEYS:
				entry[key] += int(caravan.cargo.get(key, 0))


func _heroes(team: int) -> Array[Player]:
	var result: Array[Player] = []
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if is_instance_valid(player) and player.team_id == team:
			result.append(player)
	return result


## The faction's General: its hero who joined first (lowest peer id; the host leads their own faction). 0 = none.
func general_of(team: int) -> int:
	var best := 0
	for player in _heroes(team):
		if best == 0 or player.peer_id < best:
			best = player.peer_id
	return best


## Every hero of the faction gets the held places' army cap (follower_cap is replicated; only the change is added,
## so Command levels stay theirs).
func _give_cap(team: int, bonus: int) -> void:
	for player in _heroes(team):
		var given: int = _cap_given.get(player.peer_id, 0)
		if given != bonus:
			player.follower_cap += bonus - given
			_cap_given[player.peer_id] = bonus


## Soldiers the General could muster now: what waits in the barracks, as far as their army has room.
func can_muster(player: Player) -> int:
	if player == null or player.is_dead or general_of(player.team_id) != player.peer_id:
		return 0
	var waiting := 0
	for territory in held(player.team_id):
		waiting += _available(territory)
	return mini(mini(waiting, MUSTER_BATCH), player.follower_cap - player.army_size())


## Server (the map): up to `size` soldiers of class `kind` (TerritoryNode.SOLDIER_KINDS index) from this one place's
## barracks (its lord or the General; ConquestMode.place_action checks): its armed ones of that class first, then
## people armed on the spot. They leave as a squad of `player`'s holding the place (ConquestSquads; the best
## ranked leads); `kind` -1 = any class, walking to `player` instead. Returns how many leave.
func muster_from(player: Player, territory: TerritoryNode, kind: int = -1, size: int = MAP_TAKE) -> int:
	if player == null or player.is_dead or kind >= TerritoryNode.SOLDIER_KINDS.size():
		return 0
	var count := mini(mini(_available(territory, kind), size), player.follower_cap - player.army_size())
	if count <= 0:
		return 0
	var squad := mode.squads.create(player, kind, territory) if kind >= 0 and mode.squads else 0
	_send_soldiers(player, territory, count, kind, squad)
	var what := TerritoryNode.SOLDIER_NAMES[kind].to_lower() if kind >= 0 else "soldiers"
	mode.announce("%s takes %s of %d %s from %s." % [player.display_name, "a squad" if squad else "a group", count,
			what, territory.display_name])
	if squad:
		mode.squads._send()
	return count


## How many soldiers (of class `kind`; -1 = any) `territory` can send out now: each takes a first ration, an
## unarmed one a weapon too.
func _available(territory: TerritoryNode, kind: int = -1) -> int:
	var food := int(territory.store[&"food"]) / MUSTER_FOOD
	var ready_ones := territory.barracks - territory.people if kind < 0 else territory.armed[kind]
	var from_armed := mini(ready_ones, food)
	var from_people := mini(mini(territory.people, int(territory.store[&"equipment"]) / MUSTER_EQUIPMENT),
			food - from_armed)
	return from_armed + maxi(from_people, 0)


## `count` soldiers (at most `_available`) leave `territory`'s barracks for `player`: armed ones of class `kind`
## first (any class when -1, the biggest first) with their drill's rank, then people armed now (rank 0, a weapon
## each: of `kind`, or the place's muster_kind). Each takes a ration from the store.
func _send_soldiers(player: Player, territory: TerritoryNode, count: int, kind: int = -1, squad: int = 0) -> void:
	var leaving: Array = []  # [weapon, rank]
	var kinds: Array = [kind]
	if kind < 0:
		kinds = range(TerritoryNode.SOLDIER_KINDS.size())
		kinds.sort_custom(func(a: int, b: int) -> bool: return territory.armed[a] > territory.armed[b])
	for k: int in kinds:
		var taken := mini(territory.armed[k], count - leaving.size())
		for i in taken:
			leaving.append([TerritoryNode.SOLDIER_KINDS[k], Ally.rank_for_drill(territory.drill[k])])
		territory.armed[k] -= taken
		if territory.armed[k] == 0:
			territory.drill[k] = 0.0
			territory.ranks[k] = 0
	var raw := mini(mini(count - leaving.size(), territory.people), int(territory.store[&"equipment"]) / MUSTER_EQUIPMENT)
	territory.people -= raw
	territory.store[&"equipment"] = int(territory.store[&"equipment"]) - raw * MUSTER_EQUIPMENT
	note(territory.owner_team, &"equipment", "Arming soldiers who leave", -raw * MUSTER_EQUIPMENT)
	for i in raw:
		leaving.append([TerritoryNode.SOLDIER_KINDS[kind] if kind >= 0 else muster_kind(territory, i), 0])
	territory.store[&"food"] = int(territory.store[&"food"]) - leaving.size() * MUSTER_FOOD
	note(territory.owner_team, &"food", "Rations for soldiers who leave", -leaving.size() * MUSTER_FOOD)
	note(territory.owner_team, &"people", "Left as soldiers", -leaving.size())
	leaving.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))  # the best ranked leads
	for i in leaving.size():
		var angle := TAU * i / maxf(leaving.size(), 1.0)
		var at := territory.global_position + Vector3(cos(angle), 0.0, sin(angle)) * 2.0
		NetSpawn.unit(&"ally", GameConfig.clamp_to_world(at), {"team": player.team_id, "owner": player.peer_id,
				"weapon": leaving[i][0], "muster": squad == 0, "rank": leaving[i][1], "rations": MUSTER_FOOD,
				"squad": squad, "squad_leader": squad != 0 and i == 0})


## Server: the General calls up to MUSTER_BATCH soldiers from the barracks nearest to them. Each one leaves its
## barracks at once and walks to the General (Ally "muster"): armed ones with the rank their training earned
## (`drill`), then unarmed people armed by the place (`muster_kind`: Iron Cities swordsmen, Lumber Cities archers,
## Farms healers, the rest a mix of all four). Returns how many come.
func muster(player: Player) -> int:
	var count := can_muster(player)
	if count <= 0:
		return 0
	var sources := held(player.team_id).filter(func(t: TerritoryNode) -> bool: return _available(t) > 0)
	sources.sort_custom(func(a: TerritoryNode, b: TerritoryNode) -> bool:
		return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
	var left := count
	for territory: TerritoryNode in sources:
		var taken := mini(_available(territory), left)
		left -= taken
		_send_soldiers(player, territory, taken)
		if left <= 0:
			break
	mode.announce("General %s musters %d soldiers." % [player.display_name, count])
	return count


## The kind of soldier a barracks sends (the `index`-th of a muster).
static func muster_kind(territory: TerritoryNode, index: int) -> String:
	match territory.specialty:
		TerritoryNode.Specialty.IRON:
			return "sword"
		TerritoryNode.Specialty.LUMBER:
			return "bow"
		TerritoryNode.Specialty.FARM:
			return "healer"
	return ["sword", "sword", "bow", "wizard", "healer"][index % 5]


## Each held place rebuilds its gate from its own weapons store while nobody else stands in it.
func _repair_gates(team: int) -> void:
	for territory in held(team):
		var gate := territory.gate
		if gate == null or gate.health >= gate.max_health or territory.contested() or not gate.is_calm():
			continue
		var parts := mini(ceili((gate.max_health - gate.health) / GATE_REPAIR_PER_EQUIPMENT),
				mini(GATE_REPAIR_PARTS, int(territory.store[&"equipment"])))
		if parts <= 0:
			continue
		gate.repair(parts * GATE_REPAIR_PER_EQUIPMENT)
		territory.store[&"equipment"] = int(territory.store[&"equipment"]) - parts
		note(team, &"equipment", "Gate repairs", -parts)


## Resupply one faction's soldiers from the supply point each stands near (a ration, a new weapon); at meal
## time each eats a ration and those with none die of hunger.
func _upkeep(team: int, entry: Dictionary) -> void:
	var meal := _ticks % MEAL_TICKS == 0
	var starving := 0
	var soldiers := 0
	var starved := 0
	var worn := 0
	var fed := 0
	var rearmed := 0
	for node in get_tree().get_nodes_in_group(&"allies"):
		var ally := node as Ally
		if ally == null or GameConfig.is_gone(ally) or ally.team_id != team:
			continue
		soldiers += 1
		if ally.weapon_uses < 0:
			ally.weapon_uses = 0  # joins the upkeep: from now on its battles wear the weapon
		if ally.rations < 0:
			ally.rations = START_RATIONS
		var supplies := _supplies_at(ally, team)
		if ally.rations < MAX_RATIONS and int(supplies.get(&"food", 0)) > 0:
			supplies[&"food"] = int(supplies[&"food"]) - 1  # one ration a tick: a short store feeds the first ones
			ally.rations += 1
			fed += 1
		if not supplies.is_empty() and _rearm(ally, supplies):
			rearmed += 1
		if meal:
			if ally.rations > 0:
				ally.rations -= 1
			else:
				starved += 1
				ally.die()
				continue
		ally.upkeep_speed = 1.0 if ally.rations > 0 else STARVE_SPEED
		if ally.rations <= 0:
			starving += 1
		if ally.weapon_uses >= REARM_AT:
			worn += 1
	note(team, &"food", "Rations for soldiers", -fed)
	note(team, &"equipment", "New weapons for worn ones", -rearmed)
	if starved > 0:
		mode.announce("{team:%d} lost %d soldiers to hunger!" % [team, starved])
	entry[&"soldiers"] = soldiers
	entry[&"food_need"] = soldiers - starved
	entry[&"starving"] = starving
	entry[&"worn"] = worn
	entry[&"meal_in"] = (MEAL_TICKS - _ticks % MEAL_TICKS) * int(TICK)


## The store or cargo `unit` draws on ({} when it is beyond every supply point).
func _supplies_at(unit: Node3D, team: int) -> Dictionary:
	var source := supply_source(unit, team)
	if source is CaravanUnit:
		return (source as CaravanUnit).cargo
	if source is TerritoryNode:
		return (source as TerritoryNode).store
	return {}


## A worn weapon (REARM_AT battles or more) is swapped for a new one from the supplies, outside a battle.
func _rearm(ally: Ally, supplies: Dictionary) -> bool:
	if ally.weapon_uses < REARM_AT or ally._battle > 0.0 or int(supplies.get(&"equipment", 0)) <= 0:
		return false
	supplies[&"equipment"] = int(supplies[&"equipment"]) - 1
	ally.weapon_uses = 0
	return true


## Within range of one of its faction's supply points (a held place or a caravan).
func is_supplied(unit: Node3D, team: int) -> bool:
	return supply_source(unit, team) != null


## The supply point `unit` draws on: the nearest held place in range that still has food, else a caravan with
## cargo left, else the nearest held place in range at all, else null.
func supply_source(unit: Node3D, team: int) -> Node3D:
	var place: TerritoryNode = null
	var fed_place: TerritoryNode = null
	var caravan: CaravanUnit = null
	for node in get_tree().get_nodes_in_group(&"conquest_supply"):
		var point := node as Node3D
		if point == null or int(point.get("team_id")) != team:
			continue
		var reach: float = point.call("supply_range")
		var offset := point.global_position - unit.global_position
		offset.y = 0.0
		if reach <= 0.0 or offset.length() > reach:
			continue
		if point is CaravanUnit:
			if caravan == null and (point as CaravanUnit).cargo_left() > 0:
				caravan = point
			continue
		var territory := point as TerritoryNode
		if place == null or territory.global_position.distance_to(unit.global_position) < place.global_position.distance_to(unit.global_position):
			place = territory
		if int(territory.store[&"food"]) > 0 and (fed_place == null or
				territory.global_position.distance_to(unit.global_position) < fed_place.global_position.distance_to(unit.global_position)):
			fed_place = territory
	if fed_place:
		return fed_place
	if caravan:
		return caravan
	return place


func _caravan_near(unit: Node3D, team: int) -> CaravanUnit:
	return supply_source(unit, team) as CaravanUnit


## Server: supplies handed to a faction (a caravan home again, or loot from a rival's): into its place nearest
## `at`, as much as that store takes. `reason` (loot) notes them as coming in (a caravan's own goods were counted).
func store(team: int, supplies: Dictionary, at: Vector3 = Vector3.INF, reason: String = "") -> void:
	var places := held(team)
	if places.is_empty():
		return
	var best := places[0]
	if at != Vector3.INF:
		for territory in places:
			if territory.global_position.distance_to(at) < best.global_position.distance_to(at):
				best = territory
	for key in KEYS:
		var before := int(best.store[key])
		best.store[key] = mini(before + int(supplies.get(key, 0)), best.store_cap())
		if reason != "":
			note(team, key, reason, int(best.store[key]) - before)


## A hero whose soldiers march beyond every supply point (DISPATCH_MIN of them) and has no caravan yet gets one,
## loaded at the held place within CONVOY_RANGE with the most to give (food counts double: starving kills).
func _dispatch(team: int) -> void:
	for player in _heroes(team):
		if player.is_dead or _caravan_of(player) != null:
			continue
		var cut_off := 0
		for ally in player.followers():
			if not is_supplied(ally, team):
				cut_off += 1
		if cut_off < DISPATCH_MIN:
			continue
		var from := _best_depot(team, player.global_position)
		if from == null:
			continue
		_send_courier(from, player.peer_id, -1)


## Server: one of `from`'s couriers at home sets out with a load (CaravanUnit.CARGO at most of each, what the store
## has) for place `dest` (-1: escorting hero `owner`). Returns false when there is no courier or too little to carry.
func _send_courier(from: TerritoryNode, owner: int, dest: int) -> bool:
	if from.couriers <= 0:
		return false
	var cargo := {}
	var total := 0
	for key in KEYS:
		cargo[key] = mini(int(CaravanUnit.CARGO[key]), int(from.store[key]))
		total += int(cargo[key])
	if total < DISPATCH_MIN_CARGO:
		return false
	for key in KEYS:
		from.store[key] = int(from.store[key]) - int(cargo[key])
	from.couriers -= 1
	var at := GameConfig.clamp_to_world(from.global_position + Vector3(0.0, 0.0, from.radius() * 0.5))
	NetSpawn.unit(&"caravan", at, {"team": from.owner_team, "owner": owner, "cargo": cargo, "home": from.index,
			"dest": dest})
	return true


## Every held place with a route and a courier at home sends a load along it: to another held place of the
## faction, or to its lord's army (one escort per hero at a time, only while the lord has soldiers out).
func _run_routes(team: int) -> void:
	for from in held(team):
		if from.route == TerritoryNode.ROUTE_NONE or from.couriers <= 0:
			continue
		if from.route == TerritoryNode.ROUTE_ARMY:
			var lord := from._player_of(from.lord)
			if lord == null or lord.is_dead or lord.team_id != team or lord.followers().is_empty() or _caravan_of(lord):
				continue
			_send_courier(from, lord.peer_id, -1)
			continue
		var to: TerritoryNode = mode.territories[from.route] if from.route < mode.territories.size() else null
		if to == null or to == from or to.state != TerritoryNode.State.OWNED or to.owner_team != team:
			from.route = TerritoryNode.ROUTE_NONE  # its destination was lost
			continue
		_send_courier(from, from.lord, to.index)


## Server: `supplies` into `territory`'s store, as much as it takes; returns what did not fit.
func unload(territory: TerritoryNode, supplies: Dictionary) -> Dictionary:
	var rest := {}
	for key in KEYS:
		var room := territory.store_cap() - int(territory.store[key])
		var put := clampi(int(supplies.get(key, 0)), 0, maxi(room, 0))
		territory.store[key] = int(territory.store[key]) + put
		rest[key] = int(supplies.get(key, 0)) - put
	return rest


## Server: a courier walked into `at`; it belongs to place `home` (index): back at home, or counted there
## when `at` is another place (its own was lost: then `at` keeps it if there is room).
func courier_home(at: TerritoryNode, home: int) -> void:
	var own: TerritoryNode = mode.territories[home] if home >= 0 and home < mode.territories.size() else null
	if own == at:
		at.couriers = mini(at.couriers + 1, at.courier_total)
	elif at.courier_total < TerritoryNode.COURIER_MAX:
		at.courier_total += 1
		at.couriers += 1


## Server: a courier of place `home` was killed: the place has one less.
func courier_lost(home: int) -> void:
	if home < 0 or home >= mode.territories.size():
		return
	var place := mode.territories[home]
	place.courier_total = maxi(place.courier_total - 1, place.couriers)


## Server (the map): one more courier for `territory`, paid by `player`.
func buy_courier(player: Player, territory: TerritoryNode) -> bool:
	if territory.courier_total >= TerritoryNode.COURIER_MAX or player.coins < COURIER_COST:
		return false
	player.coins -= COURIER_COST
	territory.courier_total += 1
	territory.couriers += 1
	return true


func _best_depot(team: int, near: Vector3) -> TerritoryNode:
	var best: TerritoryNode = null
	var best_score := 0.0
	for territory in held(team):
		var d := territory.global_position.distance_to(near)
		if d > CONVOY_RANGE:
			continue
		var goods := mini(int(territory.store[&"food"]), int(CaravanUnit.CARGO[&"food"])) * 2.0 \
				+ mini(int(territory.store[&"equipment"]), int(CaravanUnit.CARGO[&"equipment"]))
		var score := goods - d * 0.05  # a little farther is fine for a lot more
		if territory.couriers > 0 and goods >= DISPATCH_MIN_CARGO and (best == null or score > best_score):
			best = territory
			best_score = score
	return best


func _caravan_of(player: Player) -> CaravanUnit:
	for node in get_tree().get_nodes_in_group(&"caravans"):
		var caravan := node as CaravanUnit
		if caravan.owner_peer == player.peer_id and not caravan.is_dead:
			return caravan
	return null


@rpc("authority", "call_local", "reliable")
func _net_stock(new_stock: Dictionary, places: PackedInt32Array) -> void:
	stock = new_stock
	for i in mini(places.size() / PLACE_FIELDS, mode.territories.size()):
		var territory := mode.territories[i]
		var at := i * PLACE_FIELDS
		if not multiplayer.is_server():
			territory.people = places[at]
			for k in TerritoryNode.SOLDIER_KINDS.size():
				territory.armed[k] = places[at + 1 + k]
				territory.ranks[k] = places[at + 5 + k]
			territory.train_kind = places[at + 9]
			for k in KEYS.size():
				territory.store[KEYS[k]] = places[at + PLACE_BARRACKS + 4 + k]
		territory.treasury = places[at + PLACE_BARRACKS]
		territory.couriers = places[at + PLACE_BARRACKS + 1]
		territory.courier_total = places[at + PLACE_BARRACKS + 2]
		territory.route = places[at + PLACE_BARRACKS + 3]
		if not multiplayer.is_server():
			for u in TerritoryNode.UPGRADES.size():
				territory.upgrades[u] = places[at + PLACE_UPGRADES + u]
			territory.apply_upgrades()
	stock_changed.emit()

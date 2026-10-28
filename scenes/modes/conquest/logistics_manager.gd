class_name LogisticsManager
extends Node
## Conquest: every faction's stockpile (food, equipment, ammo) and the army upkeep, one tick every TICK seconds.
## Server: owned territories pay their income in (`TerritoryNode.income`), every soldier eats, worn weapons are
## repaired and quivers refilled for soldiers inside a supply point's range (group `conquest_supply`: owned
## territories now, caravans later), then the effects are set on the soldiers (Ally.upkeep_speed / upkeep_damage /
## durability / ammo — they stay neutral in every other mode). Every peer gets the stockpiles via `_net_stock`.

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

var mode: ConquestMode
## team -> {food, equipment, ammo, starving: bool, soldiers: int, income: Dictionary}
var stock: Dictionary = {}

var _timer: float = TICK


func _ready() -> void:
	name = "Logistics"
	for team in ConquestMode.FACTIONS:
		stock[team] = {&"food": START_STOCK, &"equipment": START_STOCK, &"ammo": START_STOCK,
				&"starving": false, &"soldiers": 0, &"income": {}}


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
	var territories := mode.territories
	for team in ConquestMode.FACTIONS:
		var entry: Dictionary = stock[team]
		var income := {&"food": 0, &"equipment": 0, &"ammo": 0}
		var points := 0
		for territory in territories:
			if territory.state == TerritoryNode.State.OWNED and territory.owner_team == team:
				var info := territory.info()
				for key in KEYS:
					income[key] += int(info[key])
				points += int(info.points)
		for key in KEYS:
			entry[key] = mini(int(entry[key]) + int(income[key]), STOCK_CAP)
		entry[&"income"] = income
		_upkeep(team, entry)
		if points > 0:
			mode.add_score(team, points)
	_net_stock.rpc(stock)


## Feed, repair and resupply one faction's soldiers, then set what they suffer from what's missing.
func _upkeep(team: int, entry: Dictionary) -> void:
	var soldiers: Array[Ally] = []
	for node in get_tree().get_nodes_in_group(&"allies"):
		var ally := node as Ally
		if ally and not GameConfig.is_gone(ally) and ally.team_id == team:
			soldiers.append(ally)
	entry[&"soldiers"] = soldiers.size()
	var food_need := soldiers.size() * FOOD_PER_SOLDIER
	var starving := int(entry[&"food"]) < food_need
	entry[&"food"] = maxi(int(entry[&"food"]) - food_need, 0)
	entry[&"starving"] = starving and food_need > 0
	for ally in soldiers:
		if ally.durability < 0.0:
			ally.durability = FULL_DURABILITY  # joins the upkeep: from now on the weapon wears
		if ally.is_archer() and ally.ammo < 0:
			ally.ammo = QUIVER
		if is_supplied(ally, team):
			_repair(ally, entry)
			_refill(ally, entry)
		ally.upkeep_speed = STARVE_SPEED if starving else 1.0
		ally.upkeep_damage = BROKEN_DAMAGE if ally.durability <= 0.0 else 1.0
		if starving and ally.health > ally.max_health * STARVE_FLOOR:
			# Straight off the health (not a hit: no knockback, no stats; the hurt flash shows the hunger).
			ally.health = maxf(ally.health - ceilf(ally.max_health * STARVE_DRAIN), ally.max_health * STARVE_FLOOR)


func _repair(ally: Ally, entry: Dictionary) -> void:
	var missing := FULL_DURABILITY - ally.durability
	var parts := mini(ceili(missing / REPAIR_PER_EQUIPMENT), int(entry[&"equipment"]))
	if parts <= 0:
		return
	entry[&"equipment"] = int(entry[&"equipment"]) - parts
	ally.durability = minf(ally.durability + parts * REPAIR_PER_EQUIPMENT, FULL_DURABILITY)


func _refill(ally: Ally, entry: Dictionary) -> void:
	if not ally.is_archer():
		return
	var bundles := mini(ceili(float(QUIVER - ally.ammo) / ARROWS_PER_AMMO), int(entry[&"ammo"]))
	if bundles <= 0:
		return
	entry[&"ammo"] = int(entry[&"ammo"]) - bundles
	ally.ammo = mini(ally.ammo + bundles * ARROWS_PER_AMMO, QUIVER)


## Within range of one of its faction's supply points (an owned territory; later a caravan).
func is_supplied(unit: Node3D, team: int) -> bool:
	for node in get_tree().get_nodes_in_group(&"conquest_supply"):
		var point := node as Node3D
		if point == null or int(point.get("team_id")) != team:
			continue
		var reach: float = point.call("supply_range")
		var offset := point.global_position - unit.global_position
		offset.y = 0.0
		if reach > 0.0 and offset.length() <= reach:
			return true
	return false


@rpc("authority", "call_local", "reliable")
func _net_stock(new_stock: Dictionary) -> void:
	stock = new_stock
	stock_changed.emit()

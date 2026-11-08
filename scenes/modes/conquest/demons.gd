class_name ConquestDemons
extends Node
## Conquest: how the demons of the open land behave (the mode's `demons` child; server rules, every peer builds
## the same lieutenant bands from the seed).
## - Respawn by zone: every roaming band gets one fallen monster back every ZONE_RESPAWN[zone] s (2 minutes in
##   the outer zone, faster toward the middle), even after it was wiped out (`Warband.steady_respawn` / `revives`).
## - Campaigns: a band at full strength (`Warband.is_full`) marches on the nearest place a faction holds within
##   CAMPAIGN_RANGE (at most CAMPAIGN_MAX at once; CAMPAIGN_REST s between a band's campaigns). At a standing gate
##   it hammers it; once it is down they go in, and a ring with demons and none of the holder's falls to them
##   (TerritoryNode; a Citadel never falls: after CAMPAIGN_TIME the band turns home). A band that took a place
##   patrols around it from then on.
## - Breaching (monsters and soldiers alike): a unit whose goal (`wanted_point()`: its target, its campaign's place,
##   its squad's spot or its hero's ordered point) lies inside a walled place it is outside of, behind a standing
##   gate of another side, doesn't press against the wall: it walks to its spot in front of the gate
##   (`Unit.breach_point`) and hits it — a monster BATTER_DAMAGE × its power a blow, a soldier its weapon's damage
##   (TerritoryGate.HAND_SHARE of it) — until it breaks. Its own side's gate opens for it instead (TerritoryGate).
##   Checked for a slice of the units every frame (each about once a second).
## - The King's four lieutenants (LIEUTENANTS), the champions who fell defending King Malakor's realm, risen as his
##   servants: Sir Eldor (sword, wide cleaves, charge), Vaira (bow, volleys, a red-X arrow rain), Valendor (magic,
##   bolts, Phantom Blink) and Mother Tyressa (heals her army, drains blood with her blows), each leading an army of LIEUTENANT_ARMY strong demons in zone 1 on
##   one diagonal (one in every faction's way). Killing one routs its army for good (BossTrait). While the King's
##   Lair (still the demons') is under attack, the lieutenants left and every band of zones 0..RALLY_ZONE rush to
##   it (to its gate while that stands) and fight; RALLY_CALM s after the last attacker they go home.

const ZONE_RESPAWN: Array[float] = [30.0, 40.0, 55.0, 70.0, 85.0, 100.0, 120.0]
const CAMPAIGN_RANGE: float = 70.0
const CAMPAIGN_MAX: int = 6
const CAMPAIGN_REST: float = 120.0
const CAMPAIGN_TIME: float = 180.0
const CAMPAIGN_EVERY: float = 5.0
const BATTER_DAMAGE: float = 4.0
## Reach to the gate from a monster's spot in front of it (+ half the gate's width).
const BATTER_REACH: float = 1.6
## A soldier's blow at a gate counts this many times its weapon's damage before TerritoryGate.HAND_SHARE (an army
## of 30 swordsmen breaks a Citadel's gate in about half a minute; siege engines are still far faster).
const SOLDIER_GATE_BLOW: float = 2.5
## The lieutenants: scene, army filler, army entries [scene, share, rear], name.
const ENEMIES := "res://scenes/characters/enemies/"
const LIEUTENANTS: Array = [
	["lieutenant_blade", "skeleton_warrior", [["orc_brute", 0.25, false]]],
	["lieutenant_marksman", "orc_grunt", [["skeleton_archer", 0.5, true], ["orc_thrower", 0.2, true]]],
	["lieutenant_warlock", "skeleton_warrior", [["necromancer", 0.2, true], ["ghost", 0.3, false]]],
	["lieutenant_mender", "zombie", [["vampire", 0.3, false]]],
]
const LIEUTENANT_ARMY: int = 12
## Their armies' power (zone 0 demons: high rank).
const LIEUTENANT_POWER: float = 1.8
## Where they stand: on the diagonals, this share of the half-size out from the middle (zone 1).
const LIEUTENANT_SHARE: float = 0.15
const RALLY_ZONE: int = 1
## A faction's unit this close to the Lair's ring (or a battered gate) means the King is under attack.
const RALLY_ALARM: float = 22.0
const RALLY_CALM: float = 30.0

## False in tests that leave held places alone (like TerritoryNode.unguarded_falls): no campaigns start.
static var campaigns_on: bool = true

var mode: ConquestMode
## The four lieutenant bands (every peer; dead ones stay in the list, `is_dead`).
var lieutenants: Array[Warband] = []
## Server: running campaigns {band, place, time}.
var campaigns: Array[Dictionary] = []
## Server: the King is under attack and the bands are rallying.
var rallying: bool = false

var _bands: Array[Warband] = []
var _rested: Dictionary = {}  # band -> seconds left before its next campaign
var _going_home: Dictionary = {}  # band -> home point
var _campaign_timer: float = 0.0
var _tick_timer: float = 0.0
var _calm: float = 0.0
var _lair_gate_health: float = -1.0
var _walled: Array[TerritoryNode] = []
var _siege_queue: Array[Node] = []
var _siege_per_frame: int = 1


## Every peer, after the world (and its warbands) is built: zone rules for the roaming bands, then the lieutenants.
func setup(world: Node3D) -> void:
	name = "Demons"
	for node in get_tree().get_nodes_in_group(&"warbands"):
		var band := node as Warband
		if band == null or not band.replicated:
			continue
		_adopt(band, ConquestMode.zone_of(band.global_position))
		band.revives = true
	_add_lieutenants(world)


func _adopt(band: Warband, zone: int) -> void:
	band.set_meta(&"conquest_zone", zone)
	band.set_meta(&"conquest_home", band.global_position)
	band.steady_respawn = true
	band.respawn_delay = ZONE_RESPAWN[zone]
	_bands.append(band)


func _add_lieutenants(world: Node3D) -> void:
	var half := GameConfig.world_half
	for i in LIEUTENANTS.size():
		var row: Array = LIEUTENANTS[i]
		var corner := Vector3(1.0 if i % 2 == 0 else -1.0, 0.0, 1.0 if i < 2 else -1.0)
		var band := Warband.new()
		band.name = "Lieutenant_%d" % i
		band.roster = _roster(row)
		band.leader_scene = load(ENEMIES + row[0] + ".tscn")
		band.size = 1 + LIEUTENANT_ARMY
		band.tier = 1.0
		band.strength_override = GameConfig.orc_strength * LIEUTENANT_POWER
		band.territory = 12.0
		band.position = _clear_spot(corner * half * LIEUTENANT_SHARE)
		band.set_meta(&"lieutenant", row[0])
		world.add_child(band)
		_adopt(band, 1)  # their own, not revived: a fallen lieutenant routs his army for good
		lieutenants.append(band)


func _roster(row: Array) -> EnemyRoster:
	var roster := EnemyRoster.new()
	roster.filler = load(ENEMIES + row[1] + ".tscn")
	var entries: Array[RosterEntry] = []
	for item: Array in row[2]:
		var entry := RosterEntry.new()
		entry.scene = load(ENEMIES + item[0] + ".tscn")
		entry.share = item[1]
		entry.rear = item[2]
		entries.append(entry)
	roster.entries = entries
	return roster


## `at`, or the nearest spot outward along the diagonal clear of every place's ring.
func _clear_spot(at: Vector3) -> Vector3:
	var spot := at
	for step in 12:
		var crowded := false
		for territory in mode.territories:
			if Warband._flat(spot, territory.position) < territory.radius() + 6.0:
				crowded = true
				break
		if not crowded:
			return spot
		spot += at.normalized() * 4.0
	return spot


## The living lieutenants.
func living_lieutenants() -> Array[Warband]:
	var alive: Array[Warband] = []
	for band in lieutenants:
		if is_instance_valid(band) and not band.is_dead:
			alive.append(band)
	return alive


func _process(delta: float) -> void:
	if not multiplayer.is_server() or mode == null or mode.is_over or not mode.get_parent().get("_started"):
		return
	for band in _rested.keys():
		_rested[band] -= delta
		if _rested[band] <= 0.0:
			_rested.erase(band)
	_breach_slice()
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = 1.0
		_run_campaigns(1.0)
		_rally(1.0)
		_walk_home()
	_campaign_timer -= delta
	if _campaign_timer <= 0.0:
		_campaign_timer = CAMPAIGN_EVERY
		if not rallying:
			_start_campaigns()


# --- Breaching ------------------------------------------------------------------------------

## Server, every frame: a slice of the awake monsters and the soldiers (all of them about once a second).
func _breach_slice() -> void:
	if _siege_queue.is_empty():
		_siege_queue.assign(get_tree().get_nodes_in_group(&"active_enemies"))
		_siege_queue.append_array(get_tree().get_nodes_in_group(&"allies"))
		_siege_per_frame = maxi(1, ceili(_siege_queue.size() / 30.0))
	for i in mini(_siege_per_frame, _siege_queue.size()):
		var node: Variant = _siege_queue.pop_back()
		if is_instance_valid(node):
			_breach_unit(node)


## Server: every unit at once (tests). Returns the damage dealt to gates.
func _breach() -> float:
	var dealt := 0.0
	for node in get_tree().get_nodes_in_group(&"active_enemies") + get_tree().get_nodes_in_group(&"allies"):
		dealt += _breach_unit(node)
	return dealt


## Server: `node` goes for the gate between it and what it wants (and hits it there), or back to its business.
func _breach_unit(node: Object) -> float:
	var unit := node as Unit
	if unit == null or GameConfig.is_gone(unit) or not unit.has_method(&"wanted_point"):
		return 0.0
	var place := walled_off(unit, unit.call(&"wanted_point"))
	if place == null:
		_set_breach(unit, Vector3.INF)
		return 0.0
	_set_breach(unit, gate_spot(place, unit))
	return _hammer(unit, place)


## The walled place around `point` whose standing gate belongs to another side than `unit`, while `unit` is
## outside it — or null (no wall in the way, the gate is down, or it is its own side's: it opens).
func walled_off(unit: Unit, point: Vector3) -> TerritoryNode:
	if point == Vector3.INF:
		return null
	if _walled.is_empty():
		_walled.assign(mode.territories.filter(func(t: TerritoryNode) -> bool: return t.gate != null))
	for place in _walled:
		if Warband._flat(point, place.position) >= place.radius():
			continue
		if place.gate.is_broken() or place.state == TerritoryNode.State.NEUTRAL \
				or not GameConfig.is_hostile(unit, place.gate):
			return null
		if Warband._flat(unit.global_position, place.position) < place.radius() + 0.6:
			return null  # already inside
		return place
	return null


func _set_breach(unit: Unit, point: Vector3) -> void:
	if unit is Ally:
		(unit as Ally).set_breach(point)
	else:
		unit.breach_point = point


func _barred(place: TerritoryNode) -> bool:
	return place.state == TerritoryNode.State.OWNED and place.gate != null and not place.gate.is_broken()


## A monster's own spot in front of the gate (spread along it, so they don't stand in one heap).
func gate_spot(place: TerritoryNode, enemy: Node) -> Vector3:
	var gate := place.gate
	var lane := float(enemy.get_instance_id() % 5 - 2) * 0.7
	var side := gate.global_basis.x.normalized()
	var depth := 1.0 + float((enemy.get_instance_id() / 5) % 3) * 0.8
	return gate.outside_point(depth) + side * lane


## One blow at the gate when the unit stands by it and its swing is ready: a monster batters it, a soldier hits it
## with its weapon (the gate takes HAND_SHARE of that).
func _hammer(unit: Unit, place: TerritoryNode) -> float:
	var gate := place.gate
	var from_gate := Warband._flat(unit.global_position, gate.outside_point(0.0))
	if from_gate > BATTER_REACH + gate.size.x * 0.5 + 2.4 or not unit.swing_at(gate.global_position):
		return 0.0
	if unit is Ally:
		var ally := unit as Ally
		var blow := ally.melee_damage * ally.upkeep_damage * SOLDIER_GATE_BLOW
		var before := gate.health
		gate.take_damage(blow, ally)
		if before > gate.health:
			ally._fight()  # a battle: it wears the weapon
		return before - gate.health
	var damage := BATTER_DAMAGE * (unit as Enemy).power
	gate.batter(damage)
	return damage


# --- Campaigns --------------------------------------------------------------------------------

func _start_campaigns() -> void:
	if not campaigns_on:
		return
	campaigns = campaigns.filter(func(c: Dictionary) -> bool: return is_instance_valid(c.band))
	for band in _bands:
		if campaigns.size() >= CAMPAIGN_MAX:
			return
		if band.is_dead or band.has_meta(&"lieutenant") or band.goal != Vector3.INF or _rested.has(band) \
				or _going_home.has(band) or not band.is_full():
			continue
		var place := _campaign_target(band)
		if place:
			start_campaign(band, place)


## The nearest held place within CAMPAIGN_RANGE nobody else is marching on.
func _campaign_target(band: Warband) -> TerritoryNode:
	var best: TerritoryNode = null
	var best_d := CAMPAIGN_RANGE
	for place in mode.territories:
		if place.state != TerritoryNode.State.OWNED or place.kind == TerritoryNode.Kind.THRONE:
			continue
		if campaigns.any(func(c: Dictionary) -> bool: return c.place == place):
			continue
		var d := Warband._flat(band.global_position, place.position)
		if d < best_d:
			best_d = d
			best = place
	return best


## Server: `band` marches on `place` (tests call it directly).
func start_campaign(band: Warband, place: TerritoryNode) -> void:
	campaigns.append({"band": band, "place": place, "time": 0.0})
	_going_home.erase(band)
	band.siege_point = place.position if place.gate else Vector3.INF  # its members go for the gate
	band.goal = _approach(place)
	mode.announce("A demon host marches on %s!" % place.display_name)


## Where a campaign heads: before the gate while it stands, else into the ring.
func _approach(place: TerritoryNode) -> Vector3:
	return place.gate.outside_point(3.0) if _barred(place) else place.position


func _run_campaigns(step: float) -> void:
	for campaign in campaigns.duplicate():
		var band: Warband = campaign.band
		var place: TerritoryNode = campaign.place
		campaign.time += step
		if not is_instance_valid(band) or band.alive <= 0:
			_end_campaign(campaign, false)
			continue
		if place.state == TerritoryNode.State.INFESTED:
			_end_campaign(campaign, true)  # taken (by them or anyone): they hold it now
			continue
		if place.state != TerritoryNode.State.OWNED or campaign.time > CAMPAIGN_TIME:
			_end_campaign(campaign, false)
			continue
		band.goal = _approach(place)


func _end_campaign(campaign: Dictionary, took: bool) -> void:
	campaigns.erase(campaign)
	var band: Warband = campaign.band
	if not is_instance_valid(band):
		return
	_rested[band] = CAMPAIGN_REST
	band.siege_point = Vector3.INF
	if took:
		band.settle((campaign.place as TerritoryNode).position)
		band.set_meta(&"conquest_home", (campaign.place as TerritoryNode).position)
	else:
		_send_home(band)


func _send_home(band: Warband) -> void:
	var home: Vector3 = band.get_meta(&"conquest_home", band.global_position)
	band.goal = home
	_going_home[band] = home


func _walk_home() -> void:
	for band: Warband in _going_home.keys():
		if not is_instance_valid(band) or band.is_dead:
			_going_home.erase(band)
		elif Warband._flat(band.global_position, _going_home[band]) < 3.0:
			band.settle(_going_home[band])
			_going_home.erase(band)


# --- The King's defence ---------------------------------------------------------------------------

## The King's Lair is the demons' and a faction's unit is at it (or its gate was hit since the last check).
func king_attacked() -> bool:
	var lair := mode.throne()
	if lair == null or lair.state != TerritoryNode.State.INFESTED:
		return false
	if lair.gate:
		var hit := _lair_gate_health >= 0.0 and lair.gate.health < _lair_gate_health
		_lair_gate_health = lair.gate.health
		if hit:
			return true
	for node in get_tree().get_nodes_in_group(&"player_units"):
		var unit := node as Unit
		if GameConfig.is_gone(unit) or unit.team_id < 0:
			continue
		if Warband._flat(unit.global_position, lair.position) < lair.radius() + RALLY_ALARM:
			return true
	return false


func _rally(step: float) -> void:
	var attacked := king_attacked()
	if attacked:
		_calm = 0.0
		if not rallying:
			rallying = true
			mode.announce("Malakor calls his risen champions! The demons rally to the Lair.")
		var point := _rally_point()
		for band in _defenders():
			for campaign in campaigns.duplicate():
				if campaign.band == band:
					campaigns.erase(campaign)
					band.siege_point = Vector3.INF
			_going_home.erase(band)
			band.goal = point
	elif rallying:
		_calm += step
		if _calm >= RALLY_CALM:
			rallying = false
			for band in _defenders():
				_send_home(band)


## The lieutenants left and the bands of the inner zones.
func _defenders() -> Array[Warband]:
	var list := living_lieutenants()
	for band in _bands:
		if not band.is_dead and not band.has_meta(&"lieutenant") and int(band.get_meta(&"conquest_zone", 6)) <= RALLY_ZONE:
			list.append(band)
	return list


## Before the Lair's gate while it stands (where its attackers are), else inside.
func _rally_point() -> Vector3:
	var lair := mode.throne()
	if lair.gate and not lair.gate.is_broken():
		return lair.gate.outside_point(4.0)
	return lair.position

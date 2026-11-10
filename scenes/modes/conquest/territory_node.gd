class_name TerritoryNode
extends Node3D
## Conquest: one place on the map a faction can hold — a Village, Outpost, specialized City, a faction's Citadel or
## the Demon's Lair in the middle. Its `zone` (ConquestMode.zone_of: 0 = the Lair ... 6 = the faction corners)
## sets how it plays: out by the corners stand strong walls, rich production and weak demons; toward the middle
## the walls thin out (none in zone 1: a plain with houses), production drops, the demons get stronger and more
## numerous, places fall faster (ZONE_CAPTURE) and demon raids (ConquestMode._raid) overrun them more often: a
## held place with demons in the ring, none of the holder's units and no standing gate goes back to the demons. Built on every peer by ConquestMode from the match seed (deterministic name
## `Territory_<n>`); the server runs the rules and sends the state with `_net_state`.
## States: INFESTED (demons hold it: kill the garrison to liberate it; the garrison appears only once a hero comes
## within GARRISON_RANGE, so a big map doesn't simulate hundreds of idle demons), NEUTRAL (liberated, nobody holds
## it: stand in the ring to raise your banner), OWNED (a faction's: enemies must first break the gate, if it has
## one, then stand in the ring with no defenders inside).
## Held places produce into their own `store` (LogisticsManager: food / weapons, by kind and specialty)
## and are supply points: soldiers within supply range eat and rearm from that store; goods reach armies
## farther away only by caravan. Every place also has a barracks: `people` come in (INFO pool × ZONE_PEOPLE, more
## out toward the corners) unarmed. Its commander picks a class (`train_kind`): people are armed with it from the
## weapons store (LogisticsManager.ARM_PER_TICK a tick) and only armed soldiers train (`drill` per class → their rank
## when they leave); unarmed people stay untrained. Soldiers are taken out by class (the map) or by the General.
## Gold goes into the place's own `treasury` (TREASURY_CAP). Its `lord` (the hero who took it) empties it into
## their purse (`withdraw`: standing in the ring, F). A place stays its lord's while they or their soldiers stand
## in the ring; left unguarded, the next hero of the faction who walks in becomes its lord (`_update_lord`).
## Guards: a held place (not a Citadel) with none of the holder's heroes or soldiers in its ring counts down
## ZONE_UNGUARDED seconds (`unguarded_left`, 120 by the corners down to 20 in zone 1); at 0 the demons take it
## (`_abandon`: INFESTED, its garrison appears when a hero comes near). Soldiers or a squad standing in it stop it.
## Couriers: every place has `courier_total` (one to start, more bought on the map, up to COURIER_MAX); those at
## home (`couriers`) carry its goods along its `route` (another place of the faction, or its lord's army) —
## LogisticsManager sends them, CaravanUnit walks the road and back.

enum Kind { VILLAGE, OUTPOST, CITY, CITADEL, THRONE }
enum State { INFESTED, NEUTRAL, OWNED }
## What a City makes: Iron (weapons: melee repairs), Lumber (bows and arrows), Farm (food).
enum Specialty { NONE, IRON, LUMBER, FARM }

## Per kind: ring radius, garrison size and the WorldEvents.WAVE_TYPES rows it comes from (+ a boss scene),
## seconds to capture, gate health (0 = no gate, no walls), points per logistics tick, production per tick (a City
## adds its specialty's SPECIALTY_OUTPUT), supply range, army cap for every hero of the holder, barracks growth
## (people per LogisticsManager.POOL_EVERY ticks, × ZONE_PEOPLE), the most people its barracks hold and wall pieces.
const INFO: Dictionary = {
	Kind.VILLAGE: {"name": "Village", "radius": 6.0, "guards": 4, "rows": 1, "capture": 8.0, "gate": 0.0,
			"points": 1, "food": 3, "equipment": 0, "gold": 1, "supply": 16.0, "cap": 2, "pool": 0.5, "pool_cap": 20},
	Kind.OUTPOST: {"name": "Outpost", "radius": 7.0, "guards": 6, "rows": 2, "capture": 10.0, "gate": 0.0,
			"points": 2, "food": 0, "equipment": 1, "gold": 2, "supply": 22.0, "cap": 5, "pool": 0.75, "pool_cap": 30},
	Kind.CITY: {"name": "City", "radius": 9.0, "guards": 10, "rows": 4, "capture": 15.0, "gate": 1200.0,
			"points": 4, "food": 0, "equipment": 0, "gold": 3, "supply": 28.0, "cap": 12, "pool": 1.0, "pool_cap": 60,
			"walls": 14},
	# A faction's home: a small baseline of everything, so a bigger army needs conquered production.
	Kind.CITADEL: {"name": "Citadel", "radius": 11.0, "guards": 0, "rows": 0, "capture": 20.0, "gate": 2000.0,
			"points": 3, "food": 3, "equipment": 2, "gold": 4, "supply": 32.0, "cap": 10, "pool": 1.0, "pool_cap": 100,
			"walls": 16},
	# The prize: the strongest garrison (led by a demon lord), the most points, a big barracks.
	Kind.THRONE: {"name": "Demon's Lair", "radius": 15.0, "guards": 18, "rows": 5, "capture": 30.0, "gate": 4000.0,
			"points": 25, "food": 4, "equipment": 4, "gold": 8, "supply": 40.0, "cap": 30, "pool": 2.0, "pool_cap": 100,
			"walls": 22,
			"boss": "malakor", "strength": 1.5},
}
const SPECIALTY_NAMES: PackedStringArray = ["", "Iron City", "Lumber City", "Farm City"]
## Per zone (0 = the Lair ... 6 = the corners): gate health share (0 = no walls, houses instead), production
## share, demon strength, garrison size share, capture time share, extra wave rows for the garrison.
const ZONE_WALLS: Array[float] = [1.0, 0.0, 0.35, 0.55, 0.75, 1.0, 1.3]
const ZONE_OUTPUT: Array[float] = [1.0, 0.5, 0.75, 1.0, 1.4, 1.8, 2.2]
const ZONE_STRENGTH: Array[float] = [2.2, 1.8, 1.55, 1.35, 1.15, 0.95, 0.8]
const ZONE_GUARDS: Array[float] = [1.0, 1.4, 1.3, 1.2, 1.1, 1.0, 0.9]
const ZONE_CAPTURE: Array[float] = [1.0, 0.5, 0.65, 0.8, 0.9, 1.0, 1.2]
const ZONE_ROWS: Array[int] = [2, 2, 2, 1, 1, 0, 0]
## Per zone: seconds a held place stands with nobody of the holder's in it before the demons take it.
const ZONE_UNGUARDED: Array[float] = [60.0, 20.0, 40.0, 60.0, 80.0, 100.0, 120.0]
## Per zone: barracks growth share (the land by the corners has the most people).
const ZONE_PEOPLE: Array[float] = [1.0, 0.4, 0.55, 0.7, 0.85, 1.0, 1.2]
## The soldier classes a barracks arms and trains (Ally.weapon), their names, and "no class picked".
const SOLDIER_KINDS: PackedStringArray = ["sword", "bow", "wizard", "healer"]
const SOLDIER_NAMES: PackedStringArray = ["Swordsmen", "Archers", "Wizards", "Healers"]
const NO_TRAINING: int = -1
## People a Citadel has at the start (unarmed).
const START_PEOPLE: int = 8
## Demons taking a place back (capturer value while they do).
const DEMONS: int = -10
## The Lair's lord stands this much bigger than its kind.
const BOSS_SIZE: float = 1.6
const HOUSE_COLOR := Color(0.62, 0.5, 0.36)
const ROOF_COLOR := Color(0.45, 0.2, 0.15)
## A City's production by specialty (on top of its kind's row).
const SPECIALTY_OUTPUT: Array[Dictionary] = [
	{},
	{"equipment": 6},
	{"equipment": 6},
	{"food": 10},
]
## Most of each supply one place stores.
const STORE_CAP: int = 300
## Upgrades: [id, name, what a level does]; indexes UP_*.
const UPGRADES: Array = [
	[&"walls", "Walls", "+50% gate health a level"],
	[&"workshops", "Workshops", "+25% food, weapons and gold a level"],
	[&"barracks", "Barracks", "+50% room, +30% people, +1 armed a tick a level"],
	[&"storehouse", "Storehouse", "+50% food / weapons it can hold a level"],
]
const UP_WALLS: int = 0
const UP_WORKSHOPS: int = 1
const UP_BARRACKS: int = 2
const UP_STOREHOUSE: int = 3
const UPGRADE_MAX: int = 3
## Gold per level (1st, 2nd, 3rd), × UPGRADE_KIND_COST[kind] (Village … Lair).
const UPGRADE_COST: Array[int] = [100, 220, 400]
const UPGRADE_KIND_COST: Array[float] = [0.6, 0.8, 1.0, 1.2, 1.5]
const WALL_BONUS: float = 0.5
const WORKSHOP_BONUS: float = 0.25
const BARRACKS_ROOM: float = 0.5
const BARRACKS_GROWTH: float = 0.3
const STOREHOUSE_BONUS: float = 0.5
## Most gold a treasury holds (production stops once it is full).
const TREASURY_CAP: int = 600
## `route`: nowhere (goods stay), or its lord's army; >= 0 = the index of the place its goods go to.
const ROUTE_NONE: int = -1
const ROUTE_ARMY: int = -2
const COURIER_MAX: int = 4
## The garrison appears when a hero is this close (and stays).
const GARRISON_RANGE: float = 70.0
## Garrison members spawned per frame (a big one over a few frames: no hitch when it rises).
const SPAWN_PER_FRAME: int = 1
## Seconds between label text updates.
const LABEL_REFRESH: float = 0.25
## Who stands in the ring (capturing, taking back) is looked at this often (s), not every frame.
const CAPTURE_STEP: float = 0.2
## The garrison sleeps (no AI, not targeted) while no hero or soldier is within this distance of the ring and none
## of it is fighting, like a far warband.
const GARRISON_WAKE: float = 50.0
## Capture progress drains this much faster than it builds when nobody is taking the place.
const DECAY: float = 0.5
## A captured gate comes back at this share of its health.
const GATE_RESTORE: float = 0.5
const MONSTER_COLOR := Color(0.55, 0.12, 0.12)
const NEUTRAL_COLOR := Color(0.9, 0.9, 0.9)
## Walled places (the ones with a gate): a ring of straight wall pieces (INFO "walls") at radius() around the
## middle; one piece, facing the middle of the map, is the gatehouse. Heights alternate so neighbouring tops are
## never coplanar (no z-fighting where the pieces cross at the corners).
const WALL_THICKNESS: float = 0.7
const WALL_HEIGHTS: Array[float] = [2.6, 2.8]
const WALL_COLOR := Color(0.58, 0.53, 0.46)

var kind: Kind = Kind.VILLAGE
var specialty: Specialty = Specialty.NONE
## 0 (the Lair) .. 6 (the corners), set before it enters the tree.
var zone: int = 6
var state: State = State.INFESTED
## Faction holding it (-1 = nobody).
var owner_team: int = -1
var display_name: String = ""
## The faction taking it right now (-1 = nobody) and how far (0..1).
var capturer: int = -1
var progress: float = 0.0
var mode: ConquestMode
var gate: TerritoryGate
## What it has made and not yet handed out (server; peers get the totals through LogisticsManager).
var store: Dictionary = {&"food": 0, &"equipment": 0}
## Upgrades (UPGRADES order, levels 0..UPGRADE_MAX): bought on the M map by its commander with this place's own
## treasury (`ConquestMode.place_action` "upgrade"); buildings, so they stay with the place whoever holds it later.
## Every peer gets them with the places' numbers (LogisticsManager `_net_stock`).
var upgrades: Array[int] = [0, 0, 0, 0]
## Its barracks (server; every peer gets them with the logistics tick): unarmed people, armed soldiers per class
## (SOLDIER_KINDS order), the class new people are armed with (NO_TRAINING = none: they stay unarmed).
var people: int = 0
var armed: Array[int] = [0, 0, 0, 0]
var train_kind: int = NO_TRAINING
## Server: seconds of training each class's armed soldiers have had on average (newcomers lower it); they leave
## with `Ally.rank_for_drill(drill[k])`. `ranks` = that rank per class (every peer, for the map's card).
var drill: Array[float] = [0.0, 0.0, 0.0, 0.0]
var ranks: Array[int] = [0, 0, 0, 0]
## Server: people on their way (a fraction of one until whole).
var growth: float = 0.0
## Everyone waiting in the barracks, armed or not.
var barracks: int:
	get:
		var total := people
		for count in armed:
			total += count
		return total
## Gold waiting for its lord (server; every peer gets it with the logistics tick).
var treasury: int = 0
## The hero (peer id) who holds it for the faction (0 = nobody yet; replicated with the state).
var lord: int = 0
## Its place in ConquestMode.territories (set when built).
var index: int = -1
## Couriers at home / in all (server; peers get them with the logistics tick), and where its goods go.
var couriers: int = 1
var courier_total: int = 1
var route: int = ROUTE_NONE
## Seconds until the demons take it, unguarded (-1 = guarded, or not held; every peer: sent with the state, then
## counted down here). Off in tests that leave places alone (`unguarded_falls`).
var unguarded_left: float = -1.0
static var unguarded_falls: bool = true
var _lord_timer: float = 0.0

var _guards: Array[Node] = []
var _guards_spawned: bool = false
## The gate's full health before Walls upgrades.
var _gate_base: float = 0.0
## Garrison members still to spawn: [scene path, spot, size].
var _spawn_queue: Array = []
var _guard_strength: float = 1.0
var _guards_awake: bool = true
var _sync_timer: float = 0.0
var _check_timer: float = 0.0
var _label_timer: float = randf() * 0.25
## Server: time since this place last looked at who stands in its ring (`_update_capture`, every CAPTURE_STEP s).
var _capture_wait: float = randf() * CAPTURE_STEP
var _material: StandardMaterial3D
var _flag_material: StandardMaterial3D
var _label: Label3D


func info() -> Dictionary:
	return INFO[kind]


func radius() -> float:
	return info().radius


## "Iron City", "Village", "King's Throne".
func kind_name() -> String:
	return SPECIALTY_NAMES[specialty] if kind == Kind.CITY else String(info().name)


## Production per logistics tick (kind + specialty, × its zone's share, × its Workshops), gold included.
func output() -> Dictionary:
	var made := {&"food": int(info().food), &"equipment": int(info().equipment),
			&"gold": int(info().get("gold", 0))}
	for key in SPECIALTY_OUTPUT[specialty]:
		made[StringName(key)] += int(SPECIALTY_OUTPUT[specialty][key])
	var boost := 1.0 + WORKSHOP_BONUS * upgrades[UP_WORKSHOPS]
	for key in made:
		made[key] = roundi(made[key] * ZONE_OUTPUT[zone] * boost)
	return made


# --- Upgrades -------------------------------------------------------------------------------

## Whether upgrade `i` fits this place (walls need a gate, barracks people) and isn't at its top level.
func can_upgrade(i: int) -> bool:
	if i < 0 or i >= UPGRADES.size() or upgrades[i] >= UPGRADE_MAX:
		return false
	if i == UP_WALLS and gate == null:
		return false
	if i == UP_BARRACKS and not has_barracks():
		return false
	return true


## Gold (from this place's treasury) for the next level of upgrade `i`; bigger places cost more.
func upgrade_cost(i: int) -> int:
	var level := clampi(upgrades[i], 0, UPGRADE_MAX - 1)
	return roundi(UPGRADE_COST[level] * UPGRADE_KIND_COST[kind])


## Most food / weapons its store holds (Storehouse).
func store_cap() -> int:
	return roundi(STORE_CAP * (1.0 + STOREHOUSE_BONUS * upgrades[UP_STOREHOUSE]))


## People armed with the trained class a logistics tick (Barracks).
func arm_per_tick() -> int:
	return LogisticsManager.ARM_PER_TICK + upgrades[UP_BARRACKS]


## Share of its normal people growth (Barracks).
func growth_boost() -> float:
	return 1.0 + BARRACKS_GROWTH * upgrades[UP_BARRACKS]


## Every peer: the Walls level on the gate (its full health; what was added is added to its health too).
func apply_upgrades() -> void:
	if gate == null or _gate_base <= 0.0:
		return
	var top := _gate_base * (1.0 + WALL_BONUS * upgrades[UP_WALLS])
	if not is_equal_approx(top, gate.max_health):
		if multiplayer.is_server() and top > gate.max_health and not gate.is_broken():
			gate.health += top - gate.max_health
		gate.max_health = top
		gate.health = minf(gate.health, top)
		gate._apply_look()


## A wall ring with a gate (walled kinds outside zone 1).
func walled() -> bool:
	return float(info().gate) > 0.0 and ZONE_WALLS[zone] > 0.0


## Seconds to raise a banner here (faster toward the middle).
func capture_time() -> float:
	return float(info().capture) * ZONE_CAPTURE[zone]


## Supply points (territories, caravans) share this interface: team_id + supply_range().
var team_id: int:
	get:
		return owner_team


func supply_range() -> float:
	return info().supply if state == State.OWNED else 0.0


func has_barracks() -> bool:
	return float(info().pool) > 0.0


## The most people (armed or not) its barracks hold (Barracks).
func barracks_cap() -> int:
	return roundi(int(info().get("pool_cap", 0)) * (1.0 + BARRACKS_ROOM * upgrades[UP_BARRACKS]))


## Server: the barracks empty (a new holder, or demons): the old soldiers scatter.
func clear_barracks() -> void:
	people = 0
	growth = 0.0
	train_kind = NO_TRAINING
	for k in SOLDIER_KINDS.size():
		armed[k] = 0
		drill[k] = 0.0
		ranks[k] = 0


func _ready() -> void:
	add_to_group(&"territories")
	add_to_group(&"conquest_supply")
	if kind == Kind.CITADEL or kind == Kind.THRONE:
		add_to_group(&"tracked")  # the corners and the prize get a screen-edge arrow + a minimap diamond
		set_meta(&"marker_label", display_name)
	_build_visuals()
	if walled():
		_build_walls()
	elif kind != Kind.CITADEL:
		_build_houses()
	_apply_look()


## The wall ring and its gatehouse (every peer, the same: static collision on the world layer).
func _build_walls() -> void:
	var holder := Node3D.new()
	holder.name = "Walls"
	# The gate (local +Z) faces the middle of the map; the Throne's (in the middle) faces +Z.
	var inward := -position
	holder.rotation.y = atan2(inward.x, inward.z) if inward.length() > 0.1 else 0.0
	add_child(holder)
	var body := StaticBody3D.new()
	body.name = "Wall"
	body.add_to_group(&"conquest_walls")
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	holder.add_child(body)
	var r := radius()
	var pieces: int = info().walls
	var chord := 2.0 * r * sin(PI / pieces)
	var material := StandardMaterial3D.new()
	material.albedo_color = WALL_COLOR
	for i in pieces:
		var angle := TAU * i / pieces
		var at := Vector3(sin(angle), 0.0, cos(angle)) * r
		if i == 0:
			gate = TerritoryGate.new()
			gate.name = "Gate"
			gate.territory = self
			_gate_base = float(info().gate) * ZONE_WALLS[zone]
			gate.max_health = _gate_base
			gate.health = gate.max_health
			gate.size = Vector3(chord, TerritoryGate.HEIGHT, WALL_THICKNESS + 0.3)
			gate.position = at
			gate.rotation.y = angle
			holder.add_child(gate)
			continue
		var height: float = WALL_HEIGHTS[i % 2]
		var size := Vector3(chord + WALL_THICKNESS, height, WALL_THICKNESS)  # long enough to close the corners
		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = at + Vector3(0.0, height * 0.5, 0.0)
		collision.rotation.y = angle
		body.add_child(collision)
		var box := BoxMesh.new()
		box.size = size
		box.material = material
		var mesh := MeshInstance3D.new()
		mesh.mesh = box
		mesh.position = collision.position
		mesh.rotation.y = angle
		holder.add_child(mesh)


## No walls: a few houses just outside the ring (static boxes with collision, roofs a step above the walls so
## nothing is coplanar), more for a City.
func _build_houses() -> void:
	var count := 4 if kind == Kind.CITY else (3 if kind == Kind.OUTPOST else 2)
	var body := StaticBody3D.new()
	body.name = "Houses"
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	var wall := StandardMaterial3D.new()
	wall.albedo_color = HOUSE_COLOR
	var roof := StandardMaterial3D.new()
	roof.albedo_color = ROOF_COLOR
	var turn := float(hash(display_name) % 628) / 100.0
	for i in count:
		var angle := turn + TAU * i / count
		var at := Vector3(cos(angle), 0.0, sin(angle)) * (radius() + 3.0)
		var size := Vector3(2.6, 1.5, 2.0)
		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = at + Vector3(0.0, size.y * 0.5, 0.0)
		collision.rotation.y = -angle
		body.add_child(collision)
		var box := BoxMesh.new()
		box.size = size
		box.material = wall
		var house := MeshInstance3D.new()
		house.mesh = box
		house.position = collision.position
		house.rotation.y = -angle
		add_child(house)
		var prism := PrismMesh.new()
		prism.size = Vector3(size.x + 0.3, 0.8, size.z + 0.3)
		prism.material = roof
		var top := MeshInstance3D.new()
		top.mesh = prism
		top.position = at + Vector3(0.0, size.y + 0.4, 0.0)
		top.rotation.y = -angle
		add_child(top)


## Every peer, before the tree: a citadel starts as its faction's, everything else infested.
func start_owned(team: int) -> void:
	owner_team = team
	state = State.OWNED


# --- Server rules ------------------------------------------------------------------

func _process(delta: float) -> void:
	_label_timer -= delta
	if _label and _label_timer <= 0.0:
		_label_timer = LABEL_REFRESH  # the text is built a few times a second, not every frame
		var text := _label_text()
		if text != _label.text:
			_label.text = text
	if unguarded_left > 0.0 and not multiplayer.is_server():
		unguarded_left = maxf(unguarded_left - delta, 0.0)  # the server sends it when it starts / stops
	if not multiplayer.is_server() or mode == null or mode.is_over:
		return
	var changed := false
	match state:
		State.INFESTED:
			changed = _update_infested(delta)
		State.NEUTRAL, State.OWNED:
			_capture_wait += delta
			if _capture_wait >= CAPTURE_STEP:  # who stands in the ring: a few times a second, not every frame
				changed = _update_capture(_capture_wait)
				_capture_wait = 0.0
			if state == State.OWNED:
				_lord_timer -= delta
				if _lord_timer <= 0.0:
					_lord_timer = 1.0
					changed = _update_lord() or changed
					changed = _update_guard(1.0) or changed
	_sync_timer -= delta
	if changed or (capturer != -1 and _sync_timer <= 0.0):
		_sync_timer = 0.5
		_send_state()


## Demons hold it until every one of the garrison is dead (the garrison appears when a hero comes near).
func _update_infested(delta: float) -> bool:
	if not _guards_spawned:
		_check_timer -= delta
		if _check_timer > 0.0:
			return false
		_check_timer = 1.0
		if _hero_within(GARRISON_RANGE):
			_spawn_guards()
		return false
	if not _spawn_queue.is_empty():
		_spawn_some()
		return false
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = 1.0
		_wake_guards(_guards_needed())
	for guard in _guards:
		if not GameConfig.is_gone(guard):
			return false
	_guards.clear()
	state = State.NEUTRAL
	mode.announce("%s is free of demons! Raise your banner there." % display_name)
	return true


func _hero_within(distance: float) -> bool:
	for player in mode.living_players():
		var offset := player.global_position - global_position
		offset.y = 0.0
		if offset.length() < distance:
			return true
	return false


## Exactly one faction (not the owner) in the ring, nobody of the owner's, the gate down: the banner rises.
## Demons (a raid) in a held ring with nobody of the owner's and no standing gate take it back the same way.
func _update_capture(delta: float) -> bool:
	var inside := _ring_census()
	var taker := -1
	var open := gate == null or gate.is_broken()
	if inside.size() == 1 and not inside.has(owner_team) and open:
		taker = inside.keys()[0]
	elif inside.is_empty() and state == State.OWNED and open and kind != Kind.CITADEL and _demons_near():
		taker = DEMONS  # a faction's Citadel never falls to demons (its gate can be broken)
	var before := progress
	var before_capturer := capturer
	if taker != -1:
		if taker != capturer:
			capturer = taker
			progress = 0.0
		progress = minf(progress + delta / capture_time(), 1.0)
		if progress >= 1.0:
			if taker == DEMONS:
				_overrun()
			else:
				_captured_by(taker)
			return true
	else:
		progress = maxf(progress - delta * DECAY / capture_time(), 0.0)
		if progress <= 0.0:
			capturer = -1
	return capturer != before_capturer or (progress == 0.0) != (before == 0.0)


## A faction other than the holder has someone standing in the ring (no gate repairs then).
func contested() -> bool:
	var inside := _teams_inside()
	inside.erase(owner_team)
	return not inside.is_empty()


## `_teams_inside()` for the capture check, which runs all the time: from the commanders' census (BattleBrain: one
## grid of everybody, a cycle old at most) — every place walking over every unit, every frame, was a frame cost that
## grew with the places held × the armies. No fresh census: the exact look.
func _ring_census() -> Dictionary:
	var brain := BattleBrain.current
	if brain and brain.has_census():
		return brain.factions_near(global_position, radius())
	return _teams_inside()


## Factions with a standing hero or soldier inside the ring right now (team -> count): a walk over every hero and
## soldier — for what is asked once a second or less (the guard countdown, gate repairs).
func _teams_inside() -> Dictionary:
	var teams := {}
	var r := radius()
	for node in get_tree().get_nodes_in_group(&"player_units"):
		var unit := node as Unit
		if GameConfig.is_gone(unit) or unit.team_id < 0 or unit.is_in_group(&"caravans"):
			continue  # pack animals don't take or hold places
		var offset := unit.global_position - global_position
		offset.y = 0.0
		if offset.length() < r:
			teams[unit.team_id] = teams.get(unit.team_id, 0) + 1
	return teams


## Server: the lord keeps it while they or their soldiers stand in the ring (or nobody else of the faction does);
## unguarded, the faction's hero standing in it takes over. A lord who left the faction or the game loses it.
## Returns whether the lord changed.
func _update_lord() -> bool:
	var before := lord
	var lord_player := _player_of(lord)
	if lord_player == null or lord_player.team_id != owner_team:
		lord = 0
	var guarded := false
	var newcomer := 0
	var r := radius()
	for node in get_tree().get_nodes_in_group(&"player_units"):
		var unit := node as Unit
		if GameConfig.is_gone(unit) or unit.team_id != owner_team or unit.is_in_group(&"caravans"):
			continue
		var offset := unit.global_position - global_position
		offset.y = 0.0
		if offset.length() >= r:
			continue
		if lord != 0 and unit.owner_peer == lord:
			guarded = true
		elif unit is Player and newcomer == 0:
			newcomer = (unit as Player).peer_id
	if (lord == 0 or not guarded) and newcomer != 0:
		lord = newcomer
	if lord != before:
		if lord != 0:
			mode.announce("%s is now held by %s." % [display_name, Net.name_of(lord)])
		return true
	return false


## Server, every second while held: nobody of the holder's in the ring → the countdown runs (announced when it
## starts); at 0 the demons take it. Someone back in it stops it. Citadels never fall this way. Returns whether the
## state peers see changed.
func _update_guard(elapsed: float) -> bool:
	if kind == Kind.CITADEL or not unguarded_falls or state != State.OWNED:
		return false
	if _teams_inside().has(owner_team):
		if unguarded_left < 0.0:
			return false
		unguarded_left = -1.0
		return true
	if unguarded_left < 0.0:
		unguarded_left = ZONE_UNGUARDED[zone]
		mode.announce("{team:%d}: %s is unguarded! Demons take it in %d s unless soldiers stay there." % [owner_team,
				display_name, roundi(unguarded_left)])
		return true
	unguarded_left = maxf(unguarded_left - elapsed, 0.0)
	if unguarded_left <= 0.0:
		_abandon()
		return true
	return false


## Server: left unguarded too long, the demons move in (its garrison appears when a hero comes near).
func _abandon() -> void:
	var previous := owner_team
	owner_team = -1
	state = State.INFESTED
	capturer = -1
	progress = 0.0
	unguarded_left = -1.0
	clear_barracks()
	lord = 0
	_reset_couriers()
	_guards.clear()
	_guards_spawned = false
	_spawn_queue.clear()
	_guards_awake = true
	mode.announce("Demons took %s: {team:%d} left it unguarded!" % [display_name, previous])
	mode.on_territory_captured(self, previous)


func _player_of(peer: int) -> Player:
	if peer == 0:
		return null
	for node in get_tree().get_nodes_in_group(&"players"):
		if (node as Player).peer_id == peer:
			return node
	return null


## Server: the lord standing in the ring takes the treasury into their purse. Returns the gold taken.
func withdraw(player: Player) -> int:
	if state != State.OWNED or player.peer_id != lord or player.team_id != owner_team or treasury <= 0:
		return 0
	var offset := player.global_position - global_position
	offset.y = 0.0
	if offset.length() >= radius():
		return 0
	var taken := treasury
	treasury = 0
	player.coins += taken
	mode.logistics.note(owner_team, &"gold", "Taken by lords", -taken)
	mode.logistics.send_places()
	return taken


## Whether a living (awake) demon stands in the ring.
func _demons_near() -> bool:
	var brain := BattleBrain.current
	if brain and brain.has_census():
		return brain.monsters_near(global_position, radius())
	return not _demons_inside().is_empty()


## Living demons standing in the ring.
func _demons_inside() -> Array[Node]:
	var found: Array[Node] = []
	var r := radius()
	for node in get_tree().get_nodes_in_group(&"active_enemies"):
		var enemy := node as Enemy
		if enemy == null or GameConfig.is_gone(enemy):
			continue
		var offset := enemy.global_position - global_position
		offset.y = 0.0
		if offset.length() < r:
			found.append(enemy)
	return found


## Server: a raid took the place back; the raiders are its new garrison (kill them to free it again).
func _overrun() -> void:
	var previous := owner_team
	_guards = _demons_inside()
	_guards_spawned = true
	_guards_awake = true
	owner_team = -1
	state = State.INFESTED
	capturer = -1
	progress = 0.0
	unguarded_left = -1.0
	clear_barracks()
	lord = 0
	_reset_couriers()
	mode.announce("Demons overran %s, {team:%d} lost it!" % [display_name, previous])
	mode.on_territory_captured(self, previous)


## A new holder: one courier at home, nothing on its way (couriers out on the road go home to their own side).
func _reset_couriers() -> void:
	couriers = 1
	courier_total = 1
	route = ROUTE_NONE


func _captured_by(team: int) -> void:
	var previous := owner_team
	owner_team = team
	state = State.OWNED
	capturer = -1
	progress = 0.0
	clear_barracks()  # the old garrison scatters; the goods (and the treasury) stay for the taker
	unguarded_left = -1.0
	lord = 0
	_reset_couriers()
	_update_lord()  # the taker's hero standing in it, if any
	if gate:
		gate.restore(GATE_RESTORE)
	if previous >= 0:
		mode.announce("{team:%d} took %s from {team:%d}!" % [team, display_name, previous])
	else:
		mode.announce("{team:%d} raised their banner over %s." % [team, display_name])
	mode.on_territory_captured(self, previous)


## Server: the demons that hold the place, from the wave rows (bigger places and inner zones bring tougher rows and
## more of them, stronger), plus its boss.
func _spawn_guards() -> void:
	_guards_spawned = true
	var rows := mini(int(info().rows) + ZONE_ROWS[zone], WorldEvents.WAVE_TYPES.size())
	var count := roundi(int(info().guards) * ZONE_GUARDS[zone])
	var strength := GameConfig.orc_strength * float(info().get("strength", 1.0)) * ZONE_STRENGTH[zone]
	var scenes: Array[String] = []
	if info().has("boss"):
		scenes.append(WorldEvents.ENEMIES + str(info().boss) + ".tscn")
	for i in count:
		var types: Array = WorldEvents.WAVE_TYPES[randi() % maxi(rows, 1)]
		scenes.append(WorldEvents.ENEMIES + str(types[randi() % types.size()]) + ".tscn")
	if kind == Kind.THRONE:
		mode.announce("Malakor, the Six-Armed Sovereign, awakens in the Lair!")
	_guard_strength = strength
	_guards_awake = true
	for i in scenes.size():
		var angle := TAU * i / scenes.size()
		var spread := 0.0 if i == 0 and info().has("boss") else radius() * 0.6
		var at := GameConfig.clamp_to_world(global_position + Vector3(cos(angle), 0.0, sin(angle)) * spread)
		var boss := i == 0 and info().has("boss")
		_spawn_queue.append([scenes[i], at, BOSS_SIZE if boss else 1.0])
	_spawn_some()


## Server: the next few of the garrison (SPAWN_PER_FRAME a frame).
func _spawn_some() -> void:
	for i in mini(SPAWN_PER_FRAME, _spawn_queue.size()):
		var row: Array = _spawn_queue.pop_front()
		var guard := NetSpawn.unit(&"enemy", row[1], {"scene": row[0], "strength": _guard_strength, "coins": 1.0,
				"size": row[2]})
		if guard:
			guard.add_to_group(&"active_enemies")  # no warband wakes them: heroes and soldiers target them as is
			_guards.append(guard)


## A hero or soldier near the ring, or one of the garrison busy fighting / walking back.
func _guards_needed() -> bool:
	var reach := radius() + GARRISON_WAKE
	var brain := BattleBrain.current
	if brain and brain.has_census():
		if brain.friends_near(global_position, reach):
			return true
	else:
		for node in get_tree().get_nodes_in_group(&"player_units"):
			var unit := node as Node3D
			if GameConfig.is_gone(unit):
				continue
			if Vector2(unit.global_position.x - global_position.x, unit.global_position.z - global_position.z).length() < reach:
				return true
	for guard in _guards:
		if not GameConfig.is_gone(guard) and (guard as Enemy).is_busy():
			return true
	return false


## Server: the garrison sleeps (no AI, nobody targets it) or wakes up.
func _wake_guards(awake: bool) -> void:
	if awake == _guards_awake:
		return
	_guards_awake = awake
	for node in _guards:
		if not is_instance_valid(node):
			continue  # (a freed guard can't even be cast)
		var guard := node as Enemy
		if GameConfig.is_gone(guard):
			continue
		guard.process_mode = Node.PROCESS_MODE_INHERIT if awake else Node.PROCESS_MODE_DISABLED
		if awake and not guard.is_downed:
			guard.add_to_group(&"active_enemies")
		else:
			guard.remove_from_group(&"active_enemies")


func _send_state() -> void:
	_net_state.rpc(state, owner_team, capturer, progress, lord, unguarded_left)


@rpc("authority", "call_local", "reliable")
func _net_state(new_state: int, new_owner: int, new_capturer: int, new_progress: float, new_lord: int = 0,
		new_unguarded: float = -1.0) -> void:
	state = new_state as State
	owner_team = new_owner
	capturer = new_capturer
	progress = new_progress
	lord = new_lord
	unguarded_left = new_unguarded
	_apply_look()


# --- Display (every peer) ---------------------------------------------------------

func color() -> Color:
	match state:
		State.INFESTED:
			return MONSTER_COLOR
		State.OWNED:
			return Net.team_color(owner_team)
	return NEUTRAL_COLOR


func _label_text() -> String:
	var text := "%s\n%s · Zone %d" % [display_name, kind_name(), zone]
	if capturer == DEMONS and progress > 0.0:
		text += "  DEMONS %d%%" % roundi(progress * 100.0)
	elif capturer >= 0 and progress > 0.0:
		text += "  %d%%" % roundi(progress * 100.0)
	elif gate and state != State.NEUTRAL and not gate.is_broken():
		text += "  gate %d%%" % roundi(gate.health / gate.max_health * 100.0)
	if state == State.OWNED and unguarded_left >= 0.0:
		text += "\nUNGUARDED: demons in %d:%02d" % [ceili(unguarded_left) / 60, ceili(unguarded_left) % 60]
	if state == State.OWNED:
		var parts := PackedStringArray()
		var levels := upgrades[0] + upgrades[1] + upgrades[2] + upgrades[3]
		if levels > 0:
			parts.append("Upgrades %d" % levels)
		if lord != 0:
			parts.append("Lord " + Net.name_of(lord))
		if treasury > 0:
			parts.append("Gold %d" % treasury)
		if has_barracks() and barracks > 0:
			parts.append("Barracks %d" % barracks)
		if not parts.is_empty():
			text += "\n" + "  ·  ".join(parts)
	return text


func _build_visuals() -> void:
	var r := radius()
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var torus := TorusMesh.new()
	torus.inner_radius = r - 0.25
	torus.outer_radius = r
	torus.rings = 64
	torus.material = _material
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.scale = Vector3(1, 0.3, 1)
	ring.position.y = 0.05
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	# Banner: a pole with a flag in the holder's color (taller over the Throne).
	var tall := 6.0 if kind == Kind.THRONE else 4.0
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.06
	pole_mesh.bottom_radius = 0.08
	pole_mesh.height = tall
	var pole := MeshInstance3D.new()
	pole.mesh = pole_mesh
	pole.position = Vector3(2.2, tall * 0.5, 0.0)
	add_child(pole)
	_flag_material = StandardMaterial3D.new()
	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(1.2, 0.7, 0.04)
	flag_mesh.material = _flag_material
	var flag := MeshInstance3D.new()
	flag.mesh = flag_mesh
	flag.position = Vector3(2.85, tall - 0.45, 0.0)
	add_child(flag)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.012
	_label.outline_size = 10
	_label.position = Vector3(0.0, tall + 0.6, 0.0)
	_label.no_depth_test = true
	add_child(_label)


func _apply_look() -> void:
	if gate:
		gate._apply_look()  # its gate layer follows the holder
	if _material == null:
		return
	var c := color()
	_material.albedo_color = Color(c, 0.55)
	_flag_material.albedo_color = c
	if is_in_group(&"tracked"):
		set_meta(&"marker_color", c)

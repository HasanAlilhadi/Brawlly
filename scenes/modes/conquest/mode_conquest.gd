class_name ConquestMode
extends GameMode
## Conquest (PC only): the land is infested by demons. Four factions start from Citadels in the four corners of a
## big map (WORLD_HALF) and push inward through Villages, Outposts and specialized Cities (Iron: weapons, Lumber:
## arrows, Farm: food) toward the Demon's Lair in the middle: walled, held by a giant demon lord, worth the most.
## The map is seven square rings (`zone_of`, ZONE_EDGES): zone 6 by the corners (strong walls, rich, weak demons)
## down to zone 1 (no walls, poor, strong demons, raided often: `_raid`) and the Lair (zone 0).
## Demons hold every place at the start (kill the garrison to liberate it), then a faction raises its banner by
## standing in the ring; walled places held by another faction need their gate broken first (siege engines).
## Held places produce into their own stores, fill barracks the faction's General musters, and score points every
## logistics tick (LogisticsManager); armies far from home live on caravans. Win: hold the Throne for
## THRONE_WIN_TICKS ticks in a row, hold every Citadel, reach the score limit, or lead when the time runs out.
## Built on top of GameMode (the base runs teams, respawns, the clock and the score RPCs unchanged); main.gd creates
## this instead of GameMode only for Net.Mode.CONQUEST. The plan of the territories comes from the match seed, so
## every peer builds the same `Territory_<n>` nodes (Citadels 0..3, the Throne 4, then Cities, Outposts,
## Villages); the server runs them.

const FACTIONS: int = 4
## Half the map's size on procedural maps (600 m across); a designed map keeps its own.
const WORLD_HALF: float = 300.0
## Warbands (demons roaming between the places): the lobby's count × this.
const BAND_FACTOR: int = 2
## Places on a full-size map (fewer on a smaller one, by area): Cities cycle Iron / Lumber / Farm.
const CITIES: int = 40
const OUTPOSTS: int = 20
const VILLAGES: int = 30
## Citadels sit this share of the half-size out on both axes (the corners).
const CORNER: float = 0.86
## Zones: square rings by the larger of |x| and |z| as a share of the half-size; zone i ends at ZONE_EDGES[i]
## (zone 6: the rest, out to the border).
const ZONE_EDGES: Array[float] = [0.08, 0.22, 0.36, 0.5, 0.64, 0.8]
const ZONES: int = 7
## Demon raids on held places (guarded or not; never a Citadel): every RAID_EVERY s each one rolls ZONE_RAID (its
## zone's chance: the nearer the Lair, the more raids); a raid is RAID_BASE + RAID_STEP × (5 - zone) demons, from
## the middle's side, RAID_DISTANCE out. At most RAID_MAX at a time. A standing gate is battered first
## (`_batter`: raiders at it deal BATTER_DAMAGE × their power a second), then they walk in.
const RAID_EVERY: float = 30.0
const ZONE_RAID: Array[float] = [0.5, 0.45, 0.3, 0.18, 0.1, 0.05, 0.02]
const BATTER_DAMAGE: float = 4.0
const BATTER_REACH: float = 4.0
const RAID_BASE: int = 3
const RAID_STEP: int = 2
const RAID_DISTANCE: float = 32.0
const RAID_MAX: int = 4
## World events reach zones 0..EVENT_ZONE only (`events_reach`); no invasion waves (raids instead, main.gd).
const EVENT_ZONE: int = 3
## Roaming warbands per zone (`band_rule_at`): size share (0 small .. 1 big) and the spacing between bands.
const ZONE_BAND_TIER: Array[float] = [1.0, 0.85, 0.68, 0.5, 0.32, 0.12, 0.0]
const ZONE_BAND_SPACING: Array[float] = [20.0, 20.0, 22.0, 25.0, 32.0, 45.0, 80.0]
const OUTER_BAND_SIZE: Vector2i = Vector2i(2, 3)
## Places stay this far apart, this far from a Citadel / the Throne, and from the map border.
const TERRITORY_SPACING: float = 26.0
const STRONGHOLD_SPACING: float = 60.0
const BORDER: float = 14.0
## Holding the Throne this many logistics ticks in a row (5 minutes) wins.
const THRONE_WIN_TICKS: int = 60
## Slaying Malakor wins: the killing blow counts this share of his health on top of a faction's damage to him.
const KING_BLOW_SHARE: float = 0.25
const THRONE_INDEX: int = FACTIONS
## Lowest score limit Conquest accepts (the lobby's range starts here; tests may leave the default).
const SCORE_LIMIT_MIN: int = 500
## A new Conquest lobby's score and time limits (Net.host from the Conquest section).
const DEFAULT_SCORE: int = 2500
const DEFAULT_TIME: int = 45
const CITADEL_NAMES: PackedStringArray = ["Highkeep", "Sunspire", "Wolfcrag", "Stormhold"]
## Place names: a front and a back from these (from the seed, never twice).
const NAME_FRONTS: PackedStringArray = ["Ash", "Bright", "Cold", "Dun", "East", "Fallow", "Grey", "Hollow", "Iron",
		"Juniper", "Kings", "Lark", "Mill", "North", "Oak", "Pine", "Queens", "Raven", "Stone", "Thorn", "Umber",
		"Vale", "West", "Yarrow", "Amber", "Black", "Copper", "Deep", "Elder", "Frost", "Gold", "Hart", "Marsh",
		"Red", "Silver", "Wolf"]
const NAME_BACKS: PackedStringArray = ["ford", "water", "harbor", "mere", "watch", "stone", "well", "brook", "moor",
		"field", "gate", "haven", "crest", "hold", "bridge", "wick", "lee", "wood", "march", "by", "dale", "fell",
		"hurst", "ton"]

## Navigation mesh voxels (the map's cell size must match).
const NAV_CELL: float = 0.5
const NAV_CELL_HEIGHT: float = 0.25

## Every territory, in plan order (every peer, after build_objectives).
var territories: Array[TerritoryNode] = []
var logistics: LogisticsManager
var squads: ConquestSquads
## The demons of the open land: respawn by zone, campaigns, breaching gates, the King's lieutenants.
var demons: ConquestDemons
## Server: the baked world for marching soldiers (navigation_ready once the bake thread is done).
var navigation: NavigationRegion3D
var navigation_ready: bool = false
## Server: who holds the Throne and for how many ticks in a row.
var throne_ticks: int = 0

## [{kind, specialty, pos, owner, name}] from the seed (setup); build_objectives turns it into nodes.
var _plan: Array[Dictionary] = []
## Server: raiding parties still on the way / fighting ([{place, demons}]).
var _raids: Array[Dictionary] = []
var _raid_timer: Timer


## The zone of a point: 0 (the middle) .. 6 (the corners).
static func zone_of(point: Vector3) -> int:
	var share := maxf(absf(point.x), absf(point.z)) / maxf(GameConfig.world_half, 1.0)
	for i in ZONE_EDGES.size():
		if share < ZONE_EDGES[i]:
			return i
	return ZONES - 1


## World events (meteors, storm, Blood Moon, goblin, Warlord, supply drops) only reach zones 0..EVENT_ZONE: the
## outer lands where the factions start stay calm.
func events_reach(point: Vector3) -> bool:
	return zone_of(point) <= EVENT_ZONE


## Roaming warbands by zone: ZONE_BAND_TIER (size, and so power: 0 = 3-4 members .. 1 = 20+), at least
## ZONE_BAND_SPACING m apart; the outermost zone only has a few small plain bands (OUTER_BAND_SIZE, filler only:
## grunts / skeleton warriors, no throwers, brutes or archers) far apart.
func band_rule_at(point: Vector3) -> Dictionary:
	var zone := zone_of(point)
	var rule := {"tier": ZONE_BAND_TIER[zone], "spacing": ZONE_BAND_SPACING[zone]}
	if zone == ZONES - 1:
		rule["size"] = randi_range(OUTER_BAND_SIZE.x, OUTER_BAND_SIZE.y)
		rule["plain"] = true
	return rule
var _throne_holder: int = -1


## Every peer: the size of a Conquest world (main.gd, before anything is built).
## False in tests written for the kinds' own numbers (INFO rows): every place is MEDIUM.
static var sizes_on: bool = true
## The land's mix of places and sizes (MapDef.conquest_places / conquest_sizes).
var _place_share := Vector3.ONE
var _size_weights := Vector3(0.3, 0.45, 0.25)


static func world_half_for(map: MapDef) -> float:
	return map.world_half if map and map.layout else WORLD_HALF


func setup(match_settings: Dictionary, players: Dictionary, map: MapDef = null) -> void:
	match_settings.team_count = FACTIONS  # the same dictionary as Net.settings: colors follow on every peer
	super.setup(match_settings, players, map)
	if not (map and map.layout):
		_place_in_corners(players)
	if map:
		_place_share = map.conquest_places
		_size_weights = map.conquest_sizes
	_plan_territories(int(settings.get("seed", 0)))
	_plan_sizes(int(settings.get("seed", 0)))


## Every place its own size (TerritoryNode.Size) by the land's weights, from the seed — every peer the same, and
## its own random stream, so the places stand where they always did. Citadels and the Lair stay MEDIUM.
func _plan_sizes(match_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = match_seed + 5222
	var total := maxf(_size_weights.x + _size_weights.y + _size_weights.z, 0.001)
	for planned in _plan:
		if not sizes_on or planned.kind == TerritoryNode.Kind.CITADEL or planned.kind == TerritoryNode.Kind.THRONE:
			planned.size = TerritoryNode.Size.MEDIUM
			continue
		var roll := rng.randf() * total
		planned.size = TerritoryNode.Size.SMALL if roll < _size_weights.x else (
				TerritoryNode.Size.MEDIUM if roll < _size_weights.x + _size_weights.y else TerritoryNode.Size.LARGE)


## Procedural maps: the four factions start in the four corners (the base put them on a circle).
func _place_in_corners(players: Dictionary) -> void:
	var half := GameConfig.world_half * CORNER
	var corners: Array[Vector3] = [Vector3(-half, 0.0, -half), Vector3(half, 0.0, -half), Vector3(half, 0.0, half),
			Vector3(-half, 0.0, half)]
	for team in FACTIONS:
		team_bases[team] = corners[team]
	var slots := {}
	var peers := players.keys()
	peers.sort()
	for peer in peers:
		var team: int = players[peer].get("team", 0)
		var slot: int = slots.get(team, 0)
		slots[team] = slot + 1
		_spawn_points[peer] = team_bases[team] + Vector3(cos(slot * 1.3), 0.0, sin(slot * 1.3)) * 2.2


## Citadels in the corners, the Lair in the middle, then Cities, Outposts and Villages spread over zones 1..6 by
## each ring's area (Cities cycle Iron / Lumber / Farm, so every ring has each; from the seed: every peer plans the
## same).
func _plan_territories(match_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = match_seed + 4111
	var half := GameConfig.world_half
	var area := clampf(pow(half / WORLD_HALF, 2.0), 0.12, 1.0)
	var names := _shuffled_names(rng)
	for team in FACTIONS:
		_plan.append({"kind": TerritoryNode.Kind.CITADEL, "pos": team_bases[team], "owner": team,
				"name": CITADEL_NAMES[team]})
	_plan.append({"kind": TerritoryNode.Kind.THRONE, "pos": Vector3.ZERO, "owner": -1, "name": "The Demon's Lair"})
	var city_index := 0
	for kind in [TerritoryNode.Kind.CITY, TerritoryNode.Kind.OUTPOST, TerritoryNode.Kind.VILLAGE]:
		var total: int = {TerritoryNode.Kind.CITY: CITIES, TerritoryNode.Kind.OUTPOST: OUTPOSTS}.get(kind, VILLAGES)
		var share: float = {TerritoryNode.Kind.CITY: _place_share.x, TerritoryNode.Kind.OUTPOST: _place_share.y}.get(
				kind, _place_share.z)  # the land's own mix (MapDef.conquest_places)
		total = maxi(roundi(total * area * share), 3)
		for zone in range(1, ZONES):
			for i in _zone_share(total, zone):
				var spot := _free_spot(rng, half, ZONE_EDGES[zone - 1], ZONE_EDGES[zone] if zone < ZONE_EDGES.size() else 1.0)
				if spot == Vector3.INF:
					continue
				var planned := {"kind": kind, "pos": spot, "owner": -1, "name": names.pop_back()}
				if kind == TerritoryNode.Kind.CITY:
					planned.specialty = 1 + city_index % 3
					city_index += 1
				_plan.append(planned)
	for planned in _plan:
		planned.zone = zone_of(planned.pos)


## How many of `total` places go into `zone` (1..6): its ring's share of the area of zones 1..6.
func _zone_share(total: int, zone: int) -> int:
	var inner: float = ZONE_EDGES[zone - 1]
	var outer: float = ZONE_EDGES[zone] if zone < ZONE_EDGES.size() else 1.0
	var whole := 1.0 - ZONE_EDGES[0] * ZONE_EDGES[0]
	return maxi(roundi(total * (outer * outer - inner * inner) / whole), 1)


## Every front + back pair once, shuffled (enough for every place).
func _shuffled_names(rng: RandomNumberGenerator) -> Array:
	var names := []
	for front in NAME_FRONTS:
		for back in NAME_BACKS:
			names.append(front + back)
	for i in names.size():
		var j := rng.randi_range(i, names.size() - 1)
		var swap: Variant = names[i]
		names[i] = names[j]
		names[j] = swap
	return names


## A spot in the square ring between `inner` and `outer` (shares of the half-size) clear of every planned place.
func _free_spot(rng: RandomNumberGenerator, half: float, inner: float, outer: float) -> Vector3:
	var spacing := TERRITORY_SPACING * clampf(half / WORLD_HALF, 0.5, 1.0)
	var edge := minf(outer * half, half - BORDER)
	for attempt in 160:
		var spot := Vector3(rng.randf_range(-edge, edge), 0.0, rng.randf_range(-edge, edge))
		if maxf(absf(spot.x), absf(spot.z)) < inner * half + 4.0:
			continue
		var crowded := false
		for planned in _plan:
			var stronghold: bool = planned.kind == TerritoryNode.Kind.CITADEL or planned.kind == TerritoryNode.Kind.THRONE
			if spot.distance_to(planned.pos) < (STRONGHOLD_SPACING * spacing / TERRITORY_SPACING if stronghold else spacing):
				crowded = true
				break
		if not crowded:
			return spot
	return Vector3.INF


## The world keeps the territories free of trees, landmarks and warbands (the citadels are spawn points already).
func world_clear_areas() -> Array[Vector3]:
	var areas: Array[Vector3] = []
	for planned in _plan:
		if planned.kind != TerritoryNode.Kind.CITADEL:
			areas.append(planned.pos)
	return areas


func world_clear_radius() -> float:
	return TerritoryNode.INFO[TerritoryNode.Kind.THRONE].radius + 3.0


func build_objectives(world: Node3D) -> void:
	super.build_objectives(world)
	add_to_group(&"conquest")
	for i in _plan.size():
		var planned: Dictionary = _plan[i]
		var territory := TerritoryNode.new()
		territory.name = "Territory_%d" % i
		territory.kind = planned.kind
		territory.specialty = int(planned.get("specialty", TerritoryNode.Specialty.NONE)) as TerritoryNode.Specialty
		territory.zone = int(planned.get("zone", zone_of(planned.pos)))
		territory.place_size = int(planned.get("size", TerritoryNode.Size.MEDIUM))
		territory.index = i
		territory.display_name = planned.name
		territory.mode = self
		territory.position = planned.pos
		if planned.owner >= 0:
			territory.start_owned(planned.owner)
		world.add_child(territory)
		territories.append(territory)
	if multiplayer.is_server():
		# With the walls, without the gatehouses (they open, break and come back; the mesh doesn't).
		for territory in territories:
			if territory.gate:
				territory.gate.hide_from_navigation(true)
		_bake_navigation(world)
		for territory in territories:
			if territory.gate:
				territory.gate.hide_from_navigation(false)
	if multiplayer.is_server():
		_raid_timer = Timer.new()
		_raid_timer.wait_time = RAID_EVERY
		_raid_timer.timeout.connect(_raid)
		add_child(_raid_timer)
		_raid_timer.start()
		var batter_timer := Timer.new()
		batter_timer.wait_time = 1.0
		batter_timer.timeout.connect(func() -> void:
			if not is_over:
				_batter())
		add_child(batter_timer)
		batter_timer.start()
	logistics = LogisticsManager.new()
	logistics.mode = self
	add_child(logistics)
	logistics.stock_changed.connect(func() -> void: scores_changed.emit())  # the HUD line shows the stock
	squads = ConquestSquads.new()
	squads.mode = self
	add_child(squads)
	demons = ConquestDemons.new()
	demons.mode = self
	add_child(demons)
	demons.setup(world)


## Server: a navigation mesh of the whole world (ground minus trees, rocks, walls and fences) for soldiers on a
## MARCH order or mustered (Ally). Parsed now, baked on a thread; soldiers walk straight until it is ready.
func _bake_navigation(world: Node3D) -> void:
	var half := GameConfig.world_half
	var mesh := NavigationMesh.new()
	mesh.cell_size = NAV_CELL
	mesh.cell_height = NAV_CELL_HEIGHT
	mesh.agent_radius = 0.5
	mesh.agent_height = 1.5
	mesh.agent_max_climb = 0.25
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_FENCE
	mesh.filter_baking_aabb = AABB(Vector3(-half, -1.0, -half), Vector3(half * 2.0, 4.0, half * 2.0))
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, world)
	# The ground, whatever the map's own ground is made of: units always stand at y = 0.
	var a := Vector3(-half, 0.0, -half)
	var b := Vector3(half, 0.0, -half)
	var c := Vector3(half, 0.0, half)
	var d := Vector3(-half, 0.0, half)
	# Both windings: whichever one the baker reads as facing up makes the ground walkable.
	source.add_faces(PackedVector3Array([a, c, b, a, d, c, a, b, c, a, c, d]), Transform3D.IDENTITY)
	var map := world.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, NAV_CELL)
	NavigationServer3D.map_set_cell_height(map, NAV_CELL_HEIGHT)
	navigation = NavigationRegion3D.new()
	navigation.name = "Navigation"
	world.add_child(navigation)
	NavigationServer3D.bake_from_source_geometry_data_async(mesh, source, func() -> void:
		if is_instance_valid(navigation):
			navigation.navigation_mesh = mesh
			navigation_ready = true)


## Server, every RAID_EVERY s: held places without a standing gate may be raided (more often toward the middle).
## The raiders come from the middle's side and walk to the place (their `home`), fighting what they meet; once
## in the ring with nobody of the holder's, they take it back (TerritoryNode).
func _raid() -> void:
	if is_over:
		return
	_raids = _raids.filter(func(raid: Dictionary) -> bool:
		return (raid.demons as Array).any(func(d: Node) -> bool: return not GameConfig.is_gone(d)))
	for territory in territories:
		if _raids.size() >= RAID_MAX:
			return
		if territory.state != TerritoryNode.State.OWNED or territory.kind == TerritoryNode.Kind.CITADEL:
			continue
		if _raids.any(func(raid: Dictionary) -> bool: return raid.place == territory):
			continue
		if randf() < ZONE_RAID[territory.zone]:
			raid_place(territory)


## Server: sends one raiding party at `territory` (tests call it directly).
func raid_place(territory: TerritoryNode) -> Array[Node]:
	var inward := -territory.position
	inward.y = 0.0
	var start := territory.position + (inward.normalized() if inward.length() > 1.0 else Vector3.FORWARD) * RAID_DISTANCE
	var count := RAID_BASE + RAID_STEP * maxi(5 - territory.zone, 0)
	var rows := mini(1 + TerritoryNode.ZONE_ROWS[territory.zone], WorldEvents.WAVE_TYPES.size())
	var strength := GameConfig.orc_strength * TerritoryNode.ZONE_STRENGTH[territory.zone]
	var demons: Array[Node] = []
	for i in count:
		var types: Array = WorldEvents.WAVE_TYPES[randi() % rows]
		var at := GameConfig.clamp_to_world(start + Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0)))
		var demon := NetSpawn.unit(&"enemy", at, {"scene": WorldEvents.ENEMIES + str(types[randi() % types.size()]) + ".tscn",
				"strength": strength, "coins": 1.0}) as Enemy
		if demon == null:
			continue
		demon.add_to_group(&"active_enemies")
		demon.follow_point(_raid_goal(territory), 1.0)
		demons.append(demon)
	_raids.append({"place": territory, "demons": demons})
	announce("Demons march on %s!" % territory.display_name)
	return demons


## Where raiders head: the gate while it stands (to batter it), else the middle of the ring.
func _raid_goal(territory: TerritoryNode) -> Vector3:
	if territory.gate and not territory.gate.is_broken():
		return territory.gate.outside_point(1.0) + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-1.0, 1.0))
	return territory.position + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))


## Server, every second: raiders at a standing gate batter it; once it is down (or there is none) they go in.
## Returns the damage dealt (tests).
func _batter() -> float:
	var dealt := 0.0
	for raid in _raids:
		var place: TerritoryNode = raid.place
		var gate := place.gate
		var standing := gate != null and not gate.is_broken() and place.state == TerritoryNode.State.OWNED
		for node in raid.demons:
			var demon := node as Enemy
			if GameConfig.is_gone(demon):
				continue
			if standing:
				var at := Ally._flat(demon.global_position - gate.outside_point(1.0)).length()
				if at < BATTER_REACH + gate.size.x * 0.5 and GameConfig.is_gone(demon.target):
					gate.batter(BATTER_DAMAGE * demon.power)
					dealt += BATTER_DAMAGE * demon.power
			demon.follow_point(_raid_goal(place) if standing else place.position, 1.0)
	return dealt


func uses_time_limit() -> bool:
	return true


## Spawn / respawn at the faction's Citadel while it holds it, else at its nearest held territory.
func spawn_point_for(peer: int) -> Vector3:
	var point := super.spawn_point_for(peer)
	var team := Net.team_of(peer)
	if territories.is_empty() or territories[team].owner_team == team:
		return point
	var best := Vector3.INF
	for territory in territories:
		if territory.owner_team == team and (best == Vector3.INF or
				territory.position.distance_to(point) < best.distance_to(point)):
			best = territory.position
	return point if best == Vector3.INF else best


func add_score(key: int, amount: int) -> void:
	super.add_score(key, amount)
	if not is_over and scores.get(key, 0) >= maxi(int(settings.score_limit), SCORE_LIMIT_MIN):
		_finish_by_score()


func throne() -> TerritoryNode:
	return territories[THRONE_INDEX] if territories.size() > THRONE_INDEX else null


## Server (TerritoryNode): a place changed hands. Every Citadel under one banner ends the match.
func on_territory_captured(territory: TerritoryNode, previous: int) -> void:
	if territory.kind == TerritoryNode.Kind.CITADEL and previous >= 0:
		announce("{team:%d} lost their Citadel!" % previous)
	if territory.kind == TerritoryNode.Kind.THRONE:
		announce("{team:%d} took the Demon's Lair! Hold it for %d minutes to rule." % [territory.owner_team,
				THRONE_WIN_TICKS * int(LogisticsManager.TICK) / 60])
	var holder := territories[0].owner_team
	for team in FACTIONS:
		if territories[team].owner_team != holder:
			return
	if holder >= 0:
		finish("{team:%d} wins!" % holder, "Every Citadel flies their banner.")


## Server, every logistics tick: the Throne's clock (it restarts whenever the Throne changes hands).
func on_logistics_tick() -> void:
	var seat := throne()
	if seat == null or is_over:
		return
	var holder := seat.owner_team if seat.state == TerritoryNode.State.OWNED else -1
	if holder != _throne_holder:
		_throne_holder = holder
		throne_ticks = 0
	if holder < 0:
		return
	throne_ticks += 1
	var left := (THRONE_WIN_TICKS - throne_ticks) * int(LogisticsManager.TICK)
	if throne_ticks >= THRONE_WIN_TICKS:
		finish("{team:%d} wins!" % holder, "They held the Demon's Lair and rule the land.")
	elif left == 60:
		announce("{team:%d} rules the Lair in one minute! Take it from them!" % holder)


## Server (Player.request_place_action, the map): an order for place `index` from `player` — its lord, the
## faction's General, or anyone of the faction while it has no lord. `action`: withdraw (the lord takes its gold,
## anywhere), muster (`arg`: a class, TerritoryNode.SOLDIER_KINDS index, or -1 = any: soldiers from its barracks),
## train (`arg`: the class its people are armed with, or TerritoryNode.NO_TRAINING), route (`arg`: a place index,
## TerritoryNode.ROUTE_ARMY or ROUTE_NONE), courier (buy one). muster's `arg` packs the squad size too: class + 10 × size (ConquestSquads.SIZES
## index; `squad_take()`). Returns whether it was done.
func place_action(player: Player, index: int, action: StringName, arg: int) -> bool:
	if player == null or player.is_dead or index < 0 or index >= territories.size() or logistics == null:
		return false
	var place := territories[index]
	if place.state != TerritoryNode.State.OWNED or place.owner_team != player.team_id:
		return false
	var general := logistics.general_of(player.team_id) == player.peer_id
	if place.lord != 0 and place.lord != player.peer_id and not general:
		return false
	var done := false
	match action:
		&"withdraw":
			if place.lord == player.peer_id and place.treasury > 0:
				player.coins += place.treasury
				announce("%s takes %d gold from %s." % [player.display_name, place.treasury, place.display_name])
				place.treasury = 0
				done = true
		&"muster":
			var kind := arg % 10 if arg >= 0 else -1
			var size: int = ConquestSquads.SIZES[clampi(arg / 10, 0, ConquestSquads.SIZES.size() - 1)] if arg >= 0 else LogisticsManager.MAP_TAKE
			done = logistics.muster_from(player, place, kind, size) > 0
		&"train":
			if arg >= TerritoryNode.NO_TRAINING and arg < TerritoryNode.SOLDIER_KINDS.size():
				place.train_kind = arg
				done = true
		&"route":
			var valid := arg == TerritoryNode.ROUTE_NONE or arg == TerritoryNode.ROUTE_ARMY
			if arg >= 0 and arg < territories.size() and arg != index:
				var to := territories[arg]
				valid = to.state == TerritoryNode.State.OWNED and to.owner_team == player.team_id
			if valid:
				place.route = arg
				if arg == TerritoryNode.ROUTE_ARMY and place.lord == 0:
					place.lord = player.peer_id  # its goods go to the army of whoever sends them
					place._send_state()
				done = true
		&"courier":
			done = logistics.buy_courier(player, place)
		&"upgrade":
			done = upgrade_place(place, arg)
	if done:
		logistics.send_places()
	return done


## Server (MalakorTrait.on_died): the King fell. The faction that slew him wins the match: the most damage to him,
## where the killing blow (`killer`) counts KING_BLOW_SHARE of his health extra. Nothing happens when no faction
## hurt him (tests killing him outright).
func king_slain(damage: Dictionary, killer: int, king_health: float) -> int:
	if is_over or damage.is_empty():
		return -1
	var total := 0.0
	for team in damage:
		total += float(damage[team])
	var best := -1
	var best_score := -1.0
	for team in damage:
		var score := float(damage[team]) + (KING_BLOW_SHARE * king_health if team == killer else 0.0)
		if score > best_score:
			best_score = score
			best = team
	var share := roundi(float(damage[best]) / maxf(total, 1.0) * 100.0)
	var blow := "and the killing blow" if best == killer else "{label:%d} struck the killing blow" % killer
	finish("{team:%d} wins!" % best, "They slew Malakor, the Six-Armed Sovereign: %d%% of his wounds, %s." % [share, blow])
	return best


## Server: the next level of upgrade `i` at `place`, paid from its own treasury. Returns whether it was bought.
func upgrade_place(place: TerritoryNode, i: int) -> bool:
	if not place.can_upgrade(i) or place.treasury < place.upgrade_cost(i):
		return false
	var cost := place.upgrade_cost(i)
	place.treasury -= cost
	place.upgrades[i] += 1
	place.apply_upgrades()
	logistics.note(place.owner_team, &"gold", "Upgrades", -cost)
	announce("%s: %s level %d" % [place.display_name, TerritoryNode.UPGRADES[i][1], place.upgrades[i]])
	return true


## Server (Player.request_withdraw, F): the hero empties the treasury of the place they lord and stand in.
func withdraw(player: Player) -> int:
	for territory in territories:
		var taken := territory.withdraw(player)
		if taken > 0:
			announce("%s takes %d gold from %s." % [player.display_name, taken, territory.display_name])
			return taken
	return 0


func _local_hero() -> Player:
	for node in get_tree().get_nodes_in_group(&"players"):
		if (node as Player).peer_id == Net.my_id():
			return node
	return null


## The place at `point` (any state), or null.
func place_at(point: Vector3) -> TerritoryNode:
	for territory in territories:
		var offset := point - territory.global_position
		offset.y = 0.0
		if offset.length() < territory.radius():
			return territory
	return null


## Server (Player, the Army tab): the General musters soldiers from the barracks.
func muster(player: Player) -> int:
	return logistics.muster(player) if logistics else 0


func can_muster(player: Player) -> int:
	return logistics.can_muster(player) if logistics else 0


## Score line plus the "F: take N gold" prompt (the lord standing in a place with gold) and the Lair's holder. The
## faction's supplies, General, meals and warnings are in the HUD's left column (ConquestPanel).
func score_text(tokens: bool = false) -> String:
	var text := super.score_text(tokens)
	if tokens or logistics == null:
		return text
	var me := _local_hero()
	var here := place_at(me.global_position) if me else null
	if here and here.state == TerritoryNode.State.OWNED and here.lord == Net.my_id() and here.treasury > 0:
		text += "\nF: take %d gold from %s" % [here.treasury, here.display_name]
	var seat := throne()
	if seat and seat.state == TerritoryNode.State.OWNED:
		text += "\nDemon's Lair: {label:%d}" % seat.owner_team
	return Net.localize(text) if "{label:" in text else text

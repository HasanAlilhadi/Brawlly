class_name ConquestMode
extends GameMode
## Conquest: three factions, each from its Citadel, fight over Villages, Outposts and Cities. Monsters hold every
## place at the start (kill the guards to liberate it), then a faction raises its banner by standing in the ring;
## places held by another faction need their gate broken first (cities, citadels). Held places pay food,
## equipment and ammo into the faction's stockpile and points into its score every logistics tick
## (LogisticsManager); the army eats and wears its weapons. Win: hold every Citadel, reach the score limit, or
## lead when the time runs out.
## Built on top of GameMode (the base runs teams, spawns, respawns, the clock and the score RPCs unchanged);
## main.gd creates this instead of GameMode only for Net.Mode.CONQUEST. The plan of the territories comes from
## the match seed, so every peer builds the same `Territory_<n>` nodes; the server runs them.

const FACTIONS: int = 3
const VILLAGES: int = 9
const OUTPOSTS: int = 6
## Territories stay this far apart, this far from a citadel and from the map border.
const TERRITORY_SPACING: float = 18.0
const CITADEL_SPACING: float = 24.0
const BORDER: float = 10.0
## Lowest score limit Conquest accepts (the lobby's range starts here; tests may leave the default).
const SCORE_LIMIT_MIN: int = 100
const PLACE_NAMES: PackedStringArray = ["Ashford", "Brightwater", "Coldharbor", "Dunmere", "Eastwatch",
		"Fallowmere", "Greystone", "Hollowell", "Ironbrook", "Juniper Hill", "Kingsmoor", "Larkfield", "Millbrook",
		"Northgate", "Oakhaven", "Pinecrest", "Queensford", "Ravenhold", "Stonebridge", "Thornwick", "Umberlee",
		"Valewood", "Westmarch", "Yarrowby"]
const CITADEL_NAMES: PackedStringArray = ["Highkeep", "Sunspire", "Wolfcrag"]

## Navigation mesh voxels (the map's cell size must match).
const NAV_CELL: float = 0.5
const NAV_CELL_HEIGHT: float = 0.25

## Every territory, in plan order (every peer, after build_objectives).
var territories: Array[TerritoryNode] = []
var logistics: LogisticsManager
## Server: the baked world for marching soldiers (navigation_ready once the bake thread is done).
var navigation: NavigationRegion3D
var navigation_ready: bool = false

## [{kind, pos, owner, name}] from the seed (setup); build_objectives turns it into nodes.
var _plan: Array[Dictionary] = []


func setup(match_settings: Dictionary, players: Dictionary, map: MapDef = null) -> void:
	match_settings.team_count = FACTIONS  # the same dictionary as Net.settings: colors follow on every peer
	super.setup(match_settings, players, map)
	_plan_territories(int(settings.get("seed", 0)))


## Citadels at the faction bases, a City between every two of them and one in the middle, then Outposts and
## Villages scattered (from the seed: every peer plans the same).
func _plan_territories(match_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = match_seed + 4111
	var half := GameConfig.world_half
	var names := Array(PLACE_NAMES)
	for i in names.size():
		var j := rng.randi_range(i, names.size() - 1)
		var swap: Variant = names[i]
		names[i] = names[j]
		names[j] = swap
	for team in FACTIONS:
		_plan.append({"kind": TerritoryNode.Kind.CITADEL, "pos": team_bases[team], "owner": team,
				"name": CITADEL_NAMES[team]})
	_plan.append({"kind": TerritoryNode.Kind.CITY, "pos": Vector3.ZERO, "owner": -1, "name": names[_plan.size() % names.size()]})
	for team in FACTIONS:
		var a := team_bases[team].normalized()
		var b := team_bases[(team + 1) % FACTIONS].normalized()
		var between := (a + b).normalized() if (a + b).length() > 0.01 else a.rotated(Vector3.UP, PI * 0.5)
		_plan.append({"kind": TerritoryNode.Kind.CITY, "pos": between * half * 0.45, "owner": -1,
				"name": names[_plan.size() % names.size()]})
	for kind in [TerritoryNode.Kind.OUTPOST, TerritoryNode.Kind.VILLAGE]:
		var count := OUTPOSTS if kind == TerritoryNode.Kind.OUTPOST else VILLAGES
		for i in count:
			var spot := _free_spot(rng, half)
			if spot != Vector3.INF:
				_plan.append({"kind": kind, "pos": spot, "owner": -1, "name": names[_plan.size() % names.size()]})


func _free_spot(rng: RandomNumberGenerator, half: float) -> Vector3:
	for attempt in 80:
		var angle := rng.randf() * TAU
		var r := rng.randf_range(0.2, 0.9) * half
		var spot := Vector3(cos(angle), 0.0, sin(angle)) * minf(r, half - BORDER)
		var crowded := false
		for planned in _plan:
			var apart := CITADEL_SPACING if planned.kind == TerritoryNode.Kind.CITADEL else TERRITORY_SPACING
			if spot.distance_to(planned.pos) < apart:
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
	return TerritoryNode.INFO[TerritoryNode.Kind.CITY].radius + 2.0


func build_objectives(world: Node3D) -> void:
	super.build_objectives(world)
	if multiplayer.is_server():
		_bake_navigation(world)  # before the gatehouses exist: they break and come back, the mesh doesn't
	for i in _plan.size():
		var planned: Dictionary = _plan[i]
		var territory := TerritoryNode.new()
		territory.name = "Territory_%d" % i
		territory.kind = planned.kind
		territory.display_name = planned.name
		territory.mode = self
		territory.position = planned.pos
		if planned.owner >= 0:
			territory.start_owned(planned.owner)
		world.add_child(territory)
		territories.append(territory)
	logistics = LogisticsManager.new()
	logistics.mode = self
	add_child(logistics)
	logistics.stock_changed.connect(func() -> void: scores_changed.emit())  # the HUD line shows the stock


## Server: a navigation mesh of the whole world (ground minus trees, rocks, walls and fences) for soldiers on a
## MARCH order (Ally._think_march). Parsed now, baked on a thread; soldiers walk straight until it is ready.
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


## Server (TerritoryNode): a place changed hands. Every Citadel under one banner ends the match.
func on_territory_captured(territory: TerritoryNode, previous: int) -> void:
	if territory.kind == TerritoryNode.Kind.CITADEL and previous >= 0:
		announce("{team:%d} lost their Citadel!" % previous)
	var holder := territories[0].owner_team
	for team in FACTIONS:
		if territories[team].owner_team != holder:
			return
	if holder >= 0:
		finish("{team:%d} wins!" % holder, "Every Citadel flies their banner.")


## Score line plus this device's faction stockpile with income and upkeep per tick
## ("Food 40 (+10 -13)  Equip 12 (+6)  Ammo 33 (+4)  Army +7", "STARVING" when short).
func score_text(tokens: bool = false) -> String:
	var text := super.score_text(tokens)
	if tokens or logistics == null:
		return text
	var mine := logistics.stock_of(Net.team_of(Net.my_id()))
	if mine.is_empty():
		return text
	var income: Dictionary = mine[&"income"]
	text += "   Food %d (+%d -%d)  Equip %d (+%d)  Ammo %d (+%d)" % [mine[&"food"], income.get(&"food", 0),
			mine[&"food_need"], mine[&"equipment"], income.get(&"equipment", 0), mine[&"ammo"], income.get(&"ammo", 0)]
	if mine[&"cap_bonus"] > 0:
		text += "  Army +%d" % mine[&"cap_bonus"]
	if mine[&"starving"]:
		text += "  STARVING"
	return text

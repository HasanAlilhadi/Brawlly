class_name WorldBuilder
extends RefCounted
## Procedurally builds the world: ground, border fence, an open spawn area at each spawn point (with a starter
## chest), graveyards (Graveyard Kit: iron fence, rows of gravestones, a crypt, lanterns, crooked pines),
## roaming warbands, forests, chests and decoration.
## Warbands farther from the start are bigger (3 → 24 members) and so stronger; the undead gather around the
## graveyards, orcs everywhere else. Decoration uses chunked MultiMeshes (one draw call per chunk, culled
## off-screen) to stay cheap on mobile.

const ORC_ROSTER := preload("res://resources/data/orc_warband.tres")
const UNDEAD_ROSTER := preload("res://resources/data/undead_warband.tres")
const GRAVEYARD_DIR := "res://assets/environment/graveyard/"
## Graveyard Kit pieces are drawn this much bigger (a gravestone reaches a hero's chest).
const GRAVEYARD_SCALE: float = 1.5
## Half the side of a graveyard's iron fence square (m).
const GRAVEYARD_HALF: float = 7.5
const GRAVESTONES: PackedStringArray = ["gravestone_bevel", "gravestone_cross", "gravestone_cross_large",
		"gravestone_decorative", "gravestone_roof", "gravestone_round", "gravestone_wide", "gravestone_broken", "cross", "cross_wood"]
const GRAVEYARD_GROUND := Color(0.36, 0.4, 0.29)
const TREE_SCENE := preload("res://scenes/world/choppable_tree.tscn")
const CHEST_SCENE := preload("res://scenes/world/chest.tscn")
## Radius around each spawn point kept free of trees, warbands, chests and scattered decor.
const SPAWN_SAFE_RADIUS: float = 14.0
## Where each spawn's starter chest stands, relative to the spawn point (the same for every spawn).
const STARTER_CHEST_OFFSET := Vector3(2.3, 0.0, -2.9)

const FENCE_MODEL := "res://assets/environment/forest/fence.glb"
const GRASS_MODEL := "res://assets/environment/forest/patch_grass.glb"
const DIRT_MODEL := "res://assets/environment/forest/patch_dirt.glb"
const PLANT_MODEL := "res://assets/environment/forest/plant.glb"
const STONES_MODEL := "res://assets/environment/forest/stones.glb"

const GROUND_COLOR := Color(0.44, 0.69, 0.35)
const CHUNK_SIZE: float = 40.0
const WAVE_GATE_RADIUS: float = 5.0

## The map being built (its `layout` = a designed map; none = the procedural Wildlands).
var map: MapDef
var band_count: int = 20
## Graveyards (0 = from band_count: one per ~6 bands, 1..5).
var graveyard_count: int = 0
## Animal groups grazing around the map (AnimalHerd); each species gets its share.
var herd_count: int = 16
## Herds stay this far from spawn points (wild pigs: twice as far) and this far apart.
var herd_spawn_distance: float = 14.0
var herd_spacing: float = 14.0
var tree_count: int = 520
var chest_count: int = 35
## No warband starts (or marches) closer than this to a spawn point, so players never start next to enemies.
var spawn_band_distance: float = 24.0
## Player / team spawn points (set by main from the game mode). Warbands get bigger away from them.
var spawn_points: Array[Vector3] = [Vector3.ZERO]
## Extra areas kept clear with `clear_radius` (e.g. the King of the Hill zone).
var clear_areas: Array[Vector3] = []
var clear_radius: float = 9.0
var min_band_spacing: float = 20.0
var min_squad: int = 3
var max_squad: int = 24

var _world: Node3D
var _half: float = GameConfig.world_half
var _occupied: PackedVector3Array = PackedVector3Array()  # (x, z, radius)
var _noise := FastNoiseLite.new()
var _chest_count: int = 0
var _graveyards: Array[Vector3] = []
var _herds: int = 0
## Where invasion waves come in (set by main from the map; empty = the middle of each edge).
static var wave_entries: PackedVector3Array = PackedVector3Array()


func build(world: Node3D) -> Array[Warband]:
	_world = world
	if map and map.layout:
		return _build_layout()
	_noise.seed = randi()
	_noise.frequency = 0.035
	for point in spawn_points:
		_occupy(point, SPAWN_SAFE_RADIUS)
	for area in clear_areas:
		_occupy(area, clear_radius)
	# Keep the four invasion gates free of warbands, chests and trees so waves can visibly march inward.
	for gate in wave_entry_points():
		_occupy(gate, WAVE_GATE_RADIUS)
	_add_ground()
	_add_border()
	_add_graveyards()
	var bands := _add_warbands()
	_add_herds()
	_add_chests()
	_add_trees()
	_add_decor()
	return bands


# --- Designed maps ---------------------------------------------------------------------

## A designed map: ground and border, the layout scene (pieces with their collision), then what its markers
## ask for — warbands, chests, choppable trees, animal herds — plus a starter chest at every spawn and light grass.
func _build_layout() -> Array[Warband]:
	_noise.seed = randi()
	for point in spawn_points:
		_occupy(point, SPAWN_SAFE_RADIUS)
	_add_ground()
	_add_border()
	var layout := map.layout.instantiate() as Node3D
	layout.name = "Layout"
	_world.add_child(layout)
	var bands: Array[Warband] = []
	var trees := 0
	var markers := layout.get_node("Markers")
	for node in markers.get_children():
		var spot := (node as Node3D).global_position
		var kind := String(node.name).get_slice("_", 0)
		match kind:
			"Band":
				bands.append(_make_band(bands.size(), spot, StringName(node.get_meta("faction", "orc")),
						int(node.get_meta("size", 6)), float(node.get_meta("territory", 12.0))))
			"Chest":
				_place_chest(spot, int(node.get_meta("rarity", Chest.Rarity.COMMON)))
			"Herd":
				_make_herd(spot, String(node.get_meta("species", "deer")))
			"Tree":
				var tree := TREE_SCENE.instantiate() as Node3D
				tree.name = "Tree_%d" % trees
				tree.position = spot
				tree.scale = Vector3.ONE * randf_range(1.0, 1.35)
				_world.add_child(tree)
				trees += 1
	for point in spawn_points:
		_place_chest(point + STARTER_CHEST_OFFSET, Chest.Rarity.UNCOMMON)
	for area in clear_areas:
		_occupy(area, clear_radius)
	_scatter(GRASS_MODEL, 160, 0.8, 1.5, true)
	_scatter(PLANT_MODEL, 220, 1.0, 1.6, true)
	return bands


# --- Placement helpers --------------------------------------------------------

func _occupy(pos: Vector3, radius: float) -> void:
	_occupied.append(Vector3(pos.x, pos.z, radius))


func _is_free(pos: Vector3, radius: float) -> bool:
	for o in _occupied:
		if Vector2(pos.x - o.x, pos.z - o.y).length() < radius + o.z:
			return false
	return true


func _random_point(margin: float) -> Vector3:
	return Vector3(randf_range(-_half + margin, _half - margin), 0.0, randf_range(-_half + margin, _half - margin))


static func wave_entry_points() -> PackedVector3Array:
	if not wave_entries.is_empty():
		return wave_entries
	var edge := GameConfig.world_half - 3.0
	return PackedVector3Array([
		Vector3(0.0, 0.0, -edge),
		Vector3(edge, 0.0, 0.0),
		Vector3(0.0, 0.0, edge),
		Vector3(-edge, 0.0, 0.0),
	])


# --- Content ------------------------------------------------------------------

func _add_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (_half * 2.0 + 40.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = map.ground_color if map else GROUND_COLOR
	material.roughness = 1.0
	plane.material = material
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = plane
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(ground)


func _add_border() -> void:
	var transforms: Array[Transform3D] = []
	var edge := _half + 0.6
	var count := ceili(_half * 2.0 / 1.05)
	for i in count + 1:
		var t := -_half + i * 1.05
		transforms.append(Transform3D(Basis(), Vector3(t, 0, -edge)))
		transforms.append(Transform3D(Basis(), Vector3(t, 0, edge)))
		transforms.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-edge, 0, t)))
		transforms.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(edge, 0, t)))
	_add_multimesh(FENCE_MODEL, transforms, true)


## Animal herds in open ground away from the spawns and warbands; species take turns so each gets herds.
func _add_herds() -> void:
	var species: Array = Animal.SPECIES.keys()
	var placed: Array[Vector3] = []
	var tries := 0
	while placed.size() < herd_count and tries < 4000:
		tries += 1
		var id: String = species[placed.size() % species.size()]
		var pos := _random_point(8.0)
		var away := herd_spawn_distance * (2.0 if id == "hog" else 1.0)
		if _distance_to_spawn(pos) < away or not _is_free(pos, 4.0):
			continue
		var too_close := false
		for other in placed:
			if pos.distance_to(other) < herd_spacing:
				too_close = true
				break
		if too_close:
			continue
		placed.append(pos)
		_occupy(pos, 2.5)  # a little meadow: no trees right on top of it
		_make_herd(pos, id)


func _make_herd(pos: Vector3, species: String) -> AnimalHerd:
	var herd := AnimalHerd.new()
	herd.name = "Herd_%d" % _herds
	_herds += 1
	herd.species = species
	var sizes: Vector2i = AnimalHerd.SIZES[species]
	herd.size = randi_range(sizes.x, sizes.y)
	herd.position = pos
	_world.add_child(herd)
	return herd


## Warbands: one marching out of each graveyard's gate (undead), the rest spread over the map,
## bigger far from the spawns; the undead near graveyards, orcs elsewhere (a few undead stray among them).
func _add_warbands() -> Array[Warband]:
	var bands: Array[Warband] = []
	var positions: Array[Vector3] = []
	for yard in _graveyards:
		if bands.size() >= band_count:
			break
		var gate := yard + Vector3(0.0, 0.0, GRAVEYARD_HALF + 3.0)
		positions.append(gate)
		bands.append(_make_band(bands.size(), gate, &"undead"))
	var tries := 0
	while bands.size() < band_count and tries < 5000:
		tries += 1
		var pos := _random_point(8.0)
		if _distance_to_spawn(pos) < spawn_band_distance or not _is_free(pos, 3.0):
			continue
		var too_close := false
		for other in positions:
			if pos.distance_to(other) < min_band_spacing:
				too_close = true
				break
		if too_close:
			continue
		positions.append(pos)
		var undead := _distance_to_graveyard(pos) < 34.0 or randf() < 0.2
		bands.append(_make_band(bands.size(), pos, &"undead" if undead else &"orc"))
	return bands


## `size` / `territory` < 0: from the distance to the spawns.
func _make_band(index: int, pos: Vector3, faction: StringName, size: int = -1, territory: float = -1.0) -> Warband:
	_occupy(pos, 3.0)
	var band := Warband.new()
	band.name = "Warband_%d" % index
	band.faction = faction
	band.roster = UNDEAD_ROSTER if faction == &"undead" else ORC_ROSTER
	band.size = size if size > 0 else _band_size_at(pos)
	band.tier = clampf(float(band.size - min_squad) / float(max_squad - min_squad), 0.0, 1.0)
	band.territory = territory if territory > 0.0 else 22.0 + band.size * 0.8
	band.avoid_points = spawn_points.duplicate()
	band.avoid_points.append_array(clear_areas)
	band.avoid_radius = spawn_band_distance
	band.position = pos
	_world.add_child(band)
	return band


func _distance_to_graveyard(pos: Vector3) -> float:
	var best := INF
	for yard in _graveyards:
		best = minf(best, pos.distance_to(yard))
	return best


## Inside the open area around a spawn point (no grass / plants / stones scattered there).
func _in_spawn_area(pos: Vector3) -> bool:
	for point in spawn_points:
		if Vector2(pos.x - point.x, pos.z - point.z).length() < SPAWN_SAFE_RADIUS:
			return true
	return false


func _distance_to_spawn(pos: Vector3) -> float:
	var best := INF
	for point in spawn_points:
		best = minf(best, pos.distance_to(point))
	return best


## 0 near a spawn … 1 far away (drives band size, and so its power).
func _tier_at(pos: Vector3) -> float:
	var far := _half * 1.2 - spawn_band_distance
	return clampf((_distance_to_spawn(pos) - spawn_band_distance) / far, 0.0, 1.0)


## Bands grow with distance from the start: 3-4 nearby, 20-25 at the far edges.
func _band_size_at(pos: Vector3) -> int:
	var t := _tier_at(pos)
	# Curved so most of the map is small/medium bands; the big ones roam near the edges.
	return clampi(roundi(lerpf(min_squad, max_squad, pow(t, 1.5))) + randi_range(-1, 1), min_squad, max_squad + 1)


# --- Graveyards ---------------------------------------------------------------------

func _add_graveyards() -> void:
	var count := graveyard_count if graveyard_count > 0 else clampi(roundi(band_count / 6.0), 1, 5)
	if band_count <= 0:
		count = 0
	var tries := 0
	while _graveyards.size() < count and tries < 3000:
		tries += 1
		var pos := _random_point(GRAVEYARD_HALF + 8.0)
		if _distance_to_spawn(pos) < spawn_band_distance + GRAVEYARD_HALF + 4.0 or not _is_free(pos, GRAVEYARD_HALF * 1.6):
			continue
		var too_close := false
		for other in _graveyards:
			if pos.distance_to(other) < 45.0:
				too_close = true
		if too_close:
			continue
		_occupy(pos, GRAVEYARD_HALF * 1.5)
		_graveyards.append(pos)
		_build_graveyard(pos, _graveyards.size() - 1)


## An iron-fenced square (gate toward +Z, a gap or two where the fence fell) with rows of gravestones and
## mounds along a path, a crypt at the back, lanterns at the gate, pumpkins / candles / urns between the
## graves and crooked pines outside. Solid pieces get box collision (world layer): cover from arrows, and
## AI walks around them.
func _build_graveyard(center: Vector3, index: int) -> void:
	var root := Node3D.new()
	root.name = "Graveyard_%d" % index
	root.position = center
	_world.add_child(root)
	var earth := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = GRAVEYARD_HALF * 1.42
	disc.bottom_radius = disc.top_radius
	disc.height = 0.02
	disc.radial_segments = 40
	var earth_material := StandardMaterial3D.new()
	earth_material.albedo_color = GRAVEYARD_GROUND
	earth_material.roughness = 1.0
	disc.material = earth_material
	earth.mesh = disc
	earth.position.y = 0.011
	earth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(earth)
	_graveyard_fence(root)
	# Rows of graves on both sides of the path from the gate (+Z) to the crypt (-Z).
	var z := GRAVEYARD_HALF - 2.6
	while z > -GRAVEYARD_HALF + 4.5:
		for x in [-5.6, -3.4, 3.4, 5.6]:
			if randf() < 0.18:
				continue
			var spot := Vector3(x + randf_range(-0.25, 0.25), 0.0, z)
			var stone: String = GRAVESTONES[randi() % GRAVESTONES.size()]
			_graveyard_piece(root, stone, spot, randf_range(-0.15, 0.15), true)
			if randf() < 0.6:
				_graveyard_piece(root, "grave" if randf() < 0.6 else "grave_border", spot + Vector3(0, 0, 1.0), 0.0, false)
			if randf() < 0.25:
				var extra: String = ["pumpkin", "pumpkin_carved", "candle", "candle_multiple", "urn_round", "lantern_candle"][randi() % 6]
				_graveyard_piece(root, extra, spot + Vector3(randf_range(-0.6, 0.6), 0, randf_range(0.4, 1.6)), randf() * TAU, false)
		z -= 2.5
	# The crypt at the back, with pillars and a fire basket.
	_graveyard_piece(root, "crypt", Vector3(0, 0, -GRAVEYARD_HALF + 2.1), PI, true, GRAVEYARD_SCALE * 1.8)
	for side in [-1.0, 1.0]:
		_graveyard_piece(root, "pillar_obelisk", Vector3(side * 2.3, 0, -GRAVEYARD_HALF + 2.2), 0.0, true)
		_graveyard_piece(root, "lightpost_single", Vector3(side * 1.6, 0, GRAVEYARD_HALF - 0.9), PI * 0.5 * (1.0 - side), true)
	_graveyard_piece(root, "fire_basket", Vector3(1.4, 0, -GRAVEYARD_HALF + 4.2), 0.0, false)
	_graveyard_piece(root, "coffin_old", Vector3(-1.6, 0, -GRAVEYARD_HALF + 4.4), 0.3, false)
	for i in 3:
		_graveyard_piece(root, "debris" if i % 2 == 0 else "gravestone_debris",
				Vector3(randf_range(-5.5, 5.5), 0, randf_range(-3.0, 4.0)), randf() * TAU, false)
	# Crooked pines around the outside.
	for i in 7:
		var angle := randf() * TAU
		var spot := Vector3(cos(angle), 0, sin(angle)) * GRAVEYARD_HALF * randf_range(1.2, 1.45)
		if spot.z > GRAVEYARD_HALF * 0.8 and absf(spot.x) < 3.5:
			continue  # keep the way to the gate clear
		var pine: String = ["pine", "pine_crooked", "pine_fall", "pine_fall_crooked"][randi() % 4]
		_graveyard_piece(root, pine, spot, randf() * TAU, true, GRAVEYARD_SCALE * randf_range(1.0, 1.3))


## The iron fence around the square: one piece per 1.5 m, a 3 m gate gap in the middle of the +Z side
## (pillars on both ends) and one fallen-down gap on another side, a few damaged pieces.
func _graveyard_fence(root: Node3D) -> void:
	var piece := GRAVEYARD_SCALE  # one fence piece is 1 m wide before scaling
	var per_side := roundi(GRAVEYARD_HALF * 2.0 / piece)
	var broken_side := randi_range(1, 3)
	var broken_at := randi_range(1, per_side - 2)
	for side in 4:
		var yaw := side * PI * 0.5
		for i in per_side:
			var along := -GRAVEYARD_HALF + piece * (i + 0.5)
			if side == 0 and absf(along) < piece:
				continue  # the gate
			if side == broken_side and i == broken_at:
				continue  # fallen down
			var local := Vector3(along, 0.0, GRAVEYARD_HALF).rotated(Vector3.UP, yaw)
			var model := "iron_fence_damaged" if randf() < 0.12 else "iron_fence"
			_graveyard_piece(root, model, local, yaw + PI, true)
		var corner := Vector3(GRAVEYARD_HALF, 0.0, GRAVEYARD_HALF).rotated(Vector3.UP, yaw)
		_graveyard_piece(root, "border_pillar", corner, 0.0, true)
	for x in [-piece, piece]:
		_graveyard_piece(root, "pillar_square", Vector3(x, 0.0, GRAVEYARD_HALF), 0.0, true)


## Places a Graveyard Kit model under `root` (local `at`, turned `yaw`); `solid`: with box collision.
func _graveyard_piece(root: Node3D, model: String, at: Vector3, yaw: float, solid: bool, scale: float = GRAVEYARD_SCALE) -> void:
	KitProps.place(root, GRAVEYARD_DIR + model + ".glb", at, yaw, scale, solid)


func _add_chests() -> void:
	# Every player/team receives the same Uncommon starter chest next to its spawn; random starter rarity would
	# be unfair in PvP.
	for point in spawn_points:
		_place_chest(point + STARTER_CHEST_OFFSET, Chest.Rarity.UNCOMMON)
	var placed := spawn_points.size()
	var tries := 0
	while placed < chest_count and tries < 4000:
		tries += 1
		var pos := _random_point(3.0)
		if _distance_to_spawn(pos) < 10.0 or not _is_free(pos, 1.5):
			continue
		_place_chest(pos)
		placed += 1


func _place_chest(pos: Vector3, forced_rarity: int = -1) -> void:
	_occupy(pos, 1.5)
	var chest := CHEST_SCENE.instantiate() as Chest
	chest.rarity = forced_rarity as Chest.Rarity if forced_rarity >= 0 else Chest.roll_rarity()
	chest.name = "Chest_%d_%s" % [_chest_count, Chest.DEFINITIONS[chest.rarity].name]
	_chest_count += 1
	chest.position = pos
	chest.rotation.y = randf() * TAU
	_world.add_child(chest)


func _add_trees() -> void:
	var placed := 0
	var tries := 0
	while placed < tree_count and tries < tree_count * 12:
		tries += 1
		var pos := _random_point(1.5)
		# Noise makes forests and open clearings instead of uniform scatter.
		var density := _noise.get_noise_2d(pos.x, pos.z)
		if density < -0.1 or randf() > (density + 0.1) * 2.0:
			continue
		if not _is_free(pos, 0.9):
			continue
		_occupy(pos, 0.9)
		var tree := TREE_SCENE.instantiate() as Node3D
		tree.name = "Tree_%d" % placed
		tree.position = pos
		tree.scale = Vector3.ONE * randf_range(1.0, 1.4)
		_world.add_child(tree)
		placed += 1


func _add_decor() -> void:
	_scatter(GRASS_MODEL, 420, 0.8, 1.6)
	_scatter(DIRT_MODEL, 90, 0.8, 1.4)
	_scatter(PLANT_MODEL, 650, 1.0, 1.8)
	_scatter(STONES_MODEL, 110, 0.5, 0.9)


## `clear_only`: also keep off the occupied spots (designed maps: the hill).
func _scatter(model_path: String, count: int, min_scale: float, max_scale: float, clear_only: bool = false) -> void:
	var transforms: Array[Transform3D] = []
	for i in count:
		var pos := _random_point(1.0)
		var basis := Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * randf_range(min_scale, max_scale))
		if clear_only and not _is_free(pos, 0.0):
			continue
		if not _in_spawn_area(pos) and _distance_to_graveyard(pos) > GRAVEYARD_HALF * 1.3:
			transforms.append(Transform3D(basis, pos))
	_add_multimesh(model_path, transforms, false)


## Builds one MultiMeshInstance3D per CHUNK_SIZE cell so off-screen chunks get culled.
func _add_multimesh(model_path: String, transforms: Array[Transform3D], shadows: bool) -> void:
	var source := (load(model_path) as PackedScene).instantiate()
	var mesh_node := source.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var mesh_offset := Transform3D()
	var node: Node = mesh_node
	while node != source:
		mesh_offset = (node as Node3D).transform * mesh_offset
		node = node.get_parent()
	var mesh := mesh_node.mesh
	source.free()

	var chunks := {}
	for t in transforms:
		var key := Vector2i(floori(t.origin.x / CHUNK_SIZE), floori(t.origin.z / CHUNK_SIZE))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(t * mesh_offset)
	for key in chunks:
		var list: Array = chunks[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = list.size()
		for i in list.size():
			multimesh.set_instance_transform(i, list[i])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		if not shadows:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world.add_child(instance)

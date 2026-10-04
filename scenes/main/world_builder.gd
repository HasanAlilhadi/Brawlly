class_name WorldBuilder
extends RefCounted
## Procedurally builds the world: ground, border fence, an open spawn area at each spawn point (with a starter
## chest), orc camps, forests, chests and decoration.
## Camps farther from the start get bigger squads (4 → 24 orcs) and bigger houses. Decoration uses chunked MultiMeshes
## (one draw call per chunk, culled off-screen) to stay cheap on mobile.

const CAMP_SCENE := preload("res://scenes/world/camp.tscn")
const TREE_SCENE := preload("res://scenes/world/choppable_tree.tscn")
const CHEST_SCENE := preload("res://scenes/world/chest.tscn")
## Radius around each spawn point kept free of trees, camps, chests and scattered decor.
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

var camp_count: int = 20
## Animal groups grazing around the map (AnimalHerd); each species gets its share.
var herd_count: int = 16
## Herds stay this far from spawn points (wild pigs: twice as far) and this far apart.
var herd_spawn_distance: float = 14.0
var herd_spacing: float = 14.0
var tree_count: int = 520
var chest_count: int = 35
## No camp closer than this to a spawn point, so players never start next to orcs.
var spawn_camp_distance: float = 24.0
## Player / team spawn points (set by main from the game mode). Camps get harder away from them.
var spawn_points: Array[Vector3] = [Vector3.ZERO]
## Extra areas kept clear with `clear_radius` (e.g. the King of the Hill zone).
var clear_areas: Array[Vector3] = []
var clear_radius: float = 9.0
var min_camp_spacing: float = 22.0
var min_camp_distance_from_spawn: float = 20.0
var min_squad: int = 4
var max_squad: int = 24

var _world: Node3D
var _half: float = GameConfig.world_half
var _occupied: PackedVector3Array = PackedVector3Array()  # (x, z, radius)
var _noise := FastNoiseLite.new()
var _chest_count: int = 0


func build(world: Node3D) -> Array[Camp]:
	_world = world
	_noise.seed = randi()
	_noise.frequency = 0.035
	for point in spawn_points:
		_occupy(point, SPAWN_SAFE_RADIUS)
	for area in clear_areas:
		_occupy(area, clear_radius)
	# Keep the four invasion gates free of camps, chests and trees so waves can visibly march inward.
	for gate in wave_entry_points():
		_occupy(gate, WAVE_GATE_RADIUS)
	_add_ground()
	_add_border()
	var camps := _add_camps()
	_add_herds()
	_add_chests()
	_add_trees()
	_add_decor()
	return camps


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
	material.albedo_color = GROUND_COLOR
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


## Animal herds in open ground away from the spawns and camps; species take turns so each gets herds.
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
		var herd := AnimalHerd.new()
		herd.name = "Herd_%d" % (placed.size() - 1)
		herd.species = id
		var sizes: Vector2i = AnimalHerd.SIZES[id]
		herd.size = randi_range(sizes.x, sizes.y)
		herd.position = pos
		_world.add_child(herd)


func _add_camps() -> Array[Camp]:
	var camps: Array[Camp] = []
	var positions: Array[Vector3] = []
	var tries := 0
	while camps.size() < camp_count and tries < 5000:
		tries += 1
		var pos := _random_point(8.0)
		if _distance_to_spawn(pos) < maxf(min_camp_distance_from_spawn, spawn_camp_distance) \
				or not _is_free(pos, 5.0):
			continue
		var too_close := false
		for other in positions:
			if pos.distance_to(other) < min_camp_spacing:
				too_close = true
				break
		if too_close:
			continue
		positions.append(pos)
		var squad := _squad_size_at(pos)
		var camp_scale := Camp.scale_for_squad(squad)
		# Clearing big enough for the house plus its rings of orcs.
		_occupy(pos, 4.5 * camp_scale + sqrt(squad) * 0.6)
		var camp := CAMP_SCENE.instantiate() as Camp
		camp.name = "Camp_%d" % camps.size()
		camp.squad_size = squad
		camp.tier = _tier_at(pos)
		camp.scale = Vector3.ONE * camp_scale
		camp.position = pos
		camp.rotation.y = randf_range(-0.4, 0.4)
		_world.add_child(camp)
		camps.append(camp)
	return camps


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


## 0 near a spawn … 1 far away (drives squad size and orc strength).
func _tier_at(pos: Vector3) -> float:
	var far := _half * 1.2 - min_camp_distance_from_spawn
	return clampf((_distance_to_spawn(pos) - min_camp_distance_from_spawn) / far, 0.0, 1.0)


## Squads grow with distance from the start: ~4-5 orcs nearby, 20-25 at the far edges.
func _squad_size_at(pos: Vector3) -> int:
	var t := _tier_at(pos)
	# Curved so most of the map is small/medium camps; the big ones sit near the edges.
	return clampi(roundi(lerpf(min_squad, max_squad, pow(t, 1.6))) + randi_range(-1, 1), min_squad - 1, max_squad + 1)


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


func _scatter(model_path: String, count: int, min_scale: float, max_scale: float) -> void:
	var transforms: Array[Transform3D] = []
	for i in count:
		var pos := _random_point(1.0)
		var basis := Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * randf_range(min_scale, max_scale))
		if not _in_spawn_area(pos):
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

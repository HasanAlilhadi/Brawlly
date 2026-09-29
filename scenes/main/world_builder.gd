class_name WorldBuilder
extends RefCounted
## Procedurally builds the world: ground, border fence, a town at each spawn (always the same layout, holding the
## shop stalls), orc camps, forests, chests and decoration.
## Camps farther from the start get bigger squads (4 → 24 orcs) and bigger houses. Decoration uses chunked MultiMeshes
## (one draw call per chunk, culled off-screen) to stay cheap on mobile.

const CAMP_SCENE := preload("res://scenes/world/camp.tscn")
const TREE_SCENE := preload("res://scenes/world/choppable_tree.tscn")
const CHEST_SCENE := preload("res://scenes/world/chest.tscn")
const STALL_SCENE := preload("res://scenes/world/shop_station.tscn")
## The town (tools/blender_town.py): decoration + collision, markers "Stall_<id>" where the stalls stand,
## "Tree_<n>" for choppable trees and "StarterChest". Never rotated, so every town looks the same.
const TOWN_SCENE := preload("res://assets/environment/buildings/town.tscn")
## Radius around a town's center (the spawn point) kept free of trees, camps, chests and scattered decor.
const TOWN_RADIUS: float = 14.0

const FENCE_MODEL := "res://assets/environment/forest/fence.glb"
const GRASS_MODEL := "res://assets/environment/forest/patch_grass.glb"
const DIRT_MODEL := "res://assets/environment/forest/patch_dirt.glb"
const PLANT_MODEL := "res://assets/environment/forest/plant.glb"
const STONES_MODEL := "res://assets/environment/forest/stones.glb"

const GROUND_COLOR := Color(0.44, 0.69, 0.35)
const CHUNK_SIZE: float = 40.0
const TOWN_MARKER_COLOR: Color = Color(1.0, 0.78, 0.28)
const WAVE_GATE_RADIUS: float = 5.0

var camp_count: int = 20
var tree_count: int = 520
var chest_count: int = 35
## No camp closer than this to a stall, so shopping is safe from orcs.
var stall_safe_distance: float = 17.0
## Player / team spawn points (set by main from the game mode). Camps get harder away from them.
var spawn_points: Array[Vector3] = [Vector3.ZERO]
## Access rule for each town in `spawn_points` (same index). See GameMode.world_town_access().
var town_access: Array[Dictionary] = []
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
var _stalls: Array[Vector3] = []
## Ground the stall buildings cover (x, z, radius): no grass / plants / stones scattered there.
var _stall_areas: Array[Vector3] = []
## Where each town's starter chest goes (its "StarterChest" marker).
var _starter_chests: Array[Vector3] = []


func build(world: Node3D) -> Array[Camp]:
	_world = world
	_noise.seed = randi()
	_noise.frequency = 0.035
	for point in spawn_points:
		_occupy(point, TOWN_RADIUS)
	for area in clear_areas:
		_occupy(area, clear_radius)
	# Keep the four invasion gates free of camps, chests and trees so waves can visibly march inward.
	for gate in wave_entry_points():
		_occupy(gate, WAVE_GATE_RADIUS)
	_add_ground()
	_add_border()
	_add_towns()
	var camps := _add_camps()
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


func _add_camps() -> Array[Camp]:
	var camps: Array[Camp] = []
	var positions: Array[Vector3] = []
	var tries := 0
	while camps.size() < camp_count and tries < 5000:
		tries += 1
		var pos := _random_point(8.0)
		if _distance_to_spawn(pos) < min_camp_distance_from_spawn or not _is_free(pos, 5.0) \
				or _near_stall(pos, stall_safe_distance):
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


## A town at every spawn point; its markers say where each stall (and the starter chest) goes.
func _add_towns() -> void:
	for p in spawn_points.size():
		var center := spawn_points[p]
		var access: Dictionary = town_access[p] if p < town_access.size() else {}
		var town := TOWN_SCENE.instantiate() as Node3D
		town.name = "Town_%d" % p
		town.position = center
		town.add_to_group(&"towns")
		town.set_meta(&"owner_peer", int(access.get("owner_peer", 0)))
		town.set_meta(&"team_id", int(access.get("team_id", -1)))
		_world.add_child(town)
		_add_town_identity(town, access)
		_stall_areas.append(Vector3(center.x, center.z, TOWN_RADIUS))
		for spot in town.get_children():
			if spot.name == &"StarterChest":
				_starter_chests.append((spot as Node3D).global_position)
			if String(spot.name).begins_with("Tree_"):  # the same choppable trees as the forest
				var tree := TREE_SCENE.instantiate() as Node3D
				tree.name = "TownTree_%d_%s" % [p, String(spot.name).trim_prefix("Tree_")]
				tree.position = (spot as Node3D).global_position
				tree.scale = Vector3.ONE * randf_range(1.0, 1.3)
				_world.add_child(tree)
			if not String(spot.name).begins_with("Stall_"):
				continue
			var id := StringName(String(spot.name).trim_prefix("Stall_"))
			var stall := STALL_SCENE.instantiate() as ShopStation
			stall.name = "Stall_%d_%s" % [p, id]
			stall.stall_id = id
			stall.access_owner_peer = int(access.get("owner_peer", 0))
			stall.access_team_id = int(access.get("team_id", -1))
			stall.position = (spot as Node3D).global_position
			stall.rotation.y = (spot as Node3D).rotation.y
			_world.add_child(stall)
			_stalls.append(stall.position)
			if stall.stall_id == ShopStation.BARRACKS:
				_occupy(stall.block_center(), stall.block_radius())


## A permanent owner/team label at the entrance and a matching ring around the compass mosaic.
## The wording is local to each peer ("Your Town" here, the owner's name for everyone else).
func _add_town_identity(town: Node3D, access: Dictionary) -> void:
	var owner_peer := int(access.get("owner_peer", 0))
	var team_id := int(access.get("team_id", -1))
	var color := TOWN_MARKER_COLOR
	var title := "Shared Town"
	if owner_peer > 0:
		color = Net.color_of(owner_peer)
		title = "Your Town" if owner_peer == Net.my_id() else "%s's Town" % Net.name_of(owner_peer)
	elif team_id >= 0:
		color = Net.TEAM_COLORS[team_id]
		title = "Your Team's Town" if Net.team_of(Net.my_id()) == team_id \
				else "%s Team Town" % Net.TEAM_NAMES[team_id]
	town.set_meta(&"display_title", title)

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 2.42
	ring_mesh.outer_radius = 2.56
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	ring_mesh.material = material
	var ring := MeshInstance3D.new()
	ring.name = "TownColorRing"
	ring.mesh = ring_mesh
	ring.position.y = 0.065
	ring.scale.y = 0.12
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	town.add_child(ring)

	var label := Label3D.new()
	label.name = "TownLabel"
	label.text = title
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 52
	label.outline_size = 14
	label.pixel_size = 0.007
	label.modulate = color.lightened(0.2)
	label.position = Vector3(0, 2.8, 7.4)
	town.add_child(label)


func _on_stall(pos: Vector3) -> bool:
	for area in _stall_areas:
		if Vector2(pos.x - area.x, pos.z - area.y).length() < area.z:
			return true
	return false


func _near_stall(pos: Vector3, distance: float) -> bool:
	for stall in _stalls:
		if pos.distance_to(stall) < distance:
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
	# Every player/team receives the same Uncommon starter chest; random starter rarity would be unfair in PvP.
	for point in _starter_chests:
		_place_chest(point, Chest.Rarity.UNCOMMON)
	var placed := _starter_chests.size()
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
		if not _on_stall(pos):
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

class_name WorldBuilder
extends RefCounted
## Procedurally builds the world of a map (`map`, a MapCatalog row): ground, border, the map's landmarks
## (Greenwood rock outcrops, Gravemoor fenced graveyards, Sunstone ruined courtyards + colonnades), an open spawn
## area at each spawn point (with a starter chest and a gold vein), orc camps, gold veins, animal herds, forests,
## chests and decoration. Every map works with every mode: landmarks keep clear of spawns and `clear_areas`.
## Camps farther from the start get bigger squads (4 → 24 orcs) and bigger houses. Repeated models (decor, fences,
## walls, gravestones) are chunked MultiMeshes (one draw call per chunk, culled off-screen) to stay cheap on
## mobile; their collision is a few plain boxes / cylinders (layer world).
## Deterministic: every peer builds the same world from the shared seed (no device-dependent branches here).

const CAMP_SCENE := preload("res://scenes/world/camp.tscn")
const TREE_SCENE := preload("res://scenes/world/choppable_tree.tscn")
const CHEST_SCENE := preload("res://scenes/world/chest.tscn")
const GOLD_VEIN_SCENE := preload("res://scenes/world/gold_vein.tscn")
## Radius around each spawn point kept free of trees, camps, chests and scattered decor.
const SPAWN_SAFE_RADIUS: float = 14.0
## Where each spawn's starter chest and gold vein stand, relative to the spawn point (the same for every spawn).
const STARTER_CHEST_OFFSET := Vector3(2.3, 0.0, -2.9)
const STARTER_VEIN_OFFSET := Vector3(-3.4, 0.0, -2.6)

const CHUNK_SIZE: float = 40.0
const WAVE_GATE_RADIUS: float = 5.0
## Content counts are tuned for this world size and scale with the area.
const REFERENCE_HALF: float = 80.0

const FOREST := MapCatalog.FOREST
const GRAVEYARD := MapCatalog.GRAVEYARD
const ARENA := MapCatalog.ARENA
const GRAVESTONES: PackedStringArray = ["gravestone_bevel", "gravestone_round", "gravestone_cross",
		"gravestone_decorative", "gravestone_roof", "gravestone_broken", "gravestone_cross_large"]
## Graveyard / ruin pieces: one Kenney tile is this many meters.
const YARD_TILE: float = 1.3
const LAMP_COLOR := Color(1.0, 0.72, 0.4)

var map: Dictionary = MapCatalog.get_map(0)
var camp_count: int = 20
## Animal groups grazing around the map (AnimalHerd); each species gets its share.
var herd_count: int = 16
## Herds stay this far from spawn points (wild pigs: twice as far) and this far apart.
var herd_spawn_distance: float = 14.0
var herd_spacing: float = 14.0
var tree_count: int = 520
var chest_count: int = 35
## Gold veins around the world besides the spawn ones and `vein_spots` (-1 = from the world's area).
var gold_vein_count: int = -1
var vein_spacing: float = 16.0
## Extra gold veins at exactly these points (e.g. one at the edge of every Last Stand circle).
var vein_spots: Array[Vector3] = []
## No camp closer than this to a spawn point, so players never start next to orcs.
var spawn_camp_distance: float = 24.0
## Player / team spawn points (set by main from the game mode). Camps get harder away from them.
var spawn_points: Array[Vector3] = [Vector3.ZERO]
## Extra areas kept clear with `clear_radius` (the King of the Hill zone, the Last Stand circles).
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
var _solid_count: int = 0
var _batches: Dictionary = {}  # model path -> {"transforms": Array[Transform3D], "shadows": bool}


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
	# Landmarks first: camps, forests and everything else flow around them.
	match map.landmarks:
		&"outcrops":
			_add_outcrops()
		&"graveyards":
			_add_graveyards()
		&"ruins":
			_add_ruins()
	var camps := _add_camps()
	_add_gold_veins()
	_add_herds()
	_add_chests()
	_add_trees()
	_add_decor()
	_flush_batches()
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


## How much bigger than the reference world this one is (content counts scale with it).
func _area_scale() -> float:
	return pow(_half / REFERENCE_HALF, 2.0)


## A free spot for a landmark of `radius` (INF when the world is full).
func _landmark_spot(radius: float, tries: int = 300) -> Vector3:
	for i in tries:
		var pos := _random_point(radius + 3.0)
		if _is_free(pos, radius):
			return pos
	return Vector3.INF


static func wave_entry_points() -> PackedVector3Array:
	var edge := GameConfig.world_half - 3.0
	return PackedVector3Array([
		Vector3(0.0, 0.0, -edge),
		Vector3(edge, 0.0, 0.0),
		Vector3(0.0, 0.0, edge),
		Vector3(-edge, 0.0, 0.0),
	])


## Queues one copy of a model for the chunked MultiMeshes (see `_flush_batches`).
func _batch(model_path: String, transform: Transform3D, shadows: bool = true) -> void:
	if not _batches.has(model_path):
		_batches[model_path] = {"transforms": [] as Array[Transform3D], "shadows": shadows}
	(_batches[model_path].transforms as Array[Transform3D]).append(transform)


func _flush_batches() -> void:
	for model_path in _batches:
		var entry: Dictionary = _batches[model_path]
		_add_multimesh(model_path, entry.transforms, entry.shadows)
	_batches.clear()


## Invisible collision: a box (`size`, bottom at the ground) turned `yaw` around its center.
func _solid_box(center: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	_solid(shape, Transform3D(Basis(Vector3.UP, yaw), Vector3(center.x, size.y * 0.5, center.z)))


func _solid_cylinder(center: Vector3, radius: float, height: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	_solid(shape, Transform3D(Basis(), Vector3(center.x, height * 0.5, center.z)))


func _solid(shape: Shape3D, transform: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Solid_%d" % _solid_count
	_solid_count += 1
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	body.transform = transform
	_world.add_child(body)


## A landmark's local frame: `origin` turned `yaw`; `at(x, z)` gives world points.
func _frame(origin: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), origin)


## A straight run of tiled pieces (fence, wall) from local `a` to `b` in `frame`, each piece `step` meters long,
## pieces whose index is in `skip` left out (gaps); each unbroken stretch gets one collision box.
## `model_offset` moves the model sideways onto the line (Kenney edge pieces sit off-center).
func _run(frame: Transform3D, a: Vector2, b: Vector2, step: float, model_path: String, model_scale: float,
		height: float, thickness: float, skip: Array = [], model_offset: float = 0.0) -> void:
	var along := b - a
	var count := maxi(roundi(along.length() / step), 1)
	var dir := along.normalized()
	var yaw := atan2(-dir.y, dir.x)
	var basis := frame.basis * Basis(Vector3.UP, yaw)
	var stretch_start := -1
	for i in count + 1:
		var solid := i < count and not skip.has(i)
		if solid:
			var mid := a + dir * (i + 0.5) * step
			var origin := frame * Vector3(mid.x, 0.0, mid.y) + basis * Vector3(0, 0, model_offset * model_scale)
			_batch(model_path, Transform3D(basis.scaled(Vector3.ONE * model_scale), origin))
			if stretch_start < 0:
				stretch_start = i
		elif stretch_start >= 0:
			var from := a + dir * stretch_start * step
			var to := a + dir * i * step
			var center := frame * Vector3((from.x + to.x) * 0.5, 0.0, (from.y + to.y) * 0.5)
			_solid_box(center, Vector3((to - from).length(), height, thickness), (frame.basis * Basis(Vector3.UP, yaw)).get_euler().y)
			stretch_start = -1


# --- Content ------------------------------------------------------------------

func _add_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (_half * 2.0 + 40.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = map.ground
	material.roughness = 1.0
	plane.material = material
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = plane
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(ground)


func _add_border() -> void:
	var transforms: Array[Transform3D] = []
	var step: float = map.border_step
	var offset: float = map.get("border_offset", 0.0)
	var edge := _half + 0.6
	var count := ceili(_half * 2.0 / step)
	for i in count + 1:
		var t := -_half + i * step
		# Each side faces into the world.
		transforms.append(Transform3D(Basis(), Vector3(t, 0, -edge + offset)))
		transforms.append(Transform3D(Basis(Vector3.UP, PI), Vector3(t, 0, edge - offset)))
		transforms.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-edge + offset, 0, t)))
		transforms.append(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(edge - offset, 0, t)))
	_add_multimesh(map.border, transforms, true)


# --- Landmarks: Greenwood ------------------------------------------------------------

## Mossy rock outcrops: a few big boulders around a center, each with its collision.
func _add_outcrops() -> void:
	var count := clampi(roundi(8 * _area_scale()), 4, 24)
	for n in count:
		var center := _landmark_spot(4.5)
		if center == Vector3.INF:
			return
		_occupy(center, 4.5)
		for i in randi_range(3, 6):
			var angle := randf() * TAU
			var distance := 0.0 if i == 0 else randf_range(1.2, 2.8)
			var at := center + Vector3(cos(angle), 0.0, sin(angle)) * distance
			var high := i == 0 or randf() < 0.4
			var s := randf_range(1.8, 2.6) if i == 0 else randf_range(1.2, 2.0)
			var basis := Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * s)
			if high:
				# rocks_high has its origin in the middle: sink it a little so it sits on the ground.
				_batch(FOREST % "rocks_high", Transform3D(basis, at + Vector3(0, s * 0.38, 0)))
				_solid_cylinder(at, s * 0.42, s * 0.9)
			else:
				_batch(FOREST % "rocks_low", Transform3D(basis, at))
				_solid_cylinder(at, s * 0.42, maxf(s * 0.5, GameConfig.HIT_HEIGHT))
		for i in 4:
			var angle := randf() * TAU
			var at := center + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(3.0, 4.2)
			_batch(FOREST % "stones", Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * randf_range(0.6, 1.0)), at), false)


# --- Landmarks: Gravemoor ------------------------------------------------------------

## Fenced graveyards: iron fence with a gate and corner pillars, rows of gravestones with an aisle from the
## gate, sometimes a crypt at the back, a lantern post (a warm light) by the gate and sometimes a chest.
func _add_graveyards() -> void:
	var count := clampi(roundi(9 * _area_scale()), 4, 22)
	for n in count:
		var columns := 2 * randi_range(2, 3)  # even: the gate (two pieces) sits in the middle
		var rows := randi_range(4, 5)
		var w := columns * YARD_TILE
		var d := rows * YARD_TILE
		var radius := Vector2(w, d).length() * 0.5 + 1.5
		var center := _landmark_spot(radius)
		if center == Vector3.INF:
			return
		_occupy(center, radius)
		var frame := _frame(center, randf() * TAU)
		var hw := w * 0.5
		var hd := d * 0.5
		var fence := GRAVEYARD % "iron_fence"
		var gate := [columns / 2 - 1, columns / 2]
		# The fence pieces sit at the back of their tile (z -0.38..-0.27): 0.33 moves them onto the line.
		_run(frame, Vector2(-hw, hd), Vector2(hw, hd), YARD_TILE, fence, YARD_TILE, 1.15, 0.25, gate, 0.33)
		_run(frame, Vector2(hw, -hd), Vector2(-hw, -hd), YARD_TILE, fence, YARD_TILE, 1.15, 0.25, [], 0.33)
		_run(frame, Vector2(-hw, -hd), Vector2(-hw, hd), YARD_TILE, fence, YARD_TILE, 1.15, 0.25, [], 0.33)
		_run(frame, Vector2(hw, hd), Vector2(hw, -hd), YARD_TILE, fence, YARD_TILE, 1.15, 0.25, [], 0.33)
		for corner in [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(-hw, hd), Vector2(hw, hd),
				Vector2(-YARD_TILE, hd), Vector2(YARD_TILE, hd)]:
			var at := frame * Vector3(corner.x, 0.0, corner.y)
			_batch(GRAVEYARD % "border_pillar", Transform3D(frame.basis.scaled(Vector3.ONE * 1.7), at))
		# A crypt at the back of bigger yards.
		var crypt := rows >= 5 and randf() < 0.65
		if crypt:
			var crypt_at := frame * Vector3(0.0, 0.0, -hd + 1.5)
			var crypt_basis := frame.basis.scaled(Vector3.ONE * 1.5)
			_batch(GRAVEYARD % "crypt_small", Transform3D(crypt_basis, crypt_at))
			_batch(GRAVEYARD % "crypt_small_roof", Transform3D(crypt_basis, crypt_at + Vector3(0, 1.5, 0)))
			_solid_box(crypt_at, Vector3(2.1, 2.0, 2.2), frame.basis.get_euler().y)
		# Gravestones in rows, an aisle from the gate up the middle.
		for row in rows - 1:
			var z := -hd + YARD_TILE * (row + 0.75)
			if crypt and z < -hd + 2.7:
				continue
			for col in columns:
				var x := -hw + YARD_TILE * (col + 0.5)
				if absf(x) < YARD_TILE * 0.9 or randf() < 0.15:
					continue
				var at := frame * Vector3(x + randf_range(-0.12, 0.12), 0.0, z)
				var yaw := frame.basis.get_euler().y + randf_range(-0.18, 0.18)
				var stone: String = GRAVEYARD % GRAVESTONES[randi() % GRAVESTONES.size()]
				_batch(stone, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * 1.4), at))
				_batch(GRAVEYARD % "grave", Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1.1, 1.0, 0.75)),
						at + Basis(Vector3.UP, yaw) * Vector3(0, 0.005, 0.62)), false)
				_solid_box(at, Vector3(0.6, GameConfig.HIT_HEIGHT, 0.4), yaw)
		# Lantern post by the gate (the moor's only warm light).
		var lamp_at := frame * Vector3(YARD_TILE * 1.6, 0.0, hd + 0.6)
		_batch(GRAVEYARD % "lightpost_single", Transform3D(frame.basis.scaled(Vector3.ONE * 1.4), lamp_at))
		_solid_cylinder(lamp_at, 0.18, 1.7)
		var light := OmniLight3D.new()
		light.name = "Lamp_%d" % n
		light.light_color = LAMP_COLOR
		light.light_energy = 1.6
		light.omni_range = 7.0
		light.shadow_enabled = false
		light.position = lamp_at + Vector3(0, 1.75, 0)
		_world.add_child(light)
		for i in 3:
			var candle_at := frame * Vector3(randf_range(-hw + 0.5, hw - 0.5), 0.0, randf_range(-hd + 0.5, hd - 0.5))
			_batch(GRAVEYARD % "candle_multiple", Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * 1.4), candle_at), false)
		if randf() < 0.4:
			_place_chest(frame * Vector3(0.0, 0.0, -hd + (3.3 if crypt else 1.0)))


# --- Landmarks: Sunstone Ruins ------------------------------------------------------------

## Ruined courtyards (paved floor with missing tiles, broken walls with gaps, columns at the corners, a statue,
## weapon racks or a chest inside) and colonnades (rows of standing and fallen columns).
func _add_ruins() -> void:
	var count := clampi(roundi(8 * _area_scale()), 4, 20)
	for n in count:
		var columns := randi_range(4, 6)
		var rows := randi_range(4, 6)
		var w := columns * YARD_TILE
		var d := rows * YARD_TILE
		var radius := Vector2(w, d).length() * 0.5 + 1.5
		var center := _landmark_spot(radius)
		if center == Vector3.INF:
			break
		_occupy(center, radius)
		var frame := _frame(center, randf() * TAU)
		var hw := w * 0.5
		var hd := d * 0.5
		for x in columns:
			for z in rows:
				if randf() < 0.22:
					continue
				var tile := ARENA % ("floor_detail" if randf() < 0.3 else "floor")
				var at := frame * Vector3(-hw + YARD_TILE * (x + 0.5), 0.015, -hd + YARD_TILE * (z + 0.5))
				_batch(tile, Transform3D(frame.basis.scaled(Vector3(YARD_TILE, 1.0, YARD_TILE)), at), false)
		# Walls: every side loses a few pieces; two sides get a wide way in.
		var sides := [[Vector2(-hw, hd), Vector2(hw, hd), columns], [Vector2(hw, -hd), Vector2(-hw, -hd), columns],
				[Vector2(-hw, -hd), Vector2(-hw, hd), rows], [Vector2(hw, hd), Vector2(hw, -hd), rows]]
		var entrances := [randi() % 4]
		entrances.append((entrances[0] + 2) % 4 if randf() < 0.5 else (entrances[0] + 1) % 4)
		for side in 4:
			var pieces: int = sides[side][2]
			var skip := []
			if entrances.has(side):
				var middle := pieces / 2
				skip.append_array([middle - 1, middle])
			for i in pieces:
				if randf() < 0.18 and not skip.has(i):
					skip.append(i)
			_run(frame, sides[side][0], sides[side][1], YARD_TILE, ARENA % "wall", YARD_TILE, 1.3, 0.75, skip)
			# Rubble where a piece fell.
			var a: Vector2 = sides[side][0]
			var dir: Vector2 = (sides[side][1] - a).normalized()
			for i in skip:
				if randf() < 0.6:
					var spot: Vector2 = a + dir * (i + 0.5) * YARD_TILE
					_batch(ARENA % "bricks", Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * randf_range(1.0, 1.4)),
							frame * Vector3(spot.x, 0.0, spot.y)), false)
		for corner in [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(-hw, hd), Vector2(hw, hd)]:
			var at := frame * Vector3(corner.x, 0.0, corner.y)
			var broken := randf() < 0.35
			_batch(ARENA % ("column_damaged" if broken else "column"), Transform3D(frame.basis.scaled(Vector3.ONE * 1.5), at))
			_solid_cylinder(at, 0.46, 1.1 if broken else 1.5)
		# Inside: a statue, weapon racks with a banner, or a chest.
		var roll := randf()
		if roll < 0.45:
			_batch(ARENA % "statue", Transform3D(frame.basis.scaled(Vector3.ONE * 1.4), center))
			_solid_cylinder(center, 0.5, 1.8)
		elif roll < 0.75:
			for side in [-1.0, 1.0]:
				var rack_at := frame * Vector3(side * (hw - 1.0), 0.0, -hd + 0.9)
				_batch(ARENA % "weapon_rack", Transform3D(frame.basis.scaled(Vector3.ONE * 1.4), rack_at))
				_solid_box(rack_at, Vector3(1.1, GameConfig.HIT_HEIGHT, 0.5), frame.basis.get_euler().y)
			_batch(ARENA % "banner", Transform3D(frame.basis.scaled(Vector3.ONE * 1.4), frame * Vector3(0.0, 0.0, -hd + 0.8)))
		else:
			_place_chest(center)
	var colonnades := clampi(roundi(6 * _area_scale()), 3, 16)
	for n in colonnades:
		var length := randi_range(5, 8)
		var spacing := 2.2
		var radius := length * spacing * 0.5 + 1.5
		var center := _landmark_spot(radius)
		if center == Vector3.INF:
			return
		_occupy(center, radius)
		var frame := _frame(center, randf() * TAU)
		for i in length:
			var local := Vector3((i - (length - 1) * 0.5) * spacing, 0.0, 0.0)
			var at := frame * local
			var roll := randf()
			if roll < 0.2:
				_batch(ARENA % "bricks", Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * 1.3), at), false)
				continue
			var broken := roll < 0.45
			_batch(ARENA % ("column_damaged" if broken else "column"), Transform3D(frame.basis.scaled(Vector3.ONE * 1.5), at))
			_solid_cylinder(at, 0.46, 1.1 if broken else 1.5)
			_batch(ARENA % "floor_detail", Transform3D(frame.basis.scaled(Vector3(YARD_TILE * 1.3, 1.0, YARD_TILE * 1.3)),
					at + Vector3(0, 0.012, 0)), false)


# --- Animals, camps, gold, chests ------------------------------------------------------

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


## Gold veins: one beside every spawn (the same spot for every team), one at each `vein_spots` point, and
## `gold_vein_count` spread over the world, apart from each other.
func _add_gold_veins() -> void:
	var placed: Array[Vector3] = []
	for point in spawn_points:
		placed.append(point + STARTER_VEIN_OFFSET)
	for spot in vein_spots:
		placed.append(spot)
	var wanted := gold_vein_count if gold_vein_count >= 0 else clampi(roundi(14 * _area_scale()), 6, 40)
	var spread := 0
	var tries := 0
	while spread < wanted and tries < 4000:
		tries += 1
		var pos := _random_point(4.0)
		if _distance_to_spawn(pos) < SPAWN_SAFE_RADIUS + 4.0 or not _is_free(pos, 1.6):
			continue
		var too_close := false
		for other in placed:
			if pos.distance_to(other) < vein_spacing:
				too_close = true
				break
		if too_close:
			continue
		placed.append(pos)
		spread += 1
	for i in placed.size():
		_occupy(placed[i], 1.4)
		var vein := GOLD_VEIN_SCENE.instantiate() as GoldVein
		vein.name = "GoldVein_%d" % i
		vein.position = placed[i]
		vein.rotation.y = randf() * TAU
		_world.add_child(vein)


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


# --- Forests & decor ------------------------------------------------------------------

func _add_trees() -> void:
	var models: Array[PackedScene] = []
	for path in map.trees:
		models.append(load(path) as PackedScene)
	var scale_range: Vector2 = map.tree_scale
	var wanted := roundi(tree_count * float(map.tree_density) * clampf(_area_scale(), 0.6, 1.6))
	var placed := 0
	var tries := 0
	while placed < wanted and tries < wanted * 12:
		tries += 1
		var pos := _random_point(1.5)
		# Noise makes forests and open clearings instead of uniform scatter.
		var density := _noise.get_noise_2d(pos.x, pos.z)
		if density < -0.1 or randf() > (density + 0.1) * 2.0:
			continue
		if not _is_free(pos, 0.9):
			continue
		_occupy(pos, 0.9)
		var tree := TREE_SCENE.instantiate() as ChoppableTree
		tree.name = "Tree_%d" % placed
		tree.models = models
		tree.position = pos
		tree.scale = Vector3.ONE * randf_range(scale_range.x, scale_range.y)
		_world.add_child(tree)
		placed += 1


func _add_decor() -> void:
	var area := clampf(_area_scale(), 0.6, 3.0)
	for entry in map.decor:
		_scatter(entry[0], roundi(entry[1] * area), entry[2], entry[3])


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

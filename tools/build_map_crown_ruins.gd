extends SceneTree
## Builds the King of the Hill map "Crown Ruins" → res://scenes/maps/crown_ruins.tscn (open it in the editor to
## look at or tweak by hand; rerun this to rebuild from the layout below):
##   "$G" --headless --path . -s tools/build_map_crown_ruins.gd
##
## Level design (104 m square, rotational symmetry: every team's quarter is the same map turned 90°, so no side is
## favored with 2, 3 or 4 teams):
## - Hill: a tiled arena in the middle (the 7 m zone), eight columns on its rim and a statue in the center —
##   cover to fight around, never a wall to hide behind for free.
## - Inner ring (15–17 m): ruined walls with a wide entry on every main lane and a narrow flank gap on every
##   diagonal — chokepoints, so holding the hill means watching 8 doors.
## - Main lane (base → hill, ~30 m, ~9 s running): fast but exposed; a broken wall and two columns halfway break
##   the straight line for archers.
## - Bases on the edges: walled courtyards (spawn safe), the front wall blocks the view from the hill, two side
##   exits (no single choke to camp).
## - Corner shrines (diagonals): a little graveyard with a Rare chest, guarded by an undead band — the risk /
##   reward side trip, equally far from both neighbouring bases.
## - Side groves between base and shrine: choppable trees and rocks — flanking routes with cover and Common
##   chests.
## - Meadows between the ring and each shrine: a grazing herd (deer, pigs, cows, foxes).
## Markers (Node3D) tell the game where team bases, bands, chests, trees and herds go (see MapDef).

const OUT := "res://scenes/maps/crown_ruins.tscn"
const ARENA := "res://assets/environment/arena/"
const FOREST := "res://assets/environment/forest/"
const DUNGEON := "res://assets/environment/dungeon/"
const GRAVE := "res://assets/environment/graveyard/"
## Arena Kit pieces are 1 m before scaling; walls end up 2 m wide and tall.
const ARENA_SCALE := 2.0
const GRAVE_SCALE := 1.5
const HALF := 52.0
const BASE_Z := 44.0
const RING_RADIUS := 16.0
## Bases in team order: two teams fight north / south.
const BASE_YAWS: Array[float] = [0.0, PI, PI * 0.5, PI * 1.5]

var map_root: Node3D
var pieces: Node3D
var markers: Node3D
var _yaw := 0.0  # quarter being built
var _counts := {}


func _init() -> void:
	seed(7)  # the same map every rebuild
	map_root = Node3D.new()
	map_root.name = "CrownRuins"
	pieces = _group(map_root, "Pieces")
	markers = _group(map_root, "Markers")
	_hill()
	for quarter in 4:
		_yaw = BASE_YAWS[quarter]
		_base(quarter)
		_main_lane()
		_ring_quarter()
		_shrine(quarter)
		_groves(quarter)
		_meadow(quarter)
	var scene := PackedScene.new()
	scene.pack(map_root)
	DirAccess.make_dir_recursive_absolute("res://scenes/maps")
	var err := ResourceSaver.save(scene, OUT)
	print("saved %s (%s): %s" % [OUT, error_string(err), _counts])
	map_root.free()
	quit()


func _group(parent: Node, group_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = group_name
	parent.add_child(node)
	node.owner = map_root
	return node


## Turns a point of the south quarter (+Z = the base side) into the quarter being built.
func q(p: Vector3) -> Vector3:
	return p.rotated(Vector3.UP, _yaw)


func piece(path: String, at: Vector3, yaw: float = 0.0, scale: float = ARENA_SCALE, solid: bool = true) -> Node3D:
	_counts[path.get_file()] = _counts.get(path.get_file(), 0) + 1
	if path.ends_with("floor.glb") or path.ends_with("floor_detail.glb"):
		at.y = 0.02  # flat tiles just above the ground plane (no z-fighting)
	return KitProps.place(pieces, path, q(at), yaw + _yaw, scale, solid, map_root)


func marker(marker_name: String, at: Vector3, metas: Dictionary = {}) -> Node3D:
	var node := Node3D.new()
	node.name = marker_name
	node.position = q(at)
	for key in metas:
		node.set_meta(key, metas[key])
	markers.add_child(node)
	node.owner = map_root
	return node


## A straight run of arena walls from `a` to `b` (south-quarter coordinates), `skip`: piece indexes left out.
func wall_run(a: Vector3, b: Vector3, model: String = "wall", skip: Array = []) -> void:
	var length := a.distance_to(b)
	var count := maxi(1, roundi(length / ARENA_SCALE))
	var dir := (b - a).normalized()
	var yaw := atan2(-dir.z, dir.x)
	for i in count:
		if skip.has(i):
			continue
		var at := a + dir * (ARENA_SCALE * (i + 0.5))
		var model_name := model
		if model == "wall" and (i * 7 + int(a.x * 3.0 + a.z)) % 5 == 0:
			model_name = "column_damaged"  # ruined: a broken stump here and there
		piece(ARENA + model_name + ".glb", at, yaw)


# --- The hill ------------------------------------------------------------------------------

func _hill() -> void:
	_yaw = 0.0
	# Tiled arena floor over the zone (flat, no collision).
	for x in range(-4, 4):
		for z in range(-4, 4):
			var at := Vector3((x + 0.5) * ARENA_SCALE, 0.0, (z + 0.5) * ARENA_SCALE)
			if at.length() < 8.2:
				var tile := "floor_detail" if (x + z) % 3 == 0 else "floor"
				piece(ARENA + tile + ".glb", at, 0.0, ARENA_SCALE, false)
	# Eight columns on the rim, a statue in the middle.
	for i in 8:
		var angle := TAU * (i + 0.5) / 8.0
		piece(ARENA + ("column" if i % 2 == 0 else "column_damaged") + ".glb", Vector3(sin(angle), 0, cos(angle)) * 9.0, angle)
	piece(ARENA + "statue.glb", Vector3.ZERO, PI * 0.25, 1.6)
	marker("Hill", Vector3.ZERO)


# --- One quarter (south: the base on +Z) ---------------------------------------------------------

func _base(quarter: int) -> void:
	# Back wall (stops 3 m short of the side walls: no z-fighting at the corners), sides, front cover wall.
	wall_run(Vector3(-8, 0, 50), Vector3(8, 0, 50))
	wall_run(Vector3(-9.5, 0, 38), Vector3(-9.5, 0, 50))
	wall_run(Vector3(9.5, 0, 38), Vector3(9.5, 0, 50))
	wall_run(Vector3(-4, 0, 36.5), Vector3(4, 0, 36.5))
	for x in [-9.5, 9.5]:
		piece(ARENA + "column.glb", Vector3(x, 0, 37.0))  # gate posts of the two side exits
	# Spawn floor and a bit of life.
	for x in range(-3, 3):
		for z in range(-2, 3):
			piece(ARENA + "floor.glb", Vector3((x + 0.5) * ARENA_SCALE, 0, BASE_Z + z * ARENA_SCALE), 0.0, ARENA_SCALE, false)
	for x in [-6.5, 6.5]:
		piece(ARENA + "banner.glb", Vector3(x, 0, 49.0), PI, ARENA_SCALE, false)
		piece(ARENA + "weapon_rack.glb", Vector3(x, 0, 41.0), PI * 0.5 if x < 0 else -PI * 0.5)
	piece(DUNGEON + "barrel.glb", Vector3(-7.5, 0, 47.5), 0.4, ARENA_SCALE)
	piece(DUNGEON + "barrel.glb", Vector3(7.6, 0, 47.2), 1.2, ARENA_SCALE)
	marker("TeamBase_%d" % quarter, Vector3(0, 0, BASE_Z))


func _main_lane() -> void:
	# Halfway cover: a broken wall across the lane and two columns beside it.
	piece(ARENA + "block.glb", Vector3(-1.0, 0, 25.0), 0.0)
	piece(ARENA + "block.glb", Vector3(1.0, 0, 25.0), 0.0)
	piece(ARENA + "bricks.glb", Vector3(2.8, 0, 25.6), 0.5, ARENA_SCALE, false)
	for x in [-5.0, 5.0]:
		piece(ARENA + "column_damaged.glb", Vector3(x, 0, 28.5))
	# Lane edging: low borders with gaps, lanterns at the base exits.
	for z in [19.0, 31.0]:
		for x in [-7.0, 7.0]:
			piece(ARENA + "border_straight.glb", Vector3(x, 0, z), PI * 0.5, ARENA_SCALE, false)
	for x in [-6.0, 6.0]:
		piece(GRAVE + "lightpost_single.glb", Vector3(x, 0, 34.5), 0.0 if x < 0 else PI, GRAVE_SCALE)
	# A dirt track down the lane (flat).
	for z in range(12, 36, 3):
		piece(FOREST + "patch_dirt.glb", Vector3(randf_range(-1.0, 1.0), 0, z), randf() * TAU, 2.4, false)


func _ring_quarter() -> void:
	# The ring around the hill between this lane (0°) and the next (90°): wall, narrow flank gap at 45°, wall.
	for span in [Vector2(17.0, 39.0), Vector2(51.0, 73.0)]:
		var steps := 3
		for i in steps:
			var angle := deg_to_rad(lerpf(span.x, span.y, (i + 0.5) / steps))
			var at := Vector3(sin(angle), 0, cos(angle)) * RING_RADIUS
			var model := "wall" if i != 1 or span.x > 40.0 else "wall_gate"
			piece(ARENA + model + ".glb", at, angle)
	# Gate posts at the flank gap.
	for deg in [41.5, 48.5]:
		var angle := deg_to_rad(deg)
		piece(ARENA + "column.glb", Vector3(sin(angle), 0, cos(angle)) * RING_RADIUS, angle)


func _shrine(quarter: int) -> void:
	# A little graveyard on the diagonal between this base and the next, with a Rare chest and its guards.
	var center := Vector3(sin(PI * 0.25), 0, cos(PI * 0.25)) * 33.0
	var facing := atan2(-center.x, -center.z)  # toward the hill
	var around := func(local: Vector3) -> Vector3: return center + local.rotated(Vector3.UP, facing)
	piece(GRAVE + "crypt.glb", around.call(Vector3(0, 0, -3.2)), facing, GRAVE_SCALE * 1.8)
	for side in [-1.0, 1.0]:
		piece(GRAVE + "pillar_obelisk.glb", around.call(Vector3(side * 2.4, 0, -3.0)), facing, GRAVE_SCALE)
		for row in 2:
			var stone: String = ["gravestone_cross", "gravestone_round", "gravestone_decorative", "gravestone_roof"][(row + int(side + 1.0)) % 4]
			piece(GRAVE + stone + ".glb", around.call(Vector3(side * 3.2, 0, 0.4 + row * 2.2)), facing, GRAVE_SCALE)
		# A broken iron fence on both sides (open toward the hill and the back).
		for i in 3:
			piece(GRAVE + ("iron_fence_damaged" if i == 1 else "iron_fence") + ".glb",
					around.call(Vector3(side * 5.2, 0, -2.0 + i * GRAVE_SCALE)), facing + PI * 0.5 * side, GRAVE_SCALE)
	piece(GRAVE + "candle_multiple.glb", around.call(Vector3(-0.9, 0, -1.4)), 0.0, GRAVE_SCALE, false)
	piece(GRAVE + "pumpkin_carved.glb", around.call(Vector3(1.2, 0, -1.6)), facing, GRAVE_SCALE, false)
	for i in 5:
		var angle := facing + PI + randf_range(-1.3, 1.3)
		var pine: String = ["pine", "pine_crooked", "pine_fall_crooked"][i % 3]
		piece(GRAVE + pine + ".glb", center + Vector3(sin(angle), 0, cos(angle)) * randf_range(6.5, 8.5), randf() * TAU, GRAVE_SCALE * randf_range(1.0, 1.3))
	marker("Chest_shrine_%d" % quarter, around.call(Vector3(0, 0, 0.6)), {"rarity": Chest.Rarity.RARE})
	marker("Band_shrine_%d" % quarter, around.call(Vector3(0, 0, 3.5)), {"size": 6, "faction": "undead", "territory": 7.0})


## Open ground between the ring and the shrine: a grazing herd (shy animals: coins and potions for the bold).
func _meadow(quarter: int) -> void:
	var species: String = ["deer", "pig", "cow", "fox"][quarter]
	marker("Herd_%d" % quarter, Vector3(27.0, 0, 6.0), {"species": species})


func _groves(quarter: int) -> void:
	# Between the base and the shrines on both sides: trees (choppable), rocks as hard cover, a Common chest.
	for side in [-1.0, 1.0]:
		var center := Vector3(side * 19.0, 0, 33.0)
		for i in 6:
			var angle := TAU * i / 6.0 + randf_range(-0.3, 0.3)
			marker("Tree_%d_%d_%d" % [quarter, int(side + 1.0), i], center + Vector3(cos(angle), 0, sin(angle)) * randf_range(2.6, 4.6))
		piece(FOREST + "rocks_high.glb", center + Vector3(side * -1.0, 0, -4.8), randf() * TAU, 2.2)
		piece(FOREST + "rocks_low.glb", center + Vector3(side * 4.5, 0, -1.0), randf() * TAU, 2.0)
		piece(FOREST + "stones.glb", center + Vector3(side * -5.0, 0, 2.5), randf() * TAU, 1.8, false)
		marker("Chest_grove_%d_%d" % [quarter, int(side + 1.0)], center + Vector3(0, 0, 0.5), {"rarity": Chest.Rarity.COMMON})
	# Rocks halfway between the lane and the shrine path (cover on the flank route).
	for side in [-1.0, 1.0]:
		piece(FOREST + "rocks_low.glb", Vector3(side * 11.0, 0, 20.0), randf() * TAU, 2.0)
		piece(DUNGEON + "barrel.glb", Vector3(side * 12.2, 0, 21.4), randf() * TAU, ARENA_SCALE)

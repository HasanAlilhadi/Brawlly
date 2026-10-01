class_name ShopStation
extends StaticBody3D
## A stall in the trading post next to each spawn (away from the orc camps). Each one sells only its own
## items (`UpgradeDef.stalls` lists the stalls that sell an item): walk up and press interact (E / B, LB /
## View, or tap the prompt) to open its shop. Part of the static world: every peer builds the same stalls
## (WorldBuilder, deterministic names); the server checks you stand at the right stall when you buy.
## The barracks is a walled training compound (model: tools/blender_barracks.py): the hall sits in the front
## wall (its door is the shop), behind it a sandy courtyard (the "pen"), a watchtower, an archery range and a
## gate in the +X wall. Soldiers bought there train for GameConfig.SOLDIER_TRAIN_TIME each (one after
## another), then wait in the courtyard (`pen_spot()`, drawn smaller: Ally.PENNED_SCALE) until their player
## takes them (at the gate — interact / tap "Take N soldiers" — or the shop's Take button,
## Player.collect_soldiers) and they file out through the gate (`gate_inside()` → `gate_point()`).
## The walls (GameConfig.LAYER_FENCE) block everyone; soldiers walking past a barracks route around the
## compound with `detour()` instead of pushing into the walls. While your soldiers wait, a pin bobs over the gate.
## Every stall is used from any side: within STALL_REACH of its building (`_footprint()`: the STALLS "block",
## the barracks' compound walls). No ground ring: in reach, the building itself glows (`set_highlight`,
## assets/shaders/highlight_glow.gdshader) and its sign turns gold.

## Stall id -> sign title, sign icon (Game Icon Pack glyph) and the props it is built from
## ([model path, position, rotation y (degrees), scale]). New stall = a row here + its id in the items' `stalls`.
## Stalls that are a building also give "block" (collision footprint in stall space, x / z), "block_height" and
## "sign_height" (the title over the roof).
const STALLS: Dictionary = {
	# Own model (tools/blender_blacksmith.py → the .glb + a .tscn placing the game's own sword / shield / barrel on it);
	# KEEP "block" IN SYNC with its layout.
	&"blacksmith": {"title": "Blacksmith", "icon": "sword", "props": [
		["res://assets/environment/buildings/blacksmith.tscn", Vector3.ZERO, 0.0, 1.0],
	], "block": Rect2(-2.0, -2.15, 4.0, 2.65), "block_height": 1.8, "sign_height": 3.3},
	# Own model (tools/blender_armory.py): a log cabin selling bows, spears and their ammo / upgrades.
	&"armory": {"title": "Bows & Spears", "icon": "bow", "props": [
		["res://assets/environment/buildings/armory.tscn", Vector3.ZERO, 0.0, 1.0],
	], "block": Rect2(-1.8, -2.15, 3.85, 2.6), "block_height": 1.8, "sign_height": 3.0},
	# Own model (tools/blender_healer.py): a herbalist's cottage with the potion table in front.
	&"healer": {"title": "Healer", "icon": "health", "props": [
		["res://assets/environment/buildings/healer.tscn", Vector3.ZERO, 0.0, 1.0],
	], "block": Rect2(-2.0, -2.15, 3.75, 2.65), "block_height": 1.8, "sign_height": 3.1},
	&"barracks": {"title": "Barracks", "icon": "user_group", "props": [
		["res://assets/environment/buildings/barracks.tscn", Vector3.ZERO, 0.0, 1.0],
	]},
}
const BARRACKS: StringName = &"barracks"
## Order of the stalls around a trading post.
const ORDER: Array[StringName] = [&"barracks", &"blacksmith", &"armory", &"healer"]
## Distance scale of `_distance()` / `nearest()`: < INTERACT_RANGE = in reach (see STALL_REACH).
const INTERACT_RANGE: float = 2.4
## Extra reach the server allows (the client's position lags a little behind).
const SERVER_SLACK: float = 1.5
## Props are modeled small (Kenney mini kits): the whole stall is scaled up by this.
const MODEL_SCALE: float = 1.5
## Customers stand this far in front of the stall.
const FRONT_DISTANCE: float = 1.7
## A stall is in reach within this distance of its building, on any side.
const STALL_REACH: float = 1.8
const HIGHLIGHT_SHADER := preload("res://assets/shaders/highlight_glow.gdshader")
const GATE_PIN_ICON := preload("res://assets/ui/icons/game/location.svg")
## Barracks compound layout in stall space (meters; rects are (x, z), +Z faces the trading post center).
## KEEP IN SYNC with tools/blender_barracks.py: the model is built from the same numbers.
const COMPOUND := Rect2(-3.3, -6.8, 6.6, 7.4)  # outer walls
const WALL_T: float = 0.3
const WALL_H: float = 1.3
const HALL := Rect2(-1.7, -1.9, 3.4, 2.5)
const HALL_HEIGHT: float = 3.2
const TOWER := Rect2(-3.3, -6.8, 1.5, 1.5)
const TOWER_HEIGHT: float = 3.6
const RANGE := Rect2(-1.4, -6.5, 3.6, 0.6)
const STAIRS := Rect2(-3.0, -5.3, 0.5, 1.9)
const GATE_PIN_HEIGHT: float = 2.2
## Where waiting soldiers stand: the open courtyard, clear of the porch, range, stairs and tower.
const PEN := Rect2(-2.2, -5.2, 4.8, 2.5)
## The soldiers' gate in the +X wall (center z, half width).
const GATE_Z: float = -3.95
const GATE_HALF: float = 1.0

@export var stall_id: StringName = &"blacksmith"

## Base access. Personal Deathmatch towns set owner_peer; team modes set team_id; co-op leaves both open.
var access_owner_peer: int = 0
var access_team_id: int = -1

var _sign: Label3D
## Barracks: the local player's soldiers ("2 ready · 1 training 7s"), over the house.
var _status: Label3D
var _status_timer: float = 0.0
var _local_player: Player
## Barracks: bobbing pin over the gate while the local player's soldiers wait in the courtyard.
var _gate_pin: Sprite3D
var _highlight: ShaderMaterial
var _meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group(&"shop_stations")
	var data: Dictionary = STALLS[stall_id]
	for prop: Array in data.props:
		var model := (load(prop[0]) as PackedScene).instantiate() as Node3D
		model.position = prop[1]
		model.rotation_degrees.y = prop[2]
		model.scale = Vector3.ONE * float(prop[3])
		$Model.add_child(model)
	$Model.scale = Vector3.ONE * MODEL_SCALE
	_sign = Label3D.new()
	_sign.text = data.title
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.no_depth_test = true
	_sign.font_size = 44
	_sign.outline_size = 12
	_sign.pixel_size = 0.006
	_sign.position = Vector3(0, 2.4, -0.3)
	add_child(_sign)
	if data.has("block"):
		var rect: Rect2 = data.block
		var height: float = data.block_height
		var box := BoxShape3D.new()
		box.size = Vector3(rect.size.x, height, rect.size.y)
		$CollisionShape3D.shape = box
		$CollisionShape3D.position = Vector3(rect.get_center().x, height * 0.5, rect.get_center().y)
		_sign.position = Vector3(0, data.sign_height, rect.get_center().y)
	if stall_id == BARRACKS:
		_build_barracks()


func _process(delta: float) -> void:
	if _status == null:
		return
	if _gate_pin.visible:
		_gate_pin.position.y = GATE_PIN_HEIGHT + sin(Time.get_ticks_msec() * 0.004) * 0.15
	_status_timer -= delta
	if _status_timer > 0.0:
		return
	_status_timer = 0.25
	if not is_instance_valid(_local_player):
		_local_player = null
		for node in get_tree().get_nodes_in_group(&"players"):
			if (node as Player).is_local():
				_local_player = node
	_status.text = soldier_status(_local_player) if can_access(_local_player) else ""
	_status.visible = _status.text != ""


## "2 ready · 1 training 7s" for `player`'s soldiers ("" when none).
static func soldier_status(player: Player) -> String:
	if player == null:
		return ""
	var parts := PackedStringArray()
	var ready := player.penned_soldiers().size()
	if ready > 0:
		parts.append("%d ready" % ready)
	if player.soldiers_training > 0:
		parts.append("%d training · next in %ds" % [player.soldiers_training, ceili(player.next_soldier_in())])
	return " · ".join(parts)


## Compound collision (hall, tower, range and stairs on the world layer; walls and gate towers on the fence
## layer), the gate pin and the status label.
func _build_barracks() -> void:
	var hall := BoxShape3D.new()
	hall.size = Vector3(HALL.size.x, HALL_HEIGHT, HALL.size.y)
	$CollisionShape3D.shape = hall
	$CollisionShape3D.position = Vector3(HALL.get_center().x, HALL_HEIGHT * 0.5, HALL.get_center().y)
	_add_box(self, TOWER, TOWER_HEIGHT)
	_add_box(self, RANGE, WALL_H)
	_add_box(self, STAIRS, WALL_H)
	var walls := StaticBody3D.new()
	walls.name = "CompoundWalls"
	walls.collision_layer = GameConfig.LAYER_FENCE
	walls.collision_mask = 0
	add_child(walls)
	var x0 := COMPOUND.position.x
	var x1 := COMPOUND.end.x
	var z0 := COMPOUND.position.y
	var z1 := COMPOUND.end.y
	for rect: Rect2 in [
			Rect2(x0, z0, WALL_T, z1 - z0),  # left
			Rect2(x0, z0, x1 - x0, WALL_T),  # back
			Rect2(x1 - WALL_T, z0, WALL_T, GATE_Z - GATE_HALF - z0),  # right, behind the gate
			Rect2(x1 - WALL_T, GATE_Z + GATE_HALF, WALL_T, z1 - GATE_Z - GATE_HALF),  # right, in front of it
			Rect2(x0, z1 - WALL_T, HALL.position.x - x0, WALL_T),  # front, left of the hall
			Rect2(HALL.end.x, z1 - WALL_T, x1 - HALL.end.x, WALL_T),  # front, right of the hall
			Rect2(x1 - 0.35, GATE_Z + GATE_HALF, 0.55, 0.5),  # gate towers
			Rect2(x1 - 0.35, GATE_Z - GATE_HALF - 0.5, 0.55, 0.5)]:
		_add_box(walls, rect, WALL_H)
	_gate_pin = Sprite3D.new()
	_gate_pin.texture = GATE_PIN_ICON
	_gate_pin.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_gate_pin.no_depth_test = true
	_gate_pin.pixel_size = 0.7 / GATE_PIN_ICON.get_width()
	_gate_pin.position = to_local(gate_point()) + Vector3(0, GATE_PIN_HEIGHT, 0)
	_gate_pin.visible = false
	add_child(_gate_pin)
	_status = Label3D.new()
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.no_depth_test = true
	_status.font_size = 36
	_status.outline_size = 10
	_status.pixel_size = 0.006
	_status.modulate = Color(0.75, 1.0, 0.7)
	_sign.position = Vector3(0, HALL_HEIGHT + 0.9, HALL.get_center().y)
	# Same spot as the sign, one line below it on screen (pixel offset: holds from every camera turn).
	_status.position = _sign.position
	_status.offset = Vector2(0, -(_sign.font_size + _status.font_size) * 0.55)
	_status.visible = false
	add_child(_status)


## A collision box standing on the ground over `rect` (stall space x, z).
func _add_box(body: StaticBody3D, rect: Rect2, height: float) -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(rect.size.x, height, rect.size.y)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(rect.get_center().x, height * 0.5, rect.get_center().y)
	body.add_child(shape)


## Barracks pen center (stall space): the middle of the courtyard's open ground.
func _pen_center() -> Vector3:
	return Vector3(PEN.get_center().x, 0, PEN.get_center().y)


func pen_center_local() -> Vector3:
	return _pen_center()


## World position of the pen (e.g. to keep trees out of it).
func pen_center() -> Vector3:
	return to_global(_pen_center())


## World center and radius of a circle covering the whole compound (e.g. to keep trees out of it).
func block_center() -> Vector3:
	var center := _block_rect().get_center()
	return to_global(Vector3(center.x, 0, center.y))


func block_radius() -> float:
	return _block_rect().size.length() * 0.5 + 0.5


## Radius around the stall's origin its model covers (keeps trees and other props off it).
func footprint_radius() -> float:
	var data: Dictionary = STALLS[stall_id]
	if not data.has("block"):
		return 1.6
	var rect: Rect2 = data.block
	var far := 0.0
	for corner: Vector2 in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
		far = maxf(far, corner.length())
	return far + 0.3




## A random spot inside the pen (world space).
func pen_spot() -> Vector3:
	var area := PEN.grow(-0.3)
	return to_global(Vector3(randf_range(area.position.x, area.end.x), 0, randf_range(area.position.y, area.end.y)))


## Just outside the gate (world space): players take soldiers here; released soldiers walk out to here
## (`across` spreads them over the gate's width, -1..1).
func gate_point(across: float = 0.0) -> Vector3:
	return to_global(Vector3(COMPOUND.end.x + 1.2, 0, GATE_Z + across * _gate_half_width()))


## Just inside the gate (world space): released soldiers pass here, then walk out.
func gate_inside(across: float = 0.0) -> Vector3:
	return to_global(Vector3(COMPOUND.end.x - WALL_T - 0.6, 0, GATE_Z + across * _gate_half_width()))


## Half the gate opening, minus a soldier's width.
func _gate_half_width() -> float:
	return GATE_HALF - 0.45


## Where a soldier at `from` should walk next to reach `to` without crossing this barracks (house + pen):
## `to` itself when the way is clear, else the next corner of the block (grown by `margin`), on the
## shorter way around. From inside the pen (and `to` outside it) the way out is always the gate: first
## to the gate on the soldier's own lane, then out through it.
func detour(from: Vector3, to: Vector3, margin: float = 0.9) -> Vector3:
	var a := _flat_local(from)
	var b := _flat_local(to)
	var block := _block_rect()
	var gate_x := COMPOUND.end.x
	var across := a.y - GATE_Z
	var lane := clampf(across / maxf(_gate_half_width(), 0.1), -1.0, 1.0)
	var in_mouth := absf(across) < _gate_half_width() + 0.15 and a.x > gate_x - 1.0 and a.x < gate_x + 0.8
	if in_pen(from, 0.0) or in_mouth:
		if in_pen(to, 0.0):
			return to
		# In the opening: straight out. Elsewhere inside: first to our lane just inside the gate.
		return gate_point(lane) if in_mouth else gate_inside(lane)
	if block.has_point(a) or block.grow(margin + 3.0).intersects(Rect2(a, Vector2.ZERO).expand(b)) == false:
		return to
	var solid := block.grow(margin - 0.05)
	var grown := block.grow(margin)
	if solid.has_point(a):
		# Brushing the block (inside the margin): plan from the nearest point on the margin's edge.
		var gaps: Array[float] = [a.x - grown.position.x, grown.end.x - a.x, a.y - grown.position.y, grown.end.y - a.y]
		var side := gaps.find(gaps.min())
		a = [Vector2(grown.position.x, a.y), Vector2(grown.end.x, a.y), Vector2(a.x, grown.position.y), Vector2(a.x, grown.end.y)][side]
	if not _segment_hits(a, b, solid):
		return to
	var corners: Array[Vector2] = [grown.position, Vector2(grown.end.x, grown.position.y), grown.end,
			Vector2(grown.position.x, grown.end.y)]
	# Tiny shortest path over {from, 4 corners, to}: edges that don't cut through the block.
	var nodes: Array[Vector2] = [a]
	nodes.append_array(corners)
	nodes.append(b)
	var best: Array[float] = [0.0, INF, INF, INF, INF, INF]
	var prev: Array[int] = [-1, -1, -1, -1, -1, -1]
	var done: Array[bool] = [false, false, false, false, false, false]
	for _step in nodes.size():
		var u := -1
		for i in nodes.size():
			if not done[i] and (u == -1 or best[i] < best[u]):
				u = i
		if u == -1 or best[u] == INF:
			break
		done[u] = true
		for v in nodes.size():
			if done[v] or _segment_hits(nodes[u], nodes[v], solid):
				continue
			var d := best[u] + nodes[u].distance_to(nodes[v])
			if d < best[v]:
				best[v] = d
				prev[v] = u
	var last := nodes.size() - 1
	if prev[last] == -1:
		return to
	var step := last
	while prev[step] != 0:
		step = prev[step]
	var point := nodes[step]
	return to_global(Vector3(point.x, 0.0, point.y)) * Vector3(1, 0, 1) + Vector3(0, from.y, 0)


## Compound footprint in stall space (x, z), with the gate towers.
func _block_rect() -> Rect2:
	return Rect2(COMPOUND.position, COMPOUND.size + Vector2(0.2, 0.0))


func _flat_local(point: Vector3) -> Vector2:
	var local := to_local(point)
	return Vector2(local.x, local.z)


## Does the segment a→b pass through `rect` (Liang–Barsky clip)?
static func _segment_hits(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		var lo := rect.position[axis]
		var hi := rect.end[axis]
		if absf(d[axis]) < 0.00001:
			if a[axis] <= lo or a[axis] >= hi:
				return false
			continue
		var ta := (lo - a[axis]) / d[axis]
		var tb := (hi - a[axis]) / d[axis]
		if ta > tb:
			var swap := ta
			ta = tb
			tb = swap
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 >= t1:
			return false
	return true


## Every barracks near `point` (soldiers check these for detours).
static func barracks_near(tree: SceneTree, point: Vector3, distance: float = 16.0) -> Array[ShopStation]:
	var result: Array[ShopStation] = []
	for node in tree.get_nodes_in_group(&"shop_stations"):
		var stall := node as ShopStation
		if stall.stall_id == BARRACKS and stall.global_position.distance_to(point) < distance:
			result.append(stall)
	return result


## Is `point` inside the compound walls (with `margin` from them)?
func in_pen(point: Vector3, margin: float = 0.3) -> bool:
	return COMPOUND.grow(-WALL_T - margin).has_point(_flat_local(point))


## Every peer: the local player has soldiers waiting here / stands at the gate (pin shown / bright).
func set_gate_state(waiting: bool, active: bool) -> void:
	if _gate_pin:
		_gate_pin.visible = waiting
		_gate_pin.modulate = Color(0.55, 1.0, 0.5) if active else Color(0.55, 1.0, 0.5, 0.75)
		_gate_pin.scale = Vector3.ONE * (1.25 if active else 1.0)


## The barracks whose gate `player` stands at (null when none is in reach).
static func nearest_gate(player: Node3D, reach: float = INTERACT_RANGE, require_access: bool = true) -> ShopStation:
	var best: ShopStation = null
	var best_dist := reach
	for node in player.get_tree().get_nodes_in_group(&"shop_stations"):
		var stall := node as ShopStation
		if stall.stall_id != BARRACKS:
			continue
		if require_access and not stall.can_access(player):
			continue
		var to := player.global_position - stall.gate_point()
		to.y = 0.0
		if to.length() < best_dist:
			best_dist = to.length()
			best = stall
	return best


func title() -> String:
	return STALLS[stall_id].title


## Shop prompt text. Locked shops identify their owner/team instead of using a generic warning.
func title_for(player: Node3D) -> String:
	if can_access(player):
		return title()
	if access_owner_peer > 0:
		return "%s's %s" % [Net.name_of(access_owner_peer), title()]
	if access_team_id >= 0:
		return "%s %s" % [Net.team_label(access_team_id), title()]
	return title()


## True when `player` owns this personal base, belongs to this team base, or the town is shared.
func can_access(player: Node3D) -> bool:
	if not player is Player:
		return false
	var customer := player as Player
	if access_owner_peer > 0:
		return customer.peer_id == access_owner_peer
	if access_team_id >= 0:
		return customer.team_id == access_team_id
	return true


func access_denied_text() -> String:
	if access_owner_peer > 0:
		return "Only %s can use this shop." % Net.name_of(access_owner_peer)
	if access_team_id >= 0:
		return "Only the %s team can use this shop." % Net.team_label(access_team_id)
	return "You cannot use this shop."


## Where customers stand (in front of the stall, facing it).
func front() -> Vector3:
	return global_position + global_basis.z * FRONT_DISTANCE


## Every peer: the local player is close enough to use it — the stall's models glow (pulsing gold
## overlay) and its sign turns gold.
func set_highlight(on: bool) -> void:
	_sign.modulate = Color(1.0, 0.9, 0.5) if on else Color.WHITE
	if _highlight == null:
		_highlight = ShaderMaterial.new()
		_highlight.shader = HIGHLIGHT_SHADER
		for node in $Model.find_children("*", "MeshInstance3D", true, false):
			_meshes.append(node as MeshInstance3D)
	for mesh in _meshes:
		mesh.material_overlay = _highlight if on else null


func sells(def: UpgradeDef) -> bool:
	return def.stalls.has(stall_id)


## How far `player` is from using this stall: < INTERACT_RANGE = in reach, i.e. within STALL_REACH of
## the building's footprint, on any side.
func _distance(player: Node3D) -> float:
	var local := _flat_local(player.global_position)
	var block := _footprint()
	var outside := Vector2(maxf(maxf(block.position.x - local.x, local.x - block.end.x), 0.0),
			maxf(maxf(block.position.y - local.y, local.y - block.end.y), 0.0))
	return outside.length() - STALL_REACH + INTERACT_RANGE


## The building's footprint in stall space (x, z): the barracks' compound, else the STALLS "block"
## (a small box around the origin for a stall without one).
func _footprint() -> Rect2:
	if stall_id == BARRACKS:
		return _block_rect()
	var data: Dictionary = STALLS[stall_id]
	return data.block if data.has("block") else Rect2(-1.0, -1.0, 2.0, 2.0)


## The stall `player` can use right now: the closest one in reach (null when none is);
## `only` = just stalls of that id.
static func nearest(player: Node3D, reach: float = INTERACT_RANGE, only: StringName = &"",
		require_access: bool = true) -> ShopStation:
	var best: ShopStation = null
	var best_dist := reach
	for node in player.get_tree().get_nodes_in_group(&"shop_stations"):
		var stall := node as ShopStation
		if only != &"" and stall.stall_id != only:
			continue
		if require_access and not stall.can_access(player):
			continue
		var d := stall._distance(player)
		if d < best_dist:
			best_dist = d
			best = stall
	return best


## Server check: `player` stands at a stall that sells `def`.
static func can_buy_here(player: Node3D, def: UpgradeDef) -> bool:
	for node in player.get_tree().get_nodes_in_group(&"shop_stations"):
		var stall := node as ShopStation
		if stall.can_access(player) and stall.sells(def) \
				and stall._distance(player) < INTERACT_RANGE + SERVER_SLACK:
			return true
	return false

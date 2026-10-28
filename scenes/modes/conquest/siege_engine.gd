class_name SiegeEngine
extends Unit
## Conquest: a siege engine bought on the Army tab (`siege_ram` / `siege_catapult`, UpgradeDef.modes = Conquest),
## owned by a hero (NetSpawn kind `siege`, "engine" = "ram" / "catapult"). Only siege engines (group `siege`) hit
## gates at full force (TerritoryGate.HAND_SHARE for everyone else).
## - Battering ram: rolls up to the nearest enemy gate within SEEK and rams it every `cooldown`.
## - Catapult: stops within `range` of the nearest enemy gate (outside the walls) and lobs a boulder at it; the
##   boulder also hurts foes near where it lands (`splash`).
## Neither has a target? It trails its hero. It never fights units; monsters and rival factions attack it (group
## `player_units`). Server runs it; every peer sees the swing / the boulder through `_net_ram` / `_net_boulder`.
## The models are primitive placeholders built in code (like the gatehouse).

const SCENE_PATH := "res://scenes/modes/conquest/siege_engine.tscn"
## Per engine: health, speed, damage per blow, seconds between blows, reach (ram: from the gate's middle;
## catapult: its range), how far it looks for a gate, boulder splash damage / radius.
const ENGINES: Dictionary = {
	"ram": {"name": "Battering Ram", "health": 450.0, "speed": 2.2, "damage": 160.0, "cooldown": 2.5,
			"reach": 2.6, "seek": 20.0, "splash": 0.0, "splash_radius": 0.0},
	"catapult": {"name": "Catapult", "health": 260.0, "speed": 1.8, "damage": 120.0, "cooldown": 6.0,
			"reach": 24.0, "seek": 28.0, "splash": 30.0, "splash_radius": 2.5},
}
## Trailing its hero this far behind.
const FOLLOW_DISTANCE: float = 5.0
## Seconds a boulder flies.
const BOULDER_FLIGHT: float = 1.2
const WOOD := Color(0.5, 0.34, 0.18)
const IRON := Color(0.3, 0.3, 0.32)

var engine: String = "ram"

var _blow_timer: float = 0.0
var _gate: TerritoryGate
var _arm: Node3D


## main.gd `_spawn_unit` (every peer).
static func create(data: Dictionary) -> SiegeEngine:
	var unit := (load(SCENE_PATH) as PackedScene).instantiate() as SiegeEngine
	unit.engine = data.get("engine", "ram") if ENGINES.has(data.get("engine", "")) else "ram"
	var row: Dictionary = ENGINES[unit.engine]
	unit.max_health = row.health
	unit.move_speed = row.speed
	return unit


## Engines of `kind` this hero owns that still stand (one of each per hero).
static func count_for(tree: SceneTree, peer: int, kind: String) -> int:
	var count := 0
	for node in tree.get_nodes_in_group(&"siege"):
		var unit := node as SiegeEngine
		if unit and unit.owner_peer == peer and unit.engine == kind and not unit.is_dead:
			count += 1
	return count


func info() -> Dictionary:
	return ENGINES[engine]


func _ready() -> void:
	_build_model()
	super()
	add_to_group(&"siege")
	add_to_group(&"player_units")  # monsters and rival factions go after it


## Wheels, a frame, and a capped log (ram) or a throwing arm (catapult), in the Model holder (no clips: an empty
## AnimationPlayer keeps Unit happy).
func _build_model() -> void:
	var body := $Model as Node3D
	body.add_child(AnimationPlayer.new())
	_box(body, Vector3(1.4, 0.3, 2.2), Vector3(0.0, 0.45, 0.0), WOOD)
	for x in [-0.8, 0.8]:
		for z in [-0.7, 0.7]:
			var wheel := _cylinder(body, 0.3, 0.15, Vector3(x, 0.3, z), WOOD.darkened(0.3))
			wheel.rotation.z = PI * 0.5
	if engine == "ram":
		_box(body, Vector3(1.5, 0.12, 2.3), Vector3(0.0, 1.55, 0.0), WOOD.darkened(0.15))  # roof
		for x in [-0.65, 0.65]:
			_box(body, Vector3(0.12, 0.9, 0.12), Vector3(x, 1.05, 0.9), WOOD)
			_box(body, Vector3(0.12, 0.9, 0.12), Vector3(x, 1.05, -0.9), WOOD)
		_arm = Node3D.new()
		_arm.position = Vector3(0.0, 0.95, 0.0)
		body.add_child(_arm)
		var log := _cylinder(_arm, 0.2, 2.6, Vector3(0.0, 0.0, 0.25), WOOD.lightened(0.1))
		log.rotation.x = PI * 0.5
		var cap := _cylinder(_arm, 0.24, 0.3, Vector3(0.0, 0.0, 1.6), IRON)
		cap.rotation.x = PI * 0.5
	else:
		for x in [-0.55, 0.55]:
			_box(body, Vector3(0.14, 1.0, 0.14), Vector3(x, 1.05, -0.2), WOOD)
		_box(body, Vector3(1.24, 0.14, 0.14), Vector3(0.0, 1.5, -0.2), WOOD)  # crossbar the arm hits
		_arm = Node3D.new()
		_arm.position = Vector3(0.0, 0.7, 0.4)
		body.add_child(_arm)
		_box(_arm, Vector3(0.16, 0.16, 1.8), Vector3(0.0, 0.0, -0.7), WOOD.lightened(0.1))
		_box(_arm, Vector3(0.45, 0.12, 0.45), Vector3(0.0, 0.1, -1.55), IRON)  # the cup
		_arm.rotation.x = 0.25
	model = body
	anim = body.get_child(0) as AnimationPlayer


func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _piece(parent, mesh, at, color)


func _cylinder(parent: Node3D, r: float, height: float, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = height
	return _piece(parent, mesh, at, color)


func _piece(parent: Node3D, mesh: PrimitiveMesh, at: Vector3, color: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	parent.add_child(instance)
	return instance


func _can_hit(_target: Object) -> bool:
	return false


func hero() -> Player:
	for node in get_tree().get_nodes_in_group(&"players"):
		if (node as Player).peer_id == owner_peer:
			return node
	return null


# --- Server ------------------------------------------------------------------------

func _get_move_input(delta: float) -> Vector3:
	if not multiplayer.is_server():
		return Vector3.ZERO
	_blow_timer = maxf(_blow_timer - delta, 0.0)
	if not is_instance_valid(_gate) or not _is_target(_gate):
		_gate = _find_gate()
	if _gate:
		return _siege(delta)
	var leader := hero()
	if leader == null or leader.is_dead:
		return Vector3.ZERO
	var to := _flat(leader.global_position - global_position)
	return steer(to.normalized(), delta) if to.length() > FOLLOW_DISTANCE else Vector3.ZERO


## A standing gate of a place another faction holds.
func _is_target(gate: TerritoryGate) -> bool:
	return gate.territory and gate.territory.state == TerritoryNode.State.OWNED \
			and gate.territory.owner_team != team_id and not gate.is_broken()


func _find_gate() -> TerritoryGate:
	var best: TerritoryGate = null
	var best_d: float = info().seek
	for node in get_tree().get_nodes_in_group(&"territories"):
		var gate := (node as TerritoryNode).gate
		if gate == null or not _is_target(gate):
			continue
		var d := _flat(gate.global_position - global_position).length()
		if d < best_d:
			best_d = d
			best = gate
	return best


## Closes in (ram: right up to the gate, from outside; catapult: into range), then strikes every cooldown.
func _siege(delta: float) -> Vector3:
	var outside := _gate.global_position + _gate.global_basis.z.normalized() * (_gate.size.z * 0.5 + 1.4)
	var aim := _flat(_gate.global_position - global_position)
	var reach: float = info().reach
	if aim.length() > reach:
		var goal := outside if engine == "ram" else _gate.global_position
		return steer(_flat(goal - global_position).normalized(), delta)
	face(aim, delta * 2.0)
	if _blow_timer <= 0.0:
		_blow_timer = info().cooldown
		if engine == "ram":
			_net_ram.rpc()
			_gate.take_damage(info().damage, self, true)
		else:
			var landing := _gate.global_position + Vector3(0.0, 1.2, 0.0)
			_net_boulder.rpc(global_position + Vector3(0.0, 2.0, 0.0), landing)
			get_tree().create_timer(BOULDER_FLIGHT).timeout.connect(_boulder_lands.bind(_gate, landing))
	return Vector3.ZERO


func _boulder_lands(gate: TerritoryGate, at: Vector3) -> void:
	if is_instance_valid(gate) and _is_target(gate):
		gate.take_damage(info().damage, self, false)
	var splash: float = info().splash
	for node in get_tree().get_nodes_in_group(&"units"):
		var unit := node as Unit
		if unit == null or GameConfig.is_gone(unit) or not GameConfig.is_hostile(self, unit):
			continue
		if _flat(unit.global_position - at).length() < float(info().splash_radius):
			unit.take_damage(splash, self, false)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# --- Every peer: the blows ----------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _net_ram() -> void:
	if _arm == null:
		return
	var tween := create_tween()
	tween.tween_property(_arm, "position:z", -0.5, 0.35).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_arm, "position:z", 0.6, 0.12).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.tween_property(_arm, "position:z", 0.0, 0.5)


## The arm swings up and a boulder arcs from `from` to `to` (a sphere, then a smoke puff where it lands).
@rpc("authority", "call_local", "reliable")
func _net_boulder(from: Vector3, to: Vector3) -> void:
	if _arm:
		var swing := create_tween()
		swing.tween_property(_arm, "rotation:x", -1.4, 0.18).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		swing.tween_property(_arm, "rotation:x", 0.25, 1.2)
	var world := get_parent()
	if world == null:
		return
	var sphere := SphereMesh.new()
	sphere.radius = 0.28
	sphere.height = 0.56
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.45, 0.43, 0.4)
	sphere.material = stone
	var boulder := MeshInstance3D.new()
	boulder.mesh = sphere
	world.add_child(boulder)
	boulder.global_position = from
	var peak := maxf(from.y, to.y) + from.distance_to(to) * 0.35
	var flight := create_tween()
	flight.tween_method(func(t: float) -> void:
		if is_instance_valid(boulder):
			var at := from.lerp(to, t)
			at.y = lerpf(from.y, to.y, t) + 4.0 * (peak - maxf(from.y, to.y)) * t * (1.0 - t)
			boulder.global_position = at, 0.0, 1.0, BOULDER_FLIGHT)
	flight.tween_callback(func() -> void:
		if is_instance_valid(boulder):
			HitFx.flash(to, HitFx.DEATH_SMOKE, Color(0.7, 0.65, 0.6, 0.9), 2.0, 0.6, Vector2(0.6, 1.4), false)
			boulder.queue_free())


func _death_visuals() -> void:
	collision_layer = 0
	collision_mask = 0
	_health_bar.hide()
	var tween := create_tween()
	tween.tween_property(model, "rotation:z", 0.5, 0.4).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(model, "position:y", -0.3, 0.4)
	HitFx.flash(global_position + Vector3(0, 0.6, 0), HitFx.DEATH_SMOKE, Color(0.6, 0.55, 0.5, 0.9), 2.2, 0.8,
			Vector2(0.6, 1.5), false)

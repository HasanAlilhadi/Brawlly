class_name TerritoryGate
extends StaticBody3D
## Conquest: the gatehouse in the wall of a City / Citadel (TerritoryNode._build_walls). While it stands, nobody can
## take the place's banner. Any weapon of another faction chips at it (group `breakable`), but only siege engines
## (group `siege`) hit it at full force; heroes and soldiers deal HAND_SHARE. Comes back at a share of its health
## when the place changes hands.
## It is solid only while the place is held and the gate stands; even then it opens for the holder's own heroes,
## soldiers and caravans near it while no foe is near (`_update_open`). Server decides; every peer gets the health
## (`_net_health`) and whether it is shut (`_net_shut`): predicted players collide on their own device too.

## Damage share of anything that isn't a siege engine.
const HAND_SHARE: float = 0.15
const HEIGHT: float = 2.4
## It opens for a friend this close while no foe is within FOE_RANGE.
const OPEN_RANGE: float = 4.5
const FOE_RANGE: float = 8.0
## How high an open gate is raised (a portcullis).
const RAISED: float = 2.0

var territory: TerritoryNode
var max_health: float = 1000.0
var health: float = 1000.0
## Set before it enters the tree (the wall piece it replaces).
var size := Vector3(2.6, HEIGHT, 1.0)
## Solid right now (replicated).
var shut: bool = false

var _material: StandardMaterial3D
var _mesh: MeshInstance3D
var _check: float = 0.0


func _ready() -> void:
	add_to_group(&"breakable")
	collision_layer = 0
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = size.y * 0.5
	add_child(collision)
	var box := BoxMesh.new()
	box.size = size
	_material = StandardMaterial3D.new()
	box.material = _material
	_mesh = MeshInstance3D.new()
	_mesh.mesh = box
	add_child(_mesh)
	shut = _should_shut()
	_apply_look()


## The holder's team: its own side can't hurt it (GameConfig.is_hostile reads this).
var team_id: int:
	get:
		return territory.owner_team if territory else -1


func is_broken() -> bool:
	return health <= 0.0


## Held, standing and not opened for a friend.
func _should_shut() -> bool:
	if territory == null or territory.state != TerritoryNode.State.OWNED or is_broken():
		return false
	return not _friend_waiting()


func _friend_waiting() -> bool:
	var friend := false
	for node in get_tree().get_nodes_in_group(&"player_units"):
		var unit := node as Unit
		if GameConfig.is_gone(unit):
			continue
		var d := Vector2(unit.global_position.x - global_position.x, unit.global_position.z - global_position.z).length()
		if unit.team_id == territory.owner_team:
			friend = friend or d < OPEN_RANGE
		elif d < FOE_RANGE:
			return false  # a foe at the gate: it stays shut
	if not friend:
		return false
	for node in get_tree().get_nodes_in_group(&"active_enemies"):
		var enemy := node as Node3D
		if not GameConfig.is_gone(enemy) and enemy.global_position.distance_to(global_position) < FOE_RANGE:
			return false
	return true


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.2
	var should := _should_shut()
	if should != shut:
		_net_shut.rpc(should)


## Server, navigation bake: out of the way while the world is parsed (it opens and breaks; the walls don't).
func hide_from_navigation(hidden: bool) -> void:
	collision_layer = 0 if hidden or not shut else GameConfig.LAYER_WORLD


func take_damage(amount: float, attacker: Node3D = null, is_melee: bool = true, crit: bool = false) -> void:
	if not multiplayer.is_server() or is_broken() or territory == null:
		return
	if territory.state != TerritoryNode.State.OWNED:
		return  # nobody's gate: nothing to break
	var attacker_team: Variant = attacker.get("team_id") if is_instance_valid(attacker) else null
	if attacker_team == null or int(attacker_team) < 0 or int(attacker_team) == territory.owner_team:
		return
	var dealt := amount * (1.0 if attacker.is_in_group(&"siege") else HAND_SHARE)
	HitFx.report_hit(self, minf(dealt, health), attacker, crit, is_melee)
	var was := health
	health = maxf(health - dealt, 0.0)
	if health <= 0.0 and was > 0.0:
		territory.mode.announce("The gate of %s is broken!" % territory.display_name)
	_net_health.rpc(health)


## Server: back to `share` of full health (the new holder rebuilds it).
func restore(share: float) -> void:
	health = max_health * share
	_net_health.rpc(health)


## Server: rebuild by `amount` (up to full); returns what it took.
func repair(amount: float) -> float:
	var added := minf(amount, max_health - health)
	if added <= 0.0:
		return 0.0
	health += added
	_net_health.rpc(health)
	return added


@rpc("authority", "call_local", "reliable")
func _net_health(value: float) -> void:
	health = value
	if multiplayer.is_server():
		shut = _should_shut()
		_net_shut.rpc(shut)
	_apply_look()


@rpc("authority", "call_local", "reliable")
func _net_shut(value: bool) -> void:
	shut = value
	_apply_look()


func _apply_look() -> void:
	if _material == null:
		return
	# Broken: rubble (walk over it); open: raised like a portcullis; shut: stone, darker as it is battered.
	var share := health / max_health if max_health > 0.0 else 0.0
	_material.albedo_color = Color(0.5, 0.42, 0.32).darkened(0.5 * (1.0 - share))
	collision_layer = GameConfig.LAYER_WORLD if shut else 0
	var height := 0.2 if is_broken() else 1.0
	_mesh.scale = Vector3(1.0, height, 1.0)
	_mesh.position.y = size.y * 0.5 * height + (RAISED if not shut and not is_broken() else 0.0)

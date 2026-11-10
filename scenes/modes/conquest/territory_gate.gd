class_name TerritoryGate
extends StaticBody3D
## Conquest: the gatehouse in the wall of a City / Citadel (TerritoryNode._build_walls). While it stands, nobody can
## take the place's banner. Any weapon of another faction chips at it (group `breakable`), but only siege engines
## (group `siege`) hit it at full force; heroes and soldiers deal HAND_SHARE. Comes back at a share of its health
## when the place changes hands.
## While it stands and the place is held (or infested) it is solid for every side but the holder's: it sits on
## its holder's gate layer (GameConfig.gate_layer), which every other side's units collide with and the holder's
## don't — the holder's heroes, soldiers, caravans (or an infested place's demons) walk through it, everyone else
## must break it, and it can be hit at any time. It looks raised (`shut` false) while one of its own side is near.
## Foes don't press against the walls: they go to the gate and hit it (ConquestDemons). Server decides; every peer gets the health
## (`_net_health`) and whether it is shut (`_net_shut`): predicted players collide on their own device too.

## Damage share of anything that isn't a siege engine.
const HAND_SHARE: float = 0.15
const HEIGHT: float = 2.4
## It opens for one of its own side this close.
const OPEN_RANGE: float = 4.5
## No rebuilding (LogisticsManager) until this many seconds after the last blow: a gate under attack stays down.
const REPAIR_CALM: float = 15.0
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
var _last_hit_ms: int = -1000000


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


## Held (or infested), standing and none of its own side at it.
func _should_shut() -> bool:
	if territory == null or is_broken() or territory.state == TerritoryNode.State.NEUTRAL:
		return false
	return not _friend_waiting()


## One of its own side within OPEN_RANGE: the holder's units (an infested place: its demons). Foes near don't
## keep it shut — the holder's soldiers must be able to get out and fight them.
func _friend_waiting() -> bool:
	var infested := territory.state == TerritoryNode.State.INFESTED
	var brain := BattleBrain.current
	if brain and brain.has_census():  # the commanders' census: no walk over every unit for every gate
		return brain.monsters_near(global_position, OPEN_RANGE) if infested \
				else brain.friends_near(global_position, OPEN_RANGE, territory.owner_team)
	for node in get_tree().get_nodes_in_group(&"active_enemies" if infested else &"player_units"):
		var unit := node as Node3D
		if GameConfig.is_gone(unit) or (not infested and unit.get("team_id") != territory.owner_team):
			continue
		if Vector2(unit.global_position.x - global_position.x, unit.global_position.z - global_position.z).length() < OPEN_RANGE:
			return true
	return false


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
	collision_layer = 0 if hidden else _layer()


## Its physics layer: its holder's gate layer while it stands and someone holds the place, else none.
func _layer() -> int:
	if territory == null or is_broken() or territory.state == TerritoryNode.State.NEUTRAL:
		return 0
	return GameConfig.gate_layer(territory.owner_team if territory.state == TerritoryNode.State.OWNED else GameConfig.ORC_TEAM)


func take_damage(amount: float, attacker: Node3D = null, is_melee: bool = true, crit: bool = false) -> void:
	if not multiplayer.is_server() or is_broken() or territory == null:
		return
	if territory.state == TerritoryNode.State.NEUTRAL:
		return  # nobody's gate: nothing to break
	var attacker_team: Variant = attacker.get("team_id") if is_instance_valid(attacker) else null
	if attacker_team == null or int(attacker_team) < 0 or int(attacker_team) == territory.owner_team:
		return
	var dealt := amount * (1.0 if attacker.is_in_group(&"siege") else HAND_SHARE)
	_last_hit_ms = Time.get_ticks_msec()
	HitFx.report_hit(self, minf(dealt, health), attacker, crit, is_melee)
	var was := health
	health = maxf(health - dealt, 0.0)
	if health <= 0.0 and was > 0.0:
		territory.mode.announce("The gate of %s is broken!" % territory.display_name)
	_net_health.rpc(health)


## Server (ConquestMode raids): demons at the gate hammer it (they can't hurt it as units: their team is < 0).
func batter(amount: float) -> void:
	if not multiplayer.is_server() or is_broken() or territory == null or territory.state != TerritoryNode.State.OWNED:
		return
	_last_hit_ms = Time.get_ticks_msec()
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		territory.mode.announce("Demons broke the gate of %s!" % territory.display_name)
	_net_health.rpc(health)


## Where attackers stand to hit it: just outside, in front of it (it faces the middle of the map).
func outside_point(margin: float = 1.4) -> Vector3:
	var at := global_position + global_basis.z.normalized() * (size.z * 0.5 + margin)
	return Vector3(at.x, 0.0, at.z)


## Server: back to `share` of full health (the new holder rebuilds it).
func restore(share: float) -> void:
	health = max_health * share
	_net_health.rpc(health)


## Not hit for REPAIR_CALM seconds (it may be rebuilt).
func is_calm() -> bool:
	return Time.get_ticks_msec() - _last_hit_ms > int(REPAIR_CALM * 1000.0)


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
	collision_layer = _layer()  # solid for every other side, raised or not
	var height := 0.2 if is_broken() else 1.0
	_mesh.scale = Vector3(1.0, height, 1.0)
	_mesh.position.y = size.y * 0.5 * height + (RAISED if not shut and not is_broken() else 0.0)

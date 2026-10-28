class_name TerritoryGate
extends StaticBody3D
## Conquest: the gatehouse of a City / Citadel. While it stands, nobody can take the place's banner. Any weapon of
## another faction chips at it (group `breakable`), but only siege engines (group `siege`) hit it at full force;
## heroes and soldiers deal HAND_SHARE. Comes back at a share of its health when the place changes hands.
## Server decides; every peer sees the health via `_net_health`. (Walls around cities come with siege, phase 4.)

## Damage share of anything that isn't a siege engine.
const HAND_SHARE: float = 0.15
const SIZE := Vector3(2.6, 2.4, 2.6)

var territory: TerritoryNode
var max_health: float = 1000.0
var health: float = 1000.0

var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"breakable")
	collision_layer = GameConfig.LAYER_WORLD
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = SIZE
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = SIZE.y * 0.5
	add_child(collision)
	var box := BoxMesh.new()
	box.size = SIZE
	_material = StandardMaterial3D.new()
	box.material = _material
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.position.y = SIZE.y * 0.5
	add_child(mesh)
	_apply_look()


## The holder's team: its own side can't hurt it (GameConfig.is_hostile reads this).
var team_id: int:
	get:
		return territory.owner_team if territory else -1


func is_broken() -> bool:
	return health <= 0.0


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


@rpc("authority", "call_local", "reliable")
func _net_health(value: float) -> void:
	health = value
	_apply_look()


func _apply_look() -> void:
	if _material == null:
		return
	# Broken: sunk and dark (walk over the rubble); standing: stone, darker as it is battered.
	var share := health / max_health if max_health > 0.0 else 0.0
	_material.albedo_color = Color(0.6, 0.55, 0.48).darkened(0.5 * (1.0 - share))
	collision_layer = 0 if is_broken() else GameConfig.LAYER_WORLD
	for child in get_children():
		if child is MeshInstance3D:
			var rubble := 0.2 if is_broken() else 1.0
			(child as MeshInstance3D).scale.y = rubble
			(child as MeshInstance3D).position.y = SIZE.y * 0.5 * rubble

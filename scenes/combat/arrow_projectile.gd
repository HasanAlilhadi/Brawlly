class_name ArrowProjectile
extends Node3D
## Flying arrow / thrown spear. Raycasts along its path each physics frame (no tunneling),
## damages the first hostile thing with `take_damage`, passes through teammates, and stops at
## trees/buildings. Point-blank shots count too: it spawns a little in front of the shooter, so the
## stretch from the shooter's body to the spawn point is checked first, and rays that start inside a
## body still hit it. Spawned by the server through NetSpawn; other peers only show the flight.

@export var speed: float = 18.0
@export var lifetime: float = 0.72
@export_flags_3d_physics var hit_mask: int = GameConfig.LAYER_WORLD | GameConfig.LAYER_UNITS

## Set before adding to the tree (from the spawn data).
var start: Vector3
var direction: Vector3 = Vector3.FORWARD
var damage: float = 0.0
var crit: bool = false
var team_id: int = GameConfig.ORC_TEAM
var owner_peer: int = 0
var shooter_path: NodePath

var _shooter: Node3D
var _age: float = 0.0


func _ready() -> void:
	global_position = start
	direction = direction.normalized()
	look_at(start + direction, Vector3.UP)
	if not shooter_path.is_empty():
		_shooter = get_node_or_null(shooter_path) as Node3D
	if multiplayer.is_server() and is_instance_valid(_shooter):
		var origin := Vector3(_shooter.global_position.x, start.y, _shooter.global_position.z)
		if _hit_something(origin, start):
			visible = false
			set_physics_process(false)
			queue_free()


func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + direction * speed * delta
	_age += delta
	if not multiplayer.is_server():
		# Visual only; the server frees the arrow (which removes it here too).
		global_position = to
		visible = _age < lifetime
		return
	if _hit_something(from, to):
		queue_free()
		return
	global_position = to
	if _age >= lifetime:
		queue_free()


## Returns true when the arrow should stop (hit a hostile or an obstacle).
func _hit_something(from: Vector3, to: Vector3) -> bool:
	var exclude: Array[RID] = []
	if is_instance_valid(_shooter) and _shooter is CollisionObject3D:
		exclude.append((_shooter as CollisionObject3D).get_rid())
	for attempt in 4:
		var query := PhysicsRayQueryParameters3D.create(from, to, hit_mask)
		query.exclude = exclude
		query.hit_from_inside = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return false
		var collider: Object = hit.collider
		if collider.get("team_id") == team_id:
			# Teammate: fly through.
			exclude.append((collider as CollisionObject3D).get_rid())
			continue
		if collider.has_method("take_damage"):
			collider.take_damage(damage, _shooter if is_instance_valid(_shooter) else self, false, crit)
		return true
	return false

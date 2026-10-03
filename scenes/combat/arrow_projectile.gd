class_name ArrowProjectile
extends Node3D
## Flying arrow / thrown spear. Raycasts along its path each physics frame (no tunneling),
## damages the first hostile thing with `take_damage`, passes through teammates, and stops at
## trees/buildings. Point-blank shots count too: it spawns a little in front of the shooter (the player's
## arrows: at the bow), so the stretch from the shooter's body to the spawn point, and as far straight ahead,
## is checked first, and rays that start inside a body still hit it. Spawned by the server through NetSpawn; other peers only show the flight.

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
## Normal shots check from the shooter's body to the projectile spawn so point-blank targets count.
## Sky-spawned ability arrows disable this because that long segment is not part of their flight.
var check_shooter_origin: bool = true
## Bow Rain arrows get local-only spawn and impact VFX on every peer.
var rain_arrow: bool = false

const RAIN_REVEAL_DELAY: float = 0.08
## Only Bow Rain gets a wider hit volume; ordinary bow shots remain precise rays.
const RAIN_HIT_RADIUS: float = 0.5
const RAIN_COLOR := Color(1.0, 0.76, 0.32, 0.9)

var _shooter: Node3D
var _age: float = 0.0
var _rain_hit_cast: ShapeCast3D


func _ready() -> void:
	global_position = start
	direction = direction.normalized()
	var up := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
	look_at(start + direction, up)
	if rain_arrow:
		_rain_hit_cast = ShapeCast3D.new()
		_rain_hit_cast.top_level = true
		_rain_hit_cast.enabled = false
		_rain_hit_cast.collision_mask = hit_mask
		_rain_hit_cast.max_results = 8
		var sphere := SphereShape3D.new()
		sphere.radius = RAIN_HIT_RADIUS
		_rain_hit_cast.shape = sphere
		add_child(_rain_hit_cast)
		visible = false
		HitFx.flash(start, HitFx.COMBO_RING, RAIN_COLOR, 0.85, 0.22, Vector2(0.35, 1.35))
		HitFx.flash(start, HitFx.REVIVE_SPARKLE, RAIN_COLOR, 0.62, 0.2)
	if not shooter_path.is_empty():
		_shooter = get_node_or_null(shooter_path) as Node3D
	if multiplayer.is_server() and is_instance_valid(_shooter) and check_shooter_origin:
		var origin := Vector3(_shooter.global_position.x, start.y, _shooter.global_position.z)
		# Also straight ahead of the shooter for as far: the bow is held to one side, and whatever touches
		# the hero in front still gets hit.
		if _hit_something(origin, start) or _hit_something(origin, origin + direction * origin.distance_to(start)):
			visible = false
			set_physics_process(false)
			queue_free()


func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + direction * speed * delta
	_age += delta
	if rain_arrow:
		visible = _age >= RAIN_REVEAL_DELAY and _age < lifetime
	if not multiplayer.is_server() and not rain_arrow:
		# Ordinary arrows are visual-only on peers; the server removes them after a hit.
		global_position = to
		visible = _age < lifetime
		return
	if _hit_something(from, to):
		if multiplayer.is_server():
			queue_free()
		else:
			visible = false
			set_physics_process(false)
		return
	global_position = to
	if _age >= lifetime:
		if multiplayer.is_server():
			queue_free()
		else:
			visible = false
			set_physics_process(false)


## Returns true when the arrow should stop (hit a hostile or an obstacle).
func _hit_something(from: Vector3, to: Vector3) -> bool:
	if rain_arrow and _hit_rain_target(from, to):
		return true
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
		if rain_arrow:
			_show_rain_impact(hit.position, hit.normal, collider.has_method("take_damage"))
		if multiplayer.is_server() and collider.has_method("take_damage"):
			collider.take_damage(damage, _shooter if is_instance_valid(_shooter) else self, false, crit)
		return true
	return false


## Sweep the wider Bow Rain sphere over this frame's travel. Non-damageable scenery still
## uses the exact center ray below, so ground impacts stay on the ground rather than floating.
func _hit_rain_target(from: Vector3, to: Vector3) -> bool:
	_rain_hit_cast.global_position = from
	_rain_hit_cast.target_position = to - from
	_rain_hit_cast.clear_exceptions()
	if is_instance_valid(_shooter) and _shooter is CollisionObject3D:
		_rain_hit_cast.add_exception(_shooter as CollisionObject3D)
	for attempt in 4:
		_rain_hit_cast.force_shapecast_update()
		if not _rain_hit_cast.is_colliding():
			return false
		var ignored_teammate := false
		for index in _rain_hit_cast.get_collision_count():
			var collider := _rain_hit_cast.get_collider(index)
			if collider == null:
				continue
			if collider.get("team_id") == team_id:
				_rain_hit_cast.add_exception_rid(_rain_hit_cast.get_collider_rid(index))
				ignored_teammate = true
				continue
			if collider.has_method("take_damage"):
				_show_rain_impact(_rain_hit_cast.get_collision_point(index),
						_rain_hit_cast.get_collision_normal(index), true)
				if multiplayer.is_server():
					collider.take_damage(damage, _shooter if is_instance_valid(_shooter) else self, false, crit)
				return true
		if not ignored_teammate:
			return false
	return false


func _show_rain_impact(at: Vector3, normal: Vector3, damageable: bool) -> void:
	var point := at + normal * 0.06
	HitFx.flash(point, HitFx.HIT_SPARK, RAIN_COLOR, 0.55, 0.18)
	HitFx.burst(point, HitFx.Kind.METAL if damageable else HitFx.Kind.DIRT, 7, normal)

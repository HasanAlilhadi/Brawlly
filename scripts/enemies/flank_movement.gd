class_name FlankMovement
extends EnemyMovement
## Quick skirmishers: instead of running straight in, circles around to the target's side or back (seen
## from where the target is facing), then darts in. Skitters a little side to side on the way.

## How far around the target's facing it goes before closing in (degrees; 180 = right behind it).
@export var flank_angle: float = 110.0
## Distance from the target where it stops circling and goes in.
@export var close_distance: float = 2.4
@export var jitter: float = 0.25

var _side: float = 1.0
var _time: float = 0.0


func setup(owner_enemy: Enemy) -> void:
	super(owner_enemy)
	_side = -1.0 if randf() < 0.5 else 1.0
	_time = randf() * 10.0


func chase(target: Node3D, delta: float) -> Vector3:
	_time += delta
	var to := flat_to(target)
	var reach := enemy.melee_range + Unit.target_radius(target)
	if to.length() < reach + 0.3:
		return enemy.engage(target, delta, false)
	var facing: Vector3 = target.call("facing") if target.has_method("facing") else -to.normalized()
	var around := facing.rotated(Vector3.UP, deg_to_rad(flank_angle) * _side)
	# Come around wide (`close_distance` out) until level with the flank spot, then step in to it.
	var from_target := -to.normalized()
	var off_angle := rad_to_deg(from_target.angle_to(around))
	var ring := reach + (0.2 if off_angle < 30.0 else close_distance)
	var spot := target.global_position + around * ring
	var want := spot - enemy.global_position
	want.y = 0.0
	if want.length() < 0.35:
		return enemy.engage(target, delta, false)
	var dir := want.normalized()
	dir += dir.cross(Vector3.UP) * sin(_time * 9.0) * jitter
	return enemy.steer(dir.normalized(), delta, target, true)

class_name KiteMovement
extends EnemyMovement
## Ranged fighters: closes in until the target is within `keep_max`, then holds there facing it, strafing
## sideways now and then, and backs off when the target comes closer than `keep_min`. With no clear line of
## fire it steps to the side that has one.

@export var keep_min: float = 4.0
@export var keep_max: float = 8.0
## Share of move_speed while strafing (0 = stand still).
@export var strafe_pace: float = 0.35
## Share of move_speed while backing off.
@export var retreat_pace: float = 0.85

var _strafe_side: float = 1.0
var _los_timer: float = 0.0
## Where to step for a clear line of fire (INF = the line is clear already / none found).
var _los_spot: Vector3 = Vector3.INF
var _strafe_timer: float = 0.0


func chase(target: Node3D, delta: float) -> Vector3:
	var to := flat_to(target)
	var dist := to.length()
	if dist > keep_max:
		return enemy.engage(target, delta, false)
	enemy.look_override = to
	if dist < keep_min:
		return enemy.steer(-to.normalized() * retreat_pace, delta)
	# No clear shot (a tree, a wall in the way): step to the side that has one, else close in.
	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = 0.4
		_los_spot = _clear_spot(target, to)
	if _los_spot != Vector3.INF:
		var way := _los_spot - enemy.global_position
		way.y = 0.0
		if way.length() > 0.4:
			return enemy.steer(way.normalized() * 0.8, delta)
		_los_spot = Vector3.INF
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(1.2, 2.6)
		_strafe_side = -1.0 if randf() < 0.5 else 1.0
		if randf() < 0.35:
			_strafe_side = 0.0  # stand and shoot for a moment
	if _strafe_side == 0.0 or strafe_pace <= 0.0:
		return enemy.steer(Vector3.ZERO, delta)
	return enemy.steer(to.normalized().cross(Vector3.UP) * _strafe_side * strafe_pace, delta)


## INF when the line to `target` is clear; else a spot 2.5 m to either side with a clear line (the nearer
## side first), else a step toward the target.
func _clear_spot(target: Node3D, to: Vector3) -> Vector3:
	if enemy.clear_line_to(target):
		return Vector3.INF
	var side := to.normalized().cross(Vector3.UP)
	for sign_ in [_strafe_side if _strafe_side != 0.0 else 1.0, -_strafe_side if _strafe_side != 0.0 else -1.0]:
		var spot: Vector3 = enemy.global_position + side * sign_ * 2.5
		if enemy.spot_is_free(spot, enemy.radius) and enemy.clear_line_to(target, spot):
			return spot
	return enemy.global_position + to.normalized() * 2.0

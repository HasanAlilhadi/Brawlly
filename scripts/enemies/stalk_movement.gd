class_name StalkMovement
extends EnemyMovement
## Predators: circle the target at `circle_radius`, watching it, then dart in for a strike and slip back
## out to circle again.

@export var circle_radius: float = 3.4
## Seconds circling before the next strike.
@export var circle_time: Vector2 = Vector2(1.2, 2.4)
@export var circle_pace: float = 0.7

var _striking: bool = false
var _timer: float = 0.0
var _side: float = 1.0
var _swung: bool = false


func setup(owner_enemy: Enemy) -> void:
	super(owner_enemy)
	_side = -1.0 if randf() < 0.5 else 1.0
	_timer = randf_range(circle_time.x, circle_time.y)


func chase(target: Node3D, delta: float) -> Vector3:
	var to := flat_to(target)
	if _striking:
		if enemy._melee_timer > 0.0:
			_swung = true
		elif _swung or to.length() > circle_radius * 2.5:
			_circle_again()
		return enemy.engage(target, delta, false)
	_timer -= delta
	if _timer <= 0.0 or to.length() > circle_radius * 2.5:
		_striking = true
		_swung = false
		return enemy.engage(target, delta, false)
	enemy.look_override = to
	var from_target := -to.normalized() if to.length() > 0.01 else Vector3.BACK
	var spot := target.global_position + from_target.rotated(Vector3.UP, 0.7 * _side) * circle_radius
	var want := spot - enemy.global_position
	want.y = 0.0
	return enemy.steer(want.normalized() * circle_pace if want.length() > 0.3 else Vector3.ZERO, delta, target, true)


func _circle_again() -> void:
	_striking = false
	_timer = randf_range(circle_time.x, circle_time.y)
	if randf() < 0.4:
		_side = -_side

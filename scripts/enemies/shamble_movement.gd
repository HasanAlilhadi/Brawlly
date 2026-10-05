class_name ShambleMovement
extends EnemyMovement
## The undead lurch: speed swells and sags (between `min_pace` and full speed) and the body sways side to
## side, so they're slow on average but hard to judge.

@export var min_pace: float = 0.45
## Lurches per second.
@export var lurch_rate: float = 0.9
## Side-to-side sway (radians).
@export var sway: float = 0.3

var _time: float = 0.0


func setup(owner_enemy: Enemy) -> void:
	super(owner_enemy)
	_time = randf() * 10.0


func chase(target: Node3D, delta: float) -> Vector3:
	_time += delta
	var move := enemy.engage(target, delta, false)
	if move.length() < 0.05:
		return move
	var pace := lerpf(min_pace, 1.0, 0.5 + 0.5 * sin(_time * TAU * lurch_rate))
	return move.rotated(Vector3.UP, sin(_time * TAU * lurch_rate * 0.5) * sway) * pace


func roam(point: Vector3, delta: float, pace: float) -> Vector3:
	_time += delta
	return super(point, delta, pace).rotated(Vector3.UP, sin(_time * TAU * lurch_rate * 0.5) * sway)

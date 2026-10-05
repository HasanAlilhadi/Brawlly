class_name EnemyMovement
extends EnemyComponent
## How an enemy moves — one per enemy (an Enemy without one gets this: run straight at the target and spread
## out around it). `chase()` while it has a target, `roam()` toward its spot in its warband (or home)
## otherwise. Both return the move input (XZ, length 0..1 of move_speed). Subclasses give each creature its
## own way of moving: kiting, flanking, shambling, floating, stalking.


func chase(target: Node3D, delta: float) -> Vector3:
	return enemy.engage(target, delta, false)


## `pace`: share of move_speed (a marching band walks; a unit that fell behind runs).
func roam(point: Vector3, delta: float, pace: float) -> Vector3:
	var to := point - enemy.global_position
	to.y = 0.0
	if enemy.drift.length() > 0.05 and to.length() < 3.0:
		# Marching with the band: its velocity plus a gentle pull toward the spot — one smooth walk.
		var move := enemy.drift / maxf(enemy.move_speed, 0.1) + to * 0.5
		return enemy.steer(move.limit_length(1.0), delta)
	if to.length() < 0.3:
		return Vector3.ZERO
	if to.length() > 3.0:
		pace = 1.0
	return enemy.steer(to.normalized() * pace, delta)


## Flat direction and distance from the enemy to `node`.
func flat_to(node: Node3D) -> Vector3:
	var to := node.global_position - enemy.global_position
	to.y = 0.0
	return to

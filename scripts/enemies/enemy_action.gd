class_name EnemyAction
extends EnemyComponent
## Something an enemy does to its target: an attack (a melee swing, a thrown spear, an arrow, a curse) or an
## ability on a cooldown (charge, stomp, blink, summon…). Each frame the Enemy offers its target to its
## actions, highest `priority` first; the first one that `can_start()` starts. While an action
## `drives_movement()` (a charge, a wind-up) it moves the enemy through `active_move()` until it ends.
## Server only; effects go through `enemy.fx()`.

@export var priority: int = 0
@export var cooldown: float = 1.0
## Random spread of each cooldown (± share), so a band doesn't act in lockstep.
@export_range(0.0, 0.5) var cooldown_jitter: float = 0.15
## Flat distance (center to center) the target must be within.
@export var min_range: float = 0.0
@export var max_range: float = 2.0
## Cooldown left when the enemy appears (abilities shouldn't all open a fight at once).
@export var first_use_delay: float = 0.0

var _cooldown_left: float = 0.0
var _active: bool = false
var _target: Node3D


func setup(owner_enemy: Enemy) -> void:
	super(owner_enemy)
	_cooldown_left = first_use_delay * randf_range(0.6, 1.0)


func server_tick(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _active:
		if GameConfig.is_gone(_target) and _ends_with_target():
			finish()
		else:
			_update(delta)


func can_start(target: Node3D) -> bool:
	if _active or _cooldown_left > 0.0 or enemy._action_time > 0.0:
		return false
	var dist := enemy.flat_distance_to(target)
	return dist >= min_range and dist <= max_range and _wants(target)


func start(target: Node3D) -> void:
	_target = target
	_cooldown_left = cooldown * randf_range(1.0 - cooldown_jitter, 1.0 + cooldown_jitter)
	_begin(target)


func is_active() -> bool:
	return _active


## True while this action moves the enemy itself (charges, wind-ups that root it).
func drives_movement() -> bool:
	return _active


func active_move(_delta: float) -> Vector3:
	return Vector3.ZERO


## Ends the action (also when the enemy dies or its target is gone).
func finish() -> void:
	_active = false


func on_died() -> void:
	if _active:
		finish()


## Virtual: extra conditions (a clear line, enough foes close by…).
func _wants(_target_node: Node3D) -> bool:
	return true


## Virtual: the action starts (set `_active` for one that lasts).
func _begin(_target_node: Node3D) -> void:
	pass


## Virtual: every frame while active.
func _update(_delta: float) -> void:
	pass


## Virtual: whether losing the target ends the action early.
func _ends_with_target() -> bool:
	return false


## Flat unit vector from the enemy toward `node`.
func dir_to(node: Node3D) -> Vector3:
	var to := node.global_position - enemy.global_position
	to.y = 0.0
	return to.normalized() if to.length_squared() > 0.0001 else enemy.facing()

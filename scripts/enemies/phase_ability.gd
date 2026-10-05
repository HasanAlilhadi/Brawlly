class_name PhaseAbility
extends EnemyAction
## Spirits fade out of this world for `duration` seconds: hits pass through them, they glide faster and
## can't attack. Triggered when struck (`on_hit_chance`) or to slip past a foe that's close.

const FX_PHASE: int = 0

@export var duration: float = 1.6
@export var speed_multiplier: float = 1.6
@export_range(0.0, 1.0) var on_hit_chance: float = 0.5
@export var faded_transparency: float = 0.8

var _time: float = 0.0


func drives_movement() -> bool:
	return false  # it keeps moving its own way, just faster


func blocks_hit(_amount: float, _attacker: Node3D) -> bool:
	return _active


func blocks_attacks() -> bool:
	return _active


func on_damaged(_attacker: Node3D, _amount: float) -> void:
	if not _active and _cooldown_left <= 0.0 and not enemy.is_dead and randf() < on_hit_chance:
		start(_attacker if _attacker else enemy)


func _begin(_target_node: Node3D) -> void:
	_active = true
	_time = duration
	enemy.speed_boost = speed_multiplier
	enemy.fx(self, FX_PHASE, enemy.global_position, duration)


func _update(delta: float) -> void:
	_time -= delta
	if _time <= 0.0:
		finish()


func finish() -> void:
	if _active:
		enemy.speed_boost = 1.0
	super()


func show_fx(_event: int, at: Vector3, value: float) -> void:
	HitFx.flash(at + Vector3(0, 0.8, 0), HitFx.REVIVE_SPARKLE, Color(0.6, 0.85, 1.0, 0.8), 1.6, 0.4)
	var movement := enemy.movement as FloatMovement
	var solid := movement.transparency if movement else 0.0
	var tween := enemy.create_tween()
	tween.tween_method(_set_see_through, solid, faded_transparency, 0.15)
	tween.tween_interval(maxf(value - 0.3, 0.0))
	tween.tween_method(_set_see_through, faded_transparency, solid, 0.15)


func _set_see_through(amount: float) -> void:
	for mesh in enemy.model.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).transparency = amount

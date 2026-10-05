class_name BlinkAbility
extends EnemyAction
## Vanishes in a puff of bats and reappears right behind its target (where it isn't looking), ready to
## strike at once.

const FX_VANISH: int = 0
const FX_APPEAR: int = 1
const SMOKE_COLOR := Color(0.25, 0.08, 0.2, 0.9)

@export var vanish_time: float = 0.35
@export var behind_distance: float = 1.3

var _time: float = 0.0


func _begin(_target_node: Node3D) -> void:
	_active = true
	_time = vanish_time
	enemy.fx(self, FX_VANISH, enemy.global_position, vanish_time)


func _update(delta: float) -> void:
	_time -= delta
	if _time > 0.0:
		return
	var spot := _spot_behind(_target)
	if spot != Vector3.INF:
		enemy.teleport(spot)
		enemy.face_now(dir_to(_target))
		enemy._melee_timer = 0.0
	enemy.fx(self, FX_APPEAR, enemy.global_position, 0.0)
	finish()


func _ends_with_target() -> bool:
	return false


func _spot_behind(target: Node3D) -> Vector3:
	if GameConfig.is_gone(target):
		return Vector3.INF
	var facing: Vector3 = target.call("facing") if target.has_method("facing") else -dir_to(target)
	var reach := behind_distance + Unit.target_radius(target)
	for angle in [0.0, 0.6, -0.6, 1.2, -1.2]:
		var spot := GameConfig.clamp_to_world(target.global_position - facing.rotated(Vector3.UP, angle) * reach)
		spot.y = 0.0
		if enemy.spot_is_free(spot, enemy.radius):
			return spot
	return Vector3.INF


func show_fx(event: int, at: Vector3, value: float) -> void:
	HitFx.flash(at + Vector3(0, 0.7, 0), HitFx.BIG_SMOKE, SMOKE_COLOR, 2.2, 0.5, Vector2(0.5, 1.4), false)
	HitFx.burst(at + Vector3(0, 0.8, 0), HitFx.Kind.BATS, 12)
	var tween := enemy.create_tween()
	if event == FX_VANISH:
		tween.tween_property(enemy.model, "scale", enemy._model_scale * 0.05, value).set_ease(Tween.EASE_IN)
	else:
		enemy.model.scale = enemy._model_scale * 0.05
		tween.tween_property(enemy.model, "scale", enemy._model_scale, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

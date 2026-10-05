class_name StompAbility
extends EnemyAction
## Ground slam: a red ring shows where it will land for `windup` seconds, then everything hostile inside
## `radius` takes `damage` and is thrown outward. Used when at least `min_foes` crowd it — and sooner
## (`crowded_cooldown`) when many do.

const FX_WARN: int = 0
const FX_IMPACT: int = 1
const WARN_COLOR := Color(1.0, 0.3, 0.15, 0.6)

@export var windup: float = 0.8
@export var radius: float = 3.2
@export var damage: float = 24.0
@export var push: float = 6.0
@export var min_foes: int = 1
@export var crowded_foes: int = 3
@export var crowded_cooldown: float = 4.0
@export var windup_animation: String = "crouch"
@export var impact_animation: String = "attack-kick-right"

var _time: float = 0.0


func _wants(_target_node: Node3D) -> bool:
	return enemy.foes_within(radius * 0.9) >= min_foes


func _begin(_target_node: Node3D) -> void:
	_active = true
	_time = windup
	if windup_animation != "":
		enemy.play_action(windup_animation, windup, Unit.ARM_BOTH)
	enemy.fx(self, FX_WARN, enemy.global_position, radius)


func _update(delta: float) -> void:
	_time -= delta
	if _time > 0.0:
		return
	var crowd := 0
	for node in get_tree().get_nodes_in_group(&"player_units"):
		var foe := node as Node3D
		if GameConfig.is_gone(foe) or not GameConfig.is_hostile(enemy, foe) or enemy.flat_distance_to(foe) > radius:
			continue
		crowd += 1
		foe.take_damage(damage * power(), enemy, true)
		if foe.has_method("shove"):
			var away := foe.global_position - enemy.global_position
			away.y = 0.0
			foe.call("shove", away.normalized() * push)
	if crowd >= crowded_foes:
		_cooldown_left = minf(_cooldown_left, crowded_cooldown)
	if impact_animation != "":
		enemy.play_action(impact_animation, 0.45 / enemy.anim_speed, Unit.ARM_BOTH)
	enemy.fx(self, FX_IMPACT, enemy.global_position, radius)
	finish()


func show_fx(event: int, at: Vector3, value: float) -> void:
	match event:
		FX_WARN:
			HitFx.ground_warning(at, value, windup, WARN_COLOR)
		FX_IMPACT:
			HitFx.shockwave(at, value)

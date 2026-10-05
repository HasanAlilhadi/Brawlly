class_name LifeStealTrait
extends EnemyComponent
## Heals itself for `share` of the damage its melee hits deal (vampires).

const FX_DRAIN: int = 0

@export_range(0.0, 2.0) var share: float = 0.5


func on_hit_dealt(victim: Node3D, amount: float) -> void:
	if enemy.health >= enemy.max_health:
		return
	enemy.heal(amount * share)
	enemy.fx(self, FX_DRAIN, victim.global_position, 0.0)


func show_fx(_event: int, at: Vector3, _value: float) -> void:
	HitFx.flash(at + Vector3(0, 0.8, 0), HitFx.REVIVE_SPARKLE, Color(1.0, 0.15, 0.2, 0.9), 0.9, 0.3)
	HitFx.flash(enemy.global_position + Vector3(0, enemy.health_bar_height * 0.6, 0), HitFx.REVIVE_SPARKLE,
			Color(1.0, 0.2, 0.25, 0.9), 1.3 * sqrt(enemy.radius / 0.35), 0.4, Vector2(1.2, 0.5))

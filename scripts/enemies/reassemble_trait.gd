class_name ReassembleTrait
extends EnemyComponent
## Skeletons: the first time it would die it falls apart into a pile of bones instead and gets back up
## `rise_time` seconds later with `health_share` of its health. While it lies there the AI ignores it, but
## any hit on the pile scatters the bones for good. A routed band doesn't get up.

const FX_COLLAPSE: int = 0
const FX_RISE: int = 1

@export var uses: int = 1
@export var rise_time: float = 3.5
@export_range(0.1, 1.0) var health_share: float = 0.5


func prevents_death() -> bool:
	if uses <= 0:
		return false
	uses -= 1
	enemy.collapse(rise_time, health_share)
	return true


func show_fx(event: int, at: Vector3, _value: float) -> void:
	HitFx.burst(at + Vector3(0, 0.5, 0), HitFx.Kind.BONES, 14)
	if event == FX_RISE:
		HitFx.flash(at + Vector3(0, 0.6, 0), HitFx.REVIVE_SPARKLE, Color(0.6, 1.0, 0.7, 0.85), 1.4, 0.45)
		FloatingText3D.spawn(HitFx.world, at + Vector3(0, enemy.health_bar_height + 0.3, 0), "Rises again!", Color(0.7, 1.0, 0.75), 32)

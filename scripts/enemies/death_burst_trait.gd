class_name DeathBurstTrait
extends EnemyComponent
## Bursts when it dies: a ring marks the spot for `delay` seconds, then a cloud hurts every hero and
## soldier inside `radius` (zombies: a rotten gas cloud). Step away from the body!

const FX_WARN: int = 0
const FX_BURST: int = 1

@export var delay: float = 0.8
@export var radius: float = 2.2
@export var damage: float = 16.0
@export var color: Color = Color(0.45, 0.9, 0.25, 0.6)


func on_died() -> void:
	if enemy.routed:
		return
	var at := enemy.global_position
	enemy.fx(self, FX_WARN, at, delay)
	var tree := get_tree()
	var strength := power()
	var source := enemy
	tree.create_timer(delay).timeout.connect(func() -> void:
		for node in tree.get_nodes_in_group(&"player_units"):
			var foe := node as Node3D
			if GameConfig.is_gone(foe) or not GameConfig.is_hostile(source if is_instance_valid(source) else self, foe):
				continue
			if Vector2(foe.global_position.x - at.x, foe.global_position.z - at.z).length() <= radius:
				foe.take_damage(damage * strength, source if is_instance_valid(source) else null, false)
		if is_instance_valid(source):
			source.fx(self, FX_BURST, at, radius))


func blocks_hit(_amount: float, _attacker: Node3D) -> bool:
	return false


func show_fx(event: int, at: Vector3, value: float) -> void:
	if event == FX_WARN:
		HitFx.ground_warning(at, radius, value, color)
	else:
		HitFx.flash(at + Vector3(0, 0.5, 0), HitFx.BIG_SMOKE, Color(color, 0.85), value * 2.2, 0.8, Vector2(0.4, 1.3), false)
		HitFx.burst(at + Vector3(0, 0.4, 0), HitFx.Kind.POISON, 20)

class_name HealAuraTrait
extends EnemyComponent
## Heals its own: every `interval` s the most wounded demon within `radius` (its band's members first, any demon
## else; itself too) gets `amount` × its power back — a green sparkle on both on every peer. Runs whether or not
## it is fighting (the healer lieutenant keeps its army standing).

const FX_HEAL: int = 0

@export var interval: float = 2.0
@export var radius: float = 12.0
@export var amount: float = 45.0
## Heals the most wounded only when it is missing at least this share of its health.
@export_range(0.0, 1.0) var below_share: float = 0.95

var _left: float = 1.0


func server_tick(delta: float) -> void:
	_left -= delta
	if _left > 0.0 or enemy.is_dead:
		return
	_left = interval
	var patient := _patient()
	if patient == null:
		return
	patient.heal(amount * power())
	enemy.fx(self, FX_HEAL, patient.global_position, 0.0)


## The most wounded (share) demon in reach: its band first.
func _patient() -> Enemy:
	var pool: Array = []
	if is_instance_valid(enemy.band):
		pool = enemy.band.members()
	if pool.size() <= 1:
		pool = enemy.get_tree().get_nodes_in_group(&"active_enemies")
	var best: Enemy = null
	var best_share := below_share
	for node in pool:
		var other := node as Enemy
		if other == null or GameConfig.is_gone(other) or other.team_id != enemy.team_id:
			continue
		if enemy.flat_distance_to(other) > radius:
			continue
		var share := other.health / maxf(other.max_health, 1.0)
		if share < best_share:
			best_share = share
			best = other
	return best


func show_fx(_event: int, at: Vector3, _value: float) -> void:
	var green := Color(0.35, 1.0, 0.45, 0.95)
	HitFx.flash(at + Vector3(0, 1.0, 0), HitFx.REVIVE_SPARKLE, green, 1.3, 0.45, Vector2(1.2, 0.5))
	HitFx.flash(enemy.global_position + Vector3(0, enemy.health_bar_height * 0.7, 0), HitFx.REVIVE_SPARKLE,
			green, 0.9, 0.3)

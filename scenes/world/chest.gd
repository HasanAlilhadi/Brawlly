class_name Chest
extends StaticBody3D
## Treasure chest: break it open (sword, arrows or spears) to spill arrows, spears, coins and
## sometimes health, then it disappears. Each hit shakes it and knocks off splinters.
## Multiplayer: the server decides (any player can break it); the effects play on every peer via RPC.

@export var max_health: float = 60.0
@export var arrows_min: int = 6
@export var arrows_max: int = 10
@export var spears_min: int = 2
@export var spears_max: int = 3
@export_range(0.0, 1.0) var health_chance: float = 0.6
@export var coins_min: int = 8
@export var coins_max: int = 16

var health: float
var is_dead: bool = false

var _shake_tween: Tween

@onready var _model: Node3D = $Model


func _ready() -> void:
	health = max_health
	add_to_group(&"breakable")


func take_damage(amount: float, attacker: Node3D = null, is_melee: bool = true, crit: bool = false) -> void:
	if is_dead or not multiplayer.is_server():
		return
	HitFx.report_hit(self, minf(amount, health), attacker, crit, is_melee)
	health -= amount
	if health <= 0.0:
		_break()
	else:
		_net_hit.rpc()


func _break() -> void:
	is_dead = true
	var world := get_parent()
	Pickup.drop(world, global_position, Pickup.Kind.ARROWS, randi_range(arrows_min, arrows_max))
	Pickup.drop(world, global_position, Pickup.Kind.SPEARS, randi_range(spears_min, spears_max))
	if randf() < health_chance:
		Pickup.drop(world, global_position, Pickup.Kind.HEALTH, 30)
	Pickup.drop(world, global_position, Pickup.Kind.COIN, randi_range(coins_min, coins_max))
	_net_open.rpc()


@rpc("authority", "call_local", "unreliable")
func _net_hit() -> void:
	HitFx.burst(global_position + Vector3(0, 0.5, 0), HitFx.Kind.WOOD, 7)
	if _shake_tween:
		_shake_tween.kill()
	_model.scale = Vector3(1.15, 0.85, 1.15)
	_model.rotation.z = 0.15
	_shake_tween = create_tween().set_parallel(true)
	_shake_tween.tween_property(_model, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_shake_tween.tween_property(_model, "rotation:z", 0.0, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


@rpc("authority", "call_local", "reliable")
func _net_open() -> void:
	if collision_layer == 0:
		return
	is_dead = true
	collision_layer = 0
	HitFx.burst(global_position + Vector3(0, 0.5, 0), HitFx.Kind.WOOD, 18)
	HitFx.flash(global_position + Vector3(0, 0.5, 0), HitFx.DEATH_SMOKE, Color(0.9, 0.85, 0.75, 0.8), 1.8, 0.6,
			Vector2(0.5, 1.4), false)
	var tween := create_tween()
	tween.tween_property(_model, "scale", Vector3(1.3, 1.5, 1.3), 0.08)
	tween.tween_property(_model, "scale", Vector3.ONE * 0.01, 0.22).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

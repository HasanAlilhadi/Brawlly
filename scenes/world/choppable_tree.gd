class_name ChoppableTree
extends StaticBody3D
## Tree that can be chopped with melee hits (arrows just stick). Some drop arrows when they fall (arrow_chance).
## Multiplayer: the server decides; the shake / fall play on every peer via RPC.

@export var models: Array[PackedScene] = []
@export var max_health: float = 60.0
@export var arrow_drop: int = 3
## Chance a felled tree drops its arrows (the rest give only wood chips).
@export_range(0.0, 1.0) var arrow_chance: float = 0.5

var health: float
var is_dead: bool = false

var _model: Node3D
var _shake_tween: Tween


func _ready() -> void:
	health = max_health
	add_to_group(&"choppable")
	if not models.is_empty():
		_model = models.pick_random().instantiate() as Node3D
		_model.rotation.y = randf() * TAU
		add_child(_model)


func take_damage(amount: float, attacker: Node3D = null, is_melee: bool = true, crit: bool = false) -> void:
	if is_dead or not is_melee or not multiplayer.is_server():
		return
	HitFx.report_hit(self, minf(amount, health), attacker, crit, is_melee)
	health -= amount
	if health <= 0.0:
		MatchStats.add(GameConfig.owner_peer_of(attacker), &"trees")
		if randf() < arrow_chance:
			Pickup.drop(get_parent(), global_position, Pickup.Kind.ARROWS, arrow_drop)
		_net_fall.rpc()
	else:
		_net_shake.rpc()


@rpc("authority", "call_local", "unreliable")
func _net_shake() -> void:
	HitFx.burst(global_position + Vector3(0, 1.1, 0), HitFx.Kind.LEAVES, 8)
	HitFx.burst(global_position + Vector3(0, 0.5, 0), HitFx.Kind.WOOD, 6)
	if _shake_tween:
		_shake_tween.kill()
	_model.rotation.z = 0.12
	_shake_tween = create_tween()
	_shake_tween.tween_property(_model, "rotation:z", 0.0, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


@rpc("authority", "call_local", "reliable")
func _net_fall() -> void:
	if is_dead:
		return
	is_dead = true
	collision_layer = 0
	HitFx.burst(global_position + Vector3(0, 1.2, 0), HitFx.Kind.LEAVES, 18)
	var tween := create_tween()
	tween.tween_property(_model, "rotation:x", PI * 0.5, 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_model, "scale", Vector3.ONE * 0.01, 0.4)
	tween.tween_callback(queue_free)

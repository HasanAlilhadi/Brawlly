class_name Chest
extends StaticBody3D
## Treasure chest: opens automatically when the player walks up to it,
## spills arrows, coins (and sometimes health), then disappears.
## Multiplayer: the server opens it (any player can); the effect plays on every peer via RPC.

@export var open_range: float = 1.2
@export var arrows_min: int = 6
@export var arrows_max: int = 10
@export_range(0.0, 1.0) var health_chance: float = 0.6
@export var coins_min: int = 8
@export var coins_max: int = 16

var _check_timer: float = 0.0
var _opened: bool = false

@onready var _model: Node3D = $Model


func _ready() -> void:
	_check_timer = randf() * 0.2


func _physics_process(delta: float) -> void:
	if _opened or not multiplayer.is_server():
		return
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = 0.2
	for player in get_tree().get_nodes_in_group(&"players"):
		if not GameConfig.is_gone(player) and global_position.distance_to((player as Node3D).global_position) < open_range:
			_open()
			return


func _open() -> void:
	var world := get_parent()
	Pickup.drop(world, global_position, Pickup.Kind.ARROWS, randi_range(arrows_min, arrows_max))
	if randf() < health_chance:
		Pickup.drop(world, global_position, Pickup.Kind.HEALTH, 30)
	Pickup.drop(world, global_position, Pickup.Kind.COIN, randi_range(coins_min, coins_max))
	_net_open.rpc()


@rpc("authority", "call_local", "reliable")
func _net_open() -> void:
	if _opened:
		return
	_opened = true
	collision_layer = 0
	var tween := create_tween()
	tween.tween_property(_model, "scale", Vector3(1.3, 1.5, 1.3), 0.12)
	tween.tween_property(_model, "scale", Vector3.ONE * 0.01, 0.3).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

class_name Pickup
extends Node3D
## Item lying on the ground (arrows, spears, health or coins). Spins, gets pulled toward the nearest player
## who can use it, and is collected on contact. Disappears after a while.
## Multiplayer: spawned by the server through NetSpawn; every peer animates the pull, only the
## server decides who collects it (freeing it removes it everywhere).

## Ammo (ARROWS / SPEARS) is only pulled to and collected by players carrying that weapon.
enum Kind { ARROWS, HEALTH, COIN, SPEARS }

const SCENE_PATH := "res://scenes/items/pickup.tscn"
const ARROW_MODEL := preload("res://assets/items/forest/arrow.glb")
const POTION_MODEL := preload("res://assets/items/dungeon/potion.glb")
const COIN_MODEL := preload("res://assets/items/dungeon/coin.glb")
const SPEAR_MODEL := preload("res://assets/items/dungeon/spear.glb")

@export var kind: Kind = Kind.ARROWS
@export var amount: int = 3
@export var magnet_range: float = 2.2
@export var collect_range: float = 0.45
@export var lifetime: float = 90.0

var _age: float = 0.0
var _visual: Node3D


## Spawns a pickup near `at` with a little pop (server only; mirrored to every peer).
static func drop(_parent: Node, at: Vector3, pickup_kind: Kind, pickup_amount: int) -> void:
	var scatter := Vector3(randf_range(-0.7, 0.7), 0.0, randf_range(-0.7, 0.7))
	NetSpawn.pickup(pickup_kind, pickup_amount, GameConfig.clamp_to_world(Vector3(at.x, 0.0, at.z) + scatter))


func _ready() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	match kind:
		Kind.ARROWS:
			for i in 3:
				var arrow := ARROW_MODEL.instantiate() as Node3D
				arrow.rotation_degrees = Vector3(0, -20.0 + i * 20.0, 0)
				arrow.position = Vector3((i - 1) * 0.06, 0, 0)
				_visual.add_child(arrow)
			_visual.scale = Vector3.ONE * 1.4
		Kind.SPEARS:
			for i in 2:
				var spear := SPEAR_MODEL.instantiate() as Node3D
				spear.rotation_degrees = Vector3(90, -15.0 + i * 30.0, 0)
				spear.position = Vector3((i - 0.5) * 0.08, 0.05, 0)
				_visual.add_child(spear)
		Kind.HEALTH:
			_visual.add_child(POTION_MODEL.instantiate())
			_visual.scale = Vector3.ONE * 1.2
		Kind.COIN:
			_visual.add_child(COIN_MODEL.instantiate())
			# Bigger piles look bigger.
			_visual.scale = Vector3.ONE * clampf(0.9 + amount * 0.03, 0.9, 1.8)
			magnet_range = 3.5
	# Pop out of the ground.
	_visual.position.y = 0.8
	create_tween().tween_property(_visual, "position:y", 0.25, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_age += delta
	_visual.rotation.y += delta * 2.0
	var server := multiplayer.is_server()
	if _age > lifetime:
		if server:
			queue_free()
		return
	var player := _nearest_collector()
	if player == null:
		return
	var to := player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < collect_range:
		if server and player.collect(kind, amount):
			queue_free()
	elif dist < magnet_range and _age > 0.4:
		global_position += to / dist * minf(dist, delta * 7.0)


func _nearest_collector() -> Player:
	var best: Player = null
	var best_dist := magnet_range
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player.is_dead or not player.can_collect(kind):
			continue
		var d := player.global_position.distance_to(global_position)
		if d < best_dist:
			best_dist = d
			best = player
	return best

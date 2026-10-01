class_name Pickup
extends Node3D
## Item lying on the ground (health, coins or XP). Spins, gets pulled toward the nearest player who can
## use it, and is collected on contact. Disappears after a while.
## Multiplayer: spawned by the server through NetSpawn; every peer animates the pull, only the
## server decides who collects it (freeing it removes it everywhere).

## Append new kinds (the ids are sent over the network). Weapons never run out of ammo, so none drop.
enum Kind { HEALTH, COIN, XP }

const SCENE_PATH := "res://scenes/items/pickup.tscn"
const POTION_MODEL := preload("res://assets/items/dungeon/potion.glb")
const COIN_MODEL := preload("res://assets/items/dungeon/coin.glb")
const XP_GLOW := preload("res://assets/vfx/particles/magic_02.png")
const XP_COLOR := Color(0.45, 0.8, 1.0)

@export var kind: Kind = Kind.COIN
@export var amount: int = 3
@export var magnet_range: float = 2.2
@export var collect_range: float = 0.45
@export var lifetime: float = 90.0

var _age: float = 0.0
var _visual: Node3D


## Spawns a pickup near `at` with a little pop (server only; mirrored to every peer).
static func drop(_parent: Node, at: Vector3, pickup_kind: Kind, pickup_amount: int) -> void:
	if pickup_amount <= 0:
		return
	var scatter := Vector3(randf_range(-0.7, 0.7), 0.0, randf_range(-0.7, 0.7))
	NetSpawn.pickup(pickup_kind, pickup_amount, GameConfig.clamp_to_world(Vector3(at.x, 0.0, at.z) + scatter))


func _ready() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	match kind:
		Kind.HEALTH:
			_visual.add_child(POTION_MODEL.instantiate())
			_visual.scale = Vector3.ONE * 1.2
		Kind.COIN:
			_visual.add_child(COIN_MODEL.instantiate())
			# Bigger piles look bigger.
			_visual.scale = Vector3.ONE * clampf(0.9 + amount * 0.03, 0.9, 1.8)
			magnet_range = 3.5
		Kind.XP:
			# A glowing orb (bigger for more XP): a soft glow around a bright core.
			var material := StandardMaterial3D.new()
			material.albedo_texture = XP_GLOW
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			material.vertex_color_use_as_albedo = true
			material.no_depth_test = false
			for layer in [[1.0, 0.55], [0.45, 1.0]]:
				var glow := Sprite3D.new()
				glow.texture = XP_GLOW
				glow.material_override = material
				glow.modulate = Color(XP_COLOR, layer[1])
				glow.pixel_size = 0.75 * layer[0] / XP_GLOW.get_width()
				_visual.add_child(glow)
			_visual.scale = Vector3.ONE * clampf(0.8 + amount * 0.06, 0.8, 1.6)
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

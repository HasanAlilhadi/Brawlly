class_name Chest
extends StaticBody3D
## Treasure chest with five color-coded rarities. Break it open (any weapon) to spill
## tiered coins and sometimes health, then it disappears.
## Multiplayer: the server decides (any player can break it); the effects play on every peer via RPC.

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const RARITY_WEIGHTS: PackedFloat32Array = [55.0, 25.0, 12.0, 6.0, 2.0]
const DEFINITIONS: Array[Dictionary] = [
	{"name": "Common", "color": Color("b8b0a3"), "health": 60.0, "heal_chance": 0.35,
		"heal": 25, "coins": Vector2i(8, 15)},
	{"name": "Uncommon", "color": Color("45cf72"), "health": 75.0, "heal_chance": 0.6,
		"heal": 30, "coins": Vector2i(16, 26)},
	{"name": "Rare", "color": Color("3f8cff"), "health": 95.0, "heal_chance": 0.8,
		"heal": 40, "coins": Vector2i(30, 48)},
	{"name": "Epic", "color": Color("a95cff"), "health": 125.0, "heal_chance": 1.0,
		"heal": 55, "coins": Vector2i(55, 85)},
	{"name": "Legendary", "color": Color("ffbd32"), "health": 170.0, "heal_chance": 1.0,
		"heal": 80, "coins": Vector2i(110, 160)},
]
const RARITY_GLOW := preload("res://assets/shaders/highlight_glow.gdshader")

@export var rarity: Rarity = Rarity.COMMON

var health: float
var max_health: float
var is_dead: bool = false

var _shake_tween: Tween

@onready var _model: Node3D = $Model


func _ready() -> void:
	max_health = float(definition().health)
	health = max_health
	add_to_group(&"breakable")
	_apply_rarity_visuals()


static func roll_rarity() -> Rarity:
	var roll := randf() * 100.0
	var total := 0.0
	for i in RARITY_WEIGHTS.size():
		total += RARITY_WEIGHTS[i]
		if roll < total:
			return i as Rarity
	return Rarity.LEGENDARY


func definition() -> Dictionary:
	return DEFINITIONS[clampi(rarity, Rarity.COMMON, Rarity.LEGENDARY)]


func rarity_name() -> String:
	return definition().name


func rarity_color() -> Color:
	return definition().color


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
	var loot := definition()
	var coins: Vector2i = loot.coins
	if randf() < float(loot.heal_chance):
		Pickup.drop(world, global_position, Pickup.Kind.HEALTH, int(loot.heal))
	Pickup.drop(world, global_position, Pickup.Kind.COIN, randi_range(coins.x, coins.y))
	_net_open.rpc()


func _apply_rarity_visuals() -> void:
	var color := rarity_color()
	var glow := ShaderMaterial.new()
	glow.shader = RARITY_GLOW
	glow.set_shader_parameter("glow_color", color)
	glow.set_shader_parameter("rim_strength", 0.7)
	glow.set_shader_parameter("fill_strength", 0.12)
	glow.set_shader_parameter("pulse_speed", 0.55 if rarity >= Rarity.RARE else 0.0)
	glow.set_shader_parameter("pulse_depth", 0.25)
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_overlay = glow

	var torus := TorusMesh.new()
	torus.inner_radius = 0.58
	torus.outer_radius = 0.7
	torus.rings = 32
	torus.ring_segments = 6
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = color
	torus.material = ring_material
	var ring := MeshInstance3D.new()
	ring.name = "RarityRing"
	ring.mesh = torus
	ring.position.y = 0.065
	ring.scale.y = 0.12
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

	var label := Label3D.new()
	label.name = "RarityLabel"
	label.text = rarity_name()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 38
	label.outline_size = 10
	label.pixel_size = 0.006
	label.modulate = color.lightened(0.18)
	label.position = Vector3(0, 1.45, 0)
	label.visibility_range_end = 14.0
	add_child(label)


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
	HitFx.flash(global_position + Vector3(0, 0.5, 0), HitFx.DEATH_SMOKE, Color(rarity_color(), 0.8), 1.8, 0.6,
			Vector2(0.5, 1.4), false)
	var tween := create_tween()
	tween.tween_property(_model, "scale", Vector3(1.3, 1.5, 1.3), 0.08)
	tween.tween_property(_model, "scale", Vector3.ONE * 0.01, 0.22).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

class_name GoldVein
extends StaticBody3D
## A boulder with gold crystals: every hit (any weapon, any hero) knocks loose `COINS_PER_HIT` coins until the
## vein is empty; left alone it grows back `REGROW_STEP` gold every `REGROW_EVERY` seconds. The crystals shrink
## as it is mined. Placed by WorldBuilder on every map (one next to each spawn, more around the world).
## Multiplayer: the server decides (coins drop as pickups); the gold left and the hit effects reach every peer
## via `_net_gold` (static world node, same name everywhere).

const MAX_GOLD: int = 30
const COINS_PER_HIT: int = 2
## A crit knocks loose one more.
const CRIT_BONUS: int = 1
## Hits closer together than this count once (a cleave or a piercing arrow touching it twice).
const HIT_COOLDOWN: float = 0.22
## Regrowth starts this long after the last hit.
const REGROW_DELAY: float = 6.0
const REGROW_EVERY: float = 8.0
const REGROW_STEP: int = 5
const GOLD_COLOR := Color(1.0, 0.8, 0.25)
const GLOW := preload("res://assets/shaders/highlight_glow.gdshader")

var gold: int = MAX_GOLD
## Static world props are never "dead" (AI and aim assist ignore them anyway).
var is_dead: bool = false

var _since_hit: float = 100.0
var _regrow_timer: float = 0.0
var _hit_cooldown: float = 0.0
var _shake_tween: Tween
var _label: Label3D

@onready var _model: Node3D = $Model
@onready var _crystals: Node3D = $Model/Crystals


func _ready() -> void:
	add_to_group(&"breakable")
	add_to_group(&"gold_veins")
	var glow := ShaderMaterial.new()
	glow.shader = GLOW
	glow.set_shader_parameter("glow_color", GOLD_COLOR)
	glow.set_shader_parameter("rim_strength", 0.9)
	glow.set_shader_parameter("fill_strength", 0.22)
	glow.set_shader_parameter("pulse_speed", 0.6)
	glow.set_shader_parameter("pulse_depth", 0.35)
	for node in _crystals.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_overlay = glow
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 34
	_label.outline_size = 10
	_label.pixel_size = 0.006
	_label.position = Vector3(0, 1.75, 0)
	_label.visibility_range_end = 13.0
	add_child(_label)
	_apply_gold(false)


func take_damage(amount: float, attacker: Node3D = null, _is_melee: bool = true, crit: bool = false) -> void:
	if not multiplayer.is_server() or amount <= 0.0 or gold <= 0 or _hit_cooldown > 0.0:
		return
	_hit_cooldown = HIT_COOLDOWN
	_since_hit = 0.0
	_regrow_timer = 0.0
	var coins := mini(COINS_PER_HIT + (CRIT_BONUS if crit else 0), gold)
	# Coins pop out toward whoever struck (they still fly to the nearest hero who can take them).
	var at := global_position
	if is_instance_valid(attacker):
		at += (attacker.global_position - global_position).normalized() * 0.9
	Pickup.drop(get_parent(), at, Pickup.Kind.COIN, coins)
	MatchStats.add(GameConfig.owner_peer_of(attacker), &"mined", coins)
	_net_gold.rpc(gold - coins, true)


func _process(delta: float) -> void:
	_hit_cooldown -= delta
	if not multiplayer.is_server() or gold >= MAX_GOLD:
		return
	_since_hit += delta
	if _since_hit < REGROW_DELAY:
		return
	_regrow_timer += delta
	if _regrow_timer >= REGROW_EVERY:
		_regrow_timer = 0.0
		_net_gold.rpc(mini(gold + REGROW_STEP, MAX_GOLD), false)


func gold_ratio() -> float:
	return float(gold) / MAX_GOLD


@rpc("authority", "call_local", "reliable")
func _net_gold(new_gold: int, hit: bool) -> void:
	gold = new_gold
	_apply_gold(hit)


func _apply_gold(hit: bool) -> void:
	_crystals.visible = gold > 0
	_crystals.scale = Vector3.ONE * lerpf(0.35, 1.0, gold_ratio())
	_label.text = "Gold vein" if gold > 0 else "Depleted"
	_label.modulate = GOLD_COLOR.lightened(0.15) if gold > 0 else Color(0.75, 0.75, 0.75, 0.8)
	if not hit:
		return
	HitFx.burst(global_position + Vector3(0, 0.7, 0), HitFx.Kind.METAL, 10)
	HitFx.flash(global_position + Vector3(0, 0.8, 0), HitFx.HIT_SPARK, GOLD_COLOR, 0.9, 0.18)
	if gold <= 0:
		HitFx.flash(global_position + Vector3(0, 0.6, 0), HitFx.DEATH_SMOKE, Color(0.7, 0.65, 0.55, 0.8), 1.6, 0.5,
				Vector2(0.5, 1.2), false)
	if _shake_tween:
		_shake_tween.kill()
	_model.scale = Vector3(1.08, 0.92, 1.08)
	_model.rotation.z = 0.07
	_shake_tween = create_tween().set_parallel(true)
	_shake_tween.tween_property(_model, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_shake_tween.tween_property(_model, "rotation:z", 0.0, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

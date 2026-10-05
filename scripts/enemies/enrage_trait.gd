class_name EnrageTrait
extends EnemyComponent
## Once its health drops below `below_share` it flies into a rage (a roar, a red glow): faster, harder
## hitting and quicker swings for the rest of the fight.

const FX_ENRAGE: int = 0

@export_range(0.05, 0.95) var below_share: float = 0.35
@export var speed_multiplier: float = 1.3
@export var damage_multiplier: float = 1.3
@export var attack_speed_multiplier: float = 1.35
@export var shout: String = "RAAAGH!"

var _done: bool = false
var _aura: MeshInstance3D


func server_tick(_delta: float) -> void:
	if _done or enemy.health > enemy.max_health * below_share:
		return
	_done = true
	enemy.rage_speed = speed_multiplier
	enemy.melee_damage *= damage_multiplier
	enemy.melee_cooldown /= attack_speed_multiplier
	if shout != "":
		enemy.shout(shout)
	enemy.fx(self, FX_ENRAGE, enemy.global_position, 0.0)


func show_fx(_event: int, at: Vector3, _value: float) -> void:
	HitFx.flash(at + Vector3(0, enemy.health_bar_height * 0.5, 0), HitFx.COMBO_RING, Color(1.0, 0.2, 0.1, 0.9),
			3.0 * sqrt(enemy.radius / 0.35), 0.5, Vector2(0.4, 1.4))
	# A red aura pulsing on the ground under it for the rest of the fight.
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE * (enemy.radius * 5.0 + 1.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_texture = HitFx.WARN_DISC
	material.albedo_color = Color(1.0, 0.15, 0.05, 0.7)
	mesh.material = material
	var aura := MeshInstance3D.new()
	aura.mesh = mesh
	aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	aura.position.y = 0.06
	enemy.add_child(aura)
	var tween := aura.create_tween().set_loops()
	tween.tween_property(aura, "scale", Vector3.ONE * 1.15, 0.45).set_trans(Tween.TRANS_SINE)
	tween.tween_property(aura, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_SINE)
	_aura = aura


func on_death_visuals() -> void:
	if is_instance_valid(_aura):
		_aura.queue_free()

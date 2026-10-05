class_name ChargeAbility
extends EnemyAction
## Winds up (a lane flashes on the ground in front of it, and it may shout), then rushes along that line
## at `speed_multiplier` × its speed: every foe it runs into takes `damage` and is shoved aside (or only the
## first one, then it stops). Walls stop it. Orc brutes and the Warlord charge; zombies lunge with a short one.

enum Phase { WINDUP, DASH, RECOVER }
const FX_LANE: int = 0
const LANE_COLOR := Color(1.0, 0.25, 0.15, 0.55)

@export var windup: float = 0.7
@export var dash_time: float = 1.0
@export var speed_multiplier: float = 2.6
@export var damage: float = 25.0
@export var push: float = 7.0
## Damage everyone crossed (true) or stop at the first foe hit.
@export var hits_all: bool = true
@export var recover: float = 0.5
@export var show_lane: bool = true
@export var lane_width: float = 1.4
@export var shout: String = ""
## Clip played during the wind-up ("" = none).
@export var windup_animation: String = ""

var _phase: int = Phase.WINDUP
var _time: float = 0.0
var _dir: Vector3 = Vector3.FORWARD
var _hit: Dictionary = {}
var _start_pos: Vector3


func _wants(target: Node3D) -> bool:
	return enemy.clear_line_to(target)


func _begin(target: Node3D) -> void:
	_active = true
	_phase = Phase.WINDUP
	_time = windup
	_dir = dir_to(target)
	enemy.face_now(_dir)
	if windup_animation != "":
		enemy.play_action(windup_animation, windup, Unit.ARM_BOTH)
	if show_lane:
		var length := minf(enemy.move_speed * speed_multiplier * dash_time, enemy.flat_distance_to(target) + 2.5)
		enemy.fx(self, FX_LANE, _dir, length)
	if shout != "":
		enemy.shout(shout)


func _update(delta: float) -> void:
	_time -= delta
	match _phase:
		Phase.WINDUP:
			enemy.face_now(_dir)
			if _time <= 0.0:
				_phase = Phase.DASH
				_time = dash_time
				_hit.clear()
				_start_pos = enemy.global_position
				enemy.speed_boost = speed_multiplier
		Phase.DASH:
			if _hit_foes() or _time <= 0.0 or (_time < dash_time - 0.2 and enemy.get_real_velocity().length() < enemy.move_speed * 0.25):
				_end_dash()
		Phase.RECOVER:
			if _time <= 0.0:
				finish()


func active_move(_delta: float) -> Vector3:
	return _dir if _phase == Phase.DASH else Vector3.ZERO


func finish() -> void:
	if _phase == Phase.DASH:
		enemy.speed_boost = 1.0
	_phase = Phase.WINDUP
	super()


func _end_dash() -> void:
	enemy.speed_boost = 1.0
	_phase = Phase.RECOVER
	_time = recover


## Returns true when the charge should stop (it hit someone and doesn't plow on).
func _hit_foes() -> bool:
	for node in get_tree().get_nodes_in_group(&"player_units"):
		var foe := node as Node3D
		if GameConfig.is_gone(foe) or _hit.has(foe) or not GameConfig.is_hostile(enemy, foe):
			continue
		if enemy.flat_distance_to(foe) > enemy.radius + Unit.target_radius(foe) + 0.4:
			continue
		_hit[foe] = true
		foe.take_damage(damage * power(), enemy, true)
		if foe.has_method("shove"):
			var side := (foe.global_position - enemy.global_position)
			side.y = 0.0
			foe.call("shove", (_dir + side.normalized() * 0.6).normalized() * push)
		if not hits_all:
			return true
	return false


func show_fx(event: int, at: Vector3, value: float) -> void:
	if event == FX_LANE:
		HitFx.lane_warning(enemy.global_position, at, value, lane_width, windup, LANE_COLOR)

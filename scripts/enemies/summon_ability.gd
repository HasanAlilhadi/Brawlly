class_name SummonAbility
extends EnemyAction
## Raises minions from the ground around it (green circles mark the spots during the wind-up); they climb
## out and join its warband. Keeps at most `max_alive` of its minions up. With `health_thresholds` it also
## summons, once each, when its health drops below those shares (the Warlord's rally, the Vampire Lord's
## undead) — `only_at_thresholds` makes those the only times.

const FX_MARK: int = 0
const MARK_COLOR := Color(0.45, 1.0, 0.4, 0.6)

@export var minions: Array[PackedScene] = []
@export var count: int = 2
@export var max_alive: int = 4
@export var windup: float = 1.0
## Minions appear this far around it.
@export var spread: float = 2.2
@export var health_thresholds: PackedFloat32Array = PackedFloat32Array()
@export var only_at_thresholds: bool = false
@export var shout: String = "Rise!"
@export var animation: String = "interact-right"
@export var mark_color: Color = MARK_COLOR

var _time: float = 0.0
var _spots: Array[Vector3] = []
var _alive: Array[Enemy] = []
var _thresholds_done: int = 0
var _pending: int = 0


func server_tick(delta: float) -> void:
	while _thresholds_done < health_thresholds.size() \
			and enemy.health <= enemy.max_health * health_thresholds[_thresholds_done]:
		_thresholds_done += 1
		_pending += 1
	super(delta)


func can_start(target: Node3D) -> bool:
	if _active or enemy._action_time > 0.0 or minions.is_empty():
		return false
	if _pending > 0:
		return true
	if only_at_thresholds or _cooldown_left > 0.0 or _living() >= max_alive:
		return false
	return enemy.flat_distance_to(target) <= max_range


func start(target: Node3D) -> void:
	if _pending > 0:
		_pending -= 1
		_target = target
		_begin(target)
	else:
		super(target)


func _begin(_target_node: Node3D) -> void:
	_active = true
	_time = windup
	_spots.clear()
	var want := count
	for i in want * 3:
		if _spots.size() >= want:
			break
		var angle := randf() * TAU
		var spot := GameConfig.clamp_to_world(enemy.global_position + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(spread * 0.6, spread))
		spot.y = 0.0
		if enemy.spot_is_free(spot, 0.4):
			_spots.append(spot)
	if animation != "":
		enemy.play_action(animation, windup, Unit.ARM_BOTH)
	if shout != "":
		enemy.shout(shout)
	for spot in _spots:
		enemy.fx(self, FX_MARK, spot, windup)


func _update(delta: float) -> void:
	_time -= delta
	if _time > 0.0:
		return
	for spot in _spots:
		var minion := enemy.spawn_minion(minions.pick_random() as PackedScene, spot)
		if minion:
			_alive.append(minion)
	finish()


func _living() -> int:
	_alive = _alive.filter(func(minion: Enemy) -> bool: return is_instance_valid(minion) and not minion.is_dead)
	return _alive.size()


func show_fx(_event: int, at: Vector3, value: float) -> void:
	HitFx.ground_warning(at, 0.7, value, mark_color)
	HitFx.flash(at + Vector3(0, 0.3, 0), HitFx.REVIVE_SPARKLE, mark_color, 1.2, value, Vector2(0.4, 1.2))

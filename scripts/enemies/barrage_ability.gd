class_name BarrageAbility
extends EnemyAction
## Marks `zones` spots (its target, other foes near it, else around the target) on the ground, then lets them have
## it: ARROWS rains `arrows` bone arrows over the marked zones (red X marks; each arrow hurts foes within
## ARROW_RADIUS of where it lands), METEORS drops one dark meteor on each (purple rings; foes within `radius` are hit
## and thrown back). Malakor's bow pair (phase 2) and grimoire (phase 3); Vaira's rain is a small one.
## Server: picks, timing, damage; every peer draws the marks, the falling arrows and the meteors (`enemy.fx`).

enum Style { ARROWS, METEORS }
const FX_MARK: int = 0
const FX_ARROW: int = 1
const FX_METEOR: int = 2
const FX_IMPACT: int = 3
const ARROW_RADIUS: float = 0.9
const ARROW_MODEL := preload("res://assets/items/forest/arrow.glb")

@export var style: Style = Style.ARROWS
@export var zones: int = 3
@export var radius: float = 2.6
## Seconds from the marks to the first hit.
@export var warning: float = 1.4
## ARROWS: how many fall in all (spread over the zones) and over how many seconds.
@export var arrows: int = 40
@export var rain_time: float = 2.0
## Per arrow (ARROWS) or per meteor (METEORS), × the enemy's power.
@export var damage: float = 9.0
@export var color: Color = Color(1.0, 0.15, 0.1, 0.75)
@export var animation: String = "holding-both-shoot"
@export var shout: String = ""
## Seconds it stands still while it marks the zones.
@export var root_time: float = 0.6

var _spots: Array[Vector3] = []
var _time: float = 0.0
var _left: int = 0
var _next_arrow: float = 0.0


func _begin(target: Node3D) -> void:
	_active = true
	_time = 0.0
	_spots = _pick_spots(target)
	_left = arrows if style == Style.ARROWS else _spots.size()
	_next_arrow = warning
	if animation != "":
		enemy.play_action(animation, 0.8, Unit.ARM_BOTH)
	if shout != "":
		enemy.shout(shout)
	for spot in _spots:
		enemy.fx(self, FX_MARK, spot, warning)


func drives_movement() -> bool:
	return _active and _time < root_time


func _update(delta: float) -> void:
	_time += delta
	if _spots.is_empty():
		finish()
		return
	if style == Style.METEORS:
		if _time >= warning:
			for spot in _spots:
				_hit(spot, radius, damage, 6.0)
				enemy.fx(self, FX_IMPACT, spot, radius)
			finish()
		return
	var step := rain_time / maxf(arrows, 1)
	while _left > 0 and _time >= _next_arrow:
		_next_arrow += step
		_left -= 1
		var zone := _spots[_left % _spots.size()]
		var angle := randf() * TAU
		var at := zone + Vector3(cos(angle), 0.0, sin(angle)) * radius * sqrt(randf())
		_hit(at, ARROW_RADIUS, damage, 0.0)
		enemy.fx(self, FX_ARROW, at, 0.0)
	if _left <= 0:
		finish()


## The target, then other foes within its reach (closest first), then spots around the target.
func _pick_spots(target: Node3D) -> Array[Vector3]:
	var spots: Array[Vector3] = [_flat(target.global_position)]
	var foes: Array = []
	for node in enemy.get_tree().get_nodes_in_group(&"player_units"):
		var foe := node as Unit
		if foe == null or foe == target or GameConfig.is_gone(foe) or not GameConfig.is_hostile(enemy, foe):
			continue
		if enemy.flat_distance_to(foe) <= max_range + 4.0:
			foes.append(foe)
	foes.sort_custom(func(a: Unit, b: Unit) -> bool: return enemy.flat_distance_to(a) < enemy.flat_distance_to(b))
	for foe: Unit in foes:
		if spots.size() >= zones:
			break
		var at := _flat(foe.global_position)
		if spots.all(func(s: Vector3) -> bool: return s.distance_to(at) > radius * 1.5):
			spots.append(at)
	while spots.size() < zones:
		var angle := randf() * TAU
		spots.append(GameConfig.clamp_to_world(spots[0] + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(radius * 1.8, radius * 3.0)))
	return spots


func _flat(at: Vector3) -> Vector3:
	return Vector3(at.x, 0.0, at.z)


## Foes of the enemy within `reach` of `at` take `amount` × power (thrown outward by `push`).
func _hit(at: Vector3, reach: float, amount: float, push: float) -> void:
	for node in enemy.get_tree().get_nodes_in_group(&"units"):
		var unit := node as Unit
		if unit == null or GameConfig.is_gone(unit) or not GameConfig.is_hostile(enemy, unit):
			continue
		var away := unit.global_position - at
		away.y = 0.0
		if away.length() > reach + unit.radius:
			continue
		unit.take_damage(amount * power(), enemy, false)
		if push > 0.0 and not unit.is_dead and away.length() > 0.05:
			unit.shove(away.normalized() * push)


func show_fx(event: int, at: Vector3, value: float) -> void:
	match event:
		FX_MARK:
			HitFx.ground_warning(at, radius, value, color)
			if style == Style.ARROWS:
				# A red X over the disc.
				for turn in [PI * 0.25, PI * 0.75]:
					var dir := Vector3(cos(turn), 0.0, sin(turn))
					HitFx.lane_warning(at - dir * radius, dir, radius * 2.0, 0.35, value + rain_time, color)
			else:
				var weather := _weather()
				if weather:
					weather.meteor_fall(at, value)
		FX_ARROW:
			_falling_arrow(at)
		FX_IMPACT:
			var weather := _weather()
			if weather:
				weather.meteor_impact(at, value)
			HitFx.flash(at + Vector3(0, 0.4, 0), HitFx.BIG_SMOKE, Color(0.45, 0.15, 0.7, 0.85), value * 2.4, 0.6,
					Vector2(0.5, 1.4), false)
			HitFx.shockwave(at, value)


## Every peer: a bone arrow drops onto `at`, a spark where it lands.
func _falling_arrow(at: Vector3) -> void:
	var world := HitFx.world
	if not is_instance_valid(world):
		return
	var arrow := ARROW_MODEL.instantiate() as Node3D
	world.add_child(arrow)
	arrow.global_position = at + Vector3(0.6, 7.0, 0.3)
	arrow.look_at(at, Vector3.FORWARD)
	arrow.scale = Vector3.ONE * 1.4
	var tween := arrow.create_tween()
	tween.tween_property(arrow, "global_position", at + Vector3(0, 0.25, 0), 0.22)
	tween.tween_callback(func() -> void:
		HitFx.flash(at + Vector3(0, 0.2, 0), HitFx.HIT_SPARK, color, 0.7, 0.15))
	tween.tween_interval(0.6)
	tween.tween_callback(arrow.queue_free)


func _weather() -> Weather:
	var main := HitFx.main
	if not is_instance_valid(main):
		return null
	var events = main.get("world_events")
	return events.weather if events else null

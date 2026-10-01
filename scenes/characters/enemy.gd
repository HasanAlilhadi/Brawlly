class_name Enemy
extends Unit
## Orc that guards its camp: wanders near home and attacks the player or soldiers that come close.
## When it (or its camp) is attacked — even from range — the whole squad is provoked: they chase
## the attacker much farther and faster, until they lose them or get dragged too far from home.
## Drops coins / health when killed. With a `projectile_scene` set, the orc throws spears from range
## (and backs off when the target gets close); otherwise it fights in melee.

## Orcs fight every player and every player's soldiers.
const TARGET_GROUPS: Array[StringName] = [&"player_units"]
const WAVE_TARGET_GROUPS: Array[StringName] = [&"players"]
## XP per point of max health (orc 80 hp: 2, giant 500: 13, Warlord: 45).
const XP_PER_HEALTH: float = 0.025
## Largest XP orb; bigger drops are split.
const XP_ORB: int = 10

@export var aggro_range: float = 6.5
## Beyond this distance from home a calm orc stops chasing and walks back.
@export var leash_range: float = 13.0
@export_group("Provoked")
## How long a provoked orc keeps hunting after the last hit / sighting.
@export var provoked_duration: float = 10.0
## Provoked orcs chase up to this far from home.
@export var provoked_leash: float = 35.0
@export var provoked_speed_multiplier: float = 1.2
## A provoked orc keeps hunting while its target is within this distance.
@export var provoked_sight_range: float = 11.0
@export_group("Ranged")
## Set to make this orc a thrower.
@export var projectile_scene: PackedScene
@export var throw_range: float = 8.0
@export var throw_cooldown: float = 2.2
@export var throw_damage: float = 14.0
## Throwers step back when the target is closer than this.
@export var keep_distance: float = 4.0
@export_group("Drops")
@export_range(0.0, 1.0) var health_drop_chance: float = 0.25
@export var health_drop_amount: int = 20
@export var coin_drop_min: int = 2
@export var coin_drop_max: int = 3
## XP dropped when killed (special abilities); 0 = from its power: max_health (after the camp's tier) × XP_PER_HEALTH.
@export var xp_value: int = 0
@export_group("Combo")
## A player's hit within this many seconds of a teammate's hit on this orc is a combo.
@export var combo_window: float = 1.0
@export var combo_damage_multiplier: float = 1.5

var home: Vector3
var target: Node3D
## The camp this orc belongs to (set by the camp on spawn).
var camp: Camp
## Or the Warlord whose warband it marches in (the Warlord moves `home` along with it).
var warlord: Warlord
## Wave-event raiders never leash or wander: they cross the map after the nearest living player.
var wave_enemy: bool = false
var wave_number: int = 0
## Set by the camp: tougher camps drop more coins.
var coin_multiplier: float = 1.0

var _think_timer: float = 0.0
var _wander_point: Vector3
var _returning: bool = false
var _provoked_time: float = 0.0
var _base_speed: float
var _alert_label: Label3D
var _alert_tween: Tween
var _throw_timer: float = 0.0
## Server: last hit time (ms) per player peer, for combos.
var _player_hits: Dictionary = {}
var _last_combo_ms: int = -100000
## Replicated: increments when the orc is provoked (shows the "!" on every peer).
var alert_seq: int = 0:
	set(value):
		if value != alert_seq:
			alert_seq = value
			if is_node_ready():
				_show_alert()


func _ready() -> void:
	super()
	add_to_group(&"enemies")
	_base_speed = move_speed
	_wander_point = global_position
	_think_timer = randf() * 0.3
	_build_alert_label()
	if wave_enemy:
		add_to_group(&"wave_enemies")
		add_to_group(&"active_enemies")
		alert_seq += 1


## Makes this orc hunt `attacker` (called by the camp / Warlord for the whole squad, and with
## `direct` = true for the orc that was hit). An orc already fighting someone keeps its target —
## the squad no longer flips between the player and their soldiers with every hit. A direct hit from
## someone much closer than the current target (once the target lock has run out) does switch it.
func provoke(attacker: Node3D, direct: bool = false) -> void:
	if is_dead or GameConfig.is_gone(attacker) or not GameConfig.is_hostile(self, attacker):
		return
	var was_provoked := is_provoked()
	_returning = false
	_provoked_time = provoked_duration
	move_speed = _base_speed * provoked_speed_multiplier
	if not was_provoked:
		alert_seq += 1
	if attacker == target:
		return
	var busy := not GameConfig.is_gone(target) and flat_distance_to(target) < provoked_sight_range
	if busy and not (direct and _target_lock <= 0.0 and flat_distance_to(attacker) < flat_distance_to(target) * TARGET_SWITCH_RATIO):
		return
	target = attacker
	lock_target()


## Warband orcs: stay near `point` (their moving home) unless they're fighting.
func follow_point(point: Vector3) -> void:
	home = point
	if is_provoked() or not GameConfig.is_gone(target):
		return
	_wander_point = point
	_returning = global_position.distance_to(point) > 2.0


func is_provoked() -> bool:
	return _provoked_time > 0.0


## True while the orc is chasing or walking home (its camp keeps it awake even if far away).
func is_busy() -> bool:
	return wave_enemy or is_provoked() or _returning


## Combo: two players of the same team hitting this orc within `combo_window` — every such hit
## (from either of them) deals bonus damage, with a "COMBO!" pop-up for everyone.
func take_damage(amount: float, attacker: Node3D = null, is_melee: bool = true, crit: bool = false) -> void:
	var player := HitFx.player_of(attacker)
	if player and not is_dead:
		var now := Time.get_ticks_msec()
		var window_ms := int(combo_window * 1000.0)
		var combo := false
		for other in _player_hits.keys():
			var mate := _player_hits[other][1] as Player
			if other != player.peer_id and now - int(_player_hits[other][0]) <= window_ms \
					and is_instance_valid(mate) and mate.team_id == player.team_id:
				combo = true
		_player_hits[player.peer_id] = [now, player]
		if combo:
			amount *= combo_damage_multiplier
			if now - _last_combo_ms > 350:
				_last_combo_ms = now
				HitFx.report_combo(self)
	super(amount, attacker, is_melee, crit)


func _on_damaged(attacker: Node3D) -> void:
	provoke(attacker, true)
	if camp and is_instance_valid(camp) and not camp.is_dead:
		camp.alert(attacker)
	elif is_instance_valid(warlord) and not warlord.is_dead:
		warlord.alert(attacker)


func _get_move_input(delta: float) -> Vector3:
	if _provoked_time > 0.0:
		_provoked_time -= delta
		if _provoked_time <= 0.0:
			_calm_down()
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = 0.25 + randf() * 0.1
		_think()

	_throw_timer = maxf(_throw_timer - delta, 0.0)
	if not GameConfig.is_gone(target):
		if projectile_scene:
			return _ranged_move(delta)
		return engage(target, delta)

	var to_point := _wander_point - global_position
	to_point.y = 0.0
	if to_point.length() > 0.3:
		return steer(to_point.normalized() * (1.0 if _returning else 0.35), delta)
	return Vector3.ZERO


func _think() -> void:
	if wave_enemy:
		var nearest := find_nearest(WAVE_TARGET_GROUPS, GameConfig.world_half * 3.0)
		if nearest != target:
			target = nearest
			if target:
				lock_target()
		_returning = false
		return
	var dist_home := global_position.distance_to(home)

	if is_provoked():
		if GameConfig.is_gone(target) and dist_home <= provoked_leash:
			# Our target fell: take on the next foe close by before giving up.
			target = find_nearest(TARGET_GROUPS, provoked_sight_range * 0.6)
			if target:
				lock_target()
		if GameConfig.is_gone(target) or dist_home > provoked_leash:
			_calm_down()
		else:
			# Still in sight: keep hunting.
			if global_position.distance_to(target.global_position) < provoked_sight_range:
				_provoked_time = maxf(_provoked_time, 3.0)
			return

	if dist_home > leash_range:
		target = null
		_returning = true
		_wander_point = home
	elif _returning and dist_home < 3.0:
		_returning = false
	if _returning:
		return
	target = choose_target(target, find_nearest(TARGET_GROUPS, aggro_range), aggro_range * 1.5)
	if target == null and randf() < 0.12:
		var angle := randf() * TAU
		_wander_point = home + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(0.5, 3.0)


## Thrower: hold position within range and throw; back off if crowded; stab when cornered.
func _ranged_move(delta: float) -> Vector3:
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if dist > throw_range or dist < melee_range + Unit.target_radius(target) * 0.5:
		return engage(target, delta)
	face(to, delta * 2.0)
	_try_throw()
	if dist < keep_distance:
		return steer(-to.normalized() * 0.7, delta)
	return _separation * 0.5


func _try_throw() -> void:
	if _throw_timer > 0.0 or _action_time > 0.0:
		return
	_throw_timer = throw_cooldown * randf_range(0.85, 1.15)
	play_action("attack-melee-right", 0.4 / anim_speed, ARM_RIGHT)
	get_tree().create_timer(attack_hit_delay / anim_speed).timeout.connect(_release_throw)


func _release_throw() -> void:
	if is_dead or GameConfig.is_gone(target):
		return
	var from := global_position + Vector3(0, 0.7, 0)
	# Lead the target a little so standing still is dangerous but moving dodges.
	var aim := target.global_position + Vector3(0, 0.5, 0)
	if target is CharacterBody3D:
		aim += (target as CharacterBody3D).velocity * 0.3
	var dir := aim - from
	dir.y = 0.0
	NetSpawn.projectile(&"spear", from + dir.normalized() * 0.4, dir.normalized(), throw_damage, self)
	# The spear in hand "leaves" and comes back a moment later.
	if _right_item:
		_right_item.visible = false
		get_tree().create_timer(0.8).timeout.connect(_show_hand_item)


func _show_hand_item() -> void:
	if _right_item:
		_right_item.visible = true


func _calm_down() -> void:
	_provoked_time = 0.0
	move_speed = _base_speed
	target = null
	if global_position.distance_to(home) > 3.0:
		_returning = true
		_wander_point = home


func _on_died() -> void:
	_alert_label.hide()
	var world := get_parent()
	if randf() < health_drop_chance:
		Pickup.drop(world, global_position, Pickup.Kind.HEALTH, health_drop_amount)
	var coins := roundi(randi_range(coin_drop_min, coin_drop_max) * coin_multiplier)
	if coins > 0:
		Pickup.drop(world, global_position, Pickup.Kind.COIN, coins)
	# Strong enemies drop several orbs (at most XP_ORB each).
	var xp := xp_drop()
	while xp > 0:
		Pickup.drop(world, global_position, Pickup.Kind.XP, mini(xp, XP_ORB))
		xp -= XP_ORB


## XP this enemy drops: `xp_value`, or its power (tougher orcs, tougher camps: more).
func xp_drop() -> int:
	return xp_value if xp_value > 0 else maxi(1, roundi(max_health * XP_PER_HEALTH))


# --- "!" alert ----------------------------------------------------------------

func _build_alert_label() -> void:
	_alert_label = Label3D.new()
	_alert_label.text = "!"
	_alert_label.font_size = 96
	_alert_label.outline_size = 18
	_alert_label.pixel_size = 0.006
	_alert_label.modulate = Color(1.0, 0.25, 0.2)
	_alert_label.outline_modulate = Color(0.15, 0.0, 0.0)
	_alert_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_alert_label.no_depth_test = true
	_alert_label.position = Vector3(0, 1.7, 0)
	_alert_label.visible = false
	add_child(_alert_label)


func _show_alert() -> void:
	if _alert_tween:
		_alert_tween.kill()
	_alert_label.visible = true
	_alert_label.scale = Vector3.ONE * 0.2
	_alert_tween = create_tween()
	_alert_tween.tween_property(_alert_label, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_alert_tween.tween_interval(1.0)
	_alert_tween.tween_callback(_alert_label.hide)

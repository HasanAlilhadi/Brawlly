class_name Enemy
extends Unit
## A hostile creature (orcs, the undead), built by composition: the child nodes of its scene decide
## - how it moves: one EnemyMovement (ChaseMovement, KiteMovement, FlankMovement, ShambleMovement,
##   FloatMovement, StalkMovement; none = straight chase),
## - what it does to its target: EnemyActions, tried highest `priority` first each frame — attacks
##   (MeleeAttack, ProjectileAttack) and abilities with cooldowns (ChargeAbility, StompAbility,
##   BlinkAbility, SummonAbility, PhaseAbility),
## - its passives: traits (LifeStealTrait, ReassembleTrait, DeathBurstTrait, EnrageTrait, BossTrait, RecolorTrait).
## See scripts/enemies/. The Enemy keeps what every creature shares: picking and keeping targets, being
## provoked (it and its warband hunt whoever hit them), following its warband (`band`) or guarding `home`,
## drops, combo hits and the "!" alert. Stats, reach, hand items and clips are the Unit exports of the scene.
##
## Multiplayer: the server runs the AI and the components' gameplay; `fx()` / `shout()` show their effects
## on every peer.

## Enemies fight every player and every player's soldiers.
const TARGET_GROUPS: Array[StringName] = [&"player_units"]
const WAVE_TARGET_GROUPS: Array[StringName] = [&"players"]
## XP per point of max health (grunt 80 hp: 2, brute 420: 10, a boss: 20+).
const XP_PER_HEALTH: float = 0.025
## Largest XP orb; bigger drops are split.
const XP_ORB: int = 10
## Extra reaction time before an enemy's first attack.
const FIRST_ATTACK_DELAY: float = 0.25
const FX_COLLAPSE: int = 0
const FX_RISE: int = 1
## Seconds a summoned / risen creature takes to climb out of the ground.
const RISE_TIME: float = 0.8

## Shown in menus / tests / the boss bar.
@export var enemy_name: String = "Orc"
## &"orc" or &"undead" (which warbands it marches in).
@export var faction: StringName = &"orc"
@export var aggro_range: float = 6.5
## Assassins: go for the most wounded foe close by instead of the nearest (flankers, vampires).
@export var prefers_weak: bool = false
## Beyond this distance from home (its spot in the band) a calm enemy stops chasing and walks back.
@export var leash_range: float = 13.0
@export_group("Provoked")
## How long a provoked enemy keeps hunting after the last hit / sighting.
@export var provoked_duration: float = 10.0
## Provoked enemies chase up to this far from home.
@export var provoked_leash: float = 35.0
@export var provoked_speed_multiplier: float = 1.2
## A provoked enemy keeps hunting while its target is within this distance.
@export var provoked_sight_range: float = 11.0
@export_group("Drops")
@export_range(0.0, 1.0) var health_drop_chance: float = 0.25
@export var health_drop_amount: int = 20
@export var coin_drop_min: int = 2
@export var coin_drop_max: int = 3
## XP dropped when killed (special abilities); 0 = from its power: max_health × XP_PER_HEALTH.
@export var xp_value: int = 0
@export_group("Combo")
## A player's hit within this many seconds of a teammate's hit on this enemy is a combo.
@export var combo_window: float = 1.0
@export var combo_damage_multiplier: float = 1.5

var home: Vector3
var target: Node3D
## The warband it marches with (set from the spawn data; null for wave raiders / training orcs).
var band: Warband
## Wave-event raiders never leash or wander: they cross the map after the nearest living player.
var wave_enemy: bool = false
var wave_number: int = 0
## Loot multiplier (stronger bands drop more coins).
var coin_multiplier: float = 1.0
## Stat multiplier from the spawn (difficulty × band power): health and melee damage are scaled at spawn,
## components scale their own damage with it.
var power: float = 1.0
## Raised by a summoner (it climbs out of the ground when it appears).
var rising: bool = false
## A world-event boss: a minimap badge and an off-screen arrow for everyone (BossTrait.track()).
var tracked: bool = false
## Collapsed (ReassembleTrait): lying in pieces, ignored by the AI (GameConfig.is_gone); a hit finishes it.
var is_downed: bool = false
## Its boss fell: it dies for good, no getting back up.
var routed: bool = false
## Speed multipliers from abilities (a charge, a phasing ghost) and rage.
var speed_boost: float = 1.0
var rage_speed: float = 1.0
## Share of move_speed while following its band (they walk together; set by the band).
var pace: float = 0.35
## The band's marching velocity (m/s): members move along with it instead of stop-go at their spot.
var drift: Vector3 = Vector3.ZERO
## How it moves (always set after _ready).
var movement: EnemyMovement

var _components: Array[EnemyComponent] = []
var _actions: Array[EnemyAction] = []
var _think_timer: float = 0.0
var _wander_point: Vector3
var _returning: bool = false
var _provoked_time: float = 0.0
var _base_speed: float
var _alert_label: Label3D
var _alert_tween: Tween
var _shout_label: Label3D
var _shout_tween: Tween
var _rise_left: float = 0.0
var _collapse_left: float = 0.0
var _collapse_health: float = 0.5
## -1 until the first attack is attempted; then counts down once.
var _first_attack_delay_left: float = -1.0
## Server: last hit time (ms) per player peer, for combos.
var _player_hits: Dictionary = {}
var _last_combo_ms: int = -100000
## Replicated: increments when the enemy is provoked (shows the "!" on every peer).
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
	for child in get_children():
		if child is EnemyComponent:
			_components.append(child)
			if child is EnemyMovement and movement == null:
				movement = child
			elif child is EnemyAction:
				_actions.append(child)
	if movement == null:
		movement = EnemyMovement.new()
		movement.name = "Movement"
		add_child(movement)
		_components.append(movement)
	_actions.sort_custom(func(a: EnemyAction, b: EnemyAction) -> bool: return a.priority > b.priority)
	for component in _components:
		component.setup(self)
	if rising:
		_rise_from_ground()
	if wave_enemy:
		add_to_group(&"wave_enemies")
		add_to_group(&"active_enemies")
		alert_seq += 1


## The component of a class (e.g. `component(SummonAbility)`), or null.
func component(type: Variant) -> EnemyComponent:
	for item in _components:
		if is_instance_of(item, type):
			return item
	return null


# --- Provoked / band ------------------------------------------------------------------

## Makes this enemy hunt `attacker` (called by its band for everyone, and with `direct` = true for the one
## that was hit). One already fighting someone keeps its target — the band doesn't flip between the player
## and their soldiers with every hit. A direct hit from someone much closer than the current target (once the
## target lock has run out) does switch it.
func provoke(attacker: Node3D, direct: bool = false) -> void:
	if is_dead or is_downed or GameConfig.is_gone(attacker) or not GameConfig.is_hostile(self, attacker):
		return
	var was_provoked := is_provoked()
	_returning = false
	_provoked_time = provoked_duration
	if not was_provoked:
		alert_seq += 1
	if attacker == target:
		return
	if prefers_weak and not direct and GameConfig.is_gone(target):
		var weak := find_weakest(provoked_sight_range)
		if weak:
			attacker = weak
	var busy := not GameConfig.is_gone(target) and flat_distance_to(target) < provoked_sight_range
	if busy and not (direct and _target_lock <= 0.0 and flat_distance_to(attacker) < flat_distance_to(target) * TARGET_SWITCH_RATIO):
		return
	target = attacker
	lock_target()


## Its band moves `point` (its spot in the formation) along; it walks there at `walk_pace` unless fighting.
func follow_point(point: Vector3, walk_pace: float, band_velocity: Vector3 = Vector3.ZERO) -> void:
	home = point
	pace = walk_pace
	drift = band_velocity
	if is_provoked() or not GameConfig.is_gone(target):
		return
	_wander_point = point
	if _returning and global_position.distance_to(point) < 2.0:
		_returning = false


func is_provoked() -> bool:
	return _provoked_time > 0.0


## True while chasing or walking home (its band keeps it awake even if far away).
func is_busy() -> bool:
	return wave_enemy or is_provoked() or _returning or not GameConfig.is_gone(target)


## Every peer: not phasing, collapsed or otherwise unable to attack.
func can_attack() -> bool:
	for item in _components:
		if item.blocks_attacks():
			return false
	return true


# --- Damage / death -------------------------------------------------------------------

## Combo: two players of the same team hitting this enemy within `combo_window` — every such hit (from
## either of them) deals bonus damage, with a "COMBO!" pop-up for everyone. A collapsed skeleton is finished
## by any hit.
func take_damage(amount: float, attacker: Node3D = null, is_melee: bool = true, crit: bool = false) -> void:
	if is_dead:
		return
	if is_downed:
		if attacker and GameConfig.owner_peer_of(attacker) != 0:
			last_attacker_peer = GameConfig.owner_peer_of(attacker)
		HitFx.report_hit(self, 1.0, attacker, crit, is_melee)
		die()
		return
	for item in _components:
		if item.blocks_hit(amount, attacker):
			return
	var player := HitFx.player_of(attacker)
	if player:
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
	if not is_dead and not is_downed:
		for item in _components:
			item.on_damaged(attacker, amount)


func _on_damaged(attacker: Node3D) -> void:
	provoke(attacker, true)
	if is_instance_valid(band):
		band.alert(attacker)


func _on_hit_dealt(victim: Node3D, amount: float) -> void:
	for item in _components:
		item.on_hit_dealt(victim, amount)


## A component (ReassembleTrait) may keep it from dying; a routed or already collapsed one always dies.
func die() -> void:
	if is_dead:
		return
	if not routed and not is_downed:
		for item in _components:
			if item.prevents_death():
				return
	super()


## Server: falls apart for `seconds`, then gets back up with `health_share` of its health.
func collapse(seconds: float, health_share: float) -> void:
	is_downed = true
	health = 0.0
	velocity = Vector3.ZERO
	target = null
	_provoked_time = 0.0
	_collapse_left = seconds
	_collapse_health = health_share
	for action in _actions:
		action.finish()
	remove_from_group(&"active_enemies")
	play_action("die", seconds, ARM_BOTH)
	fx(self, FX_COLLAPSE, global_position)


func _get_up() -> void:
	is_downed = false
	health = max_health * _collapse_health
	if process_mode != PROCESS_MODE_DISABLED:
		add_to_group(&"active_enemies")
	_action_time = 0.0
	_hold_arms()
	play_anim("idle", 0.2)
	fx(self, FX_RISE, global_position)


func _on_died() -> void:
	_alert_label.hide()
	for item in _components:
		item.on_died()
	var world := get_parent()
	if randf() < health_drop_chance:
		Pickup.drop(world, global_position, Pickup.Kind.HEALTH, health_drop_amount)
	var loot := GameConfig.BLOOD_MOON_LOOT if GameConfig.blood_moon else 1.0
	var coins := roundi(randi_range(coin_drop_min, coin_drop_max) * coin_multiplier * loot)
	if coins > 0:
		Pickup.drop(world, global_position, Pickup.Kind.COIN, coins)
	# Strong enemies drop several orbs (at most XP_ORB each).
	var xp := roundi(xp_drop() * loot)
	while xp > 0:
		Pickup.drop(world, global_position, Pickup.Kind.XP, mini(xp, XP_ORB))
		xp -= XP_ORB


func _death_visuals() -> void:
	super()
	if _alert_label:
		_alert_label.hide()
	for item in _components:
		item.on_death_visuals()


## XP this enemy drops: `xp_value`, or its power (tougher enemies, stronger bands: more).
func xp_drop() -> int:
	return xp_value if xp_value > 0 else maxi(1, roundi(max_health * XP_PER_HEALTH))


# --- AI ------------------------------------------------------------------------------

func _get_move_input(delta: float) -> Vector3:
	if _rise_left > 0.0:
		_rise_left -= delta
		return Vector3.ZERO
	if is_downed:
		_collapse_left -= delta
		if _collapse_left <= 0.0:
			_get_up()
		return Vector3.ZERO
	if _first_attack_delay_left > 0.0:
		_first_attack_delay_left = maxf(_first_attack_delay_left - delta, 0.0)
	if _provoked_time > 0.0:
		_provoked_time -= delta
		if _provoked_time <= 0.0:
			_calm_down()
	look_override = Vector3.ZERO
	for item in _components:
		item.server_tick(delta)
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = 0.25 + randf() * 0.1
		_think()
	move_speed = _base_speed * (provoked_speed_multiplier if is_provoked() else 1.0) * speed_boost * rage_speed \
			* (GameConfig.BLOOD_MOON_SPEED if GameConfig.blood_moon else 1.0)

	for action in _actions:
		if action.is_active() and action.drives_movement():
			return action.active_move(delta)
	if not GameConfig.is_gone(target):
		if can_attack():
			for action in _actions:
				if action.can_start(target):
					action.start(target)
					if action.is_active() and action.drives_movement():
						return action.active_move(delta)
					break
		return movement.chase(target, delta)
	var to_point := _wander_point - global_position
	to_point.y = 0.0
	if to_point.length() > 0.3 or (drift.length() > 0.05 and not _returning):
		return movement.roam(_wander_point, delta, 1.0 if _returning else pace)
	return Vector3.ZERO


## Blood Moon: harder hits.
func _roll_melee_damage() -> Array:
	return [melee_damage * (GameConfig.BLOOD_MOON_DAMAGE if GameConfig.blood_moon else 1.0), false]


func first_attack_ready() -> bool:
	if _first_attack_delay_left < 0.0:
		_first_attack_delay_left = FIRST_ATTACK_DELAY
		return false
	return _first_attack_delay_left <= 0.0


func melee() -> bool:
	if is_dead or _melee_timer > 0.0 or not first_attack_ready():
		return false
	return super()


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
	var before := target
	var candidate := find_weakest(aggro_range) if prefers_weak else find_nearest(TARGET_GROUPS, aggro_range)
	target = choose_target(target, candidate, aggro_range * 1.5)
	if target and target != before and is_instance_valid(band):
		band.alert(target)  # one of them spots you: the whole band comes
	if target == null and band == null and randf() < 0.12:
		var angle := randf() * TAU
		_wander_point = home + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(0.5, 3.0)


## The foe within `max_range` with the least health left (share), closer ones first on a tie.
func find_weakest(max_range: float) -> Node3D:
	var best: Node3D = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group(&"player_units"):
		var foe := node as Unit
		if foe == null or GameConfig.is_gone(foe) or not GameConfig.is_hostile(self, foe):
			continue
		var d := flat_distance_to(foe)
		if d > max_range:
			continue
		var score := foe.health / maxf(foe.max_health, 1.0) + d * 0.03
		if score < best_score:
			best_score = score
			best = foe
	return best


func _calm_down() -> void:
	_provoked_time = 0.0
	target = null
	if global_position.distance_to(home) > 3.0:
		_returning = true
		_wander_point = home


# --- Helpers for components ------------------------------------------------------------

## Nothing solid (trees, walls, buildings) between it (or `from`) and `node`, at shot height.
func clear_line_to(node: Node3D, from: Vector3 = Vector3.INF) -> bool:
	var start := global_position if from == Vector3.INF else from
	var query := PhysicsRayQueryParameters3D.create(start + Vector3(0, 0.7, 0),
			node.global_position + Vector3(0, 0.7, 0), GameConfig.LAYER_WORLD | GameConfig.LAYER_FENCE, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Heroes / soldiers hostile to it within `distance`.
func foes_within(distance: float) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(&"player_units"):
		var foe := node as Node3D
		if not GameConfig.is_gone(foe) and GameConfig.is_hostile(self, foe) and flat_distance_to(foe) < distance:
			count += 1
	return count


## No tree / wall / building within `clearance` of `spot`.
func spot_is_free(spot: Vector3, clearance: float) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(clearance, 0.2)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), spot + Vector3(0, 0.5, 0))
	query.collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_FENCE
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## Server: jump to `spot` (other peers snap there instead of sliding).
func teleport(spot: Vector3) -> void:
	global_position = spot
	net_position = spot


## Server: a minion of `scene` climbs out of the ground at `spot` and joins this enemy's band (or wave).
func spawn_minion(scene: PackedScene, spot: Vector3) -> Enemy:
	if scene == null:
		return null
	var data := {"scene": scene.resource_path, "strength": power, "coins": coin_multiplier * 0.4, "rise": true,
			"wave_enemy": wave_enemy, "wave_number": wave_number}
	if is_instance_valid(band):
		data["band"] = band.get_path()
	var minion := NetSpawn.unit(&"enemy", spot, data) as Enemy
	if minion == null:
		return null
	if is_instance_valid(band):
		band.adopt(minion)
	else:
		minion.add_to_group(&"active_enemies")
	if not GameConfig.is_gone(target):
		minion.provoke(target)
	return minion


## Server: a visual event of `source` (a component, or this enemy) on every peer.
func fx(source: Node, event: int, at: Vector3 = Vector3.ZERO, value: float = 0.0) -> void:
	if not multiplayer.is_server():
		return
	if Net.is_online():
		_net_fx.rpc(get_path_to(source), event, at, value)
	else:
		source.call("show_fx", event, at, value)


@rpc("authority", "call_local", "reliable")
func _net_fx(path: NodePath, event: int, at: Vector3, value: float) -> void:
	var source := get_node_or_null(path)
	if source and source.has_method("show_fx"):
		source.call("show_fx", event, at, value)


## Own visual events: falling apart / getting back up (ReassembleTrait).
func show_fx(event: int, at: Vector3, _value: float) -> void:
	var reassemble := component(ReassembleTrait)
	if reassemble:
		reassemble.show_fx(ReassembleTrait.FX_COLLAPSE if event == FX_COLLAPSE else ReassembleTrait.FX_RISE, at, 0.0)
	_health_bar.visible = event == FX_RISE


## Server: a battle cry over its head on every peer ("RAAAGH!", "Rise!").
func shout(text: String) -> void:
	if not multiplayer.is_server():
		return
	if Net.is_online():
		_net_shout.rpc(text)
	else:
		_show_shout(text)


@rpc("authority", "call_local", "reliable")
func _net_shout(text: String) -> void:
	_show_shout(text)


func _show_shout(text: String) -> void:
	if _shout_label == null:
		_shout_label = Label3D.new()
		_shout_label.font_size = 80
		_shout_label.outline_size = 18
		_shout_label.pixel_size = 0.006
		_shout_label.modulate = Color(1.0, 0.4, 0.25)
		_shout_label.outline_modulate = Color(0.15, 0.0, 0.0, 0.95)
		_shout_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_shout_label.no_depth_test = true
		_shout_label.position = Vector3(0, health_bar_height + 0.9, 0)
		add_child(_shout_label)
	_shout_label.text = text
	_shout_label.visible = true
	_shout_label.scale = Vector3.ONE * 0.4
	if _shout_tween:
		_shout_tween.kill()
	_shout_tween = create_tween()
	_shout_tween.tween_property(_shout_label, "scale", Vector3.ONE * 1.1, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_shout_tween.tween_interval(0.9)
	_shout_tween.tween_callback(_shout_label.hide)
	var camera := HitFx.camera
	if radius > 0.5 and is_instance_valid(camera) and camera.target and camera.target.global_position.distance_to(global_position) < 14.0:
		camera.shake(0.12, 0.3)


## Every peer: climbs out of the ground (summoned).
func _rise_from_ground() -> void:
	_rise_left = RISE_TIME
	model.position.y = -1.1 * _model_scale.y
	var tween := create_tween()
	tween.tween_property(model, "position:y", 0.0, RISE_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	HitFx.burst(global_position + Vector3(0, 0.2, 0), HitFx.Kind.DIRT, 14)
	HitFx.flash(global_position + Vector3(0, 0.3, 0), HitFx.DEATH_SMOKE, Color(0.55, 0.5, 0.42, 0.8), 1.6, 0.6, Vector2(0.5, 1.3), false)


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
	_alert_label.position = Vector3(0, health_bar_height + 0.4, 0)
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

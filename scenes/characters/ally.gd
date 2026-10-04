class_name Ally
extends Unit
## Soldier trained at a barracks (see Player.soldiers_training). It first waits inside the barracks pen
## (`penned`: group "penned", can't be targeted or hurt, wanders inside the fence) until its player takes
## it (`release()`: they file out one by one, each in its own lane through the gate); then it follows its
## player (`owner_peer`) in a compact formation, fighting nearby hostiles: orcs, and in versus modes other
## players and their soldiers. Near a barracks it routes around the house + pen (`ShopStation.detour`)
## instead of walking into the fence. Inside a barracks compound soldiers pass through each other (no
## soldier–soldier collision or separation push, so a crowded courtyard never jams); walls and buildings
## still block them. Outside, soldiers collide with each other again.
## Once dead, it is gone for good.
## Soldiers carry their player's class weapon (`weapon`, see WEAPON_STATS): sword and shield, a long
## spear (melee only: a straight stab, `_spear_stab`), or a bow — archers shoot from `archer_range()` (half
## their hero's bow range) with a clear line of fire, step back from orcs that get close and stand in a row
## behind the hero.
## Teamwork (`_best_enemy`): enemies hitting the hero, then the soldiers, come first; melee soldiers spread
## over the enemies instead of piling on one; archers focus the wounded. Following: when a wall or a building
## cuts a soldier off from its spot, it walks the hero's recent path (`Player.trail`, `_trail_point`).
## The player's army order (Player.army_order) changes where the formation stands: around the player
## (FOLLOW), or around Player.army_point, where they fight everything nearby (CHARGE) or guard it (HOLD);
## KILL hunts Player.army_target down (then CHARGE where it fell). Orders are always obeyed: on every new
## order (Player.order_serial) soldiers drop their fight at once and walk to their new spot without
## fighting (`_regroup`, until they get there or `regroup_time` runs out); KILL goes straight for the target.

const TARGET_GROUPS: Array[StringName] = [&"active_enemies", &"player_units"]
const CAMP_GROUPS: Array[StringName] = [&"camps"]
## Soldiers waiting in the barracks courtyard are drawn this much smaller (every peer; visual only).
const PENNED_SCALE: float = 0.7
const SPEAR_SCENE := preload("res://assets/items/dungeon/spear.glb")
const BOW_SCENE := preload("res://assets/items/forest/bow.glb")
## Archers shoot from this share of their hero's bow range (Player.aim_range, Fire Range included).
const ARCHER_RANGE_SHARE: float = 0.5
## An enemy closer than this makes an archer step back (still shooting).
const ARCHER_KEEP_AWAY: float = 2.6
## Picking a target, in m of extra distance: each squadmate already on an enemy (melee soldiers spread out),
## an enemy hitting the hero / one of us (it counts as closer), a blocked line of fire (archers).
const CROWD_PENALTY: float = 1.6
const DEFEND_BONUS: float = 4.0
const GUARD_BONUS: float = 2.0
const BLOCKED_PENALTY: float = 3.0
## What blocks walking and arrows (trees, houses, camp walls, fences).
const OBSTACLE_MASK: int = GameConfig.LAYER_WORLD | GameConfig.LAYER_FENCE
## Spear stab timing (shares of the action): drawn back, then out, held, back to the carry grip.
const STAB_DRAW: float = 0.35
const STAB_OUT: float = 0.55
const STAB_HOLD: float = 0.75
const STAB_BACK: float = -0.15
const STAB_REACH: float = 0.55
## Weapon id (ClassDef.ally_weapon) -> stats over the scene's (the sword soldier). `damage` is per hit
## (an arrow for the bow).
const WEAPON_STATS: Dictionary = {
	"sword": {},
	"spear": {"damage": 11.5, "range": 1.45, "cooldown": 1.1},
	"bow": {"damage": 11.0, "health": 65.0, "cooldown": 1.2},
}

@export var aggro_range: float = 6.0
## Stop chasing when this far from the player.
@export var leash_range: float = 9.0
## Soldiers move at exactly two speeds: running (move_speed) or walking (this share of it, with the walk clip),
## never faster to catch up or charge (`_get_move_input` snaps every move to one of them).
@export var walk_share: float = 0.45
## Closer than this to its spot in the formation a soldier walks the rest of the way.
@export var walk_distance: float = 2.0
## Orders: soldiers fight hostiles within this distance of the charge / hold point.
@export var charge_radius: float = 9.0
@export var hold_radius: float = 6.0
## After an order: at most this many seconds of walking to the new spot without fighting.
@export var regroup_time: float = 6.0
## Regrouping ends this close to the soldier's slot (then it fights normally again).
@export var regroup_arrive: float = 2.5
## Archers shoot from up to this far (from the target's surface); set from `archer_range()` on every think.
var shoot_range: float = 6.0

## The weapon it fights with (from the spawn data, every peer, before entering the tree).
var weapon: String = "sword"

var leader: Player
var target: Node3D
## The barracks whose pen it waits in (set at spawn on every peer).
var pen: ShopStation
## Replicated: waiting in the pen (not following / fighting yet).
var penned: bool = false:
	set(value):
		penned = value
		if penned:
			add_to_group(&"penned")
			remove_from_group(&"player_units")
		else:
			remove_from_group(&"penned")
			if is_node_ready() and not is_dead:
				add_to_group(&"player_units")
		_apply_pen_scale(true)

## Server: after being released, walk through these (inside the gate, then outside) before following.
var _exit_path: Array[Vector3] = []
## Server: seconds to wait before filing out (released soldiers leave one after another).
var _exit_delay: float = 0.0
## Server: barracks close enough to be in the way (refreshed every think).
var _nearby_barracks: Array[ShopStation] = []
## Server: inside a barracks compound right now (soldier–soldier collision off).
var _in_compound: bool = false
var _base_separation_strength: float
var _wander_point: Vector3 = Vector3.INF
var _resting: bool = false

var _think_timer: float = 0.0
## Server: the leader's order_serial this soldier has obeyed.
var _order_serial: int = 0
## Server: seconds left of walking to the ordered spot without fighting (0 = not regrouping).
var _regroup: float = 0.0
var _slot_offset: Vector3
var _base_max_health: float
var _base_damage: float
## Following: a point of the hero's trail to walk to while the straight way to the slot is blocked.
var _via: Vector3 = Vector3.INF
## The hero's walking direction (archers line up behind it).
var _heading: Vector3 = Vector3.BACK
var _stab_phase: float = -1.0  # spear stab progress 0..1, < 0 = not stabbing
var _stab_scale: Vector3 = Vector3.ONE
var _carry_transform: Transform3D
var _stab_tween: Tween


func _ready() -> void:
	_apply_weapon_stats()
	super()
	_apply_pen_scale(false)
	chase_avoid_mask = GameConfig.LAYER_ENEMIES  # go around orcs in the way to the one we're after
	add_to_group(&"allies")
	if not penned:
		add_to_group(&"player_units")
	_think_timer = randf() * 0.3
	_base_separation_strength = separation_strength
	_base_max_health = max_health
	_base_damage = melee_damage
	_find_leader()
	refresh_army_bonus()


## Hands and stats for `weapon` (before Unit._ready() attaches the hand items).
func _apply_weapon_stats() -> void:
	var stats: Dictionary = WEAPON_STATS.get(weapon, {})
	melee_damage = stats.get("damage", melee_damage)
	melee_range = stats.get("range", melee_range)
	melee_cooldown = stats.get("cooldown", melee_cooldown)
	max_health = stats.get("health", max_health)
	match weapon:
		"spear":
			# Carried like the orc spearmen; attacks are straight stabs (never thrown).
			melee_anims = PackedStringArray(["spear-stab"])
			right_hand_item = SPEAR_SCENE
			right_hand_offset = Vector3(-0.27, -0.2, 0.0)
			right_hand_rotation = Vector3.ZERO
			left_hand_item = null
		"bow":
			right_hand_item = null
			hold_right_arm = false
			left_hand_item = BOW_SCENE
			left_hand_offset = Vector3(0.27, -0.24, 0.0)
			hold_left_arm = true


func is_archer() -> bool:
	return weapon == "bow"


## How far archers shoot: half their hero's bow range.
func archer_range() -> float:
	var bow_range: float = leader.aim_range if is_instance_valid(leader) else 12.0
	return bow_range * ARCHER_RANGE_SHARE


## Every peer: the spear soldier's attack is a stab straight ahead (Kenney's melee clip swings the spear
## overhead, which reads as a throw).
func _play_action_local(anim_name: String, duration: float, release_arms: int) -> void:
	if anim_name == "spear-stab":
		_spear_stab(duration)
		return
	super(anim_name, duration, release_arms)


func _spear_stab(duration: float) -> void:
	_action_time = duration
	_was_acting = true
	_full_body_action = false
	if _right_item == null:
		return
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton and not skeleton.skeleton_updated.is_connected(_place_stab):
		_stab_scale = _right_item.global_basis.get_scale()
		_carry_transform = _right_item.transform
		skeleton.skeleton_updated.connect(_place_stab)
	if _stab_tween:
		_stab_tween.kill()
	_stab_tween = create_tween()
	_stab_tween.tween_method(func(t: float) -> void: _stab_phase = t, 0.0, 1.0, duration * 0.95)
	_stab_tween.tween_callback(func() -> void:
		_stab_phase = -1.0
		if is_instance_valid(_right_item):
			_right_item.transform = _carry_transform)
	get_tree().create_timer(duration * STAB_DRAW).timeout.connect(func() -> void:
		if not is_dead and is_inside_tree():
			var forward := facing()
			HitFx.stab(self, 0.55, atan2(forward.x, forward.z), melee_range + 0.45, 0.22, Color(1.0, 0.96, 0.85), 0.2))


## After each skeleton update while stabbing: the spear level and pointing straight ahead from the hand,
## drawn back, pushed out and back again (blended from / to the carry grip at the ends).
func _place_stab() -> void:
	if _stab_phase < 0.0 or not is_instance_valid(_right_item):
		return
	var p := _stab_phase
	var push := 0.0
	if p < STAB_DRAW:
		push = lerpf(0.0, STAB_BACK, p / STAB_DRAW)
	elif p < STAB_OUT:
		push = lerpf(STAB_BACK, STAB_REACH, ease((p - STAB_DRAW) / (STAB_OUT - STAB_DRAW), 0.3))
	elif p < STAB_HOLD:
		push = STAB_REACH
	else:
		push = lerpf(STAB_REACH, 0.0, (p - STAB_HOLD) / (1.0 - STAB_HOLD))
	var level := clampf(minf(p / 0.15, (1.0 - p) / 0.15), 0.0, 1.0)
	var carry := (_right_item.get_parent() as Node3D).global_transform * _carry_transform
	var forward := facing()
	var shaft := Basis(forward.cross(Vector3.UP), forward, Vector3.UP)  # +Y (shaft, tip) ahead
	var hand := carry.origin
	var aimed := Transform3D(shaft.scaled(_stab_scale), hand + forward * (push - 0.2))
	var blended := carry.interpolate_with(aimed, level)
	blended.origin = carry.origin.lerp(hand + forward * (push - 0.2), level)
	_right_item.global_transform = blended


func _find_leader() -> void:
	for player in get_tree().get_nodes_in_group(&"players"):
		if (player as Player).peer_id == owner_peer:
			leader = player
			_order_serial = leader.order_serial  # orders given before we joined are not news
			return


## Applies the player's soldier upgrades (keeps the current health fraction).
func refresh_army_bonus() -> void:
	var valid := is_instance_valid(leader)
	var ratio := health / max_health if max_health > 0.0 else 1.0
	max_health = _base_max_health * (leader.ally_health if valid else 1.0)
	health = max_health * ratio
	melee_damage = _base_damage * (leader.ally_damage if valid else 1.0)


## Compact spiral ("sunflower") formation around the player: slot i sits at radius ~sqrt(i),
## so followers stay packed instead of covering the screen.
## Archers stand apart: rows of five behind the hero (behind = against the way it walks).
func _update_slot() -> void:
	var squad: Array[Node] = []
	if is_instance_valid(leader):
		squad = leader.followers().filter(func(a: Node) -> bool: return a.is_archer() == is_archer())
	var index := maxi(squad.find(self), 0)
	if is_archer():
		var row := index / 5
		var spread := (index % 5 - 2) * 0.42 + (0.21 if row % 2 == 1 else 0.0)
		_slot_offset = (-_heading).rotated(Vector3.UP, spread) * (2.0 + 0.8 * row)
		return
	var angle := index * 2.39996  # golden angle
	var slot_radius := 1.1 + 0.5 * sqrt(index)
	_slot_offset = Vector3(cos(angle), 0.0, sin(angle)) * slot_radius


## Every peer: shrink while penned, back to full size when released (`animate`: grow / shrink smoothly).
func _apply_pen_scale(animate: bool) -> void:
	if not is_node_ready():
		return
	var size := _model_scale * (PENNED_SCALE if penned else 1.0)
	if animate:
		create_tween().tween_property(model, "scale", size, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		model.scale = size


## Server: the player took it from the pen.
## `delay`: wait this long before walking out; `lane` (-1..1): where to pass through the gate's width.
func release(delay: float = 0.0, lane: float = 0.0) -> void:
	if not penned:
		return
	penned = false
	_exit_path.clear()
	_exit_delay = delay
	if is_instance_valid(pen):
		_nearby_barracks = [pen]
		_exit_path.append(pen.gate_inside(lane))
		_exit_path.append(pen.gate_point(lane))
	target = null


func take_damage(amount: float, attacker: Node3D = null, is_melee: bool = true, crit: bool = false) -> void:
	if not penned:
		super(amount, attacker, is_melee, crit)


func _get_move_input(delta: float) -> Vector3:
	var move := _desired_move(delta)
	move.y = 0.0
	var strength := move.length()
	if strength < 0.15:
		return Vector3.ZERO
	return move / strength * (1.0 if strength >= 0.75 else walk_share)


## The move this frame (any length up to 1); `_get_move_input` turns it into a run or a walk.
func _desired_move(delta: float) -> Vector3:
	_update_compound_collision()
	look_override = Vector3.ZERO  # archers face their target while shooting / stepping back (`_shoot_at`)
	if penned:
		return _pen_move(delta)
	if not _exit_path.is_empty():
		return _exit_move(delta)
	_regroup = maxf(_regroup - delta, 0.0)
	_think_timer -= delta
	# A new order is obeyed this frame, not at the next think.
	if _think_timer <= 0.0 or (is_instance_valid(leader) and leader.order_serial != _order_serial):
		_think_timer = 0.25 + randf() * 0.1
		_think()

	if not GameConfig.is_gone(target):
		var via := _route(target.global_position)
		if via != target.global_position:
			return _walk_to(via, delta)
		return _shoot_at(delta) if is_archer() else engage(target, delta)
	var order := _order()
	if order == Player.Order.FOLLOW and GameConfig.is_gone(leader):
		return Vector3.ZERO
	var slot := _slot_point()
	var via := _route(slot)
	if via != slot:
		return _walk_to(via, delta)
	if _via != Vector3.INF:
		# Cut off from the slot (a wall, a house): the hero's own way around.
		if _via.distance_to(Vector3(global_position.x, 0.0, global_position.z)) < 0.5:
			_via = _trail_point(slot)
			if _via == Vector3.INF:
				return Vector3.ZERO
		return _walk_to(_via, delta)
	var to_slot := slot - global_position
	to_slot.y = 0.0
	var dist := to_slot.length()
	if dist < 0.4:
		return _separation * 0.5
	# Run when behind, walk the last bit.
	return steer(to_slot.normalized() * (1.0 if dist > walk_distance else 0.5), delta)


## Archer: walk up until the target is in range with a clear line of fire (around what blocks it), then
## shoot (leading it a little); an enemy right next to it makes it step back while shooting.
func _shoot_at(delta: float) -> Vector3:
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length() - Unit.target_radius(target) > shoot_range or not _clear_shot(target):
		return steer(to, delta, target, true)
	look_override = to.normalized()
	face(to, delta * 2.0)
	if _melee_timer <= 0.0 and _action_time <= 0.0:
		_melee_timer = melee_cooldown * randf_range(0.9, 1.1)
		play_action("holding-left-shoot", 0.3, ARM_LEFT)
		get_tree().create_timer(0.12).timeout.connect(_release_arrow)
	var away := _keep_away()
	if away != Vector3.ZERO:
		return steer(away, delta)
	return _separation * 0.5


## Away from the closest enemy within ARCHER_KEEP_AWAY (a little toward the hero), or ZERO.
func _keep_away() -> Vector3:
	var near := find_nearest([&"active_enemies", &"player_units"], ARCHER_KEEP_AWAY)
	if near == null:
		return Vector3.ZERO
	var away := global_position - near.global_position
	away.y = 0.0
	if is_instance_valid(leader):
		var home := leader.global_position - global_position
		home.y = 0.0
		if home.length() > 0.5:
			away = away.normalized() + home.normalized() * 0.35
	return away.normalized()


## Nothing (a tree, a wall) between this archer's bow and `node` (arrows would stop on it).
func _clear_shot(node: Node3D) -> bool:
	var from := global_position + Vector3(0, 0.55, 0)
	var to := node.global_position + Vector3(0, 0.55, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, OBSTACLE_MASK)
	var exclude: Array[RID] = [get_rid()]
	if node is CollisionObject3D:
		exclude.append((node as CollisionObject3D).get_rid())
	query.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## A unit-wide path from here to `point` with nothing in the way.
func _clear_walk(point: Vector3) -> bool:
	var motion := point - global_position
	motion.y = 0.0
	if motion.length() < 0.05:
		return true
	if _probe_shape == null:
		_probe_shape = SphereShape3D.new()
		_probe_shape.radius = clampf(radius * 0.6, 0.24, 0.5)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe_shape
	query.collision_mask = OBSTACLE_MASK
	query.transform = Transform3D(Basis(), global_position + Vector3(0, 0.45, 0))
	query.motion = motion
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.cast_motion(query)[0] >= 0.999


## The newest point of the hero's trail we can walk straight to (INF: none, or the slot is in reach anyway).
func _trail_point(slot: Vector3) -> Vector3:
	if not is_instance_valid(leader) or _clear_walk(slot):
		return Vector3.INF
	var points := leader.trail
	for i in range(points.size() - 1, -1, -1):
		if _clear_walk(points[i]):
			return points[i]
	return Vector3.INF


func _release_arrow() -> void:
	if is_dead or GameConfig.is_gone(target):
		return
	var from := global_position + Vector3(0, 0.55, 0)
	var aim := target.global_position
	if target is CharacterBody3D:
		aim += (target as CharacterBody3D).velocity * 0.2
	var direction := aim - from
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	direction = direction.normalized()
	face_now(direction)
	NetSpawn.projectile(&"arrow", from + direction * 0.4, direction, melee_damage, self)


## Soldier–soldier collision only outside barracks compounds: inside (walls included, so the gate
## opening counts), drop the allies bit from our mask and the separation push. Our own layer stays, so
## orcs and hits still find us; walls / buildings are on other layers and keep blocking.
func _update_compound_collision() -> void:
	var inside := false
	if is_instance_valid(pen) and pen.in_pen(global_position, -ShopStation.WALL_T):
		inside = true
	else:
		for barracks in _nearby_barracks:
			if is_instance_valid(barracks) and barracks.in_pen(global_position, -ShopStation.WALL_T):
				inside = true
				break
	if inside == _in_compound:
		return
	_in_compound = inside
	if inside:
		collision_mask &= ~GameConfig.LAYER_ALLIES
		separation_strength = 0.0
		_separation = Vector3.ZERO
	else:
		collision_mask |= GameConfig.LAYER_ALLIES
		separation_strength = _base_separation_strength


## Filing out of the pen: wait for our turn, walk to our lane inside the gate, then out through it.
func _exit_move(delta: float) -> Vector3:
	if _exit_delay > 0.0:
		_exit_delay -= delta
		return Vector3.ZERO
	var to_gate := _exit_path[0] - global_position
	to_gate.y = 0.0
	if to_gate.length() < 0.5:
		_exit_path.pop_front()
		return Vector3.ZERO
	return steer(to_gate.normalized(), delta)


## The point to walk toward on the way to `goal`: `goal`, or a corner around a barracks in the way.
func _route(goal: Vector3) -> Vector3:
	for barracks in _nearby_barracks:
		if is_instance_valid(barracks):
			var via := barracks.detour(global_position, goal, radius + 0.6)
			if via != goal:
				return via
	return goal


func _walk_to(point: Vector3, delta: float) -> Vector3:
	var to := point - global_position
	to.y = 0.0
	return steer(to.normalized(), delta) if to.length() > 0.05 else Vector3.ZERO


## In the pen: mostly stand around, now and then stroll to another spot inside the fence (the pen is
## a plain square, so the way there is straight).
func _pen_move(delta: float) -> Vector3:
	if not is_instance_valid(pen):
		return Vector3.ZERO
	_think_timer -= delta
	if _wander_point == Vector3.INF or not pen.in_pen(_wander_point, 0.2):
		_wander_point = pen.pen_spot()
	elif _think_timer <= 0.0:
		_think_timer = randf_range(4.0, 9.0)
		if randf() < 0.35:
			_wander_point = pen.pen_spot()
	var to_spot := _wander_point - global_position
	to_spot.y = 0.0
	# Resting soldiers only walk back when shoved well away (else a crowd keeps pushing each other
	# off their spots and walking back: jitter).
	if to_spot.length() < (1.2 if _resting else 0.5):
		_resting = true
		return Vector3.ZERO
	_resting = false
	return to_spot.normalized() * 0.5  # strolls (walk speed)


func _think() -> void:
	if not is_instance_valid(leader):
		_find_leader()
	_nearby_barracks = ShopStation.barracks_near(get_tree(), global_position)
	if is_instance_valid(leader) and leader.order_serial != _order_serial:
		_obey()
	shoot_range = archer_range()
	if is_instance_valid(leader):
		var walking := leader.velocity
		walking.y = 0.0
		if walking.length() > 0.8:
			_heading = _heading.slerp(walking.normalized(), 0.5).normalized()
	_via = Vector3.INF
	var order := _order()
	if order == Player.Order.KILL:
		_think_kill()
		return
	if _regroup > 0.0:
		# Carrying out an order: go to the new spot, ignore fights on the way.
		_update_slot()
		target = null
		if not GameConfig.is_gone(leader) and _slot_point().distance_to(global_position) < regroup_arrive:
			_regroup = 0.0
		return
	if order != Player.Order.FOLLOW:
		_think_order(order)
		return
	var sight := _sight()
	if GameConfig.is_gone(leader):
		target = _commit_target(target if is_instance_valid(target) and target is Unit else null,
				_best_enemy(global_position, sight), sight + 2.5)
		return
	_update_slot()
	if global_position.distance_to(leader.global_position) > leash_range:
		target = null
		_via = _trail_point(_slot_point())
		return
	var unit_target := target if is_instance_valid(target) and target is Unit else null
	# Archers stand behind the hero: they look out from the hero, as far as they shoot and a bit more.
	var candidate := _best_enemy(leader.global_position, shoot_range + 3.0) if is_archer() \
			else _best_enemy(global_position, sight)
	target = _commit_target(unit_target, candidate, sight + 2.5)
	if target == null:
		target = _camp_to_attack()
	if target == null:
		_via = _trail_point(_slot_point())


## The leader's army order (FOLLOW without a leader).
func _order() -> int:
	return leader.army_order if is_instance_valid(leader) else Player.Order.FOLLOW


## How far a soldier looks for enemies: archers a little past their shooting range.
func _sight() -> float:
	return maxf(aggro_range, shoot_range + 1.5) if is_archer() else aggro_range


## Melee soldiers finish the enemy they're after: no switching to a closer one that got in the way (they
## steer around those, `chase_avoid_mask`), only to one that is hitting the hero or a squadmate while ours
## isn't. A new target once it's dead or out of `keep_range`. Archers pick again every think (`_best_enemy`
## keeps the current one a little ahead).
func _commit_target(current: Node3D, candidate: Node3D, keep_range: float) -> Node3D:
	if GameConfig.is_gone(current) or flat_distance_to(current) > keep_range or is_archer():
		return candidate
	if candidate and candidate != current and _defending(candidate) and not _defending(current):
		return candidate
	return current


## `enemy` is attacking our hero or one of our squad.
func _defending(enemy: Node3D) -> bool:
	var victim: Variant = enemy.get("target")
	if not victim is Node3D or not is_instance_valid(victim):
		return false
	return victim == leader or (victim is Ally and (victim as Ally).owner_peer == owner_peer)


## Teamwork target choice within `max_range` of `origin`: the closest, but enemies hitting the hero count as
## DEFEND_BONUS m closer (hitting a squadmate: GUARD_BONUS); melee soldiers add CROWD_PENALTY per squadmate
## already on it (they spread over the enemies); archers prefer the wounded and a clear line of fire.
func _best_enemy(origin: Vector3, max_range: float) -> Node3D:
	var squad: Array[Node] = leader.followers() if is_instance_valid(leader) else []
	var best: Node3D = null
	var best_score := INF
	for group in TARGET_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			if GameConfig.is_gone(node) or node == self or not GameConfig.is_hostile(self, node):
				continue
			var enemy := node as Node3D
			var d := Vector2(enemy.global_position.x - origin.x, enemy.global_position.z - origin.z).length()
			if d > max_range:
				continue
			var score := d
			if _defending(enemy):
				score -= DEFEND_BONUS if enemy.get("target") == leader else GUARD_BONUS
			if is_archer():
				var hp: Variant = enemy.get("health")
				var top: Variant = enemy.get("max_health")
				if hp is float and top is float and top > 0.0:
					score -= 2.0 * (1.0 - hp / top)
				if not _clear_shot(enemy):
					score += BLOCKED_PENALTY
			else:
				for mate in squad:
					if mate != self and not mate.is_archer() and mate.target == enemy:
						score += CROWD_PENALTY
			if enemy == target:
				score -= 1.0  # no flip-flopping between two close ones
			if score < best_score:
				best_score = score
				best = enemy
	return best


## A new order: drop the current fight and go (KILL: straight for the target).
func _obey() -> void:
	_order_serial = leader.order_serial
	target = null
	_target_lock = 0.0
	_regroup = 0.0 if leader.army_order == Player.Order.KILL else regroup_time


## Where this soldier stands in the formation: around the player (FOLLOW) or the ordered point.
func _slot_point() -> Vector3:
	var anchor := leader.global_position if _order() == Player.Order.FOLLOW else leader.army_point
	return anchor + _slot_offset


## KILL: everyone on the ordered target, no leash, no switching (the player turns the order into a
## CHARGE once it is dead).
func _think_kill() -> void:
	_update_slot()
	if GameConfig.is_gone(leader.army_target):
		_think_order(Player.Order.CHARGE)
		return
	target = leader.army_target


## CHARGE / HOLD: fight what comes near the point (charging soldiers also fight on the way there).
func _think_order(order: int) -> void:
	_update_slot()
	var point := leader.army_point
	var guard := charge_radius if order == Player.Order.CHARGE else hold_radius
	var candidate := _best_enemy(point, guard)
	if candidate == null and order == Player.Order.CHARGE:
		candidate = _best_enemy(global_position, _sight())
	target = _commit_target(target if is_instance_valid(target) and target is Unit else null, candidate, guard + 6.0)
	if target == null:
		target = _camp_near(point, guard + 3.0)
	if target and target.global_position.distance_to(point) > guard + 6.0:
		target = null  # don't get dragged away from the point


func _camp_near(point: Vector3, max_distance: float) -> Node3D:
	var best: Node3D = null
	var best_dist := max_distance
	for node in get_tree().get_nodes_in_group(CAMP_GROUPS[0]):
		var camp := node as Camp
		if camp == null or camp.is_dead:
			continue
		var d := camp.global_position.distance_to(point) - camp.radius
		if d < best_dist:
			best_dist = d
			best = camp
	return best


## Help knock down a camp the player is attacking or standing next to.
func _camp_to_attack() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group(CAMP_GROUPS[0]):
		var camp := node as Camp
		if camp == null or camp.is_dead:
			continue
		var from_leader := camp.global_position.distance_to(leader.global_position)
		if from_leader > 8.0 + camp.radius and not (camp.attacked_recently_by(owner_peer) and from_leader < 16.0):
			continue
		var d := camp.global_position.distance_to(global_position)
		if d < best_dist:
			best_dist = d
			best = camp
	return best


func _on_died() -> void:
	remove_from_group(&"allies")
	remove_from_group(&"penned")
	remove_from_group(&"player_units")

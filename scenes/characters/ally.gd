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
## The player's army order (Player.army_order) changes where the formation stands: around the player
## (FOLLOW), or around Player.army_point, where they fight everything nearby (CHARGE) or guard it (HOLD);
## KILL hunts Player.army_target down (then CHARGE where it fell). Orders are always obeyed: on every new
## order (Player.order_serial) soldiers drop their fight at once and walk to their new spot without
## fighting (`_regroup`, until they get there or `regroup_time` runs out); KILL goes straight for the target.

const TARGET_GROUPS: Array[StringName] = [&"active_enemies", &"player_units"]
const CAMP_GROUPS: Array[StringName] = [&"camps"]
## Soldiers waiting in the barracks courtyard are drawn this much smaller (every peer; visual only).
const PENNED_SCALE: float = 0.7

@export var aggro_range: float = 6.0
## Stop chasing when this far from the player.
@export var leash_range: float = 9.0
## Speed boost while far from the formation, so the army keeps up after long runs.
@export var catch_up_multiplier: float = 1.5
@export var catch_up_distance: float = 4.0
## Orders: soldiers fight hostiles within this distance of the charge / hold point.
@export var charge_radius: float = 9.0
@export var hold_radius: float = 6.0
## After an order: at most this many seconds of walking to the new spot without fighting.
@export var regroup_time: float = 6.0
## Regrouping ends this close to the soldier's slot (then it fights normally again).
@export var regroup_arrive: float = 2.5

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
var _base_speed: float
var _base_max_health: float
var _base_damage: float


func _ready() -> void:
	super()
	_apply_pen_scale(false)
	chase_avoid_mask = GameConfig.LAYER_ENEMIES  # go around orcs in the way to the one we're after
	add_to_group(&"allies")
	if not penned:
		add_to_group(&"player_units")
	_think_timer = randf() * 0.3
	_base_speed = move_speed
	_base_separation_strength = separation_strength
	_base_max_health = max_health
	_base_damage = melee_damage
	_find_leader()
	refresh_army_bonus()


func _find_leader() -> void:
	for player in get_tree().get_nodes_in_group(&"players"):
		if (player as Player).peer_id == owner_peer:
			leader = player
			_order_serial = leader.order_serial  # orders given before we joined are not news
			return


## Applies the player's soldier upgrades (keeps the current health fraction).
func refresh_army_bonus() -> void:
	var power: float = leader.ally_power if is_instance_valid(leader) else 1.0
	var ratio := health / max_health if max_health > 0.0 else 1.0
	max_health = _base_max_health * power
	health = max_health * ratio
	melee_damage = _base_damage * power


## Compact spiral ("sunflower") formation around the player: slot i sits at radius ~sqrt(i),
## so followers stay packed instead of covering the screen.
func _update_slot() -> void:
	var index := maxi(leader.followers().find(self), 0) if is_instance_valid(leader) else 0
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
	_update_compound_collision()
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
		move_speed = _base_speed
		var via := _route(target.global_position)
		if via != target.global_position:
			return _walk_to(via, delta)
		return engage(target, delta)
	var order := _order()
	if order == Player.Order.FOLLOW and GameConfig.is_gone(leader):
		return Vector3.ZERO
	var slot := _slot_point()
	var via := _route(slot)
	if via != slot:
		move_speed = _base_speed * catch_up_multiplier
		return _walk_to(via, delta)
	var to_slot := slot - global_position
	to_slot.y = 0.0
	var dist := to_slot.length()
	move_speed = _base_speed * (catch_up_multiplier if dist > catch_up_distance else 1.0)
	if dist < 0.4:
		return _separation * 0.5
	# Hurry when far behind, stroll when close.
	return steer(to_slot.normalized() * clampf(dist / 3.0, 0.3, 1.0), delta)


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
	move_speed = _base_speed
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
	move_speed = _base_speed * 0.45
	return to_spot.normalized() * 0.7


func _think() -> void:
	if not is_instance_valid(leader):
		_find_leader()
	_nearby_barracks = ShopStation.barracks_near(get_tree(), global_position)
	if is_instance_valid(leader) and leader.order_serial != _order_serial:
		_obey()
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
	if GameConfig.is_gone(leader):
		target = _commit_target(target if is_instance_valid(target) and target is Unit else null, find_nearest(TARGET_GROUPS, aggro_range), aggro_range + 2.5)
		return
	_update_slot()
	if global_position.distance_to(leader.global_position) > leash_range:
		target = null
		return
	var unit_target := target if is_instance_valid(target) and target is Unit else null
	target = _commit_target(unit_target, find_nearest(TARGET_GROUPS, aggro_range), aggro_range + 2.5)
	if target == null:
		target = _camp_to_attack()


## The leader's army order (FOLLOW without a leader).
func _order() -> int:
	return leader.army_order if is_instance_valid(leader) else Player.Order.FOLLOW


## Soldiers finish the enemy they're after: no switching to a closer one that got in the way (they steer
## around those, `chase_avoid_mask`). A new target only once it's dead or out of `keep_range`.
func _commit_target(current: Node3D, candidate: Node3D, keep_range: float) -> Node3D:
	if not GameConfig.is_gone(current) and flat_distance_to(current) <= keep_range:
		return current
	return candidate


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
	var candidate := find_nearest(TARGET_GROUPS, guard, point)
	if candidate == null and order == Player.Order.CHARGE:
		candidate = find_nearest(TARGET_GROUPS, aggro_range)
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

class_name Ally
extends Unit
## Soldier freed from a destroyed camp. Follows its player (`owner_peer`) in a compact formation and
## fights nearby hostiles: orcs, and in versus modes other players and their soldiers.
## Once dead, it is gone for good. At most Player.follower_cap are in the world per player; extra
## soldiers wait in that player's reserve and run in as replacements (see main.gd).
## The player's army order (Player.army_order) changes where the formation stands: around the player
## (FOLLOW), or around Player.army_point, where they fight everything nearby (CHARGE) or guard it (HOLD).

const TARGET_GROUPS: Array[StringName] = [&"active_enemies", &"player_units"]
const CAMP_GROUPS: Array[StringName] = [&"camps"]

@export var aggro_range: float = 6.0
## Stop chasing when this far from the player.
@export var leash_range: float = 9.0
## Speed boost while far from the formation, so the army keeps up after long runs.
@export var catch_up_multiplier: float = 1.5
@export var catch_up_distance: float = 4.0
## Orders: soldiers fight hostiles within this distance of the charge / hold point.
@export var charge_radius: float = 9.0
@export var hold_radius: float = 6.0

var leader: Player
var target: Node3D

var _think_timer: float = 0.0
var _slot_offset: Vector3
var _base_speed: float
var _base_max_health: float
var _base_damage: float


func _ready() -> void:
	super()
	add_to_group(&"allies")
	add_to_group(&"player_units")
	_think_timer = randf() * 0.3
	_base_speed = move_speed
	_base_max_health = max_health
	_base_damage = melee_damage
	_find_leader()
	refresh_army_bonus()


func _find_leader() -> void:
	for player in get_tree().get_nodes_in_group(&"players"):
		if (player as Player).peer_id == owner_peer:
			leader = player
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


func _get_move_input(delta: float) -> Vector3:
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = 0.25 + randf() * 0.1
		_think()

	if not GameConfig.is_gone(target):
		move_speed = _base_speed
		return engage(target, delta)
	var order := _order()
	if order == Player.Order.FOLLOW and GameConfig.is_gone(leader):
		return Vector3.ZERO
	var anchor := leader.global_position if order == Player.Order.FOLLOW else leader.army_point
	var to_slot := anchor + _slot_offset - global_position
	to_slot.y = 0.0
	var dist := to_slot.length()
	move_speed = _base_speed * (catch_up_multiplier if dist > catch_up_distance else 1.0)
	if dist < 0.4:
		return _separation * 0.5
	# Hurry when far behind, stroll when close.
	return steer(to_slot.normalized() * clampf(dist / 3.0, 0.3, 1.0), delta)


func _think() -> void:
	if not is_instance_valid(leader):
		_find_leader()
	var order := _order()
	if order != Player.Order.FOLLOW:
		_think_order(order)
		return
	if GameConfig.is_gone(leader):
		target = choose_target(target if target is Unit else null, find_nearest(TARGET_GROUPS, aggro_range), aggro_range + 2.5)
		return
	_update_slot()
	if global_position.distance_to(leader.global_position) > leash_range:
		target = null
		return
	# Sticky: keep fighting the current enemy unless another one is much closer.
	var unit_target := target if target is Unit else null
	target = choose_target(unit_target, find_nearest(TARGET_GROUPS, aggro_range), aggro_range + 2.5)
	if target == null:
		target = _camp_to_attack()


## The leader's army order (FOLLOW without a leader).
func _order() -> int:
	return leader.army_order if is_instance_valid(leader) else Player.Order.FOLLOW


## CHARGE / HOLD: fight what comes near the point (charging soldiers also fight on the way there).
func _think_order(order: int) -> void:
	_update_slot()
	var point := leader.army_point
	var guard := charge_radius if order == Player.Order.CHARGE else hold_radius
	var candidate := find_nearest(TARGET_GROUPS, guard, point)
	if candidate == null and order == Player.Order.CHARGE:
		candidate = find_nearest(TARGET_GROUPS, aggro_range)
	target = choose_target(target if target is Unit else null, candidate, guard + 6.0)
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
	remove_from_group(&"player_units")

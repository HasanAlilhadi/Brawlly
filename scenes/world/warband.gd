class_name Warband
extends Node3D
## A roaming group of enemies (they replaced the old camps). Its size is its power: a few grunts or
## skeletons near the start; bigger bands bring throwers, archers and elites (brutes, ghosts, necromancers,
## vampires) and are tougher (`tier`); the biggest are led by a boss (Orc Warlord, Vampire Lord) — slay
## the boss and the rest of the band is routed. What a band is made of comes from its `roster`
## (resources/data/orc_warband.tres, undead_warband.tres).
##
## The band walks in formation (melee in front, ranged at the back, the leader in the middle) from one
## open spot of its territory to the next, rests a little, and goes on. When one of them spots or is hit by a
## hero or soldier, the whole band attacks; after the fight it regroups where it stands and marches on.
## Fallen members come back (one by one, while no hero is near and the band is calm) until the whole band
## is wiped out: then it is `defeated` for good. With a `quarry` (the Warlord's event band) it marches on
## that player instead, picking up reinforcements on the way.
##
## Bands far from every hero are paused (their members neither think nor replicate); the band then keeps
## walking on its own and moves the members along, cheaply. Nothing floats over a band in the world — only
## large bands (at least LARGE_SIZE alive) show on the minimap.
##
## Multiplayer: every peer builds the same bands (same names) from the shared seed; only the server spawns
## members and runs them; clients get the position / count (`_net_state`) and the defeat by RPC. Event bands
## exist on the server only (`replicated` = false).

signal defeated(band: Warband)

## Bands with at least this many alive show on the minimap.
const LARGE_SIZE: int = 10
## Members stand this far apart in the formation.
const SPACING: float = 1.25
## Seconds between the band's decisions.
const THINK_INTERVAL: float = 0.25
enum State { MARCH, REST, FIGHT }

## What the band is made of (set before adding to the tree).
@export var roster: EnemyRoster
## Members are only simulated while a player is within this distance — farther than the widest view (desktop,
## zoomed out for the bow), so nobody ever sees a paused band standing frozen.
@export var activation_range: float = 50.0
## Waypoints are picked within this distance of where the band started.
@export var territory: float = 30.0
## Seconds resting at each waypoint.
@export var rest_time: Vector2 = Vector2(3.0, 8.0)
## March speed as a share of its slowest member's speed (they walk, the walk clip plays).
@export var march_share: float = 0.5
## Respawn delay of fallen members (scaled by the match's difficulty) — only while calm and unseen.
@export var respawn_delay: float = 14.0
## No respawns until the band has been left alone this long.
@export var calm_before_respawn: float = 20.0
## Health / damage multiplier for the smallest (`tier` 0) and the biggest bands (tier 1), × difficulty.
@export var weak_stat_multiplier: float = 0.8
@export var strong_stat_multiplier: float = 1.3

## Set before adding to the tree.
var size: int = 4
## 0 = smallest band … 1 = biggest (stats and loot grow with it).
var tier: float = 0.0
## Orc / undead (for the minimap badge).
var faction: StringName = &"orc"
## Points the band never marches within `avoid_radius` of (spawn areas).
var avoid_points: Array[Vector3] = []
var avoid_radius: float = 24.0
## False for bands made at runtime on the server only (the Warlord event).
var replicated: bool = true
## Event bands march on this player instead of patrolling (re-picked when gone).
var quarry: Node3D
## Leads the band instead of the roster's leaders (the Warlord event).
var leader_scene: PackedScene
## The leader gets a minimap badge and an off-screen arrow for everyone (the Warlord event).
var track_leader: bool = false
## > 0: members' stat multiplier instead of the one from `tier` (event bands).
var strength_override: float = 0.0
## Event bands: 2 reinforcements every this many seconds (0 = none), up to `reinforce_max` members.
var reinforce_interval: float = 0.0
var reinforce_max: int = 0
## Orcs are their own team.
var team_id: int = GameConfig.ORC_TEAM
## Members alive (server counts; clients receive it).
var alive: int = 0
var is_dead: bool = false
## Its composition has a boss leader (known on every peer).
var has_boss: bool = false
## The member in the middle of the formation: the boss, or the strongest (server).
var leader: Enemy

var _slot_scenes: Array[PackedScene] = []
var _slot_rear: Array[bool] = []
var _slot_offsets: Array[Vector3] = []
var _members: Array[Enemy] = []
var _extra: Array[Enemy] = []  # minions and reinforcements (not respawned)
var _respawn_timers: Array[float] = []
var _origin: Vector3
var _heading: Vector3 = Vector3.FORWARD
var _waypoint: Vector3 = Vector3.INF
var _state: int = State.REST
var _state_time: float = 0.0
var _think_timer: float = 0.0
var _snap_timer: float = 0.0
var _sync_timer: float = 0.0
var _reinforce_timer: float = 0.0
var _active: bool = false
var _started: bool = false
var _last_fight_ms: int = -100000
var _last_hit_peer: int = 0
var _march_speed: float = 1.4
var _lag_time: float = 0.0
var _coordinate_timer: float = 0.0
## At most this many melee members on one foe; the others take on the next one close by.
const MAX_ON_ONE: int = 5


func _ready() -> void:
	add_to_group(&"warbands")
	_origin = global_position
	_compose()
	alive = size
	_heading = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	_think_timer = randf() * THINK_INTERVAL


## Which scene stands in which slot (leaders first, the ranged last). Runs on every peer in the same order
## (shared seed), so `has_boss` is known everywhere.
func _compose() -> void:
	var leaders: Array[PackedScene] = []
	var front: Array[PackedScene] = []
	var rear: Array[PackedScene] = []
	if leader_scene:
		leaders.append(leader_scene)
	for entry in roster.entries:
		for i in entry.count_for(size):
			if entry.leader:
				if leader_scene == null:
					leaders.append(entry.scene)
			elif entry.rear:
				rear.append(entry.scene)
			else:
				front.append(entry.scene)
	has_boss = not leaders.is_empty()
	while leaders.size() + front.size() + rear.size() < size:
		front.append(roster.filler)
	front.shuffle()
	# Too many specialists for the size: the rear (ranged) gives way first, then the front.
	while leaders.size() + front.size() + rear.size() > size and not rear.is_empty():
		rear.pop_back()
	while leaders.size() + front.size() + rear.size() > size and not front.is_empty():
		front.pop_back()
	_slot_scenes.clear()
	_slot_rear.clear()
	for scene in leaders + front:
		_slot_scenes.append(scene)
		_slot_rear.append(false)
	for scene in rear:
		_slot_scenes.append(scene)
		_slot_rear.append(true)
	size = _slot_scenes.size()
	_slot_offsets = _formation()
	_members.resize(size)
	_respawn_timers.resize(size)
	_respawn_timers.fill(0.0)


## Spots in the band's own frame (+Z = where it marches): the leader in the middle, the melee in a blob
## around and ahead of it, the ranged in rows behind.
func _formation() -> Array[Vector3]:
	var offsets: Array[Vector3] = []
	var melee := 0
	var ranged := 0
	for i in size:
		if _slot_rear[i]:
			ranged += 1
		else:
			melee += 1
	var melee_index := 0
	var melee_extent := 0.0
	for i in size:
		if _slot_rear[i]:
			offsets.append(Vector3.ZERO)
			continue
		# Sunflower spiral: an even blob, the first slots (leader, big ones) in the middle.
		var r := SPACING * sqrt(melee_index + (0.0 if melee_index == 0 else 0.5)) * 0.95
		var angle := melee_index * 2.39996
		var spot := Vector3(cos(angle) * r, 0.0, sin(angle) * r * 0.8 + 0.4)
		melee_extent = maxf(melee_extent, r)
		offsets.append(spot)
		melee_index += 1
	var ranged_index := 0
	var per_row := maxi(3, ceili(sqrt(float(ranged)) * 1.5))
	for i in size:
		if not _slot_rear[i]:
			continue
		var row := ranged_index / per_row
		var in_row := mini(per_row, ranged - row * per_row)
		var column := ranged_index % per_row
		var x := (column - (in_row - 1) * 0.5) * SPACING * 1.1
		offsets[i] = Vector3(x, 0.0, -(melee_extent * 0.8 + 1.4 + row * SPACING))
		ranged_index += 1
	return offsets


## Health / damage multiplier of its members (difficulty × band power).
func strength() -> float:
	if strength_override > 0.0:
		return strength_override
	return lerpf(weak_stat_multiplier, strong_stat_multiplier, tier) * GameConfig.orc_strength


## Server: spawn the band (called by main when the match starts).
func start() -> void:
	if _started or not multiplayer.is_server():
		return
	_started = true
	for i in size:
		_spawn(i, _slot_point(i))
	_pick_leader()
	_march_speed = _slowest_speed() * march_share
	_set_active(_is_player_near())
	_state = State.REST
	_state_time = randf_range(0.5, rest_time.y)
	_reinforce_timer = reinforce_interval


func _spawn(slot: int, at: Vector3) -> Enemy:
	var spot := at + Vector3(randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2))
	var data := {"scene": _slot_scenes[slot].resource_path, "strength": strength(), "coins": 1.0 + tier}
	if replicated:
		data["band"] = get_path()
	if track_leader and slot == 0:
		data["tracked"] = true
	var enemy := NetSpawn.unit(&"enemy", GameConfig.clamp_to_world(spot), data) as Enemy
	if enemy == null:
		return null
	enemy.band = self
	enemy.home = spot
	enemy.died.connect(_on_member_died.bind(slot))
	_members[slot] = enemy
	_apply_run_state(enemy, _active or enemy.is_busy())
	_update_alive()
	return enemy


## Server: a summoned minion / reinforcement joins the band (not respawned when it falls).
func adopt(enemy: Enemy) -> void:
	enemy.band = self
	_extra.append(enemy)
	enemy.died.connect(func(_unit: Unit) -> void: _update_alive())
	_apply_run_state(enemy, true)
	_update_alive()


func members() -> Array[Enemy]:
	var list: Array[Enemy] = []
	for enemy in _members + _extra:
		if is_instance_valid(enemy) and not enemy.is_dead:
			list.append(enemy)
	return list


func _on_member_died(unit: Unit, slot: int) -> void:
	if _members[slot] == unit:
		_members[slot] = null
		_respawn_timers[slot] = respawn_delay * GameConfig.orc_respawn_scale
	if unit.last_attacker_peer != 0:
		_last_hit_peer = unit.last_attacker_peer
	_update_alive()
	if unit == leader:
		_pick_leader()
	if alive <= 0 and not is_dead:
		_defeat()


func _update_alive() -> void:
	# filter() returns an untyped Array (assign() keeps ours typed); untyped parameter: freed members can't be Enemy.
	_extra.assign(_extra.filter(func(enemy: Variant) -> bool: return is_instance_valid(enemy) and not enemy.is_dead))
	var count := members().size()
	if count != alive:
		alive = count
		_sync_timer = 0.0


func _pick_leader() -> void:
	leader = null
	for enemy in members():
		if leader == null or enemy.max_health > leader.max_health:
			leader = enemy


## Server: its boss fell — everyone left is routed (falls and drops their loot).
func rout(boss: Enemy) -> void:
	if boss.last_attacker_peer != 0:
		_last_hit_peer = boss.last_attacker_peer
	for enemy in members():
		if enemy != boss:
			enemy.routed = true
			enemy.die()
	_members.fill(null)
	if not is_dead:
		_defeat()


func _defeat() -> void:
	is_dead = true
	alive = 0
	MatchStats.add(_last_hit_peer, &"bands")
	if replicated and Net.is_online():
		_net_defeated.rpc(_last_hit_peer)
	else:
		_net_defeated(_last_hit_peer)
	if not replicated:
		queue_free.call_deferred()  # event bands are gone with their last member


## Peer who finished this band (valid after `defeated`).
func defeated_by() -> int:
	return _last_hit_peer


## The band or one of its members was attacked / spotted a foe: everyone hunts the attacker.
func alert(attacker: Node3D) -> void:
	if is_dead or GameConfig.is_gone(attacker):
		return
	_last_fight_ms = Time.get_ticks_msec()
	for enemy in members():
		enemy.provoke(attacker)
	_set_active(_active)


# --- Marching ----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _started or is_dead:
		return
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = THINK_INTERVAL
		_think(THINK_INTERVAL)
	if _state == State.MARCH:
		if not _lagging():
			_lag_time = 0.0
			_advance(delta)
		else:
			_lag_time += delta
			if _lag_time > 4.0:
				# Stuck behind something: gather where they are and take another way.
				_lag_time = 0.0
				_regroup()
	if not _active:
		_snap_timer -= delta
		if _snap_timer <= 0.0:
			_snap_timer = 1.0
			_snap_members()
	_sync_timer -= delta
	if _sync_timer <= 0.0:
		_sync_timer = 0.5
		if replicated and Net.is_online():
			_net_state.rpc(global_position, alive)


func _think(step: float) -> void:
	_set_active(_is_player_near())
	_reinforce(step)
	var fighting := false
	for enemy in members():
		if enemy.is_busy() and not GameConfig.is_gone(enemy.target):
			fighting = true
			break
	if fighting:
		_last_fight_ms = Time.get_ticks_msec()
		_state = State.FIGHT
		_coordinate_timer -= step
		if _coordinate_timer <= 0.0:
			_coordinate_timer = 1.0
			_coordinate()
	elif _state == State.FIGHT:
		if Time.get_ticks_msec() - _last_fight_ms > 2500:
			_regroup()
	elif quarry != null or reinforce_interval > 0.0:
		_march_on_quarry()
	else:
		_state_time -= step
		if _state == State.REST and _state_time <= 0.0:
			_waypoint = _next_waypoint()
			_state = State.MARCH if _waypoint != Vector3.INF else State.REST
			_state_time = rest_time.x
		elif _state == State.MARCH and (_waypoint == Vector3.INF or _flat(global_position, _waypoint) < 1.5):
			_state = State.REST
			_state_time = randf_range(rest_time.x, rest_time.y)
	_respawn(step)
	var marching := _state == State.MARCH
	var band_velocity := Vector3.ZERO
	if marching and _waypoint != Vector3.INF and _lag_time <= 0.0 and _flat(global_position, _waypoint) > 0.5:
		band_velocity = _heading * _march_speed * (1.6 if quarry != null else 1.0)
	for i in size:
		var enemy := _members[i]
		if is_instance_valid(enemy) and not enemy.is_dead:
			enemy.follow_point(_slot_point(i), _pace_for(enemy) if marching else 0.4, band_velocity)
	for enemy in _extra:
		if is_instance_valid(enemy) and not enemy.is_dead:
			enemy.follow_point(global_position + (enemy.global_position - global_position).limit_length(3.5), 0.5)


## After a fight: the band gathers where most of it stands and marches on from there.
func _regroup() -> void:
	var living := members()
	if not living.is_empty():
		var center := Vector3.ZERO
		for enemy in living:
			center += enemy.global_position
		center /= living.size()
		global_position = GameConfig.clamp_to_world(Vector3(center.x, 0.0, center.z))
	_state = State.REST
	_state_time = randf_range(rest_time.x, rest_time.y) * 0.5


func _march_on_quarry() -> void:
	if GameConfig.is_gone(quarry):
		quarry = _nearest_player()
	if quarry == null:
		_state = State.REST
		return
	_waypoint = quarry.global_position
	_state = State.MARCH


func _advance(delta: float) -> void:
	if _waypoint == Vector3.INF:
		return
	var to := _waypoint - global_position
	to.y = 0.0
	if to.length() < 0.05:
		return
	var speed := _march_speed * (1.6 if quarry != null else 1.0)
	_heading = _heading.slerp(to.normalized(), minf(1.0, delta * 2.0)).normalized()
	global_position = GameConfig.clamp_to_world(global_position + to.normalized() * minf(speed * delta, to.length()))


## Fight tactics for the melee members (plain chasers: flankers, stalkers and spirits have their own ways):
## no more than MAX_ON_ONE on one foe (the farthest extras go for the nearest other foe), and those on the
## same foe spread evenly around it — they surround it instead of queueing on one side.
func _coordinate() -> void:
	var by_target := {}
	for enemy in members():
		if GameConfig.is_gone(enemy.target) or not _plain_melee(enemy):
			continue
		if not by_target.has(enemy.target):
			by_target[enemy.target] = []
		by_target[enemy.target].append(enemy)
	for target in by_target.keys():
		var attackers: Array = by_target[target]
		if attackers.size() > MAX_ON_ONE:
			attackers.sort_custom(func(a: Enemy, b: Enemy) -> bool: return a.flat_distance_to(target) < b.flat_distance_to(target))
			for extra in attackers.slice(MAX_ON_ONE):
				var other := _other_foe_near(extra, target)
				if other:
					extra.target = other
					extra.lock_target()
			attackers = attackers.slice(0, MAX_ON_ONE)
		if attackers.size() < 2:
			continue
		# Evenly spaced around the foe, in the order they already stand (nobody crosses through the others).
		var center := (target as Node3D).global_position
		attackers.sort_custom(func(a: Enemy, b: Enemy) -> bool:
			return _angle_around(a, center) < _angle_around(b, center))
		var mean := 0.0
		var sum := Vector2.ZERO
		for enemy: Enemy in attackers:
			var angle := _angle_around(enemy, center)
			sum += Vector2(cos(angle), sin(angle))
		mean = sum.angle()
		var spread := minf(TAU, attackers.size() * 1.6)
		var step := spread / attackers.size()
		for i in attackers.size():
			var enemy: Enemy = attackers[i]
			enemy._slot_target = target
			enemy._slot_angle = mean - spread * 0.5 + step * (i + 0.5)


func _plain_melee(enemy: Enemy) -> bool:
	var movement := enemy.movement
	return not (movement is KiteMovement or movement is FlankMovement or movement is StalkMovement or movement is FloatMovement)


func _angle_around(enemy: Enemy, center: Vector3) -> float:
	return atan2(enemy.global_position.z - center.z, enemy.global_position.x - center.x)


## The nearest foe other than `busy` within 8 m of `enemy` (heroes and soldiers hostile to the band).
func _other_foe_near(enemy: Enemy, busy: Node3D) -> Node3D:
	var best: Node3D = null
	var best_dist := 8.0
	for node in get_tree().get_nodes_in_group(&"player_units"):
		var foe := node as Node3D
		if foe == busy or GameConfig.is_gone(foe) or not GameConfig.is_hostile(enemy, foe):
			continue
		var d := enemy.flat_distance_to(foe)
		if d < best_dist:
			best_dist = d
			best = foe
	return best


## Members fell behind (stuck at a tree, a wall): the band waits for them.
func _lagging() -> bool:
	if not _active:
		return false
	var behind := 0.0
	var count := 0
	for i in size:
		var enemy := _members[i]
		if is_instance_valid(enemy) and not enemy.is_dead:
			behind += _flat(enemy.global_position, _slot_point(i))
			count += 1
	return count > 0 and behind / count > 3.0


## Paused band: members are moved along with it (onto free spots), without simulating them.
func _snap_members() -> void:
	for i in size:
		var enemy := _members[i]
		if not is_instance_valid(enemy) or enemy.is_dead or enemy.process_mode != PROCESS_MODE_DISABLED:
			continue
		var spot := _slot_point(i)
		if _flat(enemy.global_position, spot) > 0.5 and _is_open(spot, 0.45):
			enemy.global_position = spot
			enemy.net_position = spot
			enemy.home = spot
			enemy.face_now(_heading)
			enemy.net_yaw = enemy.model.rotation.y


func _slot_point(slot: int) -> Vector3:
	var offset := _slot_offsets[slot].rotated(Vector3.UP, atan2(_heading.x, _heading.z))
	return GameConfig.clamp_to_world(global_position + offset)


## Members walk at the band's speed (the walk clip), whoever is faster or slower.
func _pace_for(enemy: Enemy) -> float:
	var speed: float = maxf(enemy._base_speed, 0.1)
	return clampf(_march_speed * (1.6 if quarry != null else 1.0) / speed, 0.25, 1.0)


func _slowest_speed() -> float:
	var slowest := INF
	for enemy in members():
		slowest = minf(slowest, enemy._base_speed)
	return slowest if slowest < INF else 2.5


## An open spot of its territory 12+ m away, away from the spawn areas — preferably one with nothing big
## (a graveyard wall, a tree line) in the way.
func _next_waypoint() -> Vector3:
	var half := GameConfig.world_half - 6.0
	var fallback := Vector3.INF
	for attempt in 12:
		var angle := randf() * TAU
		var spot := _origin + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(territory * 0.3, territory)
		spot.x = clampf(spot.x, -half, half)
		spot.z = clampf(spot.z, -half, half)
		spot.y = 0.0
		if _flat(spot, global_position) < 12.0 or _near_avoided(spot):
			continue
		if _is_open(spot, 2.5):
			if _path_clear(global_position, spot):
				return spot
			if fallback == Vector3.INF:
				fallback = spot
	return fallback


func _path_clear(from: Vector3, to: Vector3) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = 0.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), from + Vector3(0, 0.6, 0))
	query.motion = Vector3(to.x - from.x, 0.0, to.z - from.z)
	query.collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_FENCE
	return get_world_3d().direct_space_state.cast_motion(query)[0] >= 0.999


func _near_avoided(spot: Vector3) -> bool:
	for point in avoid_points:
		if _flat(spot, point) < avoid_radius:
			return true
	return false


func _is_open(spot: Vector3, clearance: float) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = clearance
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), spot + Vector3(0, 0.5, 0))
	query.collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_FENCE
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


# --- Respawns / reinforcements -------------------------------------------------------------

func _respawn(step: float) -> void:
	if _active or _state == State.FIGHT or reinforce_interval > 0.0 \
			or Time.get_ticks_msec() - _last_fight_ms < calm_before_respawn * 1000.0:
		return
	for i in size:
		if _members[i] == null and _respawn_timers[i] > 0.0:
			_respawn_timers[i] -= step
			if _respawn_timers[i] <= 0.0 and _is_open(_slot_point(i), 0.45):
				_spawn(i, _slot_point(i))
				return  # one at a time


## Event bands pick up 2 more on the way every `reinforce_interval` seconds.
func _reinforce(step: float) -> void:
	if reinforce_interval <= 0.0:
		return
	_reinforce_timer -= step
	if _reinforce_timer > 0.0:
		return
	_reinforce_timer = reinforce_interval
	for i in 2:
		if members().size() >= reinforce_max:
			return
		var angle := randf() * TAU
		var spot := GameConfig.clamp_to_world(global_position + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(2.5, 4.0))
		var data := {"scene": roster.filler.resource_path, "strength": strength(), "coins": 1.5}
		var enemy := NetSpawn.unit(&"enemy", spot, data) as Enemy
		if enemy:
			adopt(enemy)


# --- Activity ---------------------------------------------------------------------------

## Downed players still count (only `is_dead` doesn't), or their enemies would freeze mid-fight.
func _is_player_near() -> bool:
	if quarry != null or reinforce_interval > 0.0:
		return true  # event bands always run
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if is_instance_valid(player) and not player.is_dead and _flat(global_position, player.global_position) < activation_range:
			return true
	return false


func _nearest_player() -> Node3D:
	var best: Node3D = null
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if GameConfig.is_gone(player):
			continue
		if best == null or _flat(global_position, player.global_position) < _flat(global_position, best.global_position):
			best = player
	return best


## Pauses members while players are far away, except those chasing someone or walking back.
func _set_active(active: bool) -> void:
	_active = active
	for enemy in _members + _extra:
		if is_instance_valid(enemy) and not enemy.is_dead:
			_apply_run_state(enemy, active or enemy.is_busy())


## Running members think and are targetable ("active_enemies"); paused ones cost nothing.
func _apply_run_state(enemy: Enemy, run: bool) -> void:
	enemy.process_mode = Node.PROCESS_MODE_INHERIT if run else Node.PROCESS_MODE_DISABLED
	if run and not enemy.is_downed:
		enemy.add_to_group(&"active_enemies")
	else:
		enemy.remove_from_group(&"active_enemies")


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Replication ---------------------------------------------------------------------------

@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(at: Vector3, new_alive: int) -> void:
	global_position = at
	alive = new_alive


@rpc("authority", "call_local", "reliable")
func _net_defeated(by_peer: int) -> void:
	is_dead = true
	alive = 0
	_last_hit_peer = by_peer
	defeated.emit(self)

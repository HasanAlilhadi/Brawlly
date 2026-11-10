class_name BattleBrain
extends Node
## The commanders' mind (server only; main.gd makes one): **it thinks, the units carry out**. Every `CYCLE_FRAMES`
## physics frames it takes a snapshot of every unit awake on the battlefield (heroes, soldiers, monsters of awake
## bands), hands it to a worker thread (`BrainJob`) and, when the thread is done, gives every soldier and monster its
## orders as instance ids on the unit (`Unit.brain_*`): the foe to go for, a second choice for shooters, the nearest
## foe, a healer's patient. One pass for a whole army (so its soldiers spread over the foes) instead of every unit
## scanning the battlefield for itself on the main thread — that scan was a third of a big fight's frame.
##
## Units only **check** an order against what they are doing right now (still alive, hostile, in reach) and carry it
## out; what they still do themselves is small and local: walk to the gate of a walled place they are sent at, step
## around what stands in the way (three tries, `Unit.STEER_TRIES`), a line-of-fire ray for the pick.
##
## **Census**: the last finished snapshot also answers "who stands near this point" (`factions_near`,
## `monsters_near`, `friends_near`, `nearest_foe_of`) from its grid — places (who is in the ring), gates (is one of
## ours at it) and animals (who scares them) ask it instead of each walking over every unit in the world. It is up
## to a cycle old (`has_census()`: none yet, or stale → they fall back to looking for themselves).
##
## Orders that can't wait a cycle don't go through here: a hit provokes a monster at once (`Enemy.provoke`), a band
## alerts its members (`Warband.alert`), the hero's KILL order names the target itself.

## A new snapshot this often (physics frames, game time): ~6 a second.
const CYCLE_FRAMES: int = 10
## The thread gets this many frames; then the main thread waits for it (it is all but done by then — this keeps the
## orders' age bounded, and the same in tests that run faster than real time).
const WAIT_FRAMES: int = 4
## Shooters and healers are told about the nearest foe this much beyond Ally.ARCHER_KEEP_AWAY (it may come closer
## before the next cycle).
const NEAR_SLACK: float = 2.0
## Picks reach this much beyond what was asked (the unit checks the real distance when it uses one).
const REACH_SLACK: float = 1.0

## The one in the running match (null in menus and on clients).
static var current: BattleBrain

## Off: no new orders (the dev panel's switch; units then stand by their last ones).
var enabled: bool = true
## Finished cycles.
var cycle: int = 0
## The last finished cycle: rows in the snapshot, how many of them took orders, the thread's time and the main
## thread's share (snapshot + handing the orders out), in ms.
var last_rows: int = 0
var last_asking: int = 0
var last_thread_ms: float = 0.0
var last_main_ms: float = 0.0

var _job: BrainJob
## The last finished job: the census (the thread is done with it).
var _census: BrainJob
var _census_frame: int = 0
var _task: int = -1
var _started_frame: int = 0
var _next_frame: int = 0
var _snapshot_ms: float = 0.0
## Units that think but are in none of the snapshot's groups (see `include()`), for the next snapshot.
var _extras: Array[Unit] = []


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)  # never leave a task running on a freed job
		_task = -1
	if current == self:
		current = null


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	var frame := Engine.get_physics_frames()
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task) and frame - _started_frame < WAIT_FRAMES:
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_hand_out()
	if enabled and frame >= _next_frame:
		_next_frame = frame + CYCLE_FRAMES
		_start(frame)


## A unit that thinks without being in `player_units` / `active_enemies` (a monster nothing woke the usual way):
## it gets orders from the next cycle on.
func include(unit: Unit) -> void:
	if not _extras.has(unit):
		_extras.append(unit)


# --- Census --------------------------------------------------------------------------------------------------------

## A snapshot at most CENSUS_MAX_AGE frames old is there to ask.
const CENSUS_MAX_AGE: int = 45

func has_census() -> bool:
	return _census != null and Engine.get_physics_frames() - _census_frame <= CENSUS_MAX_AGE


## Heroes, soldiers and siege engines (no pack animals) standing within `radius` of `point`: {faction: count}.
func factions_near(point: Vector3, radius: float) -> Dictionary:
	return _census.teams_within(point.x, point.z, radius, BrainJob.FRIENDLY, BrainJob.PACK)


## Whether an awake monster stands within `radius` of `point`.
func monsters_near(point: Vector3, radius: float) -> bool:
	return _census.any_within(point.x, point.z, radius, BrainJob.ENEMY)


## Whether a hero / soldier / engine / caravan of `team` (BrainJob.ANY_TEAM: of any faction) is within `radius`.
func friends_near(point: Vector3, radius: float, team: int = BrainJob.ANY_TEAM) -> bool:
	return _census.any_within(point.x, point.z, radius, BrainJob.FRIENDLY, team)


## The nearest hero / soldier / engine hostile to `team` within `radius` of `point` (null: none).
func nearest_foe_of(team: int, point: Vector3, radius: float) -> Node3D:
	var row := _census.nearest_foe(point.x, point.z, radius, team, BrainJob.FRIENDLY)
	var found := instance_from_id(_census.ids[row]) as Node3D if row >= 0 else null
	return null if GameConfig.is_gone(found) else found


## Tests: one whole cycle right now (snapshot, think, orders), on the main thread.
func think_now() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	_job = _snapshot()
	_job.run()
	_hand_out()


func _start(frame: int) -> void:
	_job = _snapshot()
	_started_frame = frame
	_task = WorkerThreadPool.add_task(_job.run, false, "BattleBrain")


## Every unit awake on the battlefield as plain numbers (main thread).
func _snapshot() -> BrainJob:
	var started := Time.get_ticks_usec()
	var job := BrainJob.new()
	job.crowd_penalty = Ally.CROWD_PENALTY
	job.defend_bonus = Ally.DEFEND_BONUS
	job.guard_bonus = Ally.GUARD_BONUS
	job.blocked_penalty = Ally.BLOCKED_PENALTY
	job.heal_sight = Ally.HEAL_SIGHT
	job.orc_team = GameConfig.ORC_TEAM
	job.animal_team = GameConfig.ANIMAL_TEAM
	var tree := get_tree()
	for node in tree.get_nodes_in_group(&"player_units"):
		_add(job, node as Unit, BrainJob.FRIENDLY)
	for node in tree.get_nodes_in_group(&"active_enemies"):
		_add(job, node as Unit, 0)
	for unit in _extras:
		if is_instance_valid(unit) and not unit.is_in_group(&"active_enemies") and not unit.is_in_group(&"player_units"):
			_add(job, unit, 0)
	_extras.clear()
	_snapshot_ms = (Time.get_ticks_usec() - started) / 1000.0
	return job


func _add(job: BrainJob, unit: Unit, kind: int) -> void:
	if unit == null or unit.is_dead:
		return
	var at := unit.global_position
	var hurt := 1.0 - unit.health / unit.max_health if unit.max_health > 0.0 else 0.0
	if unit is Ally:
		var ally := unit as Ally
		kind |= BrainJob.ALLY | BrainJob.ASKS
		var close := 0.0
		if ally.is_ranged():
			kind |= BrainJob.RANGED
			close = Ally.ARCHER_KEEP_AWAY + NEAR_SLACK
		if ally.is_healer():
			kind |= BrainJob.HEALER
		job.add(unit.get_instance_id(), at, unit.team_id, kind, hurt, unit.owner_peer, _id_of(ally.target),
				ally.scan_origin, ally.scan_range + REACH_SLACK, ally.scan_own + REACH_SLACK if ally.scan_own > 0.0 else 0.0,
				close)
	elif unit is Enemy:
		var enemy := unit as Enemy
		if enemy.is_downed:
			return  # a collapsed skeleton: nobody goes for it, it wants nothing
		kind |= BrainJob.ENEMY | BrainJob.ASKS
		if enemy.prefers_weak:
			kind |= BrainJob.WEAK
		if enemy.wave_enemy:
			kind |= BrainJob.WAVE
		job.add(unit.get_instance_id(), at, unit.team_id, kind, hurt, 0, _id_of(enemy.target), Vector3.INF,
				enemy.aggro_range + REACH_SLACK, 0.0, enemy.spot_range() + REACH_SLACK)
	elif unit is Player:
		if (unit as Player).is_downed:
			return
		job.add(unit.get_instance_id(), at, unit.team_id, kind | BrainJob.HERO, hurt, unit.owner_peer, 0)
	else:
		# Caravans, siege engines, angry animals: there to be picked (and for whom they are after).
		if unit.is_in_group(&"caravans"):
			kind |= BrainJob.PACK
		job.add(unit.get_instance_id(), at, unit.team_id, kind, hurt, unit.owner_peer, _id_of(unit.get("target")))


static func _id_of(node: Variant) -> int:
	# (validity first: `is` on a freed instance is an error)
	return (node as Object).get_instance_id() if typeof(node) == TYPE_OBJECT and is_instance_valid(node) else 0


## The finished job's picks → orders on the units (main thread).
func _hand_out() -> void:
	var started := Time.get_ticks_usec()
	var job := _job
	_job = null
	_census = job
	_census_frame = Engine.get_physics_frames()
	var asking := 0
	for i in job.ids.size():
		if not job.flags[i] & BrainJob.ASKS:
			continue
		var unit := instance_from_id(job.ids[i]) as Unit
		if unit == null:
			continue  # gone since the snapshot
		asking += 1
		unit.brain_best = job.ids[job.best[i]] if job.best[i] >= 0 else 0
		unit.brain_alt = job.ids[job.alt[i]] if job.alt[i] >= 0 else 0
		unit.brain_near = job.ids[job.near[i]] if job.near[i] >= 0 else 0
		unit.brain_patient = job.ids[job.patient[i]] if job.patient[i] >= 0 else 0
		unit.brain_cycle = cycle
	cycle += 1
	last_rows = job.ids.size()
	last_asking = asking
	last_thread_ms = job.took_ms
	last_main_ms = _snapshot_ms + (Time.get_ticks_usec() - started) / 1000.0

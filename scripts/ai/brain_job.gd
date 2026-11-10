class_name BrainJob
extends RefCounted
## One BattleBrain cycle, worked out on a WorkerThreadPool thread: plain numbers in (a snapshot of every unit awake on
## the battlefield), picks out (rows of that snapshot). **It never touches a node, the scene tree or the physics
## space** — that is what makes it safe off the main thread. BattleBrain fills the arrays (`add`), starts `run()`
## and reads the answers once the task is done.
## Units are bucketed in a grid per team, so a pick only looks at the other sides' units near it. The finished job
## also answers "who stands near this point" for the main thread (`teams_within` / `any_within` / `nearest_foe`:
## BattleBrain's census, for places, gates and animals).

# Row flags.
const HERO: int = 1  ## a hero
const ALLY: int = 2  ## a soldier
const ENEMY: int = 4  ## a monster
const FRIENDLY: int = 8  ## hero / soldier / caravan / siege engine: what monsters go after
const RANGED: int = 16  ## soldier: shoots or heals from the back rows
const HEALER: int = 32  ## soldier: heals, never fights
const WEAK: int = 64  ## monster: goes for the most wounded
const WAVE: int = 128  ## monster: hunts the nearest hero, however far
const ASKS: int = 256  ## wants answers (soldiers, monsters)
const PACK: int = 512  ## a caravan: fights nobody, takes and holds no place

## `any_within`: every team.
const ANY_TEAM: int = -1000

## Grid cell (m).
const CELL: float = 6.0
const SPAN: int = 8192  # cells per axis in a key (far more than any map)
const HALF: int = 4096

# --- In: one row per unit -------------------------------------------------------------------------------------
var ids: PackedInt64Array = []
var x: PackedFloat32Array = []
var z: PackedFloat32Array = []
var team: PackedInt32Array = []
var flags: PackedInt32Array = []
## 0 whole .. 1 nearly dead.
var hurt: PackedFloat32Array = []
## The peer that controls it (heroes, soldiers), 0 = nobody.
var owner: PackedInt32Array = []
## Instance id of what it is after (0 = nothing).
var target_id: PackedInt64Array = []
# What it asks for (rows with ASKS): foes within `reach` of (ox, oz), else within `own_reach` of itself; the nearest
# foe within `near_reach` of itself.
var ox: PackedFloat32Array = []
var oz: PackedFloat32Array = []
var reach: PackedFloat32Array = []
var own_reach: PackedFloat32Array = []
var near_reach: PackedFloat32Array = []
# The soldiers' rules (Ally's constants, copied in so the thread reads no other script).
var crowd_penalty: float = 1.6
var defend_bonus: float = 4.0
var guard_bonus: float = 2.0
var blocked_penalty: float = 3.0
var heal_sight: float = 9.0
var orc_team: int = -1
var animal_team: int = -2

# --- Out: rows (-1 = none) ---------------------------------------------------------------------------------------
## The foe to go for.
var best: PackedInt32Array = []
## Soldiers that shoot: the next best (when something blocks the line to `best`).
var alt: PackedInt32Array = []
## The nearest foe (monsters: who they spot; shooters and healers: who to step back from).
var near: PackedInt32Array = []
## Healers: the most wounded friend in sight.
var patient: PackedInt32Array = []
## How long `run()` took (ms).
var took_ms: float = 0.0

var _target: PackedInt32Array = []
## team -> {cell key -> [rows]}.
var _grids: Dictionary = {}
## team -> [the grids of the teams hostile to it].
var _foe_grids: Dictionary = {}
var _hero_of: Dictionary = {}
var _heroes: PackedInt32Array = []
## army (peer) × 100000 + foe row -> melee soldiers of that army on it.
var _crowd: Dictionary = {}


func add(id: int, at: Vector3, unit_team: int, unit_flags: int, hurt_share: float, peer: int, after: int,
		origin: Vector3 = Vector3.INF, max_reach: float = 0.0, self_reach: float = 0.0, close_reach: float = 0.0) -> void:
	ids.append(id)
	x.append(at.x)
	z.append(at.z)
	team.append(unit_team)
	flags.append(unit_flags)
	hurt.append(hurt_share)
	owner.append(peer)
	target_id.append(after)
	ox.append(at.x if origin == Vector3.INF else origin.x)
	oz.append(at.z if origin == Vector3.INF else origin.z)
	reach.append(max_reach)
	own_reach.append(self_reach)
	near_reach.append(close_reach)


func run() -> void:
	var started := Time.get_ticks_usec()
	var n := ids.size()
	best.resize(n)
	best.fill(-1)
	alt.resize(n)
	alt.fill(-1)
	near.resize(n)
	near.fill(-1)
	patient.resize(n)
	patient.fill(-1)
	_target.resize(n)
	_grids = {}
	_foe_grids = {}
	_hero_of = {}
	_heroes = PackedInt32Array()
	_crowd = {}
	var row_of := {}
	for i in n:
		row_of[ids[i]] = i
	for i in n:
		_target[i] = row_of.get(target_id[i], -1)
		if flags[i] & HERO:
			_hero_of[owner[i]] = i
			_heroes.append(i)
		var grid: Variant = _grids.get(team[i])
		if grid == null:
			grid = {}
			_grids[team[i]] = grid
		var key := (int(floor(x[i] / CELL)) + HALF) * SPAN + int(floor(z[i] / CELL)) + HALF
		var cell: Variant = (grid as Dictionary).get(key)
		if cell == null:
			(grid as Dictionary)[key] = [i]
		else:
			(cell as Array).append(i)
	for mine: int in _grids:
		var foes: Array = []
		for other: int in _grids:
			if other != mine and not ((mine == orc_team and other == animal_team) or (mine == animal_team and other == orc_team)):
				foes.append(_grids[other])  # (orcs and animals ignore each other)
		_foe_grids[mine] = foes
	# How many melee soldiers of each army are on each foe (they spread over the foes).
	for i in n:
		if flags[i] & ALLY and not flags[i] & (RANGED | HEALER) and _target[i] >= 0:
			var key := owner[i] * 100000 + _target[i]
			_crowd[key] = int(_crowd.get(key, 0)) + 1
	for i in n:
		var kind := flags[i]
		if not kind & ASKS:
			continue
		if kind & ENEMY:
			_monster(i)
		else:
			_soldier(i)
	took_ms = (Time.get_ticks_usec() - started) / 1000.0


## A monster: the nearest hero / soldier within `near_reach` (who it spots, who it takes on next), and for those that
## prefer the weak the most wounded within `reach`. Wave monsters: the nearest hero anywhere.
func _monster(i: int) -> void:
	var xs := x
	var zs := z
	var px := xs[i]
	var pz := zs[i]
	if flags[i] & WAVE:
		var mine := team[i]
		var closest := INF
		for j in _heroes:
			if team[j] == mine:
				continue
			var d := (xs[j] - px) * (xs[j] - px) + (zs[j] - pz) * (zs[j] - pz)
			if d < closest:
				closest = d
				near[i] = j
		return
	var weak := flags[i] & WEAK != 0
	var radius := maxf(near_reach[i], reach[i])
	var near_sq := near_reach[i] * near_reach[i]
	var reach_sq := reach[i] * reach[i]
	var best_score := INF
	var found := -1
	var weakest := -1
	var x0 := int(floor((px - radius) / CELL)) + HALF
	var x1 := int(floor((px + radius) / CELL)) + HALF
	var z0 := int(floor((pz - radius) / CELL)) + HALF
	var z1 := int(floor((pz + radius) / CELL)) + HALF
	for grid: Dictionary in _foe_grids[team[i]]:
		for cx in range(x0, x1 + 1):
			for cz in range(z0, z1 + 1):
				var cell: Variant = grid.get(cx * SPAN + cz)
				if cell == null:
					continue
				for j: int in cell:
					var dx := xs[j] - px
					var dz := zs[j] - pz
					var d := dx * dx + dz * dz
					if d < near_sq and flags[j] & FRIENDLY:
						near_sq = d
						found = j
					if weak and d <= reach_sq and flags[j] & FRIENDLY:
						var score := 1.0 - hurt[j] + sqrt(d) * 0.03
						if score < best_score:
							best_score = score
							weakest = j
	near[i] = found
	best[i] = weakest


## A soldier. Fighters: the foe to go for around the point it asked about (else around itself). Shooters and
## healers: the nearest foe (to step back from). Healers: the patient — the most wounded friend in sight, its hero
## first.
func _soldier(i: int) -> void:
	var kind := flags[i]
	if not kind & HEALER and reach[i] > 0.0:
		_pick(i, ox[i], oz[i], reach[i])
		if best[i] < 0 and own_reach[i] > 0.0:
			_pick(i, x[i], z[i], own_reach[i])
		if best[i] >= 0 and not kind & RANGED and _target[i] < 0:
			var key := owner[i] * 100000 + best[i]  # it will take it: the next soldiers count it in
			_crowd[key] = int(_crowd.get(key, 0)) + 1
	var xs := x
	var zs := z
	var px := xs[i]
	var pz := zs[i]
	if near_reach[i] > 0.0:
		var radius := near_reach[i]
		var near_sq := radius * radius
		var found := -1
		var x0 := int(floor((px - radius) / CELL)) + HALF
		var x1 := int(floor((px + radius) / CELL)) + HALF
		var z0 := int(floor((pz - radius) / CELL)) + HALF
		var z1 := int(floor((pz + radius) / CELL)) + HALF
		for grid: Dictionary in _foe_grids[team[i]]:
			for cx in range(x0, x1 + 1):
				for cz in range(z0, z1 + 1):
					var cell: Variant = grid.get(cx * SPAN + cz)
					if cell == null:
						continue
					for j: int in cell:
						var dx := xs[j] - px
						var dz := zs[j] - pz
						var d := dx * dx + dz * dz
						if d < near_sq:
							near_sq = d
							found = j
		near[i] = found
	if kind & HEALER:
		var sight_sq := heal_sight * heal_sight
		var leader: int = _hero_of.get(owner[i], -1)
		var best_share := 0.97
		var found := -1
		var friends: Dictionary = _grids[team[i]]
		for cx in range(int(floor((px - heal_sight) / CELL)) + HALF, int(floor((px + heal_sight) / CELL)) + HALF + 1):
			for cz in range(int(floor((pz - heal_sight) / CELL)) + HALF, int(floor((pz + heal_sight) / CELL)) + HALF + 1):
				var cell: Variant = friends.get(cx * SPAN + cz)
				if cell == null:
					continue
				for j: int in cell:
					var dx := xs[j] - px
					var dz := zs[j] - pz
					if dx * dx + dz * dz > sight_sq or not flags[j] & FRIENDLY:
						continue
					var share := 1.0 - hurt[j] - (0.1 if j == leader else 0.0)  # the hero first
					if share < best_share:
						best_share = share
						found = j
		patient[i] = found


## The foe for soldier `i` within `radius` of (cx, cz): the closest to that point, but one hitting its hero counts
## `defend_bonus` m closer (hitting a soldier of its army: `guard_bonus`), the one it is already on 1 m closer;
## melee soldiers add `crowd_penalty` per comrade already on it, shooters prefer the wounded and get a second
## choice (`alt`) when it is nearly as good.
func _pick(i: int, px: float, pz: float, radius: float) -> void:
	var xs := x
	var zs := z
	var ranged := flags[i] & RANGED != 0
	var mine := _target[i]
	var army := owner[i]
	var crowd_base := army * 100000
	var leader: int = _hero_of.get(army, -1)
	var radius_sq := radius * radius
	var best_score := INF
	var alt_score := INF
	var first := -1
	var second := -1
	var x0 := int(floor((px - radius) / CELL)) + HALF
	var x1 := int(floor((px + radius) / CELL)) + HALF
	var z0 := int(floor((pz - radius) / CELL)) + HALF
	var z1 := int(floor((pz + radius) / CELL)) + HALF
	for grid: Dictionary in _foe_grids[team[i]]:
		for cx in range(x0, x1 + 1):
			for cz in range(z0, z1 + 1):
				var cell: Variant = grid.get(cx * SPAN + cz)
				if cell == null:
					continue
				for j: int in cell:
					var dx := xs[j] - px
					var dz := zs[j] - pz
					var d := dx * dx + dz * dz
					if d > radius_sq:
						continue
					var score := sqrt(d)
					var victim := _target[j]
					if victim >= 0:
						if victim == leader:
							score -= defend_bonus
						elif flags[victim] & ALLY and owner[victim] == army:
							score -= guard_bonus
					if j == mine:
						score -= 1.0  # no flip-flopping between two close ones
					if ranged:
						score -= 2.0 * hurt[j]
					elif score < best_score:  # (the crowd only makes it worse: no need to look it up otherwise)
						score += crowd_penalty * maxi(int(_crowd.get(crowd_base + j, 0)) - (1 if j == mine else 0), 0)
					if score < best_score:
						alt_score = best_score
						second = first
						best_score = score
						first = j
					elif score < alt_score:
						alt_score = score
						second = j
	best[i] = first
	alt[i] = second if ranged and alt_score <= best_score + blocked_penalty else -1


# --- Census: questions from the main thread, once `run()` is done -------------------------------------------------

## The cells of `grid` that a square of cells holds (walking whichever is smaller: the square or the grid).
func _cells_in(grid: Dictionary, x0: int, x1: int, z0: int, z1: int) -> Array:
	var cells: Array = []
	if grid.size() <= (x1 - x0 + 1) * (z1 - z0 + 1):
		for key: int in grid:
			@warning_ignore("integer_division")
			var cx := key / SPAN
			var cz := key % SPAN
			if cx >= x0 and cx <= x1 and cz >= z0 and cz <= z1:
				cells.append(grid[key])
	else:
		for cx in range(x0, x1 + 1):
			for cz in range(z0, z1 + 1):
				var cell: Variant = grid.get(cx * SPAN + cz)
				if cell != null:
					cells.append(cell)
	return cells


## Units with all the `need` flags and none of `skip` standing within `radius` of (px, pz), per faction:
## {team (>= 0): count}.
func teams_within(px: float, pz: float, radius: float, need: int, skip: int = 0) -> Dictionary:
	var found := {}
	var radius_sq := radius * radius
	var x0 := int(floor((px - radius) / CELL)) + HALF
	var x1 := int(floor((px + radius) / CELL)) + HALF
	var z0 := int(floor((pz - radius) / CELL)) + HALF
	var z1 := int(floor((pz + radius) / CELL)) + HALF
	for side: int in _grids:
		if side < 0:
			continue
		var count := 0
		for cell: Array in _cells_in(_grids[side], x0, x1, z0, z1):
			for j: int in cell:
				var dx := x[j] - px
				var dz := z[j] - pz
				if dx * dx + dz * dz < radius_sq and flags[j] & need == need and not flags[j] & skip:
					count += 1
		if count > 0:
			found[side] = count
	return found


## Whether a unit of `only_team` (ANY_TEAM: any) with all the `need` flags stands within `radius` of (px, pz).
func any_within(px: float, pz: float, radius: float, need: int, only_team: int = ANY_TEAM) -> bool:
	var radius_sq := radius * radius
	var x0 := int(floor((px - radius) / CELL)) + HALF
	var x1 := int(floor((px + radius) / CELL)) + HALF
	var z0 := int(floor((pz - radius) / CELL)) + HALF
	var z1 := int(floor((pz + radius) / CELL)) + HALF
	for side: int in _grids:
		if only_team != ANY_TEAM and side != only_team:
			continue
		for cell: Array in _cells_in(_grids[side], x0, x1, z0, z1):
			for j: int in cell:
				var dx := x[j] - px
				var dz := z[j] - pz
				if dx * dx + dz * dz < radius_sq and flags[j] & need == need:
					return true
	return false


## The nearest unit hostile to `for_team` with all the `need` flags within `radius` of (px, pz): its row, -1 = none.
func nearest_foe(px: float, pz: float, radius: float, for_team: int, need: int) -> int:
	var closest := radius * radius
	var found := -1
	var x0 := int(floor((px - radius) / CELL)) + HALF
	var x1 := int(floor((px + radius) / CELL)) + HALF
	var z0 := int(floor((pz - radius) / CELL)) + HALF
	var z1 := int(floor((pz + radius) / CELL)) + HALF
	for side: int in _grids:
		if side == for_team or (side == orc_team and for_team == animal_team) or (side == animal_team and for_team == orc_team):
			continue
		for cell: Array in _cells_in(_grids[side], x0, x1, z0, z1):
			for j: int in cell:
				var dx := x[j] - px
				var dz := z[j] - pz
				var d := dx * dx + dz * dz
				if d < closest and flags[j] & need == need:
					closest = d
					found = j
	return found

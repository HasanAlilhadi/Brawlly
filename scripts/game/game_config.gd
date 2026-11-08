class_name GameConfig
## Game-wide constants and per-match settings: world size, physics layers, teams, difficulty.

## The playable world is a square from -world_half to +world_half on X and Z.
## Set by main.gd (from the match settings) before the world is built.
static var world_half: float = 80.0
## Army size every player starts with (soldiers following + in training).
## The "Command" upgrade (Army tab) raises Player.follower_cap by 5 per level (4 levels), up to 50.
const BASE_FOLLOWER_CAP: int = 30
## Seconds a recruited soldier trains before it joins its player.
const SOLDIER_TRAIN_TIME: float = 5.0

## Orcs are their own team, hostile to everyone.
const ORC_TEAM: int = -1
## Wild animals (Animal): fair game for heroes and soldiers, but orcs and animals leave each other alone.
const ANIMAL_TEAM: int = -2

# Physics layer bits (Project Settings → Layer Names mirror these).
const LAYER_WORLD: int = 1      # ground props, trees, camps, chests
const LAYER_PLAYER: int = 2
const LAYER_ENEMIES: int = 4
const LAYER_ALLIES: int = 8
## Walls that block everyone (every unit's mask includes it; nothing in the world uses it at the moment).
const LAYER_FENCE: int = 16
const LAYER_UNITS: int = LAYER_PLAYER | LAYER_ENEMIES | LAYER_ALLIES
## Conquest gates: one layer per holder (factions 0..3, then the demons), so a standing gate is solid for every side
## but its own — the holder's units walk through it, everyone else must break it (TerritoryGate). Units' masks get
## every gate layer but their own team's (`hostile_gates`), melee and arrows hit every gate layer.
const GATE_LAYER_FIRST: int = 256  # layer 9
const GATE_DEMONS: int = 4096  # layer 13
const ALL_GATES: int = 256 | 512 | 1024 | 2048 | 4096


## The gate layer of `team`'s gates (factions 0..3; the demons / any other: GATE_DEMONS).
static func gate_layer(team: int) -> int:
	return GATE_LAYER_FIRST << team if team >= 0 and team < 4 else GATE_DEMONS


## Every gate layer but `team`'s own.
static func hostile_gates(team: int) -> int:
	return ALL_GATES & ~gate_layer(team)
## Shots fly at 0.55 m (arrows) to 0.7 m (spears): anything hittable needs a collision shape from the
## ground up to at least this height, or arrows and spears pass over it (melee hits by distance).
const HIT_HEIGHT: float = 1.0

## Difficulty (set per match): orc health/damage multiplier and respawn-delay multiplier.
static var orc_strength: float = 1.0
static var orc_respawn_scale: float = 1.0
## Blood Moon event (WorldEvents): every enemy is faster and hits harder, and drops double loot.
static var blood_moon: bool = false
## The host's physics tick is running long (a big fight): units that fight think every other frame until it
## calms down (`update_load`, called by main every physics frame; Enemy / Ally `_physics_step_frames`).
static var overloaded: bool = false
## Physics tick time (ms, smoothed) above which it counts as overloaded, and below which it stops.
const LOAD_HIGH_MS: float = 11.0
const LOAD_LOW_MS: float = 7.0
static var _load_ms: float = 0.0


## Server: one more physics tick took `tick_ms` (Performance.TIME_PHYSICS_PROCESS).
static func update_load(tick_ms: float) -> void:
	_load_ms = lerpf(_load_ms, tick_ms, 0.1)
	if overloaded and _load_ms < LOAD_LOW_MS:
		overloaded = false
	elif not overloaded and _load_ms > LOAD_HIGH_MS:
		overloaded = true
## Where world events reach (GameMode.events_reach, set by main per match; empty = everywhere): the Blood Moon
## only drives enemies standing there.
static var event_area: Callable = Callable()
const BLOOD_MOON_SPEED: float = 1.2
const BLOOD_MOON_DAMAGE: float = 1.3
const BLOOD_MOON_LOOT: float = 2.0


## The Blood Moon is up and reaches `point` (see `event_area`).
static func raging_at(point: Vector3) -> bool:
	return blood_moon and (not event_area.is_valid() or event_area.call(point))
## Players at 0 health go down (teammates can revive them) instead of dying. Set by main.gd per match.
static var downed_enabled: bool = false


static func clamp_to_world(point: Vector3) -> Vector3:
	return Vector3(
		clampf(point.x, -world_half, world_half),
		point.y,
		clampf(point.z, -world_half, world_half))


## True when `node` is null, freed, dead or downed (works for units and camps): AI and aim assist
## ignore it. Untyped on purpose: a typed parameter would error when passed a freed object.
static func is_gone(node: Variant) -> bool:
	return node == null or not is_instance_valid(node) or node.get("is_dead") == true or node.get("is_downed") == true


## Whether two units/camps are on opposing teams.
static func is_hostile(a: Object, b: Object) -> bool:
	var team_a: Variant = a.get("team_id")
	var team_b: Variant = b.get("team_id")
	if team_a == null or team_b == null or team_a == team_b:
		return false
	# Orcs and animals ignore each other.
	return not ((team_a == ORC_TEAM and team_b == ANIMAL_TEAM) or (team_a == ANIMAL_TEAM and team_b == ORC_TEAM))


## The player (peer id) who controls `node`: a player, one of their soldiers, or their arrow. 0 = nobody.
static func owner_peer_of(node: Variant) -> int:
	if node == null or not is_instance_valid(node):
		return 0
	var peer: Variant = node.get("owner_peer")
	return peer if peer is int else 0

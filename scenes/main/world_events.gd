class_name WorldEvents
extends Node
## Timed world events that pull players together (server), each switched on / off in the lobby (setting
## `events` = the ids in EVENTS that are on):
## - treasure goblin; the Orc Warlord's warband (marches on a player, grows on the way); invasion waves from the
##   map edges (WorldBuilder.wave_entry_points);
## - meteor shower: burning rocks fall around the heroes (a red ring first), hurting everyone they land on;
##   some leave a star shard (coins + XP);
## - thunderstorm: rain and darkness (Weather), lightning strikes around the heroes;
## - Blood Moon: night falls, every enemy rages (GameConfig.blood_moon: faster, harder hits) but drops double loot;
## - supply drop: a Legendary chest parachutes in (by the hill in King of the Hill), tracked on the minimap.
## Visuals go to every peer by RPC (`_net_*`); damage and loot only on the server. Off with the lobby's "World events" setting.
## Created by main.gd (same name on every peer); announcements go through GameMode.

## Every event: [id, name, one-line description, Game Icon Pack glyph]. The lobby shows one checkbox each;
## the setting `events` lists the ids that are on.
const EVENTS: Array = [
	["goblin", "Treasure goblin", "A goblin full of coins runs from you", "star_coin"],
	["warlord", "Orc Warlord", "A boss marches on a player with its warband", "boss"],
	["waves", "Invasion waves", "Raiders storm in from the map edges", "flag"],
	["meteors", "Meteor shower", "Burning rocks fall — dodge the red rings, grab the star shards", "target"],
	["storm", "Thunderstorm", "Rain, darkness and lightning strikes", "exclamation"],
	["blood_moon", "Blood Moon", "Night falls: monsters rage, but drop double loot", "skull"],
	["supply_drop", "Supply drop", "A Legendary crate parachutes in — race for it", "shop"],
]
const GOBLIN_SCENE := "res://scenes/characters/treasure_goblin.tscn"
const WARLORD_SCENE := preload("res://scenes/characters/enemies/orc_warlord.tscn")
const ORC_ROSTER := preload("res://resources/data/orc_warband.tres")
const ENEMIES := "res://scenes/characters/enemies/"
## Wave raiders by the wave they first appear in (each wave adds the next row, later rows in smaller numbers).
const WAVE_TYPES: Array = [
	["orc_grunt", "skeleton_warrior"],
	["orc_thrower", "zombie"],
	["skeleton_archer", "ghost"],
	["orc_brute", "vampire"],
	["necromancer"],
]
const GOLD := Color(1.0, 0.8, 0.2)
const WARLORD_COLOR := Color(0.55, 0.08, 0.08)
const WAVE_COLOR := Color(1.0, 0.2, 0.12)
const WAVE_MAX_ENEMIES: int = 50
const CHEST_SCENE := preload("res://scenes/world/chest.tscn")
const METEOR_COLOR := Color(1.0, 0.45, 0.1, 0.65)
const LIGHTNING_COLOR := Color(0.6, 0.8, 1.0, 0.6)
const SUPPLY_ICON := preload("res://assets/ui/icons/game/shop.svg")

## Seconds until the first event, then between events (random in the range).
@export var first_goblin: Vector2 = Vector2(60, 90)
@export var goblin_every: Vector2 = Vector2(150, 220)
@export var first_warlord: Vector2 = Vector2(240, 300)
@export var warlord_every: Vector2 = Vector2(420, 540)
@export var first_wave: Vector2 = Vector2(105, 135)
## Rest after a wave has been defeated. The next wave never starts while raiders remain alive.
@export var wave_every: Vector2 = Vector2(45, 65)
@export var wave_warning_time: float = 5.0
## Goblins appear this far from a player (just off-screen: the desktop view zoomed out for the bow reaches
## ~18.5 m into the top corners, see main.gd CAMERA_ZOOM); the Warlord much farther away.
@export var goblin_distance: float = 21.0
@export var warlord_distance: float = 42.0
@export_group("Meteor shower")
@export var first_meteors: Vector2 = Vector2(150, 200)
@export var meteors_every: Vector2 = Vector2(220, 300)
@export var meteor_duration: float = 18.0
## Seconds between meteors (each lands this long after its ring shows).
@export var meteor_interval: Vector2 = Vector2(0.45, 0.9)
@export var meteor_warning: float = 1.6
@export var meteor_radius: float = 3.0
@export var meteor_damage: float = 40.0
@export_range(0.0, 1.0) var shard_chance: float = 0.35
@export_group("Thunderstorm")
@export var first_storm: Vector2 = Vector2(200, 260)
@export var storm_every: Vector2 = Vector2(300, 380)
@export var storm_duration: float = 45.0
@export var lightning_interval: Vector2 = Vector2(1.5, 3.5)
@export var lightning_warning: float = 0.9
@export var lightning_radius: float = 2.2
@export var lightning_damage: float = 32.0
@export_group("Blood Moon")
@export var first_blood_moon: Vector2 = Vector2(330, 400)
@export var blood_moon_every: Vector2 = Vector2(420, 520)
@export var blood_moon_duration: float = 60.0
@export_group("Supply drop")
@export var first_supply: Vector2 = Vector2(90, 120)
@export var supply_every: Vector2 = Vector2(150, 210)
@export var supply_fall_time: float = 12.0
@export_group("")

## Ids of the events that are on (from the lobby; Last Stand: without "waves", the circles get assaults instead).
var enabled_events: PackedStringArray = PackedStringArray()
var goblin: TreasureGoblin
## The Warlord leading the event band (server).
var warlord: Enemy
var warlord_band: Warband
var wave_number: int = 0
var wave_active: bool = false
var meteors_left: float = 0.0
var storm_left: float = 0.0
var blood_moon_left: float = 0.0
## Supply crates dropped so far (deterministic chest names on every peer).
var supply_drops: int = 0
## Rain, darkness, lightning flashes, the Blood Moon's red night (every peer).
var weather: Weather

var _main: Node
var _game_mode: GameMode
var _goblin_timer: float
var _warlord_timer: float
var _wave_timer: float
var _wave_spawning: bool = false
var _meteor_timer: float
var _storm_timer: float
var _blood_moon_timer: float
var _supply_timer: float
var _strike_timer: float = 0.0


## Every event id, in lobby order (the default: all on).
static func all_ids() -> Array:
	return EVENTS.map(func(row: Array) -> String: return row[0])


## The ids that are on from the `events` setting (a list; old saves / tests may hold true / false).
static func ids_from_setting(value: Variant) -> PackedStringArray:
	if value is bool:
		return PackedStringArray(all_ids() if value else [])
	return PackedStringArray(value) if value is Array or value is PackedStringArray else PackedStringArray()


func setup(main: Node, game_mode: GameMode, events: PackedStringArray) -> void:
	name = "WorldEvents"
	_main = main
	_game_mode = game_mode
	enabled_events = events
	_goblin_timer = randf_range(first_goblin.x, first_goblin.y)
	_warlord_timer = randf_range(first_warlord.x, first_warlord.y)
	_wave_timer = randf_range(first_wave.x, first_wave.y)
	_meteor_timer = randf_range(first_meteors.x, first_meteors.y)
	_storm_timer = randf_range(first_storm.x, first_storm.y)
	_blood_moon_timer = randf_range(first_blood_moon.x, first_blood_moon.y)
	_supply_timer = randf_range(first_supply.x, first_supply.y)
	weather = Weather.new()
	weather.setup(main)
	add_child(weather)


func is_on(id: String) -> bool:
	return enabled_events.has(id)


func _process(delta: float) -> void:
	if not multiplayer.is_server() or _game_mode.is_over or not _main.get("_started"):
		return
	_run_weather(delta)
	if is_on("meteors") and meteors_left <= 0.0:
		_meteor_timer -= delta
		if _meteor_timer <= 0.0:
			start_meteor_shower()
	if is_on("storm") and storm_left <= 0.0 and blood_moon_left <= 0.0:
		_storm_timer -= delta
		if _storm_timer <= 0.0:
			start_storm()
	if is_on("blood_moon") and blood_moon_left <= 0.0 and storm_left <= 0.0:
		_blood_moon_timer -= delta
		if _blood_moon_timer <= 0.0:
			start_blood_moon()
	if is_on("supply_drop"):
		_supply_timer -= delta
		if _supply_timer <= 0.0:
			drop_supplies()
	if is_on("goblin") and not is_instance_valid(goblin):
		_goblin_timer -= delta
		if _goblin_timer <= 0.0:
			spawn_goblin()
	if is_on("warlord") and not is_instance_valid(warlord):
		_warlord_timer -= delta
		if _warlord_timer <= 0.0:
			spawn_warlord()
	if wave_active:
		if not _wave_spawning and _living_wave_enemies() == 0:
			wave_active = false
			_wave_timer = randf_range(wave_every.x, wave_every.y)
			_game_mode.announce("Wave %d defeated!" % wave_number)
	elif is_on("waves"):
		_wave_timer -= delta
		if _wave_timer <= 0.0:
			start_wave()


## Server: warns at four visible border gates, then starts the next escalating invasion.
## `warning_override` is used by automated tests; normal events use `wave_warning_time`.
func start_wave(warning_override: float = -1.0) -> bool:
	if not multiplayer.is_server() or wave_active or _game_mode.is_over:
		return false
	wave_number += 1
	wave_active = true
	_wave_spawning = true
	var entries := _wave_entries()
	var total := mini(wave_number * 10, WAVE_MAX_ENEMIES)
	var warning := wave_warning_time if warning_override < 0.0 else warning_override
	_game_mode.announce("Wave %d incoming from all sides — %d raiders!" % [wave_number, total])
	_net_wave_warning.rpc(wave_number, entries)
	get_tree().create_timer(maxf(warning, 0.01)).timeout.connect(_spawn_wave.bind(wave_number, entries))
	return true


func _spawn_wave(number: int, entries: PackedVector3Array) -> void:
	if not wave_active or number != wave_number or _game_mode.is_over:
		_wave_spawning = false
		return
	_net_wave_arrival.rpc(entries)
	var scenes := _wave_scenes(number)
	scenes.shuffle()
	var strength := GameConfig.orc_strength * minf(1.0 + (number - 1) * 0.08, 1.6)
	for i in scenes.size():
		var entry_index := i % entries.size()
		var inward := -entries[entry_index].normalized()
		var side := Vector3(-inward.z, 0.0, inward.x)
		var rank := i / entries.size()
		var lane := float(rank % 5 - 2) * 0.75
		var depth := float(rank / 5) * 0.8
		var spot := entries[entry_index] + side * lane + inward * depth
		NetSpawn.unit(&"enemy", spot, {"scene": scenes[i], "strength": strength, "coins": 0.6,
				"wave_enemy": true, "wave_number": number})
		# A short stagger makes the raiders visibly stream through the marked gates.
		if i + 1 < scenes.size():
			await get_tree().create_timer(0.06).timeout
	_wave_spawning = false
	_game_mode.announce("Wave %d has reached the battlefield!" % number)


## 10 / 20 / 30 / 40 / 50 enemies. Each wave brings in the next row of WAVE_TYPES (the newest in smaller
## numbers); later waves stay capped at 50 and gain strength only up to a safe 1.6x multiplier.
func _wave_scenes(number: int) -> Array[String]:
	var total := mini(number * 10, WAVE_MAX_ENEMIES)
	var weighted: Array[String] = []
	var rows := mini(number, WAVE_TYPES.size())
	for row in rows:
		# Older rows are common, the newest one is rare.
		var weight := 1 if row == rows - 1 and number > 1 else 3
		for type: String in WAVE_TYPES[row]:
			for i in weight:
				weighted.append(ENEMIES + type + ".tscn")
	var result: Array[String] = []
	for i in total:
		result.append(weighted[i % weighted.size()] if i < weighted.size() else weighted.pick_random())
	return result


func _wave_entries() -> PackedVector3Array:
	return WorldBuilder.wave_entry_points()


func _living_wave_enemies() -> int:
	return get_tree().get_nodes_in_group(&"wave_enemies").filter(
			func(enemy: Node) -> bool: return not GameConfig.is_gone(enemy)).size()


@rpc("authority", "call_local", "reliable")
func _net_wave_warning(number: int, entries: PackedVector3Array) -> void:
	for point in entries:
		PingMarker.spawn(_main.world, point, "Incoming!", WAVE_COLOR, "Wave %d" % number)


@rpc("authority", "call_local", "reliable")
func _net_wave_arrival(entries: PackedVector3Array) -> void:
	for point in entries:
		HitFx.burst(point + Vector3(0, 0.4, 0), HitFx.Kind.DIRT, 24)
		HitFx.flash(point + Vector3(0, 0.5, 0), HitFx.DEATH_SMOKE, Color(WAVE_COLOR, 0.8), 2.4, 0.8,
				Vector2(0.7, 1.6), false)


## Server: a treasure goblin near `near` (default: a random player).
func spawn_goblin(near: Player = null) -> TreasureGoblin:
	near = near if near else _random_player()
	if near == null:
		return null
	var spot: Vector3 = _main.free_spot_around(near.global_position, goblin_distance)
	if spot == Vector3.INF:
		return null
	var players := get_tree().get_nodes_in_group(&"players").size()
	goblin = NetSpawn.unit(&"goblin", spot, {"color": GOLD, "health_scale": 0.7 + 0.3 * players}) as TreasureGoblin
	goblin.finished.connect(_on_goblin_finished)
	_goblin_timer = randf_range(goblin_every.x, goblin_every.y)
	_game_mode.announce("A treasure goblin appeared%s! Catch it!" % (" near %s" % near.display_name if Net.is_online() else ""))
	return goblin


## Server: the Orc Warlord's warband, marching on `quarry` (default: the leading player / team, or a random
## one). The Warlord with 6 + players orcs, 2 more every 25 s on the way (up to 14), led by the Warlord.
func spawn_warlord(quarry: Player = null) -> Enemy:
	quarry = quarry if quarry else _pick_quarry()
	if quarry == null:
		return null
	var spot: Vector3 = _main.free_spot_around(quarry.global_position, warlord_distance)
	if spot == Vector3.INF:
		spot = _main.free_spot_around(quarry.global_position, warlord_distance * 0.6)
	if spot == Vector3.INF:
		return null
	var players := get_tree().get_nodes_in_group(&"players").size()
	var band := Warband.new()
	band.name = "WarlordBand_%d" % Time.get_ticks_msec()
	band.roster = ORC_ROSTER
	band.leader_scene = WARLORD_SCENE
	band.track_leader = true
	band.size = 1 + 6 + players
	band.strength_override = GameConfig.orc_strength * (0.6 + 0.4 * players)
	band.replicated = false
	band.quarry = quarry
	band.reinforce_interval = 25.0
	band.reinforce_max = 14
	band.position = spot
	_main.world.add_child(band)
	band.start()
	warlord_band = band
	warlord = band.leader
	if warlord:
		warlord.died.connect(_on_warlord_died)
	_warlord_timer = randf_range(warlord_every.x, warlord_every.y)
	var who := quarry.display_name
	if Net.is_team_mode(_game_mode.match_mode):
		who = "{team:%d}" % quarry.team_id
	_game_mode.announce("The Orc Warlord marches on %s!" % who if Net.is_online() else "The Orc Warlord is coming for you!")
	return warlord


func _on_goblin_finished(_goblin: TreasureGoblin, caught: bool, by_peer: int) -> void:
	if caught:
		_game_mode.announce("%s caught the treasure goblin!" % Net.name_of(by_peer) if by_peer != 0 else "The treasure goblin was caught!")
	else:
		_game_mode.announce("The treasure goblin got away...")


func _on_warlord_died(unit: Unit) -> void:
	var by_peer := unit.last_attacker_peer
	if by_peer != 0:
		_game_mode.announce("%s slew the Orc Warlord! Its warband is routed." % Net.name_of(by_peer))
	else:
		_game_mode.announce("The Orc Warlord has fallen!")


func _random_player() -> Player:
	var alive := get_tree().get_nodes_in_group(&"players").filter(func(p: Node) -> bool: return not GameConfig.is_gone(p))
	return alive.pick_random() if not alive.is_empty() else null


## Versus: the leader (player or a player of the leading team), so the boss helps whoever is behind.
func _pick_quarry() -> Player:
	var match_mode := _game_mode.match_mode
	if match_mode == Net.Mode.COOP or _game_mode.scores.is_empty():
		return _random_player()
	var best_key: Variant = null
	var best := -1
	for key in _game_mode.scores:
		if _game_mode.scores[key] > best:
			best = _game_mode.scores[key]
			best_key = key
	var candidates := get_tree().get_nodes_in_group(&"players").filter(func(p: Node) -> bool:
		if GameConfig.is_gone(p):
			return false
		return (p as Player).team_id == best_key)
	return candidates.pick_random() if not candidates.is_empty() else _random_player()


# --- Meteor shower ------------------------------------------------------------------------

## Server: burning rocks fall around the heroes for `duration` seconds.
func start_meteor_shower(duration: float = -1.0) -> void:
	meteors_left = meteor_duration if duration < 0.0 else duration
	_meteor_timer = randf_range(meteors_every.x, meteors_every.y)
	_strike_timer = 1.5
	_game_mode.announce("Meteor shower! Watch for the red rings!")


## Server: one meteor at `at` (default: near a random hero): a ring now, the impact `meteor_warning` s later.
func drop_meteor(at: Vector3 = Vector3.INF) -> void:
	if at == Vector3.INF:
		at = _spot_near_heroes(3.0, 14.0)
	if at == Vector3.INF:
		return
	_net_meteor_warning.rpc(at, meteor_warning)
	get_tree().create_timer(meteor_warning).timeout.connect(_meteor_impact.bind(at))


func _meteor_impact(at: Vector3) -> void:
	_hurt_everyone(at, meteor_radius, meteor_damage, 7.0)
	_net_meteor_impact.rpc(at, meteor_radius)
	if randf() < shard_chance:
		# A star shard: a handful of coins and some XP where it hit.
		Pickup.drop(_main.world, at, Pickup.Kind.COIN, randi_range(6, 12))
		Pickup.drop(_main.world, at + Vector3(0.6, 0, 0), Pickup.Kind.XP, 3)


@rpc("authority", "call_local", "reliable")
func _net_meteor_warning(at: Vector3, seconds: float) -> void:
	HitFx.ground_warning(at, meteor_radius, seconds, METEOR_COLOR)
	weather.meteor_fall(at, seconds)


@rpc("authority", "call_local", "reliable")
func _net_meteor_impact(at: Vector3, radius: float) -> void:
	weather.meteor_impact(at, radius)


# --- Thunderstorm -----------------------------------------------------------------------------

## Server: rain and darkness for `duration` seconds, lightning striking around the heroes.
func start_storm(duration: float = -1.0) -> void:
	storm_left = storm_duration if duration < 0.0 else duration
	_storm_timer = randf_range(storm_every.x, storm_every.y)
	_strike_timer = 4.0
	_net_storm.rpc(true)
	_game_mode.announce("A thunderstorm rolls in! Stay away from the bright spots.")


## Server: a lightning strike at `at` (default: near a random hero) after a short flicker on the ground.
func strike_lightning(at: Vector3 = Vector3.INF) -> void:
	if at == Vector3.INF:
		at = _spot_near_heroes(2.0, 12.0)
	if at == Vector3.INF:
		return
	_net_lightning_warning.rpc(at, lightning_warning)
	get_tree().create_timer(lightning_warning).timeout.connect(func() -> void:
		_hurt_everyone(at, lightning_radius, lightning_damage, 4.0)
		_net_lightning.rpc(at))


@rpc("authority", "call_local", "reliable")
func _net_storm(on: bool) -> void:
	weather.set_storm(on)


@rpc("authority", "call_local", "reliable")
func _net_lightning_warning(at: Vector3, seconds: float) -> void:
	HitFx.ground_warning(at, lightning_radius, seconds, LIGHTNING_COLOR)


@rpc("authority", "call_local", "reliable")
func _net_lightning(at: Vector3) -> void:
	weather.lightning(at)


# --- Blood Moon ---------------------------------------------------------------------------------

## Server: night falls for `duration` seconds — enemies rage (faster, harder) but drop double loot.
func start_blood_moon(duration: float = -1.0) -> void:
	blood_moon_left = blood_moon_duration if duration < 0.0 else duration
	_blood_moon_timer = randf_range(blood_moon_every.x, blood_moon_every.y)
	_net_blood_moon.rpc(true)
	_game_mode.announce("The Blood Moon rises! Monsters rage — and drop double loot.")


@rpc("authority", "call_local", "reliable")
func _net_blood_moon(on: bool) -> void:
	GameConfig.blood_moon = on
	weather.set_blood_moon(on)


func _run_weather(delta: float) -> void:
	if meteors_left > 0.0:
		meteors_left -= delta
		_strike_timer -= delta
		if _strike_timer <= 0.0:
			_strike_timer = randf_range(meteor_interval.x, meteor_interval.y)
			drop_meteor()
	if storm_left > 0.0:
		storm_left -= delta
		_strike_timer -= delta
		if _strike_timer <= 0.0 and meteors_left <= 0.0:
			_strike_timer = randf_range(lightning_interval.x, lightning_interval.y)
			strike_lightning()
		if storm_left <= 0.0:
			_net_storm.rpc(false)
			_game_mode.announce("The storm passes.")
	if blood_moon_left > 0.0:
		blood_moon_left -= delta
		if blood_moon_left <= 0.0:
			_net_blood_moon.rpc(false)
			_game_mode.announce("The sun comes back. The Blood Moon has set.")


# --- Supply drop ------------------------------------------------------------------------------------

## Server: a Legendary chest parachutes down (`fall_time` s) at `at` (default: by the hill in King of the
## Hill, else in the open near a random hero). Everyone sees where on the minimap.
func drop_supplies(at: Vector3 = Vector3.INF, fall_time: float = -1.0) -> void:
	_supply_timer = randf_range(supply_every.x, supply_every.y)
	if at == Vector3.INF:
		var hill := get_tree().get_first_node_in_group(&"hill") as Node3D
		if hill:
			at = _main.free_spot_around(hill.global_position, randf_range(10.5, 12.5))
		else:
			var hero := _random_player()
			if hero == null:
				return
			at = _main.free_spot_around(hero.global_position, randf_range(16.0, 24.0))
	if at == Vector3.INF:
		return
	supply_drops += 1
	_net_supply_drop.rpc(supply_drops, at, supply_fall_time if fall_time < 0.0 else fall_time)
	_game_mode.announce("Supply drop incoming! A Legendary crate is falling.")


@rpc("authority", "call_local", "reliable")
func _net_supply_drop(number: int, at: Vector3, fall_time: float) -> void:
	weather.supply_fall(at, fall_time, SUPPLY_ICON, GOLD)
	get_tree().create_timer(fall_time).timeout.connect(func() -> void:
		if not is_instance_valid(_main) or not _main.is_inside_tree():
			return
		# The same chest (same name) on every peer, so its own RPCs work everywhere.
		var chest := CHEST_SCENE.instantiate() as Chest
		chest.name = "SupplyDrop_%d" % number
		chest.rarity = Chest.Rarity.LEGENDARY
		chest.position = at
		chest.set_meta(&"marker_color", GOLD)
		chest.set_meta(&"marker_label", "Supply crate")
		chest.set_meta(&"marker_icon", SUPPLY_ICON)
		_main.world.add_child(chest)
		chest.add_to_group(&"tracked")
		HitFx.shockwave(at, 2.5))


# --- Shared -------------------------------------------------------------------------------------------

## A point `min_distance`..`max_distance` from a random living hero, in the world.
func _spot_near_heroes(min_distance: float, max_distance: float) -> Vector3:
	var hero := _random_player()
	if hero == null:
		return Vector3.INF
	var angle := randf() * TAU
	var spot := hero.global_position + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(min_distance, max_distance)
	return GameConfig.clamp_to_world(Vector3(spot.x, 0.0, spot.z))


## Server: nature's damage — heroes, soldiers, enemies and animals within `radius` all take it, thrown outward.
func _hurt_everyone(at: Vector3, radius: float, damage: float, push: float) -> void:
	for node in get_tree().get_nodes_in_group(&"units"):
		var unit := node as Unit
		if GameConfig.is_gone(unit):
			continue
		var away := unit.global_position - at
		away.y = 0.0
		if away.length() > radius + unit.radius:
			continue
		unit.take_damage(damage, null, false)
		if not unit.is_dead and away.length() > 0.05:
			unit.shove(away.normalized() * push)

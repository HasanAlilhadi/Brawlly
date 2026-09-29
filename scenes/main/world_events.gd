class_name WorldEvents
extends Node
## Timed world events that pull players together (server): the treasure goblin, the Orc Warlord, and
## escalating invasion waves entering from the four map borders. Off with the lobby's "World events" setting.
## Created by main.gd (same name on every peer); announcements go through GameMode.

const GOBLIN_SCENE := "res://scenes/characters/treasure_goblin.tscn"
const WARLORD_SCENE := "res://scenes/characters/warlord.tscn"
const SPEARMAN_SCENE := "res://scenes/characters/enemy.tscn"
const SWORDSMAN_SCENE := "res://scenes/characters/enemy_swordsman.tscn"
const THROWER_SCENE := "res://scenes/characters/enemy_thrower.tscn"
const GIANT_SCENE := "res://scenes/characters/enemy_giant.tscn"
const GOLD := Color(1.0, 0.8, 0.2)
const WARLORD_COLOR := Color(0.55, 0.08, 0.08)
const WAVE_COLOR := Color(1.0, 0.2, 0.12)
const WAVE_MAX_ENEMIES: int = 50

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

var enabled: bool = true
var goblin: TreasureGoblin
var warlord: Warlord
var wave_number: int = 0
var wave_active: bool = false

var _main: Node
var _game_mode: GameMode
var _goblin_timer: float
var _warlord_timer: float
var _wave_timer: float
var _wave_spawning: bool = false


func setup(main: Node, game_mode: GameMode, events_on: bool) -> void:
	name = "WorldEvents"
	_main = main
	_game_mode = game_mode
	enabled = events_on
	_goblin_timer = randf_range(first_goblin.x, first_goblin.y)
	_warlord_timer = randf_range(first_warlord.x, first_warlord.y)
	_wave_timer = randf_range(first_wave.x, first_wave.y)


func _process(delta: float) -> void:
	if not enabled or not multiplayer.is_server() or _game_mode.is_over or not _main.get("_started"):
		return
	if not is_instance_valid(goblin):
		_goblin_timer -= delta
		if _goblin_timer <= 0.0:
			spawn_goblin()
	if not is_instance_valid(warlord):
		_warlord_timer -= delta
		if _warlord_timer <= 0.0:
			spawn_warlord()
	if wave_active:
		if not _wave_spawning and _living_wave_enemies() == 0:
			wave_active = false
			_wave_timer = randf_range(wave_every.x, wave_every.y)
			_game_mode.announce("Wave %d defeated!" % wave_number)
	else:
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


## 10 / 20 / 30 / 40 / 50 enemies. New enemy classes enter as the waves advance; later waves
## stay capped at 50 and gain strength only up to a safe 1.6x multiplier.
func _wave_scenes(number: int) -> Array[String]:
	var counts: Array[int]
	match number:
		1:
			counts = [10, 0, 0, 0]
		2:
			counts = [10, 10, 0, 0]
		3:
			counts = [10, 10, 10, 0]
		4:
			counts = [16, 12, 10, 2]
		_:
			counts = [18, 15, 12, 5]
	var result: Array[String] = []
	var types: Array[String] = [SPEARMAN_SCENE, SWORDSMAN_SCENE, THROWER_SCENE, GIANT_SCENE]
	for type in types.size():
		for _enemy in counts[type]:
			result.append(types[type])
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


## Server: the Orc Warlord, marching on `quarry` (default: the leading player / team, or a random one).
func spawn_warlord(quarry: Player = null) -> Warlord:
	quarry = quarry if quarry else _pick_quarry()
	if quarry == null:
		return null
	var spot: Vector3 = _main.free_spot_around(quarry.global_position, warlord_distance)
	if spot == Vector3.INF:
		spot = _main.free_spot_around(quarry.global_position, warlord_distance * 0.6)
	if spot == Vector3.INF:
		return null
	var players := get_tree().get_nodes_in_group(&"players").size()
	var strength := GameConfig.orc_strength * (0.6 + 0.4 * players)
	warlord = NetSpawn.unit(&"enemy", spot, {"scene": WARLORD_SCENE, "strength": strength, "coins": 1.0,
			"color": WARLORD_COLOR}) as Warlord
	warlord.quarry = quarry
	warlord.band_strength = GameConfig.orc_strength
	warlord.raise_warband(warlord.warband_start + players)
	warlord.defeated.connect(_on_warlord_defeated)
	warlord.rallied.connect(func(_w: Warlord) -> void: _game_mode.announce("The Warlord roars for reinforcements!"))
	_warlord_timer = randf_range(warlord_every.x, warlord_every.y)
	var who := quarry.display_name
	if Net.is_team_mode(_game_mode.match_mode):
		who = "the %s team" % Net.TEAM_NAMES[quarry.team_id]
	_game_mode.announce("The Orc Warlord marches on %s!" % who if Net.is_online() else "The Orc Warlord is coming for you!")
	return warlord


func _on_goblin_finished(_goblin: TreasureGoblin, caught: bool, by_peer: int) -> void:
	if caught:
		_game_mode.announce("%s caught the treasure goblin!" % Net.name_of(by_peer) if by_peer != 0 else "The treasure goblin was caught!")
	else:
		_game_mode.announce("The treasure goblin got away...")


func _on_warlord_defeated(_warlord: Warlord, by_peer: int) -> void:
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
		return (p as Player).peer_id == best_key if match_mode == Net.Mode.DEATHMATCH else (p as Player).team_id == best_key)
	return candidates.pick_random() if not candidates.is_empty() else _random_player()

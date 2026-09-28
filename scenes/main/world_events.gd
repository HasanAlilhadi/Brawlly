class_name WorldEvents
extends Node
## Timed world events that pull players together (server): the treasure goblin (a golden goblin that
## runs off with coins) and the Orc Warlord (a boss marching on a player — in versus modes on the
## leader — with a growing warband). Off with the lobby's "World events" setting.
## Created by main.gd (same name on every peer); announcements go through GameMode.

const GOBLIN_SCENE := "res://scenes/characters/treasure_goblin.tscn"
const WARLORD_SCENE := "res://scenes/characters/warlord.tscn"
const GOLD := Color(1.0, 0.8, 0.2)
const WARLORD_COLOR := Color(0.55, 0.08, 0.08)

## Seconds until the first event, then between events (random in the range).
@export var first_goblin: Vector2 = Vector2(60, 90)
@export var goblin_every: Vector2 = Vector2(150, 220)
@export var first_warlord: Vector2 = Vector2(240, 300)
@export var warlord_every: Vector2 = Vector2(420, 540)
## Goblins appear this far from a player (just off-screen); the Warlord much farther away.
@export var goblin_distance: float = 15.0
@export var warlord_distance: float = 42.0

var enabled: bool = true
var goblin: TreasureGoblin
var warlord: Warlord

var _main: Node
var _game_mode: GameMode
var _goblin_timer: float
var _warlord_timer: float


func setup(main: Node, game_mode: GameMode, events_on: bool) -> void:
	name = "WorldEvents"
	_main = main
	_game_mode = game_mode
	enabled = events_on
	_goblin_timer = randf_range(first_goblin.x, first_goblin.y)
	_warlord_timer = randf_range(first_warlord.x, first_warlord.y)


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
		_game_mode.announce("%s slew the Orc Warlord! Its warband joins them." % Net.name_of(by_peer))
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

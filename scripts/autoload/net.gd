extends Node
## Networking, lobby and player profile (autoload "Net"). The game is multiplayer only.
## - An offline peer (`open_offline_lobby()`, you are the server, id 1) is only for automated tests and
##   running the match scene directly from the editor; no menu offers it.
## - Hosting opens an ENet server on the local network; joining connects by IP (or a discovered game).
## - The host owns the match settings and team assignment; clients get them via `_sync_lobby`.
## - Hosts announce themselves with a UDP broadcast so nearby players can find the game.

signal lobby_changed
signal servers_changed
signal connection_failed(reason: String)
signal left_game(reason: String)
## The host started the match: every lobby shows a countdown of `seconds`.
signal countdown_started(seconds: int)

const GAME_ID := "mygame-lan-v1"
const PORT: int = 24565
const DISCOVERY_PORT: int = 24566
const MAX_PLAYERS: int = 8
## Seconds of "3… 2… 1…" in the lobby before the match loads.
const START_COUNTDOWN: int = 3
const PROFILE_PATH := "user://profile.cfg"
const GAME_SCENE := "res://scenes/main/main.tscn"
const LOBBY_SCENE := "res://scenes/ui/lobby.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

enum Mode { COOP, DEATHMATCH, TEAM_DEATHMATCH, CAPTURE_THE_FLAG, KING_OF_THE_HILL }
enum Difficulty { EASY, NORMAL, HARD, BRUTAL }

const MODE_NAMES: PackedStringArray = ["Co-op vs Orcs", "Deathmatch", "Team Deathmatch", "Capture the Flag", "King of the Hill"]
const MODE_HINTS: PackedStringArray = [
	"Everyone together: destroy every orc camp.",
	"Every player for themselves. Score by defeating other players.",
	"Teams score by defeating players of other teams.",
	"Bring the enemy flag to your base while yours is home.",
	"Hold the hill in the middle to earn points.",
]
const SCORE_LIMIT_LABELS: PackedStringArray = ["", "Kills to win", "Team kills to win", "Captures to win", "Hill seconds to win"]
const DIFFICULTY_NAMES: PackedStringArray = ["Easy", "Normal", "Hard", "Brutal"]
const DIFFICULTY_STRENGTH: Array[float] = [0.7, 1.0, 1.3, 1.65]
const DIFFICULTY_RESPAWN: Array[float] = [1.5, 1.0, 0.8, 0.6]
## Colors (and team names) are relative to who is looking — every device colors the world for its own player,
## nobody picks a color: you and your soldiers blue, your teammates and theirs green, enemies red (team modes:
## each enemy team its own color, red first). See `color_of()`, `team_color()`, `team_label()`.
const SELF_COLOR := Color("3c8ee8")
const TEAMMATE_COLOR := Color("46c04c")
const ENEMY_COLORS: Array[Color] = [Color("e8483c"), Color("f2c230"), Color("a45de0")]
const ENEMY_TEAM_NAMES: PackedStringArray = ["Red", "Yellow", "Purple"]

var profile: Dictionary = {"name": "Player", "class": &"swordsman"}
## peer id -> {"name": String, "team": int, "class": StringName (ClassDef.id)}
var players: Dictionary = {}
var settings: Dictionary = default_settings()
## Discovered games: ip -> {"name", "players", "max", "mode", "port", "in_game", "seen"}
var servers: Dictionary = {}
var game_in_progress: bool = false
var counting_down: bool = false
var _countdown_end_ms: int = 0

var _online: bool = false
var _broadcaster: PacketPeerUDP
var _listener: PacketPeerUDP
var _broadcast_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_profile()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


static func default_settings() -> Dictionary:
	return {
		"mode": Mode.COOP,
		"camp_count": 24,
		"difficulty": Difficulty.NORMAL,
		"start_coins": 0,
		"team_count": 2,
		"score_limit": 10,
		"time_limit": 10,
		"events": true,
		"seed": 0,
	}


# --- Queries -------------------------------------------------------------------

func is_online() -> bool:
	return _online


func is_host() -> bool:
	return multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id()


func mode() -> int:
	return settings.get("mode", Mode.COOP)


static func is_team_mode(match_mode: int) -> bool:
	return match_mode in [Mode.TEAM_DEATHMATCH, Mode.CAPTURE_THE_FLAG, Mode.KING_OF_THE_HILL]


## Team a player fights for in the current mode (co-op: everyone 0; deathmatch: alone).
func team_of(peer: int) -> int:
	match mode():
		Mode.COOP:
			return 0
		Mode.DEATHMATCH:
			return peer
	return players.get(peer, {}).get("team", 0)


## A player's color on this device: blue for you, else their team's (`team_color`).
func color_of(peer: int) -> Color:
	return SELF_COLOR if peer == my_id() else team_color(team_of(peer))


## A team's color on this device: green for your own team, red / yellow / purple for the others.
func team_color(team: int) -> Color:
	var slot := _enemy_slot(team)
	return TEAMMATE_COLOR if slot < 0 else ENEMY_COLORS[slot]


## A team's name on this device: "Your team", or the enemy team's color ("Red").
func team_label(team: int) -> String:
	var slot := _enemy_slot(team)
	return "Your team" if slot < 0 else ENEMY_TEAM_NAMES[slot]


## -1 for this device's own team, else which enemy team it is (0 = red; deathmatch: every enemy is red).
func _enemy_slot(team: int) -> int:
	var mine := team_of(my_id())
	if team == mine:
		return -1
	if not is_team_mode(mode()):
		return 0
	var slot := 0
	for other in int(settings.get("team_count", 2)):
		if other == team:
			break
		if other != mine:
			slot += 1
	return mini(slot, ENEMY_COLORS.size() - 1)


## Server-made text shown on every device: "{team:N}" becomes "your team" / "the Red team" here,
## "{label:N}" becomes `team_label(N)`; the first letter is capitalized.
func localize(text: String) -> String:
	var pattern := RegEx.create_from_string("\\{(team|label):(-?\\d+)\\}")
	var result := text
	for found in pattern.search_all(text):
		var team := int(found.get_string(2))
		var word := team_label(team)
		if found.get_string(1) == "team":
			word = "your team" if _enemy_slot(team) < 0 else "the %s team" % word
		result = result.replace(found.get_string(), word)
	return result.left(1).to_upper() + result.substr(1)


func name_of(peer: int) -> String:
	return players.get(peer, {}).get("name", "Player")


## The ClassDef id a player picked.
func class_of(peer: int) -> StringName:
	return StringName(players.get(peer, {}).get("class", &""))


## Local IPv4 addresses (shown in the lobby so others can join by IP).
func local_addresses() -> PackedStringArray:
	var result := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
			result.append(address)
	return result


# --- Profile -------------------------------------------------------------------

func set_profile(player_name: String) -> void:
	profile.name = _clean_name(player_name)
	_profile_changed()


## Your class (ClassDef id), remembered for the next game and sent to the host while in a lobby.
func set_class(class_id: StringName) -> void:
	profile["class"] = ClassDef.find(class_id).id
	_profile_changed()


func _profile_changed() -> void:
	_save_profile()
	if multiplayer.has_multiplayer_peer() and not game_in_progress and players.has(my_id()):
		if is_host():
			_update_player(1, profile.name, profile["class"])
		else:
			_request_profile.rpc_id(1, profile.name, profile["class"])


func _load_profile() -> void:
	var config := ConfigFile.new()
	if config.load(PROFILE_PATH) == OK:
		profile.name = _clean_name(config.get_value("profile", "name", "Player"))
		profile["class"] = ClassDef.find(StringName(config.get_value("profile", "class", ""))).id


func _save_profile() -> void:
	var config := ConfigFile.new()
	config.set_value("profile", "name", profile.name)
	config.set_value("profile", "class", String(profile["class"]))
	config.save(PROFILE_PATH)


static func _clean_name(value: String) -> String:
	var cleaned := value.strip_edges().substr(0, 16)
	return cleaned if cleaned != "" else "Player"


# --- Session -------------------------------------------------------------------

## Tests / running main.tscn directly only: a local "lobby" with no network (players always host or join).
func open_offline_lobby() -> void:
	_reset()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players = {1: _entry(profile.name, 0, profile["class"])}
	lobby_changed.emit()


func host() -> Error:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_online = true
	players = {1: _entry(profile.name, 0, profile["class"])}
	_start_broadcast()
	lobby_changed.emit()
	return OK


func join(address: String, port: int = PORT) -> Error:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_online = true
	return OK


## Drops any connection without changing scene (e.g. cancelling a join attempt).
func close_connection() -> void:
	_reset()


func leave(reason: String = "") -> void:
	_reset()
	get_tree().paused = false
	left_game.emit(reason)
	Transition.change_scene(MENU_SCENE)


func _reset() -> void:
	_stop_broadcast()
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_online = false
	players = {}
	settings = default_settings()
	game_in_progress = false
	counting_down = false


# --- Lobby (host) ----------------------------------------------------------------

func set_setting(key: String, value: Variant) -> void:
	if not is_host() or game_in_progress:
		return
	settings[key] = value
	if key == "mode" or key == "team_count":
		_balance_teams()
	_broadcast_lobby()


func set_team(peer: int, team: int) -> void:
	if not is_host() or not players.has(peer):
		return
	players[peer]["team"] = clampi(team, 0, settings.team_count - 1)
	_broadcast_lobby()


## Asks the host to put this player on `team`.
func request_team(team: int) -> void:
	if is_host():
		set_team(1, team)
	else:
		_request_team.rpc_id(1, team)


## Host: count down in every lobby, then load the match (`countdown` false = load right away, e.g.
## "Play again" offline in tests).
func start_game(countdown: bool = true) -> void:
	if not is_host() or counting_down:
		return
	settings.seed = randi()
	game_in_progress = true
	if countdown:
		counting_down = true
		_countdown.rpc(START_COUNTDOWN)
		await get_tree().create_timer(START_COUNTDOWN).timeout
		if not counting_down or not is_host():
			return  # left / cancelled meanwhile
		counting_down = false
	_load_game.rpc(players, settings)


## After a match: everyone goes back to the lobby (host only).
func return_to_lobby() -> void:
	if not is_host():
		return
	game_in_progress = false
	_go_to_lobby.rpc(players, settings)


func _balance_teams() -> void:
	var team := 0
	for peer in players:
		players[peer]["team"] = team % settings.team_count
		team += 1


func _entry(player_name: String, team: int, class_id: StringName) -> Dictionary:
	return {"name": _clean_name(player_name), "team": team, "class": ClassDef.find(class_id).id}


func _update_player(peer: int, player_name: String, class_id: StringName) -> void:
	if not players.has(peer):
		return
	players[peer]["name"] = _clean_name(player_name)
	players[peer]["class"] = ClassDef.find(class_id).id
	_broadcast_lobby()


func _broadcast_lobby() -> void:
	if _online:
		_sync_lobby.rpc(players, settings)
	lobby_changed.emit()


# --- RPCs ------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _register(player_name: String, class_id: StringName) -> void:
	if not is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	if game_in_progress or players.size() >= MAX_PLAYERS:
		_rejected.rpc_id(peer, "The game already started." if game_in_progress else "The game is full.")
		return
	# New players join the smallest team.
	var counts := {}
	for p in players:
		counts[players[p].team] = counts.get(players[p].team, 0) + 1
	var team := 0
	for t in settings.team_count:
		if counts.get(t, 0) < counts.get(team, 0):
			team = t
	players[peer] = _entry(player_name, team, class_id)
	_broadcast_lobby()


@rpc("any_peer", "call_remote", "reliable")
func _request_profile(player_name: String, class_id: StringName) -> void:
	if is_host() and not game_in_progress:
		_update_player(multiplayer.get_remote_sender_id(), player_name, class_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_team(team: int) -> void:
	if is_host() and not game_in_progress:
		set_team(multiplayer.get_remote_sender_id(), team)


@rpc("authority", "call_remote", "reliable")
func _sync_lobby(new_players: Dictionary, new_settings: Dictionary) -> void:
	players = new_players
	settings = new_settings
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	leave(reason)


@rpc("authority", "call_local", "reliable")
func _countdown(seconds: int) -> void:
	game_in_progress = true
	_countdown_end_ms = Time.get_ticks_msec() + seconds * 1000
	countdown_started.emit(seconds)


## Whole seconds left in the start countdown (0 = none running). Lets a lobby that opened late catch up.
func countdown_remaining() -> int:
	return maxi(ceili((_countdown_end_ms - Time.get_ticks_msec()) / 1000.0), 0)


@rpc("authority", "call_local", "reliable")
func _load_game(new_players: Dictionary, new_settings: Dictionary) -> void:
	players = new_players
	settings = new_settings
	game_in_progress = true
	get_tree().paused = false
	# Stay black: the game fades in once this device's player has spawned (main.gd).
	Transition.change_scene(GAME_SCENE, false)


@rpc("authority", "call_local", "reliable")
func _go_to_lobby(new_players: Dictionary, new_settings: Dictionary) -> void:
	players = new_players
	settings = new_settings
	game_in_progress = false
	get_tree().paused = false
	Transition.change_scene(LOBBY_SCENE)


# --- Connection events -------------------------------------------------------------

func _on_peer_connected(_peer: int) -> void:
	pass  # clients announce themselves with _register once connected


func _on_peer_disconnected(peer: int) -> void:
	if is_host() and players.erase(peer):
		_broadcast_lobby()


func _on_connected() -> void:
	_register.rpc_id(1, profile.name, profile["class"])


func _on_connection_failed() -> void:
	_reset()
	connection_failed.emit("Could not connect to the game.")


func _on_server_disconnected() -> void:
	leave("The host left the game.")


# --- LAN discovery -------------------------------------------------------------------

func _start_broadcast() -> void:
	_broadcaster = PacketPeerUDP.new()
	_broadcaster.set_broadcast_enabled(true)
	_broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_broadcast_timer = 0.0


func _stop_broadcast() -> void:
	if _broadcaster:
		_broadcaster.close()
		_broadcaster = null


## Start / stop listening for games on the local network (join screen).
func start_discovery() -> void:
	stop_discovery()
	servers.clear()
	_listener = PacketPeerUDP.new()
	if _listener.bind(DISCOVERY_PORT) != OK:
		_listener = null


func stop_discovery() -> void:
	if _listener:
		_listener.close()
		_listener = null


func _process(delta: float) -> void:
	if _broadcaster:
		_broadcast_timer -= delta
		if _broadcast_timer <= 0.0:
			_broadcast_timer = 1.0
			var info := {"game": GAME_ID, "name": profile.name, "players": players.size(),
					"max": MAX_PLAYERS, "mode": mode(), "port": PORT, "in_game": game_in_progress}
			_broadcaster.put_packet(JSON.stringify(info).to_utf8_buffer())
	if _listener:
		var changed := false
		while _listener.get_available_packet_count() > 0:
			var packet := _listener.get_packet().get_string_from_utf8()
			var ip := _listener.get_packet_ip()
			var info: Variant = JSON.parse_string(packet)
			if info is Dictionary and info.get("game") == GAME_ID:
				info["seen"] = Time.get_ticks_msec()
				servers[ip] = info
				changed = true
		for ip in servers.keys():
			if Time.get_ticks_msec() - int(servers[ip].seen) > 4000:
				servers.erase(ip)
				changed = true
		if changed:
			servers_changed.emit()

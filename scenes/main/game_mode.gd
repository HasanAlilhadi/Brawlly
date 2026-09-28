class_name GameMode
extends Node
## Match rules for every mode: spawn points, objectives (flags / hill), scoring, respawns, time limit
## and the end of the match. Created by main.gd with the same name on every peer; the server decides,
## other peers receive scores / announcements / game over via RPC.

signal scores_changed
signal announced(message: String)
signal match_over(title: String, subtitle: String)

const COOP_RESPAWN: float = 8.0
const VERSUS_RESPAWN: float = 5.0

var settings: Dictionary
var match_mode: int = Net.Mode.COOP
## Score per team (team modes) or per player peer (deathmatch).
var scores: Dictionary = {}
var time_left: float = 0.0
var team_bases: Array[Vector3] = []
var flags: Array[CaptureFlag] = []
var hill: Hill
var is_over: bool = false

var _spawn_points: Dictionary = {}  # peer -> Vector3
var _names: Dictionary = {}  # peer -> name (kept if a player leaves mid-match)
var _sync_timer: float = 0.0


func setup(match_settings: Dictionary, players: Dictionary) -> void:
	name = "GameMode"
	settings = match_settings
	match_mode = settings.mode
	time_left = float(settings.time_limit) * 60.0
	var half := GameConfig.world_half
	var peers := players.keys()
	peers.sort()
	for peer in peers:
		_names[peer] = players[peer].get("name", "Player")
	var team_count: int = settings.team_count
	if Net.is_team_mode(match_mode):
		for team in team_count:
			var angle: float = PI * 0.5 + TAU * team / team_count
			team_bases.append(Vector3(cos(angle), 0.0, sin(angle)) * half * 0.62)
			scores[team] = 0
	var team_slots := {}
	for i in peers.size():
		var peer: int = peers[i]
		var point := Vector3.ZERO
		match match_mode:
			Net.Mode.COOP:
				point = Vector3(cos(TAU * i / peers.size()), 0, sin(TAU * i / peers.size())) * (2.5 if peers.size() > 1 else 0.0)
			Net.Mode.DEATHMATCH:
				var angle: float = TAU * i / maxi(peers.size(), 2)
				point = Vector3(cos(angle), 0.0, sin(angle)) * half * 0.6
				scores[peer] = 0
			_:
				var team: int = players[peer].get("team", 0)
				var slot: int = team_slots.get(team, 0)
				team_slots[team] = slot + 1
				point = team_bases[team] + Vector3(cos(slot * 1.3), 0.0, sin(slot * 1.3)) * 2.2
		_spawn_points[peer] = point


## Where the world must stay clear of camps (spawns / bases).
func world_spawn_points() -> Array[Vector3]:
	if Net.is_team_mode(match_mode):
		return team_bases
	var points: Array[Vector3] = []
	if match_mode == Net.Mode.COOP:
		points.append(Vector3.ZERO)
	else:
		for peer in _spawn_points:
			points.append(_spawn_points[peer])
	return points


func world_clear_areas() -> Array[Vector3]:
	var areas: Array[Vector3] = []
	if match_mode == Net.Mode.KING_OF_THE_HILL:
		areas.append(Vector3.ZERO)
	return areas


func spawn_point_for(peer: int) -> Vector3:
	return _spawn_points.get(peer, Vector3.ZERO)


## Flags / hill (every peer builds them; the server runs them).
func build_objectives(world: Node3D) -> void:
	match match_mode:
		Net.Mode.CAPTURE_THE_FLAG:
			for team in settings.team_count:
				var flag := CaptureFlag.new()
				flag.name = "Flag_%d" % team
				flag.team_id = team
				flag.home = team_bases[team]
				flag.game_mode = self
				world.add_child(flag)
				flags.append(flag)
		Net.Mode.KING_OF_THE_HILL:
			hill = Hill.new()
			hill.name = "Hill"
			hill.game_mode = self
			world.add_child(hill)


func uses_time_limit() -> bool:
	return match_mode != Net.Mode.COOP


func uses_respawn() -> bool:
	return Net.is_online() or match_mode != Net.Mode.COOP


func respawn_time() -> float:
	return COOP_RESPAWN if match_mode == Net.Mode.COOP else VERSUS_RESPAWN


# --- Server rules ------------------------------------------------------------------

func _process(delta: float) -> void:
	if not multiplayer.is_server() or is_over:
		return
	if uses_time_limit():
		time_left = maxf(time_left - delta, 0.0)
		if time_left <= 0.0:
			_finish_by_score()
			return
	_sync_timer -= delta
	if _sync_timer <= 0.0:
		_sync_timer = 1.0
		_publish()


## Server: a player died — credit the kill and schedule the respawn.
func on_player_died(player: Player) -> void:
	if not multiplayer.is_server() or is_over:
		return
	var killer := player.last_attacker_peer
	if killer != 0 and killer != player.peer_id and Net.team_of(killer) != player.team_id:
		match match_mode:
			Net.Mode.DEATHMATCH:
				add_score(killer, 1)
			Net.Mode.TEAM_DEATHMATCH:
				add_score(Net.team_of(killer), 1)
		announce("%s defeated %s" % [Net.name_of(killer), player.display_name])
	for flag in flags:
		flag.on_carrier_died(player)


## Server: a player went down (they can still be revived) — a carried flag drops right away.
func on_player_downed(player: Player) -> void:
	if not multiplayer.is_server() or is_over:
		return
	announce("%s is down!" % player.display_name)
	for flag in flags:
		flag.on_carrier_died(player)


func add_score(key: int, amount: int) -> void:
	if is_over:
		return
	scores[key] = scores.get(key, 0) + amount
	_publish()
	if match_mode != Net.Mode.COOP and scores[key] >= int(settings.score_limit):
		_finish_by_score()


func announce(message: String) -> void:
	_net_announce.rpc(message)


func finish(title: String, subtitle: String) -> void:
	if is_over:
		return
	_net_match_over.rpc(title, subtitle)


func _finish_by_score() -> void:
	var best_key := -999
	var best := -1
	var tie := false
	for key in scores:
		if scores[key] > best:
			best = scores[key]
			best_key = key
			tie = false
		elif scores[key] == best:
			tie = true
	if tie or best_key == -999:
		finish("Draw!", "Nobody broke the tie.")
	elif match_mode == Net.Mode.DEATHMATCH:
		finish("%s wins!" % player_name(best_key), "%d kill%s" % [best, "" if best == 1 else "s"])
	else:
		finish("%s team wins!" % Net.TEAM_NAMES[best_key], score_text())


func _publish() -> void:
	_net_scores.rpc(scores, time_left)


# --- Display (all peers) ---------------------------------------------------------

## peer -> name for everyone who played this match (also players who left).
func player_names() -> Dictionary:
	return _names.duplicate()


func player_name(peer: int) -> String:
	return _names.get(peer, Net.name_of(peer))


## One-line summary for the HUD, e.g. "Red 3 - 2 Blue   4:12".
func score_text() -> String:
	var parts := PackedStringArray()
	match match_mode:
		Net.Mode.COOP:
			return ""
		Net.Mode.DEATHMATCH:
			var ranked := scores.keys()
			ranked.sort_custom(func(a: int, b: int) -> bool: return scores[a] > scores[b])
			for peer in ranked.slice(0, 3):
				parts.append("%s %d" % [player_name(peer), scores[peer]])
		_:
			for team in settings.team_count:
				parts.append("%s %d" % [Net.TEAM_NAMES[team], scores.get(team, 0)])
	var text := "   ".join(parts)
	if uses_time_limit():
		text += "   %d:%02d" % [int(time_left) / 60, int(time_left) % 60]
	return text


@rpc("authority", "call_local", "unreliable_ordered")
func _net_scores(new_scores: Dictionary, new_time_left: float) -> void:
	scores = new_scores
	time_left = new_time_left
	scores_changed.emit()


@rpc("authority", "call_local", "reliable")
func _net_announce(message: String) -> void:
	announced.emit(message)


@rpc("authority", "call_local", "reliable")
func _net_match_over(title: String, subtitle: String) -> void:
	is_over = true
	match_over.emit(title, subtitle)

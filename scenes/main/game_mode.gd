class_name GameMode
extends Node
## Match rules for every mode (co-op, King of the Hill, Last Stand): spawn points, the hill / circles, scoring,
## respawns, time limit and the end of the match. Created by main.gd with the same name on every peer; the server
## decides, other peers receive scores / circle state / announcements / game over via RPC.
## Last Stand: ten circles (positions from the match seed, so every peer knows them) held for `circle_seconds`
## each by enough standing heroes (`circle_required`: a share of the heroes still alive, more for later circles);
## stepping out pauses the clock. While heroes are near the circle, enemy squads assault it, stronger every circle
## (also every enemy spawned anywhere: `GameConfig.orc_strength`); the last circle brings the Orc Warlord. No
## respawns: a downed hero nobody revives is gone for the match and spectates; everyone gone = defeat.

signal scores_changed
signal announced(message: String)
signal match_over(title: String, subtitle: String)
## Last Stand: the circle's state changed (every peer).
signal objective_changed

const COOP_RESPAWN: float = 8.0
const VERSUS_RESPAWN: float = 5.0

const CIRCLE_COUNT: int = 10
const CIRCLE_SECONDS: float = 60.0
## Orc strength per circle: × (1 + this × circle index), on top of the difficulty (last circle ≈ 2.1×).
const CIRCLE_STRENGTH_STEP: float = 0.12
## Coins for every hero still in the match when a circle is held: base + per circle.
const CIRCLE_REWARD: int = 30
const CIRCLE_REWARD_STEP: int = 15
## Assault squads come while a standing hero is this close to the circle, from this far away.
const ASSAULT_ENGAGE_RANGE: float = 32.0
const ASSAULT_DISTANCE: Vector2 = Vector2(24.0, 30.0)
## Seconds between squads (first circle → last), and the first one after heroes arrive.
const ASSAULT_EVERY: Vector2 = Vector2(16.0, 8.0)
const ASSAULT_FIRST: float = 4.0
## Orcs per squad (first circle → last) for one hero; more heroes bring bigger squads.
const ASSAULT_SQUAD: Vector2 = Vector2(3.0, 8.0)
## Living assault orcs at most: base + per hero alive.
const ASSAULT_CAP: Vector2i = Vector2i(10, 5)
## Assault squads draw from the wave enemy rows (WorldEvents.WAVE_TYPES): one more row every this many circles.
const ASSAULT_ROW_EVERY: int = 2
## Circles stay this far apart, and this far from the start / map border.
const CIRCLE_SPACING: float = 22.0
const CIRCLE_BORDER: float = 14.0

var settings: Dictionary
var match_mode: int = Net.Mode.COOP
## Score per team (King of the Hill).
var scores: Dictionary = {}
var time_left: float = 0.0
var team_bases: Array[Vector3] = []
var hill: Hill
var is_over: bool = false

## Last Stand: the circles in order, the one to hold now (CIRCLE_COUNT = all held), seconds held of it, how many
## standing heroes it needs and how many stand in it (all replicated).
var circles: Array[Vector3] = []
var circle_index: int = 0
var circle_time: float = 0.0
var circle_required: int = 1
var circle_inside: int = 0
var hold_circle: HoldCircle
## Tests shorten this.
var circle_seconds: float = CIRCLE_SECONDS

var _spawn_points: Dictionary = {}  # peer -> Vector3
var _names: Dictionary = {}  # peer -> name (kept if a player leaves mid-match)
var _sync_timer: float = 0.0
var _circles_started: bool = false
var _base_required: int = 1
var _assault_timer: float = ASSAULT_FIRST
var _base_strength: float = 1.0


## `map`: a designed map brings its own team bases.
func setup(match_settings: Dictionary, players: Dictionary, map: MapDef = null) -> void:
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
			if map and map.team_bases.size() >= team_count:
				team_bases.append(map.team_bases[team])
			else:
				var angle: float = PI * 0.5 + TAU * team / team_count
				team_bases.append(Vector3(cos(angle), 0.0, sin(angle)) * half * 0.62)
			scores[team] = 0
	# Co-op modes start together: in the middle of a procedural map, at the first base of a designed one.
	var coop_spawn := map.team_bases[0] if map and map.layout and not map.team_bases.is_empty() else Vector3.ZERO
	if Net.is_coop_mode(match_mode):
		team_bases.append(coop_spawn)
	if match_mode == Net.Mode.LAST_STAND:
		if map and not map.hold_circles.is_empty():
			for spot in map.hold_circles:
				circles.append(spot)  # a designed map places its own
		else:
			_plan_circles(int(settings.get("seed", 0)))
	var team_slots := {}
	for i in peers.size():
		var peer: int = peers[i]
		var point := Vector3.ZERO
		if Net.is_coop_mode(match_mode):
			point = coop_spawn + Vector3(cos(TAU * i / peers.size()), 0, sin(TAU * i / peers.size())) * (2.5 if peers.size() > 1 else 0.0)
		else:
			var team: int = players[peer].get("team", 0)
			var slot: int = team_slots.get(team, 0)
			team_slots[team] = slot + 1
			point = team_bases[team] + Vector3(cos(slot * 1.3), 0.0, sin(slot * 1.3)) * 2.2
		_spawn_points[peer] = point


## Last Stand: ten circles, each a walk away from the last (turning 70–140° around the start), farther out — among
## bigger warbands — the later they come. From the seed, so every peer plans the same.
func _plan_circles(match_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = match_seed + 7919
	var half := GameConfig.world_half
	var angle := rng.randf() * TAU
	var previous := Vector3.ZERO
	for i in CIRCLE_COUNT:
		var t := float(i) / (CIRCLE_COUNT - 1)
		var radius := clampf(lerpf(0.24, 0.76, t) * half, 21.0, half - CIRCLE_BORDER)
		var spot := Vector3.INF
		for attempt in 60:
			var turn := rng.randf_range(1.2, 2.4) * (1.0 if rng.randf() < 0.5 else -1.0)
			var r := clampf(radius + rng.randf_range(-0.06, 0.06) * half, 21.0, half - CIRCLE_BORDER)
			var candidate := Vector3(cos(angle + turn), 0.0, sin(angle + turn)) * r
			if candidate.distance_to(previous) < CIRCLE_SPACING:
				continue
			var crowded := false
			for other in circles:
				if candidate.distance_to(other) < CIRCLE_SPACING:
					crowded = true
					break
			if not crowded:
				spot = candidate
				angle += turn
				break
		if spot == Vector3.INF:
			angle += 2.0
			spot = Vector3(cos(angle), 0.0, sin(angle)) * radius
		circles.append(spot)
		previous = spot


## Where the world must stay clear of camps (spawns / bases).
func world_spawn_points() -> Array[Vector3]:
	if Net.is_team_mode(match_mode) or not team_bases.is_empty():
		return team_bases
	var points: Array[Vector3] = [Vector3.ZERO]
	return points


## Objective areas the world keeps free (the hill, the circles), `world_clear_radius()` around each.
func world_clear_areas() -> Array[Vector3]:
	var areas: Array[Vector3] = []
	if match_mode == Net.Mode.KING_OF_THE_HILL:
		areas.append(Vector3.ZERO)
	elif match_mode == Net.Mode.LAST_STAND:
		areas.append_array(circles)
	return areas


func world_clear_radius() -> float:
	return HoldCircle.RADIUS + 5.0 if match_mode == Net.Mode.LAST_STAND else 9.0


## Gold veins the mode wants: one inside the edge of every circle (mine while you hold it).
func world_vein_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	if match_mode == Net.Mode.LAST_STAND:
		for i in circles.size():
			var inward := -circles[i].normalized() if circles[i].length() > 0.1 else Vector3.BACK
			spots.append(circles[i] + inward.rotated(Vector3.UP, 0.6 if i % 2 == 0 else -0.6) * (HoldCircle.RADIUS - 1.7))
	return spots


func spawn_point_for(peer: int) -> Vector3:
	return _spawn_points.get(peer, Vector3.ZERO)


## The hill / the circle (every peer builds it; the server runs it).
func build_objectives(world: Node3D) -> void:
	if match_mode == Net.Mode.KING_OF_THE_HILL:
		hill = Hill.new()
		hill.name = "Hill"
		hill.game_mode = self
		world.add_child(hill)
	elif match_mode == Net.Mode.LAST_STAND:
		hold_circle = HoldCircle.new()
		hold_circle.name = "HoldCircle"
		hold_circle.total = CIRCLE_COUNT
		hold_circle.position = circles[0]
		world.add_child(hold_circle)


func uses_time_limit() -> bool:
	return match_mode == Net.Mode.KING_OF_THE_HILL


func uses_respawn() -> bool:
	if match_mode == Net.Mode.LAST_STAND:
		return false
	return Net.is_online() or match_mode != Net.Mode.COOP


func respawn_time() -> float:
	return COOP_RESPAWN if match_mode == Net.Mode.COOP else VERSUS_RESPAWN


# --- Server rules ------------------------------------------------------------------

func _process(delta: float) -> void:
	if hold_circle and not is_over:
		# Clients run the clock between the server's updates; every peer fills the ring smoothly.
		if not multiplayer.is_server() and circle_inside >= circle_required and circle_inside > 0:
			circle_time = minf(circle_time + delta, circle_seconds)
		hold_circle.set_progress(circle_time / circle_seconds)
	if not multiplayer.is_server() or is_over:
		return
	if match_mode == Net.Mode.LAST_STAND:
		_update_last_stand(delta)
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
		announce("%s defeated %s" % [Net.name_of(killer), player.display_name])


## Server: a player went down (they can still be revived).
func on_player_downed(player: Player) -> void:
	if not multiplayer.is_server() or is_over:
		return
	announce("%s is down!" % player.display_name)
	if match_mode == Net.Mode.LAST_STAND:
		_check_wipe()


## Server, Last Stand: a hero is gone for good (bled out, or died with nobody to revive them).
func on_player_fell(player: Player) -> void:
	if not multiplayer.is_server() or is_over:
		return
	var left := living_players().size()
	if left > 0:
		announce("%s has fallen! %d %s left." % [player.display_name, left, "hero" if left == 1 else "heroes"])
	_check_wipe()


func add_score(key: int, amount: int) -> void:
	if is_over:
		return
	scores[key] = scores.get(key, 0) + amount
	_publish()
	if match_mode == Net.Mode.KING_OF_THE_HILL and scores[key] >= int(settings.score_limit):
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
	else:
		finish("{team:%d} wins!" % best_key, score_text(true))


func _publish() -> void:
	_net_scores.rpc(scores, time_left)


# --- Last Stand (server) ------------------------------------------------------------------

## Heroes still in the match (downed ones too: they can be revived).
func living_players() -> Array[Player]:
	var result: Array[Player] = []
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if is_instance_valid(player) and not player.is_dead:
			result.append(player)
	return result


## Orc strength for a circle (× the difficulty).
static func circle_strength(index: int) -> float:
	return 1.0 + CIRCLE_STRENGTH_STEP * index


func _update_last_stand(delta: float) -> void:
	var alive := living_players()
	if not _circles_started:
		if alive.is_empty():
			return  # the heroes haven't spawned yet
		_circles_started = true
		_base_strength = GameConfig.orc_strength
		_start_circle(0)
	if alive.is_empty():
		_check_wipe()
		return
	var center := circles[circle_index]
	var inside := 0
	var engaged := false
	for player in alive:
		if player.is_downed:
			continue
		var offset := player.global_position - center
		offset.y = 0.0
		if offset.length() < HoldCircle.RADIUS:
			inside += 1
		if offset.length() < ASSAULT_ENGAGE_RANGE:
			engaged = true
	var required := mini(_base_required, alive.size())
	var changed := inside != circle_inside or required != circle_required
	circle_inside = inside
	circle_required = required
	if inside >= required:
		circle_time += delta
		if circle_time >= circle_seconds:
			_complete_circle(alive)
			return
	if engaged:
		_assault_timer -= delta
		if _assault_timer <= 0.0:
			_assault_timer = lerpf(ASSAULT_EVERY.x, ASSAULT_EVERY.y, _circle_t())
			_send_assault(alive.size())
	_sync_timer -= delta
	if changed or _sync_timer <= 0.0:
		_net_circle.rpc(circle_index, circle_time, circle_required, circle_inside)


## 0 on the first circle … 1 on the last.
func _circle_t() -> float:
	return float(circle_index) / (CIRCLE_COUNT - 1)


func _start_circle(index: int) -> void:
	circle_index = index
	circle_time = 0.0
	_assault_timer = ASSAULT_FIRST
	GameConfig.orc_strength = _base_strength * circle_strength(index)
	var alive := living_players().size()
	# Later circles need more of the heroes still standing (the last one: all of them).
	var share := lerpf(0.45, 1.0, _circle_t()) + randf_range(-0.15, 0.15)
	_base_required = clampi(ceili(alive * share), 1, maxi(alive, 1)) if index < CIRCLE_COUNT - 1 else maxi(alive, 1)
	circle_required = mini(_base_required, maxi(alive, 1))
	circle_inside = 0
	_net_circle.rpc(circle_index, circle_time, circle_required, circle_inside)
	var who := "%d heroes must stand in it" % circle_required if circle_required > 1 else "stand in it"
	if index == 0:
		announce("Hold circle 1 of %d: %s for %d seconds!" % [CIRCLE_COUNT, who, roundi(circle_seconds)])
	elif index == CIRCLE_COUNT - 1:
		announce("The last circle! Everyone in — the Orc Warlord is coming!")
		var main := get_parent()
		var events: WorldEvents = main.get("world_events")
		var alive_players := living_players()
		if events and not is_instance_valid(events.warlord) and not alive_players.is_empty():
			events.spawn_warlord(alive_players.pick_random())
	else:
		announce("Circle %d of %d: %s. The orcs grow stronger!" % [index + 1, CIRCLE_COUNT, who])


func _complete_circle(alive: Array[Player]) -> void:
	var reward := CIRCLE_REWARD + CIRCLE_REWARD_STEP * circle_index
	for player in alive:
		player.coins += reward
		MatchStats.add(player.peer_id, &"coins", reward)
	var held := circle_index + 1
	if held >= CIRCLE_COUNT:
		circle_time = circle_seconds
		_net_circle.rpc(circle_index, circle_time, circle_required, circle_inside)
		finish("Victory!", "All %d circles held. The land is yours." % CIRCLE_COUNT)
		return
	announce("Circle %d held! +%d coins" % [held, reward])
	_start_circle(held)


## Everyone gone (or everyone left is down with nobody to help them up) = defeat.
func _check_wipe() -> void:
	if is_over or not _circles_started:
		return
	var alive := living_players()
	var standing := alive.filter(func(player: Player) -> bool: return not player.is_downed)
	if not alive.is_empty() and standing.is_empty():
		for player in alive:
			player.die()  # nobody can revive them: gone for good
		return  # each death comes back here through on_player_fell
	if alive.is_empty():
		finish("Defeat", "The horde overran circle %d of %d." % [circle_index + 1, CIRCLE_COUNT])


## A squad marches on the circle from out of sight: the wave enemy rows, one more row every ASSAULT_ROW_EVERY
## circles (grunts and skeletons first, then throwers and zombies, archers and ghosts, brutes and vampires,
## necromancers); the newest row comes in smaller numbers.
func _send_assault(heroes: int) -> void:
	var living := get_tree().get_nodes_in_group(&"wave_enemies").filter(
			func(enemy: Node) -> bool: return not GameConfig.is_gone(enemy)).size()
	var room := ASSAULT_CAP.x + ASSAULT_CAP.y * heroes - living
	var t := _circle_t()
	var size := mini(roundi(lerpf(ASSAULT_SQUAD.x, ASSAULT_SQUAD.y, t) * (0.7 + 0.3 * heroes)), room)
	if size <= 0:
		return
	var main := get_parent()
	var center := circles[circle_index]
	var spot: Vector3 = main.free_spot_around(center, randf_range(ASSAULT_DISTANCE.x, ASSAULT_DISTANCE.y))
	if spot == Vector3.INF:
		return
	var rows := mini(1 + circle_index / ASSAULT_ROW_EVERY, WorldEvents.WAVE_TYPES.size())
	for i in size:
		var row := randi() % rows
		if row == rows - 1 and rows > 1 and randf() < 0.5:
			row = randi() % (rows - 1)  # the newest row: about half as many
		var types: Array = WorldEvents.WAVE_TYPES[row]
		var scene := WorldEvents.ENEMIES + str(types[randi() % types.size()]) + ".tscn"
		var at := GameConfig.clamp_to_world(spot + Vector3(i % 3 - 1, 0.0, i / 3) * 0.9)
		NetSpawn.unit(&"enemy", at, {"scene": scene, "strength": GameConfig.orc_strength, "coins": 0.7,
				"wave_enemy": true, "wave_number": circle_index + 1})


# --- Display (all peers) ---------------------------------------------------------

## peer -> name for everyone who played this match (also players who left).
func player_names() -> Dictionary:
	return _names.duplicate()


func player_name(peer: int) -> String:
	return _names.get(peer, Net.name_of(peer))


## One-line summary for the HUD, e.g. "Your team 3   Red 2   4:12" (`tokens`: team names as
## Net.localize() tokens, for text the server sends to everyone). Co-op modes have none.
func score_text(tokens: bool = false) -> String:
	if Net.is_coop_mode(match_mode):
		return ""
	var parts := PackedStringArray()
	for team in settings.team_count:
		parts.append("%s %d" % ["{label:%d}" % team if tokens else Net.team_label(team), scores.get(team, 0)])
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
func _net_circle(index: int, held: float, required: int, inside: int) -> void:
	var moved := index != circle_index
	circle_index = index
	circle_time = held
	circle_required = required
	circle_inside = inside
	if hold_circle:
		if moved or hold_circle.position != circles[index]:
			hold_circle.position = circles[index]
		hold_circle.show_state(index, CIRCLE_COUNT, required, inside, clampf(held / circle_seconds, 0.0, 1.0))
	objective_changed.emit()


@rpc("authority", "call_local", "reliable")
func _net_announce(message: String) -> void:
	announced.emit(message)


@rpc("authority", "call_local", "reliable")
func _net_match_over(title: String, subtitle: String) -> void:
	is_over = true
	match_over.emit(Net.localize(title), Net.localize(subtitle))

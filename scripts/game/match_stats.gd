class_name MatchStats
extends Node
## Per-player match statistics (server) and the end-of-match awards shown to everyone.
## Gameplay code reports events through the static helpers (`MatchStats.add(peer, &"revives")`);
## they do nothing on clients or outside a match. main.gd creates one node per match, with the same
## name on every peer, so the awards reach everyone through `_net_awards`.

signal awards_ready(awards: Array)

## [stat, title, detail ("%d" = the value), minimum value to earn it, icon: a Game Icon Pack glyph (assets/ui/icons/game/), see UiKit.medal].
## The order is the priority.
const AWARDS: Array = [
	[&"warlord_kills", "Warlord Slayer", "Final blow on the Warlord", 1, "boss"],
	[&"revives", "Medic", "Revives: %d", 1, "medical_kit"],
	[&"goblin_kills", "Goblin Hunter", "Goblins caught: %d", 1, "star_coin"],
	[&"player_kills", "Headhunter", "Players defeated: %d", 2, "skull"],
	[&"camps", "Camp Crusher", "Camps destroyed: %d", 2, "tent"],
	[&"orc_kills", "Orc Slayer", "Orcs defeated: %d", 8, "broadsword"],
	[&"arrow_damage", "Sharpshooter", "Arrow damage: %d", 400, "target"],
	[&"coins", "Moneybags", "Coins collected: %d", 80, "coin"],
	[&"trees", "Lumberjack", "Trees chopped: %d", 3, "axe"],
	[&"downs", "Floor Inspector", "Times downed: %d", 2, "heart_break"],
	[&"soldiers_lost", "Where's My Army?", "Soldiers lost: %d", 10, "ghost"],
	[&"pings", "Chatterbox", "Pings: %d", 8, "message"],
]
const MAX_AWARDS: int = 6
const MAX_AWARDS_PER_PLAYER: int = 2

static var current: MatchStats

var _stats: Dictionary = {}  # peer -> {stat: float}


func _enter_tree() -> void:
	name = "MatchStats"
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


# --- Reporting (server) ----------------------------------------------------------

static func add(peer: int, stat: StringName, amount: float = 1.0) -> void:
	if peer == 0 or current == null or not current.multiplayer.is_server():
		return
	var stats: Dictionary = current._stats.get_or_add(peer, {})
	stats[stat] = stats.get(stat, 0.0) + amount


## A player (or their arrow) hit something.
static func on_hit(peer: int, amount: float, is_melee: bool) -> void:
	add(peer, &"damage", amount)
	if not is_melee:
		add(peer, &"arrow_damage", amount)


## Any unit died: kill credit, deaths and lost soldiers.
static func on_unit_died(unit: Unit) -> void:
	var killer := unit.last_attacker_peer
	if unit is Player:
		add((unit as Player).peer_id, &"deaths")
		if killer != 0 and killer != (unit as Player).peer_id and Net.team_of(killer) != unit.team_id:
			add(killer, &"player_kills")
	elif unit is Ally:
		add(unit.owner_peer, &"soldiers_lost")
	elif unit is Warlord:
		add(killer, &"warlord_kills")
	elif unit is TreasureGoblin:
		add(killer, &"goblin_kills")
	elif unit is Enemy:
		add(killer, &"orc_kills")


func stat(peer: int, key: StringName) -> float:
	return _stats.get(peer, {}).get(key, 0.0)


# --- Awards --------------------------------------------------------------------------

## Server: work out the awards and send them to every peer.
func publish_awards(names: Dictionary) -> void:
	if multiplayer.is_server():
		_net_awards.rpc(compute_awards(names))


## [{title, peer, name, detail}] — MVP first (with more than one player), then the AWARDS table.
func compute_awards(names: Dictionary) -> Array:
	var awards: Array = []
	var peers: Array = names.keys()
	var per_player: Dictionary = {}
	if peers.size() > 1:
		var mvp := -1
		var best := -INF
		for peer in peers:
			var score := _mvp_score(peer)
			if score > best:
				best = score
				mvp = peer
		if mvp != -1 and best > 0.0:
			awards.append({"title": "MVP", "peer": mvp, "name": names[mvp], "icon": "crown",
					"detail": "%d damage · %d orcs · %d revives" % [stat(mvp, &"damage"), stat(mvp, &"orc_kills"), stat(mvp, &"revives")]})
	for entry in AWARDS:
		if awards.size() >= MAX_AWARDS:
			break
		var key: StringName = entry[0]
		var winner := -1
		var best_value := 0.0
		for peer in peers:
			var value := stat(peer, key)
			if value > best_value and per_player.get(peer, 0) < MAX_AWARDS_PER_PLAYER:
				best_value = value
				winner = peer
		if winner == -1 or best_value < float(entry[3]):
			continue
		per_player[winner] = per_player.get(winner, 0) + 1
		var detail: String = entry[2]
		awards.append({"title": entry[1], "peer": winner, "name": names[winner], "icon": entry[4],
				"detail": detail % int(best_value) if detail.contains("%d") else detail})
	if awards.is_empty() and peers.size() == 1:
		var peer: int = peers[0]
		awards.append({"title": "Your match", "peer": peer, "name": names[peer], "icon": "trophy",
				"detail": "%d orcs · %d camps · %d coins" % [stat(peer, &"orc_kills"), stat(peer, &"camps"), stat(peer, &"coins")]})
	return awards


func _mvp_score(peer: int) -> float:
	return stat(peer, &"damage") * 0.02 + stat(peer, &"orc_kills") + stat(peer, &"player_kills") * 5.0 \
			+ stat(peer, &"camps") * 6.0 + stat(peer, &"revives") * 5.0 + stat(peer, &"warlord_kills") * 15.0 \
			+ stat(peer, &"goblin_kills") * 6.0 - stat(peer, &"deaths") * 2.0


@rpc("authority", "call_local", "reliable")
func _net_awards(awards: Array) -> void:
	awards_ready.emit(awards)

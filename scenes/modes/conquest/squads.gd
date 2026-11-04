class_name ConquestSquads
extends Node
## Conquest squads: soldiers taken from a barracks on the M map leave as a squad of SIZES (4 or 8) of one class,
## led by one of them (`Ally.squad_leader`, a banner on its back; the best ranked). The squad is not part of its
## hero's army formation (Player.followers() leaves it out; it still counts toward the army cap) and takes its
## own orders from the map (`order`, server; ConquestMode.squad_action):
## - GO: the leader walks to a place (`place`) on the navigation mesh, the others follow it; there they guard it
##   — standing in its ring they capture it and keep it guarded (they are its garrison).
## - HOLD: the same, at a point on the map (`point`).
## - JOIN: the squad breaks up and its soldiers walk to their hero and follow in the army (`_join`).
## A squad starts holding the place it left. The leader falls → the best ranked one left leads (`_check`); none
## left → the squad is gone. Every peer gets the squads (`_net_squads`, on change and every second while any
## exist); members and their leader come from the allies themselves (`Ally.squad` / `squad_leader`, replicated).

enum Order { HOLD, GO, JOIN }
const SIZES: Array[int] = [4, 8]
const ORDER_NAMES: PackedStringArray = ["Holding", "Going to", "Joining"]
## A squad's guard area: it fights what comes this close to its point once there (on the way only what comes
## within the soldiers' aggro_range), and stands within ARRIVE of it.
const GUARD: float = 12.0
const ARRIVE: float = 4.0
const CHECK_EVERY: float = 1.0

var mode: ConquestMode
## id -> {owner: peer, team, kind: SOLDIER_KINDS index, order: Order, place: index (-1 = a point), point: Vector3}
var squads: Dictionary = {}

var _next_id: int = 1
var _check_timer: float = CHECK_EVERY


func _ready() -> void:
	name = "Squads"
	add_to_group(&"conquest_squads")


## Server: a new squad of `player` holding `place`; returns its id (spawn data "squad" of its soldiers).
func create(player: Player, kind: int, place: TerritoryNode) -> int:
	var id := _next_id
	_next_id += 1
	squads[id] = {"owner": player.peer_id, "team": player.team_id, "kind": kind, "order": Order.HOLD,
			"place": place.index, "point": place.global_position}
	return id


func squad(id: int) -> Dictionary:
	return squads.get(id, {})


## Its living soldiers (every peer), the leader first.
func members(id: int) -> Array[Ally]:
	var result: Array[Ally] = []
	for node in get_tree().get_nodes_in_group(&"allies"):
		var ally := node as Ally
		if ally and ally.squad == id and not ally.is_dead:
			if ally.squad_leader:
				result.push_front(ally)
			else:
				result.append(ally)
	return result


func leader_of(id: int) -> Ally:
	var all := members(id)
	return all[0] if not all.is_empty() and all[0].squad_leader else null


## Where the squad goes and stands (its place's middle, or the held point).
func goal(id: int) -> Vector3:
	var data := squad(id)
	if data.is_empty():
		return Vector3.INF
	var place := int(data.place)
	if place >= 0 and place < mode.territories.size():
		return mode.territories[place].global_position
	return data.point


## The squads of one hero (every peer), oldest first.
func of_player(peer: int) -> Array[int]:
	var result: Array[int] = []
	for id: int in squads:
		if int(squads[id].owner) == peer:
			result.append(id)
	return result


## "Holding Highkeep", "Going to a point".
func order_text(id: int) -> String:
	var data := squad(id)
	if data.is_empty():
		return ""
	var place := int(data.place)
	var where := mode.territories[place].display_name if place >= 0 and place < mode.territories.size() else "a point"
	return "%s %s" % [ORDER_NAMES[int(data.order)], where]


## Server (Player.request_squad_action, the map): an order for squad `id` from its hero or the faction's General.
## `action`: go (`arg` = a place index), hold (`point`), join (back to the hero's army). Returns whether it was done.
func command(player: Player, id: int, action: StringName, arg: int, point: Vector3) -> bool:
	var data := squad(id)
	if player == null or player.is_dead or data.is_empty() or int(data.team) != player.team_id:
		return false
	if int(data.owner) != player.peer_id and mode.logistics.general_of(player.team_id) != player.peer_id:
		return false
	match action:
		&"go":
			if arg < 0 or arg >= mode.territories.size():
				return false
			data.order = Order.GO
			data.place = arg
			data.point = mode.territories[arg].global_position
		&"hold":
			data.order = Order.HOLD
			data.place = -1
			data.point = GameConfig.clamp_to_world(Vector3(point.x, 0.0, point.z))
		&"join":
			_join(id)
			return true
		_:
			return false
	for ally in members(id):
		ally.squad_ordered()
	_send()
	return true


## The squad breaks up: its soldiers walk to their hero (Ally.mustering) and follow in the army.
func _join(id: int) -> void:
	for ally in members(id):
		ally.squad_leader = false
		ally.squad = 0
		ally.mustering = true
		ally.target = null
	squads.erase(id)
	_send()


func _process(delta: float) -> void:
	if not multiplayer.is_server() or squads.is_empty():
		return
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = CHECK_EVERY
	_check()
	_send()


## Server: a squad without a leader gets the best ranked one left; an empty one is gone; a GO squad there holds.
func _check() -> void:
	for id: int in squads.keys():
		var all := members(id)
		if all.is_empty():
			squads.erase(id)
			continue
		if not all[0].squad_leader:
			var best := all[0]
			for ally in all:
				if ally.rank > best.rank:
					best = ally
			best.squad_leader = true
		var data: Dictionary = squads[id]
		if int(data.order) == Order.GO and leader_of(id) and \
				Ally._flat(leader_of(id).global_position - goal(id)).length() < GUARD:
			data.order = Order.HOLD  # there: it holds the place


func _send() -> void:
	_net_squads.rpc(squads)


@rpc("authority", "call_remote", "reliable")
func _net_squads(data: Dictionary) -> void:
	squads = data

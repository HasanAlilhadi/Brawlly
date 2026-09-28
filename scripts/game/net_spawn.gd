class_name NetSpawn
## Server-side spawning mirrored to every peer. main.gd owns two MultiplayerSpawners (units, items)
## whose spawn functions build nodes from these data dictionaries on the server and on clients.
## All calls are ignored on clients (only the server creates gameplay objects).

static var units: MultiplayerSpawner
static var items: MultiplayerSpawner
static var _counter: int = 0


static func _is_server() -> bool:
	return units != null and is_instance_valid(units) and units.multiplayer.is_server()


static func _name(kind: StringName) -> String:
	_counter += 1
	return "%s_%d" % [kind, _counter]


## kind: &"player", &"ally" or &"enemy". `extra` carries team / owner / color / scene etc.
static func unit(kind: StringName, position: Vector3, extra: Dictionary = {}) -> Node:
	if not _is_server():
		return null
	var data := {"kind": kind, "pos": position, "name": _name(kind)}
	data.merge(extra)
	return units.spawn(data)


static func pickup(kind: int, amount: int, position: Vector3) -> void:
	if not _is_server():
		return
	items.spawn({"kind": &"pickup", "pickup_kind": kind, "amount": amount, "pos": position,
			"name": _name(&"pickup")})


## kind: &"arrow", &"spear" (orc throwers) or &"player_spear" (hits orcs).
static func projectile(kind: StringName, from: Vector3, direction: Vector3, damage: float, shooter: Node,
		crit: bool = false) -> void:
	if not _is_server():
		return
	items.spawn({"kind": kind, "pos": from, "dir": direction, "damage": damage, "crit": crit,
			"team": shooter.get("team_id"), "owner": GameConfig.owner_peer_of(shooter),
			"shooter": shooter.get_path(), "name": _name(kind)})

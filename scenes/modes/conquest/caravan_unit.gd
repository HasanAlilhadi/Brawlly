class_name CaravanUnit
extends Unit
## Conquest: a pack animal (a cow with crates) that carries supplies from a held territory to a hero's army in
## the field. LogisticsManager sends one (NetSpawn kind `caravan`, with "cargo" and the escorted hero as owner)
## when soldiers are out of every supply point's reach; it walks behind the hero and is a supply point itself
## (group `conquest_supply`): soldiers near it eat, are repaired and refill their quivers from its `cargo` before
## the faction's stockpile. Empty, or its hero gone, it walks back to the nearest held territory and hands back
## what is left. It never fights; monsters and rival factions attack it (group `player_units`). Killed by a rival
## faction, its cargo goes to theirs (looted); killed by monsters, it is lost and spills a few coins.
## Couriers: every caravan belongs to a place (`home`, its index) and counts as one of its couriers while out.
## With a `dest` (a place's index) it carries the cargo there, unloads what that store takes, and walks home;
## without one it escorts its hero (the army route, or a cut-off army). Home again it hands back what is left and
## the place has its courier back. It walks on the navigation mesh (`_drive_to`).
## Server runs it; clients see position / health through Sync like any unit.

const SCENE_PATH := "res://scenes/modes/conquest/caravan_unit.tscn"
const PET := preload("res://assets/characters/pets/cow.glb")
const PET_SCALE: float = 0.55
## What a caravan sets out with, at most, of each supply (taken from the faction's stockpile).
const CARGO: Dictionary = {&"food": 30, &"equipment": 30}
## Soldiers within this range draw on its cargo.
const SUPPLY_RANGE: float = 9.0
## It keeps this far behind its hero; home means this close to the territory.
const FOLLOW_DISTANCE: float = 4.5
const HOME_DISTANCE: float = 3.0
## Coins spilled when monsters destroy it.
const SPILL_COINS: int = 6

## Supplies on board (same keys as the stockpile; server).
var cargo: Dictionary = {}

## The place it belongs to and the place it carries goods to (-1: none / escorting its hero).
var home: int = -1
var dest: int = -1
var _going_home: bool = false
var _nav: NavigationAgent3D
## Home again: it leaves without loot.
var _retired: bool = false


## main.gd `_spawn_unit`: the caravan for spawn data {"cargo": {...}} (every peer).
static func create(data: Dictionary) -> CaravanUnit:
	var caravan := (load(SCENE_PATH) as PackedScene).instantiate() as CaravanUnit
	caravan.cargo = data.get("cargo", {}).duplicate()
	caravan.home = data.get("home", -1)
	caravan.dest = data.get("dest", -1)
	return caravan


func _ready() -> void:
	_build_model()
	super()
	add_to_group(&"caravans")
	add_to_group(&"player_units")  # monsters and rival factions go after it
	add_to_group(&"conquest_supply")
	for clip in ["walk", "run"]:
		if anim and anim.has_animation(clip):
			anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


## The pet in a scaled holder (some clips key the pet's own root scale) with crates on its back.
func _build_model() -> void:
	var body := $Model as Node3D
	body.scale = Vector3.ONE * PET_SCALE
	body.position.y = 0.3 * PET_SCALE
	body.add_child(PET.instantiate())
	var crate := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.1, 0.7, 1.0)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.38, 0.2)
	box.material = wood
	crate.mesh = box
	crate.position = Vector3(0.0, 1.85, -0.1)
	body.add_child(crate)
	model = body
	anim = body.find_child("AnimationPlayer", true, false) as AnimationPlayer


## Only an escorting caravan feeds soldiers (a delivery keeps its cargo for the place it goes to).
func supply_range() -> float:
	return SUPPLY_RANGE if not is_dead and not _going_home and dest < 0 else 0.0


func cargo_left() -> int:
	var total := 0
	for key in cargo:
		total += int(cargo[key])
	return total


func escort() -> Player:
	for node in get_tree().get_nodes_in_group(&"players"):
		if (node as Player).peer_id == owner_peer:
			return node
	return null


func _move_anim(_strength: float) -> String:
	return "walk"


## Pets have no attack / hit clips: missing ones are skipped.
func _play_action_local(anim_name: String, duration: float, release_arms: int) -> void:
	if anim and anim.has_animation(anim_name):
		super(anim_name, duration, release_arms)
	else:
		_action_time = duration
		_full_body_action = false


func _can_hit(_target: Object) -> bool:
	return false


# --- Server ------------------------------------------------------------------------

func _get_move_input(delta: float) -> Vector3:
	if not multiplayer.is_server():
		return Vector3.ZERO
	if not _going_home and dest >= 0:
		return _deliver(delta)
	var hero := escort()
	if not _going_home and (cargo_left() <= 0 or hero == null or hero.is_dead):
		_going_home = true
	if _going_home:
		return _go_home(delta)
	return _drive_to(hero.global_position, FOLLOW_DISTANCE, delta)


func _logistics() -> LogisticsManager:
	return get_tree().get_first_node_in_group(&"logistics") as LogisticsManager


func _place(i: int) -> TerritoryNode:
	var logistics := _logistics()
	if logistics == null or i < 0 or i >= logistics.mode.territories.size():
		return null
	return logistics.mode.territories[i]


## To the place it carries goods to; there they go into its store (what does not fit rides home again).
func _deliver(delta: float) -> Vector3:
	var place := _place(dest)
	if place == null or place.state != TerritoryNode.State.OWNED or place.owner_team != team_id:
		_going_home = true
		return Vector3.ZERO
	var to := place.global_position - global_position
	to.y = 0.0
	if to.length() < place.radius() * 0.7:
		cargo = _logistics().unload(place, cargo)
		_going_home = true
		return Vector3.ZERO
	return _drive_to(place.global_position, 0.0, delta)


## Toward `goal` along the navigation path (straight while there is none); stops within `arrive`.
func _drive_to(goal: Vector3, arrive: float, delta: float) -> Vector3:
	var to := goal - global_position
	to.y = 0.0
	if to.length() <= arrive:
		return Vector3.ZERO
	if _nav == null:
		_nav = NavigationAgent3D.new()
		_nav.radius = radius
		_nav.path_desired_distance = 1.0
		_nav.target_desired_distance = 0.8
		add_child(_nav)
	if _nav.target_position.distance_to(goal) > 1.0:
		_nav.target_position = goal
	var step := to
	var next := _nav.get_next_path_position() - global_position
	next.y = 0.0
	if next.length() > 0.05 and not _nav.is_navigation_finished():
		step = next
	return steer(step.normalized(), delta)


## Back to its own place (or, lost to another holder, the nearest held one of its faction); there it hands back
## the rest, is a courier at home again and leaves the map.
func _go_home(delta: float) -> Vector3:
	var target: TerritoryNode = _place(home)
	if target == null or target.state != TerritoryNode.State.OWNED or target.owner_team != team_id:
		target = null
		for node in get_tree().get_nodes_in_group(&"territories"):
			var territory := node as TerritoryNode
			if territory.owner_team == team_id and territory.state == TerritoryNode.State.OWNED and (target == null or
					territory.global_position.distance_to(global_position) < target.global_position.distance_to(global_position)):
				target = territory
	if target == null:
		return Vector3.ZERO  # nowhere to go: it waits (and can still be looted)
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length() < maxf(HOME_DISTANCE, target.radius() * 0.6):
		var logistics := _logistics()
		if logistics:
			logistics.unload(target, cargo)
			logistics.courier_home(target, home)
		cargo.clear()
		# Leaves like a unit that died (AI holding it as a target sees is_dead before the node is freed).
		_retired = true
		die()
		return Vector3.ZERO
	return _drive_to(target.global_position, 0.0, delta)


func _on_died() -> void:
	remove_from_group(&"player_units")
	remove_from_group(&"conquest_supply")
	if not multiplayer.is_server() or _retired:
		return
	var looter := last_attacker_peer
	var logistics := _logistics()
	if logistics:
		logistics.courier_lost(home)
	if logistics:
		for key in cargo:
			logistics.note(team_id, key, "Caravans lost", -int(cargo[key]))
	if looter != 0 and Net.team_of(looter) != team_id and logistics:
		logistics.store(Net.team_of(looter), cargo, global_position, "Looted caravans")
		logistics.mode.announce("{team:%d} looted a caravan of {team:%d}!" % [Net.team_of(looter), team_id])
	else:
		Pickup.drop(get_parent(), global_position, Pickup.Kind.COIN, SPILL_COINS)
	cargo.clear()


func _death_visuals() -> void:
	collision_layer = 0
	collision_mask = 0
	_health_bar.hide()
	if anim:
		anim.pause()
	var tween := create_tween()
	tween.tween_property(model, "rotation:z", PI * 0.5, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	HitFx.flash(global_position + Vector3(0, 0.4, 0), HitFx.DEATH_SMOKE, Color(0.85, 0.85, 0.8, 0.8), 1.2, 0.6,
			Vector2(0.5, 1.3), false)

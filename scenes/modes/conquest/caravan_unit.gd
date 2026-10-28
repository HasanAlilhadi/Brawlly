class_name CaravanUnit
extends Unit
## Conquest: a pack animal (a cow with crates) that carries supplies from a held territory to a hero's army in
## the field. LogisticsManager sends one (NetSpawn kind `caravan`, with "cargo" and the escorted hero as owner)
## when soldiers are out of every supply point's reach; it walks behind the hero and is a supply point itself
## (group `conquest_supply`): soldiers near it eat, are repaired and refill their quivers from its `cargo` before
## the faction's stockpile. Empty, or its hero gone, it walks back to the nearest held territory and hands back
## what is left. It never fights; monsters and rival factions attack it (group `player_units`). Killed by a rival
## faction, its cargo goes to theirs (looted); killed by monsters, it is lost and spills a few coins.
## Server runs it; clients see position / health through Sync like any unit.

const SCENE_PATH := "res://scenes/modes/conquest/caravan_unit.tscn"
const PET := preload("res://assets/characters/pets/cow.glb")
const PET_SCALE: float = 0.55
## What a caravan sets out with, at most, of each supply (taken from the faction's stockpile).
const CARGO: Dictionary = {&"food": 30, &"equipment": 20, &"ammo": 20}
## Soldiers within this range draw on its cargo.
const SUPPLY_RANGE: float = 9.0
## It keeps this far behind its hero; home means this close to the territory.
const FOLLOW_DISTANCE: float = 4.5
const HOME_DISTANCE: float = 3.0
## Coins spilled when monsters destroy it.
const SPILL_COINS: int = 6

## Supplies on board (same keys as the stockpile; server).
var cargo: Dictionary = {}

var _going_home: bool = false
## Home again: it leaves without loot.
var _retired: bool = false


## main.gd `_spawn_unit`: the caravan for spawn data {"cargo": {...}} (every peer).
static func create(data: Dictionary) -> CaravanUnit:
	var caravan := (load(SCENE_PATH) as PackedScene).instantiate() as CaravanUnit
	caravan.cargo = data.get("cargo", {}).duplicate()
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


func supply_range() -> float:
	return SUPPLY_RANGE if not is_dead and not _going_home else 0.0


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
	var hero := escort()
	if not _going_home and (cargo_left() <= 0 or hero == null or hero.is_dead):
		_going_home = true
	if _going_home:
		return _go_home(delta)
	var to := hero.global_position - global_position
	to.y = 0.0
	if to.length() < FOLLOW_DISTANCE:
		return Vector3.ZERO
	return steer(to.normalized(), delta)


## Back to the nearest held territory of its faction; there it hands back the rest and leaves the map.
func _go_home(delta: float) -> Vector3:
	var home := Vector3.INF
	for node in get_tree().get_nodes_in_group(&"territories"):
		var territory := node as TerritoryNode
		if territory.owner_team == team_id and (home == Vector3.INF or
				territory.global_position.distance_to(global_position) < home.distance_to(global_position)):
			home = territory.global_position
	if home == Vector3.INF:
		return Vector3.ZERO  # nowhere to go: it waits (and can still be looted)
	var to := home - global_position
	to.y = 0.0
	if to.length() < HOME_DISTANCE:
		var logistics := get_tree().get_first_node_in_group(&"logistics") as LogisticsManager
		if logistics:
			logistics.store(team_id, cargo)
		cargo.clear()
		# Leaves like a unit that died (AI holding it as a target sees is_dead before the node is freed).
		_retired = true
		die()
		return Vector3.ZERO
	return steer(to.normalized(), delta)


func _on_died() -> void:
	remove_from_group(&"player_units")
	remove_from_group(&"conquest_supply")
	if not multiplayer.is_server() or _retired:
		return
	var looter := last_attacker_peer
	var logistics := get_tree().get_first_node_in_group(&"logistics") as LogisticsManager
	if looter != 0 and Net.team_of(looter) != team_id and logistics:
		logistics.store(Net.team_of(looter), cargo)
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

class_name AnimalHerd
extends Node3D
## A group of one animal species hanging around its home (this node's position; built identically on every
## peer by WorldBuilder, group `herds`). The server spawns its animals when the match starts (`start()`) and,
## once they are all gone, a new group RESPAWN_TIME later — but only while no hero is close enough to see it pop
## in (RESPAWN_CLEAR).

const RESPAWN_TIME: float = 60.0
const RESPAWN_CLEAR: float = 22.0
## Group sizes per species (min, max).
const SIZES: Dictionary = {"pig": Vector2i(2, 5), "cow": Vector2i(2, 4), "deer": Vector2i(2, 4),
		"fox": Vector2i(1, 3), "hog": Vector2i(1, 3)}

## Set by WorldBuilder before entering the tree.
var species: String = "pig"
var size: int = 3

var _animals: Array[Animal] = []
var _started: bool = false
var _respawn_left: float = 0.0


func _ready() -> void:
	add_to_group(&"herds")
	set_process(false)


## Server: spawn the group (main.gd when the match starts).
func start() -> void:
	if _started or not multiplayer.is_server():
		return
	_started = true
	_spawn_group()
	set_process(true)


func _process(delta: float) -> void:
	_animals = alive()
	if not _animals.is_empty():
		_respawn_left = RESPAWN_TIME
		return
	_respawn_left -= delta
	if _respawn_left <= 0.0 and not _hero_near():
		_spawn_group()


func _spawn_group() -> void:
	_respawn_left = RESPAWN_TIME
	for i in size:
		var angle := TAU * i / float(size) + randf_range(-0.4, 0.4)
		var at := GameConfig.clamp_to_world(global_position + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(0.8, 2.2))
		var animal := NetSpawn.unit(&"animal", at, {"species": species, "home": global_position}) as Animal
		if animal:
			_animals.append(animal)


func _hero_near() -> bool:
	for player in get_tree().get_nodes_in_group(&"players"):
		if (player as Node3D).global_position.distance_to(global_position) < RESPAWN_CLEAR:
			return true
	return false


## The herd's animals still alive.
func alive() -> Array[Animal]:
	var result: Array[Animal] = []
	for animal in _animals:
		if is_instance_valid(animal) and not animal.is_dead:
			result.append(animal)
	return result

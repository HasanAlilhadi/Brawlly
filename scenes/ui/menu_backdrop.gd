extends Node3D
## Main-menu background: a small camp diorama (house, orcs, soldiers, the archer, trees)
## with a camera slowly circling it. Characters are the real unit scenes with their AI off.

const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const ALLY_SCENE := preload("res://scenes/characters/ally.tscn")
const ORC_SCENES: Array[PackedScene] = [
	preload("res://scenes/characters/enemy.tscn"),
	preload("res://scenes/characters/enemy_swordsman.tscn"),
	preload("res://scenes/characters/enemy_thrower.tscn"),
]
const GIANT_SCENE := preload("res://scenes/characters/enemy_giant.tscn")
const STRUCTURE := preload("res://assets/environment/forest/building_structure.glb")
const ROOF := preload("res://assets/environment/forest/building_roof.glb")
const BANNER := preload("res://assets/environment/dungeon/banner.glb")
const TREES: Array[PackedScene] = [
	preload("res://assets/environment/forest/tree.glb"),
	preload("res://assets/environment/forest/tree_high.glb"),
]
const DECOR: Array[PackedScene] = [
	preload("res://assets/environment/forest/patch_grass.glb"),
	preload("res://assets/environment/forest/plant.glb"),
	preload("res://assets/environment/forest/stones.glb"),
]

## Camera circles `center` from high up, so the view only ever shows ground (no sky / horizon).
@export var orbit_radius: float = 7.0
@export var orbit_height: float = 10.0
@export var orbit_speed: float = 0.08
@export var center: Vector3 = Vector3(0, 0.5, 0.6)
## Aim this far past the camp toward the camera, so the camp sits above the menu panel.
@export var aim_offset: float = 2.6
## Moves the view sideways (negative = the camp appears further right), e.g. to leave room for a side menu.
@export var view_shift: float = 0.0:
	set(value):
		view_shift = value
		if _camera:
			_camera.h_offset = value

var _angle: float = 0.6

@onready var _camera: Camera3D = $Camera


func _ready() -> void:
	FollowCamera3D.fit_fov_to_short_side(_camera)
	get_viewport().size_changed.connect(func() -> void: FollowCamera3D.fit_fov_to_short_side(_camera))
	_build_house(Vector3(0, 0, -2.2))
	# Orcs guarding the house, soldiers facing them, the archer in front.
	var orc_spots := [Vector3(-2.0, 0, -0.2), Vector3(-0.7, 0, 0.3), Vector3(0.7, 0, 0.2), Vector3(2.0, 0, -0.3)]
	for i in orc_spots.size():
		_add_unit(ORC_SCENES[i % ORC_SCENES.size()], orc_spots[i], Vector3(0, 0, 1))
	_add_unit(GIANT_SCENE, Vector3(2.9, 0, -2.4), Vector3(-0.3, 0, 1))
	for x in [-1.6, 0.0, 1.6]:
		_add_unit(ALLY_SCENE, Vector3(x, 0, 2.6), Vector3(0, 0, -1))
	_add_unit(PLAYER_SCENE, Vector3(0.2, 0, 3.8), Vector3(0, 0, -1))
	for i in 90:
		var angle := randf() * TAU
		var tree := (TREES.pick_random() as PackedScene).instantiate() as Node3D
		tree.position = Vector3(cos(angle), 0, sin(angle)) * randf_range(6.5, 34.0)
		tree.rotation.y = randf() * TAU
		tree.scale = Vector3.ONE * randf_range(1.0, 1.5)
		add_child(tree)
	for i in 220:
		var decor := (DECOR.pick_random() as PackedScene).instantiate() as Node3D
		decor.position = Vector3(randf_range(-30, 30), 0, randf_range(-30, 30))
		decor.rotation.y = randf() * TAU
		add_child(decor)


func _process(delta: float) -> void:
	_angle += orbit_speed * delta
	var toward_camera := Vector3(sin(_angle), 0, cos(_angle))
	_camera.position = center + toward_camera * orbit_radius + Vector3(0, orbit_height, 0)
	_camera.look_at(center + toward_camera * aim_offset, Vector3.UP)


func _build_house(at: Vector3) -> void:
	var house := Node3D.new()
	house.position = at
	add_child(house)
	var structure := STRUCTURE.instantiate() as Node3D
	structure.scale = Vector3.ONE * 1.9
	house.add_child(structure)
	var roof := ROOF.instantiate() as Node3D
	roof.scale = Vector3.ONE * 1.9
	roof.position.y = 1.9
	house.add_child(roof)
	var banner := BANNER.instantiate() as Node3D
	banner.scale = Vector3(-1.3, 1.3, -1.3)
	banner.position = Vector3(0, 0.3, 0.35)
	house.add_child(banner)


func _add_unit(scene: PackedScene, at: Vector3, facing: Vector3) -> void:
	var unit := scene.instantiate() as Unit
	# Decoration only: no network sync (the lobby is online while this backdrop shows).
	var sync := unit.get_node_or_null("Sync")
	if sync:
		unit.remove_child(sync)
		sync.free()
	unit.position = at
	add_child(unit)
	# Scenery only: no AI, no collisions, no groups the game would pick up.
	unit.set_physics_process(false)
	unit.collision_layer = 0
	unit.collision_mask = 0
	for group in unit.get_groups():
		unit.remove_from_group(group)
	unit.face_now(facing)
	unit.play_anim("idle", 0.0)
	unit.anim.seek(randf() * 1.0, true)

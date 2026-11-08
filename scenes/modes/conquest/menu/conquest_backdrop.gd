class_name ConquestBackdrop
extends Node3D
## Conquest pages' background (instead of the classic camp): the Demon's Lair at a blood-red dusk — Malakor on a
## dais between fire baskets and obelisks, his four risen champions before him, demons around, crooked pines and
## gravestones in red fog — with a camera slowly circling it. Everything is built in code; characters are the real
## enemy scenes with their AI and syncing off.

const MALAKOR := preload("res://scenes/characters/enemies/malakor.tscn")
const CHAMPIONS: Array[PackedScene] = [
	preload("res://scenes/characters/enemies/lieutenant_blade.tscn"),
	preload("res://scenes/characters/enemies/lieutenant_marksman.tscn"),
	preload("res://scenes/characters/enemies/lieutenant_warlock.tscn"),
	preload("res://scenes/characters/enemies/lieutenant_mender.tscn"),
]
const DEMONS: Array[PackedScene] = [
	preload("res://scenes/characters/enemies/skeleton_warrior.tscn"),
	preload("res://scenes/characters/enemies/zombie.tscn"),
	preload("res://scenes/characters/enemies/vampire.tscn"),
	preload("res://scenes/characters/enemies/skeleton_archer.tscn"),
	preload("res://scenes/characters/enemies/orc_brute.tscn"),
	preload("res://scenes/characters/enemies/necromancer.tscn"),
]
const KIT := "res://assets/environment/graveyard/%s.glb"
const KIT_SCALE: float = 1.5

@export var orbit_radius: float = 8.5
@export var orbit_height: float = 5.2
## Radians the orbit swings to either side of the front (it never goes behind the King).
@export var orbit_swing: float = 0.7
@export var orbit_speed: float = 0.12
@export var center: Vector3 = Vector3(0, 2.2, -0.6)
@export var aim_offset: float = 0.0
## Moves the view sideways (negative = the scene appears further right), e.g. to leave room for a side menu.
@export var view_shift: float = 0.0:
	set(value):
		view_shift = value
		if _camera:
			_camera.h_offset = value

var _angle: float = 0.0
var _camera: Camera3D
var _flames: Array[OmniLight3D] = []
var _time: float = 0.0
var _units: Array[Unit] = []


func _ready() -> void:
	_build_sky()
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.current = true
	add_child(_camera)
	_camera.h_offset = view_shift
	FollowCamera3D.fit_fov_to_short_side(_camera)
	get_viewport().size_changed.connect(func() -> void: FollowCamera3D.fit_fov_to_short_side(_camera))
	var rng := RandomNumberGenerator.new()
	rng.seed = 666
	_build_lair()
	# The King on his dais, his champions on the steps before him, the horde around.
	_add_unit(MALAKOR, Vector3(0, 0.0, -1.6), Vector3(0, 0, 1), 1.6)
	var champion_spots := [Vector3(-2.6, 0, 0.6), Vector3(-0.9, 0, 1.4), Vector3(0.9, 0, 1.4), Vector3(2.6, 0, 0.6)]
	for i in CHAMPIONS.size():
		_add_unit(CHAMPIONS[i], champion_spots[i], Vector3(0, 0, 1), 1.0)
	for i in 22:
		var angle := rng.randf_range(-PI * 0.95, PI * 0.95) + PI * 0.5
		var distance := rng.randf_range(4.6, 9.0)
		var spot := Vector3(cos(angle), 0, sin(angle)) * distance
		_add_unit(DEMONS[i % DEMONS.size()], spot, -spot.normalized() + Vector3(0, 0, 0.6), 1.0)
	for i in 60:
		var angle := rng.randf() * TAU
		_kit("pine_crooked" if i % 3 else "pine", Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(11.0, 30.0),
				rng.randf() * TAU, KIT_SCALE * rng.randf_range(1.0, 1.6))
	for i in 46:
		var angle := rng.randf() * TAU
		var stone: String = ["gravestone_cross", "gravestone_broken", "gravestone_round", "grave", "debris", "rocks"][i % 6]
		_kit(stone, Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(6.0, 14.0), rng.randf() * TAU, KIT_SCALE)


func _process(delta: float) -> void:
	_time += delta
	_angle = sin(_time * orbit_speed) * orbit_swing  # sways in front of the King
	var toward_camera := Vector3(sin(_angle), 0, cos(_angle))
	_camera.position = center + toward_camera * orbit_radius + Vector3(0, orbit_height, 0)
	_camera.look_at(center + toward_camera * aim_offset, Vector3.UP)
	if _time < 2.0:
		_hide_labels()  # boss names / health bars some units add a moment after they enter the tree
	for i in _flames.size():
		_flames[i].light_energy = 2.4 + sin(_time * 9.0 + i * 1.7) * 0.35 + sin(_time * 23.0 + i) * 0.2


func _build_sky() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("1a0607")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("5a2a30")
	environment.ambient_light_energy = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("4a0d0d")
	environment.fog_density = 0.035
	environment.glow_enabled = true
	environment.glow_intensity = 0.9
	environment.glow_bloom = 0.15
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color("ff7a5c")
	moon.light_energy = 0.85
	moon.rotation_degrees = Vector3(-48, 35, 0)
	moon.shadow_enabled = true
	add_child(moon)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, 90)
	var earth := StandardMaterial3D.new()
	earth.albedo_color = Color("2a1d1c")
	earth.roughness = 1.0
	plane.material = earth
	ground.mesh = plane
	add_child(ground)


## The dais: a raised dark slab with steps, obelisks at the corners, fire baskets and candles that flicker.
func _build_lair() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("3a3234")
	stone.roughness = 0.9
	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(5.6, 0.05, 4.2)
	box.material = stone
	slab.mesh = box
	slab.position = Vector3(0, 0.025, -1.4)
	add_child(slab)
	var blood := StandardMaterial3D.new()
	blood.albedo_color = Color("5c0d0d")
	blood.emission_enabled = true
	blood.emission = Color("7a0f0f")
	blood.emission_energy_multiplier = 0.6
	var carpet := MeshInstance3D.new()
	var strip := BoxMesh.new()
	strip.size = Vector3(1.4, 0.06, 7.0)
	strip.material = blood
	carpet.mesh = strip
	carpet.position = Vector3(0, 0.03, 1.2)
	add_child(carpet)
	for x in [-3.4, 3.4]:
		for z in [-3.2, 1.2]:
			_kit("pillar_obelisk", Vector3(x, 0, z), 0.0, KIT_SCALE)
	for spot in [Vector3(-1.9, 0, 3.2), Vector3(1.9, 0, 3.2), Vector3(-4.2, 0, -0.9), Vector3(4.2, 0, -0.9)]:
		_kit("fire_basket", spot, 0.0, KIT_SCALE)
		var flame := OmniLight3D.new()
		flame.light_color = Color("ff5a24")
		flame.omni_range = 6.5
		flame.position = spot + Vector3(0, 1.4, 0)
		add_child(flame)
		_flames.append(flame)
	for i in 10:
		var angle := TAU * i / 10.0
		_kit("candle_multiple", Vector3(cos(angle) * 5.4, 0, sin(angle) * 4.2 - 0.6), angle, KIT_SCALE)
	_kit("crypt_large", Vector3(0, 0, -6.8), 0.0, KIT_SCALE)


func _kit(piece: String, at: Vector3, yaw: float, size: float) -> void:
	var scene := load(KIT % piece) as PackedScene
	if scene == null:
		return
	var node := scene.instantiate() as Node3D
	node.position = at
	node.rotation.y = yaw
	node.scale = Vector3.ONE * size
	add_child(node)


func _add_unit(scene: PackedScene, at: Vector3, facing: Vector3, size: float) -> void:
	var unit := scene.instantiate() as Unit
	# Decoration only: no network sync (the lobby is online while this backdrop shows), no AI, no collisions.
	var sync := unit.get_node_or_null("Sync")
	if sync:
		unit.remove_child(sync)
		sync.free()
	unit.position = at
	add_child(unit)
	unit.scale *= size
	unit.set_physics_process(false)
	unit.set_process(false)
	for child in unit.get_children():
		if child is EnemyComponent:
			child.process_mode = Node.PROCESS_MODE_DISABLED
	unit.collision_layer = 0
	unit.collision_mask = 0
	for group in unit.get_groups():
		unit.remove_from_group(group)
	_units.append(unit)
	unit.face_now(facing.normalized() if facing.length() > 0.01 else Vector3(0, 0, 1))
	unit.play_anim("idle", 0.0)
	if unit.anim and unit.anim.has_animation("idle"):
		unit.anim.seek(randf() * 1.0, true)


## No names, alerts or health bars over the scenery.
func _hide_labels() -> void:
	for unit in _units:
		for label in unit.find_children("*", "Label3D", true, false):
			(label as Label3D).hide()
		for bar in unit.find_children("*", "HealthBar3D", true, false):
			(bar as Node3D).hide()

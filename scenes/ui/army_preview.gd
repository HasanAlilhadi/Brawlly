class_name ArmyPreview
extends SubViewportContainer
## Small 3D preview of the archer and two soldiers in a player color (used next to the color picker).
## Each figure slowly turns in place.
## Uses the real unit scenes with AI, networking and groups removed. Call `set_color()`.

const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const ALLY_SCENE := preload("res://scenes/characters/ally.tscn")

@export var turn_speed: float = 0.45

var _viewport: SubViewport
var _pivot: Node3D
var _color: Color = Color.RED


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.9, 0.9, 1.0)
	environment.ambient_light_energy = 0.7
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_energy = 1.1
	_viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 28.0
	_viewport.add_child(camera)
	camera.position = Vector3(0, 1.7, 3.4)
	camera.look_at(Vector3(0, 0.5, 0), Vector3.UP)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_rebuild()


func set_color(color: Color) -> void:
	_color = color
	if is_node_ready():
		_rebuild()


func _process(delta: float) -> void:
	if _pivot == null:
		return
	for unit in _pivot.get_children():
		if unit is Unit and not unit.is_queued_for_deletion():
			(unit as Unit).model.rotation.y += turn_speed * delta


func _rebuild() -> void:
	for child in _pivot.get_children():
		child.queue_free()
	_add(PLAYER_SCENE, Vector3(0, 0, 0.45), 0.0)
	_add(ALLY_SCENE, Vector3(-0.95, 0, -0.25), 0.6)
	_add(ALLY_SCENE, Vector3(0.95, 0, -0.25), -0.6)


func _add(scene: PackedScene, at: Vector3, yaw: float) -> void:
	var unit := scene.instantiate() as Unit
	var sync := unit.get_node_or_null("Sync")
	if sync:
		unit.remove_child(sync)
		sync.free()
	unit.unit_color = _color
	unit.position = at
	_pivot.add_child(unit)
	unit.set_physics_process(false)
	unit.collision_layer = 0
	unit.collision_mask = 0
	for group in unit.get_groups():
		unit.remove_from_group(group)
	unit.model.rotation.y = yaw
	unit.play_anim("idle", 0.0)

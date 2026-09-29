class_name Hill
extends Node3D
## King of the Hill zone in the middle of the map. Every second, if players of exactly one team stand
## inside, that team scores a point. The zone shows the controlling team's color (yellow = contested).
## Server runs the rules; every peer shows the color via `_net_state`.

const RADIUS: float = 7.0
const NEUTRAL := Color(0.9, 0.9, 0.9)
const CONTESTED := Color(1.0, 0.85, 0.2)

var game_mode: GameMode
## Team holding the hill (-1 = nobody, -2 = contested).
var holder: int = -1

var _tick: float = 1.0
var _material: StandardMaterial3D
var _ring: MeshInstance3D


func _ready() -> void:
	add_to_group(&"hill")
	position = Vector3.ZERO
	var disc := CylinderMesh.new()
	disc.top_radius = RADIUS
	disc.bottom_radius = RADIUS
	disc.height = 0.04
	disc.radial_segments = 48
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc.material = _material
	var zone := MeshInstance3D.new()
	zone.mesh = disc
	zone.position.y = 0.03
	zone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(zone)
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS - 0.25
	torus.outer_radius = RADIUS
	torus.rings = 64
	torus.material = _material
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.scale = Vector3(1, 0.3, 1)
	_ring.position.y = 0.05
	add_child(_ring)
	_apply_color()


func _process(delta: float) -> void:
	_ring.rotation.y += delta * 0.4
	if not multiplayer.is_server() or game_mode.is_over:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0
	var teams := {}
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if not GameConfig.is_gone(player) and player.global_position.distance_to(global_position) < RADIUS:
			teams[player.team_id] = true
	var new_holder := -1
	if teams.size() == 1:
		new_holder = teams.keys()[0]
		game_mode.add_score(new_holder, 1)
	elif teams.size() > 1:
		new_holder = -2
	if new_holder != holder:
		_net_state.rpc(new_holder)


@rpc("authority", "call_local", "reliable")
func _net_state(new_holder: int) -> void:
	holder = new_holder
	_apply_color()


func _apply_color() -> void:
	var color := NEUTRAL
	if holder == -2:
		color = CONTESTED
	elif holder >= 0 and holder < Net.TEAM_COLORS.size():
		color = Net.TEAM_COLORS[holder]
	_material.albedo_color = Color(color, 0.3)

class_name HoldCircle
extends Node3D
## Last Stand: the circle the heroes must hold (one node, moved by GameMode from circle to circle). Every peer
## shows it: a ground disc + edge ring in its state color, a progress ring filling around the edge, a beam of light
## so it is easy to find, and a label ("Circle 3 / 10", "2 / 3 heroes"). Joins `tracked` (screen-edge arrow +
## minimap diamond) and `hold_circles` (drawn at its real size on the minimap).

const RADIUS: float = 7.0
## Waiting for heroes / enough heroes inside (the clock runs) / heroes inside, but too few.
const IDLE := Color(1.0, 0.84, 0.3)
const HOLDING := Color(0.45, 1.0, 0.5)
const SHORT := Color(1.0, 0.45, 0.3)
const FLAG_ICON := preload("res://assets/ui/icons/game/flag.svg")

var index: int = 0
var total: int = 10
var required: int = 1
var inside: int = 0
## 0..1 of the current circle held.
var progress: float = 0.0

var _material: StandardMaterial3D
var _beam_material: StandardMaterial3D
var _progress_material: StandardMaterial3D
var _ring: MeshInstance3D
var _progress_mesh := ImmediateMesh.new()
var _drawn_progress: float = -1.0
var _label: Label3D
var _pulse: float = 0.0


func _ready() -> void:
	add_to_group(&"hold_circles")
	add_to_group(&"tracked")
	set_meta(&"marker_icon", FLAG_ICON)
	_material = _unshaded(true)
	var disc := CylinderMesh.new()
	disc.top_radius = RADIUS
	disc.bottom_radius = RADIUS
	disc.height = 0.04
	disc.radial_segments = 48
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
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_progress_material = _unshaded(false)
	var progress_ring := MeshInstance3D.new()
	progress_ring.mesh = _progress_mesh
	progress_ring.material_override = _progress_material
	progress_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(progress_ring)
	# A soft beam of light over the middle: visible from far away (the camera looks down steeply).
	_beam_material = _unshaded(true)
	_beam_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.9
	beam_mesh.bottom_radius = 0.45
	beam_mesh.height = 14.0
	beam_mesh.radial_segments = 16
	beam_mesh.cap_top = false
	beam_mesh.cap_bottom = false
	beam_mesh.material = _beam_material
	var beam := MeshInstance3D.new()
	beam.mesh = beam_mesh
	beam.position.y = 7.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 54
	_label.outline_size = 14
	_label.pixel_size = 0.008
	_label.position = Vector3(0, 0.4, 0)
	_label.offset = Vector2(0, 90)
	_label.render_priority = 3  # over the disc and the beam (both transparent)
	_label.outline_render_priority = 2
	add_child(_label)
	show_state(index, total, required, inside, progress)


func _unshaded(transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func holding() -> bool:
	return inside >= required and inside > 0


func state_color() -> Color:
	if holding():
		return HOLDING
	return SHORT if inside > 0 else IDLE


## Every peer: the circle's state from the server (GameMode).
func show_state(new_index: int, new_total: int, new_required: int, new_inside: int, new_progress: float) -> void:
	index = new_index
	total = new_total
	required = new_required
	inside = new_inside
	progress = new_progress
	if _material == null:
		return
	var color := state_color()
	_material.albedo_color = Color(color, 0.26)
	_beam_material.albedo_color = Color(color, 0.18)
	_progress_material.albedo_color = color.lightened(0.2)
	_label.text = "Circle %d / %d\n%d / %d %s" % [index + 1, total, inside, required, "hero" if required == 1 else "heroes"]
	_label.modulate = color.lightened(0.25)
	_label.outline_modulate = Color(color.darkened(0.85), 1.0)
	set_meta(&"marker_color", color)
	set_meta(&"marker_label", "Circle %d" % (index + 1))
	set_progress(progress)


## Every peer, every frame: the ring fills as the circle is held (the label / colors come from `show_state`).
func set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	if absf(progress - _drawn_progress) > 0.004 or (progress == 0.0 and _drawn_progress > 0.0):
		_draw_progress()


func _process(delta: float) -> void:
	_ring.rotation.y += delta * 0.4
	_pulse += delta
	if holding():
		_ring.scale = Vector3(1.0 + 0.02 * sin(_pulse * 6.0), 0.3, 1.0 + 0.02 * sin(_pulse * 6.0))


## The held share as a band just inside the edge, clockwise from the top.
func _draw_progress() -> void:
	_drawn_progress = progress
	_progress_mesh.clear_surfaces()
	if progress <= 0.0:
		return
	var segments := maxi(ceili(96 * progress), 2)
	_progress_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in segments + 1:
		var angle := -PI * 0.5 + TAU * progress * i / segments
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		_progress_mesh.surface_add_vertex(dir * (RADIUS - 0.95) + Vector3(0, 0.07, 0))
		_progress_mesh.surface_add_vertex(dir * (RADIUS - 0.3) + Vector3(0, 0.07, 0))
	_progress_mesh.surface_end()

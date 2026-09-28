class_name PingMarker
extends Node3D
## A teammate's ping in the world: a light beam, a pulsing ring on the ground and a label
## ("Attack!", "Help!"…) with the pinger's name. Fades out after `LIFETIME`; while it lasts it shows on
## the minimap and as an off-screen arrow (group "tracked"). Purely visual (created on each peer).

const LIFETIME: float = 5.0

var _age: float = 0.0
var _ring: MeshInstance3D
var _beam_material: StandardMaterial3D
var _label: Label3D


static func spawn(parent: Node3D, at: Vector3, text: String, color: Color, pinger: String) -> PingMarker:
	var marker := PingMarker.new()
	marker.set_meta(&"marker_color", color)
	marker.set_meta(&"marker_label", "%s: %s" % [pinger, text])
	parent.add_child(marker)
	marker.global_position = Vector3(at.x, 0.0, at.z)
	marker._build(text, color, pinger)
	return marker


func _build(text: String, color: Color, pinger: String) -> void:
	add_to_group(&"tracked")
	add_to_group(&"pings")
	var beam := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.05
	cylinder.bottom_radius = 0.12
	cylinder.height = 3.2
	_beam_material = _material(Color(color, 0.45))
	cylinder.material = _beam_material
	beam.mesh = cylinder
	beam.position.y = 1.6
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.7
	torus.material = _material(Color(color, 0.8))
	_ring.mesh = torus
	_ring.scale = Vector3(1, 0.1, 1)
	_ring.position.y = 0.05
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_label = Label3D.new()
	_label.text = "%s\n%s" % [text, pinger]
	_label.font_size = 56
	_label.outline_size = 14
	_label.pixel_size = 0.006
	_label.modulate = color.lightened(0.25)
	_label.outline_modulate = Color(0.08, 0.04, 0.0, 0.95)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position.y = 3.5
	add_child(_label)


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	var pulse := fmod(_age * 1.6, 1.0)
	_ring.scale = Vector3(1.0 + pulse * 1.2, 0.1, 1.0 + pulse * 1.2)
	var fade := clampf((LIFETIME - _age) / 1.0, 0.0, 1.0)
	_label.modulate.a = fade
	_beam_material.albedo_color.a = 0.45 * fade


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	return material

extends MeshInstance3D
## Look of the sword wave (Wave upgrade): a flat glowing crescent bulging forward (-Z, the projectile's flight
## direction), lying a little tilted so the steep game camera sees it. Grows slightly and fades over the flight.
## Not additive: a glow would vanish on light ground.

const SEGMENTS := 16
const RADIUS: float = 0.95
const WIDTH: float = 0.42
const HALF_ARC: float = 65.0
const COLOR := Color(0.45, 0.8, 1.0)

var _material := StandardMaterial3D.new()
var _age: float = 0.0
var _lifetime: float = 0.4


func _ready() -> void:
	var parent := get_parent()
	if parent and parent.get("lifetime") != null:
		_lifetime = float(parent.get("lifetime"))
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.vertex_color_use_as_albedo = true
	_material.albedo_color = COLOR
	var crescent := ImmediateMesh.new()
	crescent.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _material)
	for i in SEGMENTS + 1:
		var t := float(i) / SEGMENTS
		var a := deg_to_rad(lerpf(-HALF_ARC, HALF_ARC, t))
		var taper := sin(t * PI)  # thin at the tips, widest in the middle
		var outer := Vector3(sin(a) * RADIUS, 0.0, RADIUS - cos(a) * RADIUS)
		var inner := Vector3(sin(a) * (RADIUS - WIDTH * taper), 0.0, RADIUS - cos(a) * (RADIUS - WIDTH * taper))
		crescent.surface_set_color(Color(1, 1, 1, 0.95 * taper))
		crescent.surface_add_vertex(outer - Vector3(0, 0, RADIUS * 0.15))
		crescent.surface_set_color(Color(1, 1, 1, 0.0))
		crescent.surface_add_vertex(inner + Vector3(0, 0, WIDTH * 0.6) - Vector3(0, 0, RADIUS * 0.15))
	crescent.surface_end()
	mesh = crescent
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rotation.x = deg_to_rad(-20.0)


func _process(delta: float) -> void:
	_age += delta
	var t := clampf(_age / _lifetime, 0.0, 1.0)
	scale = Vector3.ONE * lerpf(0.8, 1.25, t)
	_material.albedo_color = Color(COLOR, 1.0 - t * t)

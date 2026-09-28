class_name HealthBar3D
extends Node3D
## Small health bar floating over a 3D object. Always faces the active camera,
## draws on top of everything, and hides itself while health is full.
## Add as a child, position it above the object, then call `set_ratio(health / max_health)`.

@export var width: float = 0.7
@export var height: float = 0.08
@export var fill_color: Color = Color(0.9, 0.22, 0.2)
@export var hide_when_full: bool = true
## If > 0, the bar also hides this many seconds after the last change (less clutter in crowds).
@export var auto_hide_delay: float = 0.0

static var _materials: Dictionary = {}

var _fill: MeshInstance3D
var _ratio: float = 1.0
var _hide_timer: float = 0.0


func _ready() -> void:
	_make_quad(Color(0, 0, 0, 0.65), Vector2(width + 0.05, height + 0.05), 0)
	_fill = _make_quad(fill_color, Vector2(width, height), 1)
	visible = not hide_when_full


func set_ratio(ratio: float) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	visible = _ratio < 1.0 or not hide_when_full
	_hide_timer = auto_hide_delay
	if _fill:
		_fill.scale.x = maxf(_ratio, 0.001)
		_fill.position.x = -width * (1.0 - _ratio) * 0.5


func _process(delta: float) -> void:
	if auto_hide_delay > 0.0:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			visible = false
			return
	var camera := get_viewport().get_camera_3d()
	if camera:
		global_basis = camera.global_basis


func _make_quad(color: Color, quad_size: Vector2, priority: int) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = quad_size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = quad
	mesh_instance.material_override = _material(color, priority)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	return mesh_instance


static func _material(color: Color, priority: int) -> StandardMaterial3D:
	var key := "%s_%d" % [color.to_html(), priority]
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = color
		material.no_depth_test = true
		material.render_priority = priority
		_materials[key] = material
	return _materials[key]

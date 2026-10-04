extends Node3D
## Animated white Bull Rush wake attached directly to the spearhead.

const WIND_SHADER := preload("res://assets/shaders/rush_wind.gdshader")
const SEGMENTS := 12

var _material: ShaderMaterial
var _active := false
var _age := 0.0
var _wisps: Array[MeshInstance3D] = []
var _wisp_materials: Array[ShaderMaterial] = []


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = WIND_SHADER
	# A bright tapered core hugs the blade, with a narrow wake trailing down the shaft.
	var core := PackedVector3Array()
	for i in SEGMENTS + 1:
		core.append(Vector3(0.0, 0.0, lerpf(0.25, -0.6, float(i) / SEGMENTS)))
	_add_ribbon(core, 0.36, 1.0, _material)
	var cross_core := _add_ribbon(core, 0.2, 0.7, _material)
	cross_core.rotation.z = PI * 0.5
	for side in [-1.0, 1.0]:
		var points := PackedVector3Array()
		for i in SEGMENTS + 1:
			var t := float(i) / SEGMENTS
			points.append(Vector3(side * sin(t * PI) * 0.14,
					0.0, lerpf(0.12, -0.9, t)))
		_add_ribbon(points, 0.05, 0.55, _material)
	# Recycle four small drifting wisps instead of spawning nodes each frame.
	for i in 4:
		var points := PackedVector3Array()
		for j in SEGMENTS + 1:
			points.append(Vector3(0.0, 0.0, -float(j) / SEGMENTS * 0.27))
		var material := _material.duplicate() as ShaderMaterial
		var wisp := _add_ribbon(points, 0.04, 0.65, material)
		wisp.visible = false
		_wisps.append(wisp)
		_wisp_materials.append(material)
	visible = false
	set_process(false)


func set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	_age = 0.0
	visible = active
	set_process(active)
	if active:
		_material.set_shader_parameter("age", 0.0)
		_material.set_shader_parameter("strength", 0.0)
		for wisp in _wisps:
			wisp.visible = false


func _process(delta: float) -> void:
	_age += delta
	_material.set_shader_parameter("age", _age)
	_material.set_shader_parameter("strength", minf(_age / 0.1, 1.0))
	for i in _wisps.size():
		var elapsed := _age - float(i) * 0.1
		_wisps[i].visible = elapsed >= 0.0
		if elapsed < 0.0:
			continue
		var phase := fposmod(elapsed, 0.4) / 0.4
		var side := -1.0 if i % 2 == 0 else 1.0
		_wisps[i].position = Vector3(side * (0.04 + phase * 0.1),
				sin(phase * PI + float(i)) * 0.035, -0.08 - phase * 0.68)
		_wisps[i].scale = Vector3.ONE * (1.0 - phase * 0.45)
		_wisp_materials[i].set_shader_parameter("age", _age + float(i))
		_wisp_materials[i].set_shader_parameter("strength", sin(phase * PI) * (1.0 - phase))


func _add_ribbon(points: PackedVector3Array, width: float, alpha: float,
		material: ShaderMaterial) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, material)
	for i in points.size():
		var tangent := points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]
		var t := float(i) / (points.size() - 1)
		var taper := pow(sin(t * PI), 0.8) * (1.0 - t * 0.65)
		var across := Vector3(tangent.z, 0.0, -tangent.x).normalized() * width * taper * 0.5
		for edge in 2:
			mesh.surface_set_color(Color(1.0, 1.0, 1.0, alpha))
			mesh.surface_set_uv(Vector2(float(i) / (points.size() - 1), float(edge)))
			mesh.surface_add_vertex(points[i] + across * (-1.0 if edge == 0 else 1.0))
	mesh.surface_end()
	var ribbon := MeshInstance3D.new()
	ribbon.mesh = mesh
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ribbon)
	return ribbon

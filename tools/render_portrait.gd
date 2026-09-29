extends SceneTree
## Renders a round head portrait of a character model to a PNG (minimap / HUD icons).
## Needs a window (not --headless):
##   "$G" --path . -s res://tools/render_portrait.gd -- --model=res://assets/characters/orc.glb \
##       --out=res://assets/ui/icons/portraits/warlord.png [--size=128] [--yaw=20] [--zoom=1.0]
## The model plays its "idle" pose; the camera frames the top of its bounding box (Kenney minis: the head).

var _model_path := "res://assets/characters/orc.glb"
var _out := "res://assets/ui/icons/portraits/portrait.png"
var _size := 128
var _yaw := 20.0
var _zoom := 1.0
var _viewport: SubViewport
var _frames := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		if parts.size() < 2:
			continue
		match parts[0]:
			"model": _model_path = parts[1]
			"out": _out = parts[1]
			"size": _size = parts[1].to_int()
			"yaw": _yaw = parts[1].to_float()
			"zoom": _zoom = parts[1].to_float()
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(_size, _size) * 4  # rendered big, scaled down (smooth edges)
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var world := World3D.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.55
	world.environment = environment
	_viewport.world_3d = world
	root.add_child(_viewport)
	var model := (load(_model_path) as PackedScene).instantiate() as Node3D
	model.rotation_degrees.y = _yaw
	_viewport.add_child(model)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player and player.has_animation("idle"):
		player.play("idle")
		player.seek(0.0, true)
	var bounds := _bounds(model)
	# Kenney minis: the head is the top ~45% of the model.
	var head_center := Vector3(bounds.get_center().x, bounds.end.y - bounds.size.y * 0.25, bounds.get_center().z)
	var head_size := maxf(bounds.size.y * 0.5, bounds.size.x * 0.6) / _zoom
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = head_size * 1.1
	_viewport.add_child(camera)
	camera.look_at_from_position(head_center + Vector3(0, head_size * 0.1, 10.0), head_center)
	var light := DirectionalLight3D.new()
	light.light_energy = 1.1
	_viewport.add_child(light)
	light.look_at_from_position(Vector3(2, 3, 4), Vector3.ZERO)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 6:
		return false
	var image := _viewport.get_texture().get_image()
	image.resize(_size, _size, Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGBA8)
	# Round mask (soft 1 px edge) so the icon sits in a circular badge.
	var center := Vector2(_size, _size) * 0.5
	var radius := _size * 0.5
	for y in _size:
		for x in _size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var color := image.get_pixel(x, y)
			color.a *= clampf(radius - d, 0.0, 1.0)
			image.set_pixel(x, y, color)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out.get_base_dir()))
	image.save_png(ProjectSettings.globalize_path(_out))
	print("saved ", _out)
	return true


func _bounds(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var box := mesh.global_transform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

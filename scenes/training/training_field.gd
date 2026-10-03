class_name TrainingField
extends Node3D
## Welcoming local practice area: class gallery, indestructible targets and concise onboarding UI.

const SPAWN_POINT := Vector3(0.0, 0.0, -8.0)
const SWITCH_RANGE: float = 2.2
const ORC_STATION := Vector3(-13.0, 0.0, 4.0)
const ORC_SPAWN_CENTER := Vector3(-8.8, 0.0, 4.0)
const ORC_INTERACT_RANGE: float = 2.6
const ORC_LIMIT: int = 8
const ORC_SCENE := "res://scenes/characters/enemy.tscn"
const TARGET_SCENE := preload("res://scenes/training/training_target.tscn")
const BANNER_SCENE := preload("res://assets/environment/arena/banner.glb")
const WEAPON_RACK_SCENE := preload("res://assets/environment/arena/weapon_rack.glb")
const TREE_SCENE := preload("res://assets/environment/arena/tree.glb")

var _stations: Array[Dictionary] = []
var _prompt_panel: PanelContainer
var _prompt_label: Label
var _nearby_class: StringName = &""
var _nearby_orc_station := false
var _next_orc_slot := 0


func _ready() -> void:
	_build_ground()
	_build_walls()
	_build_gallery()
	_build_targets()
	_build_orc_station()
	_build_decor()
	_build_ui()


func update_player(player: Player) -> void:
	_nearby_class = nearby_class_id(player.global_position) if is_instance_valid(player) else &""
	_nearby_orc_station = is_instance_valid(player) and is_near_orc_station(player.global_position)
	_prompt_panel.visible = _nearby_class != &"" or _nearby_orc_station
	if _nearby_orc_station:
		_prompt_label.text = "F   Spawn Orc  (%d/%d)" % [live_orc_count(), ORC_LIMIT]
	elif _nearby_class != &"":
		var def := ClassDef.find(_nearby_class)
		_prompt_label.text = "F   Play as %s" % def.display_name


func hide_prompt() -> void:
	_nearby_class = &""
	_nearby_orc_station = false
	if _prompt_panel:
		_prompt_panel.hide()


func selected_class_id() -> StringName:
	return _nearby_class


func nearby_class_id(at: Vector3) -> StringName:
	var best: StringName = &""
	var best_distance := SWITCH_RANGE
	for station in _stations:
		var distance: float = Vector2(at.x - station.position.x, at.z - station.position.z).length()
		if distance < best_distance:
			best_distance = distance
			best = station.id
	return best


func is_near_orc_station(at: Vector3) -> bool:
	return Vector2(at.x - ORC_STATION.x, at.z - ORC_STATION.z).length() <= ORC_INTERACT_RANGE


func live_orc_count() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(&"training_orcs"):
		if node is Enemy and not (node as Enemy).is_dead and not node.is_queued_for_deletion():
			count += 1
	return count


## Training-only, server-authoritative. One F press creates one orc; nothing spawns on a timer.
func spawn_orc(player: Player) -> Enemy:
	if not multiplayer.is_server() or not is_instance_valid(player) or not player.training_mode \
			or player.is_dead or not is_near_orc_station(player.global_position) or live_orc_count() >= ORC_LIMIT:
		return null
	for attempt in ORC_LIMIT:
		var slot := (_next_orc_slot + attempt) % ORC_LIMIT
		var angle := TAU * slot / float(ORC_LIMIT)
		var spot := ORC_SPAWN_CENTER + Vector3(cos(angle), 0.0, sin(angle)) * 1.5
		var occupied := false
		for node in get_tree().get_nodes_in_group(&"training_orcs"):
			if node is Enemy and not (node as Enemy).is_dead \
					and (node as Enemy).global_position.distance_to(spot) < 0.9:
				occupied = true
				break
		if occupied:
			continue
		_next_orc_slot = (slot + 1) % ORC_LIMIT
		return NetSpawn.unit(&"enemy", spot, {"scene": ORC_SCENE, "strength": 1.0, "coins": 0.0,
				"training_orc": true}) as Enemy
	return null


func _build_ground() -> void:
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("6fa956")
	ground_material.roughness = 1.0
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(46.0, 40.0)
	ground_mesh.material = ground_material
	var ground := MeshInstance3D.new()
	ground.name = "TrainingGrass"
	ground.mesh = ground_mesh
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

	var path_material := StandardMaterial3D.new()
	path_material.albedo_color = Color("caa66a")
	path_material.roughness = 1.0
	for strip in [Rect2(-2.8, -16.0, 5.6, 31.0), Rect2(-17.0, -2.8, 34.0, 5.6)]:
		var path_mesh := PlaneMesh.new()
		path_mesh.size = strip.size
		path_mesh.material = path_material
		var path := MeshInstance3D.new()
		path.mesh = path_mesh
		path.position = Vector3(strip.position.x + strip.size.x * 0.5, 0.012, strip.position.y + strip.size.y * 0.5)
		path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(path)

	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = GameConfig.LAYER_WORLD
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(46.0, 0.2, 40.0)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.12
	floor_body.add_child(floor_shape)
	add_child(floor_body)


func _build_walls() -> void:
	_add_wall(Vector3(0, 0.55, -19.5), Vector3(46.0, 1.1, 0.7))
	_add_wall(Vector3(0, 0.55, 19.5), Vector3(46.0, 1.1, 0.7))
	_add_wall(Vector3(-22.5, 0.55, 0), Vector3(0.7, 1.1, 40.0))
	_add_wall(Vector3(22.5, 0.55, 0), Vector3(0.7, 1.1, 40.0))


func _add_wall(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = GameConfig.LAYER_WORLD
	body.position = at
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("7b6a55")
	material.roughness = 0.95
	mesh.material = material
	mesh_node.mesh = mesh
	body.add_child(mesh_node)
	add_child(body)


func _build_gallery() -> void:
	_add_section_label("CHOOSE YOUR HERO", Vector3(0, 3.6, -17.1), Color("ffd36b"), 64)
	var classes := ClassDef.all()
	for i in classes.size():
		var def := classes[i]
		var x := (i - (classes.size() - 1) * 0.5) * 5.5
		var at := Vector3(x, 0.0, -13.0)
		_stations.append({"id": def.id, "position": at})
		_add_pedestal(at, def)


func _add_pedestal(at: Vector3, def: ClassDef) -> void:
	var pedestal_body := StaticBody3D.new()
	pedestal_body.collision_layer = GameConfig.LAYER_WORLD
	pedestal_body.position = at + Vector3(0, 0.18, 0)
	var pedestal_collision := CollisionShape3D.new()
	var pedestal_shape := CylinderShape3D.new()
	pedestal_shape.radius = 1.3
	pedestal_shape.height = 0.35
	pedestal_collision.shape = pedestal_shape
	pedestal_body.add_child(pedestal_collision)
	add_child(pedestal_body)

	var pedestal := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.35
	cylinder.bottom_radius = 1.55
	cylinder.height = 0.35
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("695b4b")
	stone.roughness = 0.9
	cylinder.material = stone
	pedestal.mesh = cylinder
	pedestal.position = at + Vector3(0, 0.18, 0)
	add_child(pedestal)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.38
	torus.outer_radius = 1.52
	torus.rings = 36
	torus.ring_segments = 8
	var gold := StandardMaterial3D.new()
	gold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gold.albedo_color = Color("f3bf4b")
	torus.material = gold
	ring.mesh = torus
	ring.position = at + Vector3(0, 0.38, 0)
	ring.scale.y = 0.15
	add_child(ring)

	var preview := def.model.instantiate() as Node3D
	preview.position = at + Vector3(0, 0.35, 0)
	preview.rotation.y = PI
	preview.scale = Vector3.ONE * 1.25
	add_child(preview)
	var animation := preview.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation and animation.has_animation("idle"):
		animation.play("idle")

	var label := Label3D.new()
	label.text = "%s\nF to play" % def.display_name
	label.position = at + Vector3(0, 2.65, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 44
	label.outline_size = 12
	label.pixel_size = 0.006
	label.modulate = Color("fff0bf")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)


func _build_targets() -> void:
	_add_section_label("DAMAGE RANGE", Vector3(14.0, 3.0, -8.0), Color("ffcf72"), 54)
	var positions := [Vector3(10, 0, -5), Vector3(14, 0, -5), Vector3(18, 0, -5),
			Vector3(12, 0, 4), Vector3(17, 0, 7)]
	for i in positions.size():
		var target := TARGET_SCENE.instantiate() as TrainingTarget
		target.position = positions[i]
		target.rotation.y = PI if i < 3 else -PI * 0.5
		target.title = "Range Target" if i < 3 else "Combat Dummy"
		add_child(target)


func _build_orc_station() -> void:
	var base := MeshInstance3D.new()
	base.name = &"OrcPracticeStation"
	var disk := CylinderMesh.new()
	disk.top_radius = 0.95
	disk.bottom_radius = 1.1
	disk.height = 0.18
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("695b4b")
	stone.roughness = 0.9
	disk.material = stone
	base.mesh = disk
	base.position = ORC_STATION + Vector3(0.0, 0.09, 0.0)
	add_child(base)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.83
	torus.outer_radius = 1.02
	var gold := StandardMaterial3D.new()
	gold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gold.albedo_color = Color("f3bf4b")
	torus.material = gold
	ring.mesh = torus
	ring.position = ORC_STATION + Vector3(0.0, 0.2, 0.0)
	ring.scale.y = 0.12
	add_child(ring)
	_add_section_label("ORC PRACTICE\nF to spawn", ORC_STATION + Vector3(0.0, 2.1, 0.0), Color("ffd36b"), 42)
	var spawn_ring := MeshInstance3D.new()
	var spawn_torus := TorusMesh.new()
	spawn_torus.inner_radius = 1.25
	spawn_torus.outer_radius = 1.38
	spawn_torus.material = gold
	spawn_ring.mesh = spawn_torus
	spawn_ring.position = ORC_SPAWN_CENTER + Vector3(0.0, 0.06, 0.0)
	spawn_ring.scale.y = 0.1
	add_child(spawn_ring)


func _build_decor() -> void:
	for x in [-19.0, 19.0]:
		for z in [-15.5, 15.5]:
			var tree := TREE_SCENE.instantiate() as Node3D
			tree.position = Vector3(x, 0, z)
			tree.rotation.y = (x + z) * 0.17
			add_child(tree)
	for x in [-8.5, 8.5]:
		var banner := BANNER_SCENE.instantiate() as Node3D
		banner.position = Vector3(x, 0, -18.8)
		banner.rotation.y = PI
		add_child(banner)
	var rack := WEAPON_RACK_SCENE.instantiate() as Node3D
	rack.position = Vector3(-14.0, 0, -8.0)
	rack.rotation.y = PI * 0.5
	add_child(rack)
	_add_section_label("Move • Aim • Attack • Block • Use your special", Vector3(0, 2.4, 17.8), Color.WHITE, 40)


func _add_section_label(text: String, at: Vector3, color: Color, size: int) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = size
	label.outline_size = 14
	label.pixel_size = 0.006
	label.modulate = color
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var header := PanelContainer.new()
	header.theme_type_variation = &"PanelBrown"
	header.set_anchors_preset(Control.PRESET_CENTER_TOP)
	header.offset_left = -310.0
	header.offset_top = 18.0
	header.offset_right = 310.0
	header.offset_bottom = 112.0
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(header)
	var header_box := VBoxContainer.new()
	header_box.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(header_box)
	var title := Label.new()
	title.text = "TRAINING FIELD"
	title.theme_type_variation = &"HeaderLabel"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Try every hero. Abilities are always ready. Targets never break."
	subtitle.theme_type_variation = &"HintLabel"
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_box.add_child(subtitle)

	_prompt_panel = PanelContainer.new()
	_prompt_panel.theme_type_variation = &"PanelLight"
	_prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_panel.offset_left = -190.0
	_prompt_panel.offset_top = -126.0
	_prompt_panel.offset_right = 190.0
	_prompt_panel.offset_bottom = -48.0
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_panel.hide()
	root.add_child(_prompt_panel)
	_prompt_label = Label.new()
	_prompt_label.theme_type_variation = &"HeaderLabel"
	_prompt_label.add_theme_font_size_override("font_size", 28)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_panel.add_child(_prompt_label)

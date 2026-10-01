extends ShowcaseDemo
## The classes race side by side, again and again, at their real running speeds: ClassDef.move_speed, and
## shield_move_speed in a second lane for classes with a shield. A board shows speeds, times and gaps.

const TRACK := 16.0  # meters to the finish line
const LANE_GAP := 1.8
const PAUSE := 1.5  # seconds at the finish before the next race

var _runners: Array[Dictionary] = []
var _time := 0.0
var _finished_at := -1.0
var _board: Label3D


func _ready() -> void:
	var lanes: Array[Dictionary] = []
	var base := _player_move_speed()
	for def in ClassDef.all():
		var speed := def.move_speed if def.move_speed > 0.0 else base
		lanes.append({def = def, speed = speed, shield = false})
		if def.shield:
			lanes.append({def = def, speed = def.shield_move_speed if def.shield_move_speed > 0.0 else speed, shield = true})
	lanes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.speed > b.speed)
	for i in lanes.size():
		var z := (i - (lanes.size() - 1) * 0.5) * LANE_GAP
		_runners.append(_add_runner(lanes[i].def, lanes[i].speed, lanes[i].shield, z))
	var half := lanes.size() * LANE_GAP * 0.5
	for x in [0.0, TRACK]:
		_box(Vector3(0.15, 0.02, half * 2.0), Vector3(x - TRACK * 0.5, 0.01, 0), Color.WHITE if x > 0.0 else Color(0.2, 0.2, 0.2))
	for m in range(2, int(TRACK), 2):
		var mark := _label("%d m" % m, 0.012)
		mark.rotation_degrees.x = -90
		mark.position = Vector3(m - TRACK * 0.5, 0.02, half + 0.4)
		add_child(mark)
	_board = _label("", 0.012)
	_board.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_board.font_size = 32
	_board.position = Vector3(-3.5, 2.6, -half - 1.0)
	add_child(_board)
	_restart()


func _player_move_speed() -> float:
	var state := (load("res://scenes/characters/player.tscn") as PackedScene).get_state()
	for p in state.get_node_property_count(0):
		if state.get_node_property_name(0, p) == &"move_speed":
			return float(state.get_node_property_value(0, p))
	return 3.5


func _label(text: String, pixel_size: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.pixel_size = pixel_size
	label.outline_size = 12
	return label


func _box(size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	(mesh.mesh as BoxMesh).size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	mesh.position = at
	add_child(mesh)


func _add_runner(def: ClassDef, speed: float, shield: bool, lane_z: float) -> Dictionary:
	var name_text := def.display_name + (" + shield" if shield else "")
	var body := def.model.instantiate() as Node3D
	body.scale = Vector3.ONE * 1.25
	body.rotation_degrees.y = 90  # models face +Z; the track runs along +X
	add_child(body)
	var anim := body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for clip in ["sprint", "idle"]:
		if anim and anim.has_animation(clip):
			anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	var skeleton := _find_skeleton(body)
	if shield and skeleton and skeleton.find_bone("arm-left") >= 0:
		var hand := BoneAttachment3D.new()
		hand.bone_name = "arm-left"
		skeleton.add_child(hand)
		var item := def.shield.instantiate() as Node3D
		item.scale = Vector3.ONE * def.shield_scale
		item.rotation_degrees.y = -90
		item.position = Vector3(0.12, -0.15, 0.0)
		hand.add_child(item)
	var lane := _label(name_text, 0.012)
	lane.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lane.rotation_degrees.x = -50
	lane.position = Vector3(-TRACK * 0.5 - 0.6, 0.4, lane_z)
	lane.offset = Vector2(-80, 0)
	add_child(lane)
	return {name = name_text, speed = speed, body = body, anim = anim, lane = lane_z, done = -1.0}


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _restart() -> void:
	_time = 0.0
	_finished_at = -1.0
	for r in _runners:
		r.done = -1.0
		(r.body as Node3D).position = Vector3(-TRACK * 0.5, 0, r.lane)
		if r.anim:
			(r.anim as AnimationPlayer).play("sprint")


func _process(delta: float) -> void:
	_time += delta
	var all_done := true
	for r in _runners:
		var body := r.body as Node3D
		if r.done < 0.0:
			body.position.x = minf(body.position.x + r.speed * delta, TRACK * 0.5)
			if body.position.x >= TRACK * 0.5:
				r.done = _time
				if r.anim:
					(r.anim as AnimationPlayer).play("idle", 0.2)
			else:
				all_done = false
	if all_done and _finished_at < 0.0:
		_finished_at = _time
	if _finished_at >= 0.0 and _time - _finished_at > PAUSE:
		_restart()
	var lead := (_runners[0].body as Node3D).position.x
	var lines: PackedStringArray = ["Race to %d m" % int(TRACK)]
	for i in _runners.size():
		var r: Dictionary = _runners[i]
		var shown := "%.2f s" % (r.done if r.done >= 0.0 else _time)
		var gap := "   -%.2f m" % (lead - (r.body as Node3D).position.x) if i > 0 else ""
		lines.append("%d. %s   %.1f m/s   %s%s" % [i + 1, r.name, r.speed, shown, gap])
	_board.text = "\n".join(lines)

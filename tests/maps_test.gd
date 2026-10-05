extends Node
## Every map (MapCatalog) in every mode (offline): the world builds (landmarks / layout with collision, warbands, gold
## veins — one at every spawn — the map's light and minimap color); procedural maps keep spawn areas and objectives
## (hill / circles) clear of trees, graveyards and landmark collision; on every map nothing solid stands on a spawn,
## a circle's middle or a gold vein; the hero spawns and plays for a moment.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/maps_test.gd

const MODES: Array[int] = [Net.Mode.COOP, Net.Mode.KING_OF_THE_HILL, Net.Mode.LAST_STAND]

var t := 0.0
var pt := 0.0
var failures := 0
var _case := -1
var _checked := false


func _ready() -> void:
	_next_case()


func _log(msg: String) -> void:
	printerr("[%.1fs] %s" % [t, msg])


func _check(ok: bool, what: String) -> void:
	_log(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


func _map() -> MapDef:
	return MapCatalog.all()[_case / MODES.size()]


func _next_case() -> void:
	_case += 1
	if _case >= MapCatalog.all().size() * MODES.size():
		_log("done: %d failure(s)" % failures)
		get_tree().quit(1 if failures > 0 else 0)
		return
	Net.open_offline_lobby()
	Net.settings.map = String(_map().id)
	Net.settings.mode = MODES[_case % MODES.size()]
	Net.settings.seed = 1000 + _case
	Net.settings.events = []
	_checked = false
	pt = 0.0
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _process(delta: float) -> void:
	t += delta
	pt += delta
	var main := get_tree().current_scene
	if main == null or main.name != "Main" or main.get("local_player") == null:
		if pt > 20.0:
			_check(false, "case %d started" % _case)
			_next_case()
		return
	if pt < 0.3:
		return  # one physics frame so the world's collision is in the space
	if not _checked:
		_checked = true
		_inspect(main)
		return
	if pt > 1.8:
		_check(not main.local_player.is_dead, "  the hero plays")
		_next_case()


## World-layer collision at `at` (a cylinder of `radius`, 1 m tall), ignoring `exclude`.
func _solid_at(main: Node3D, at: Vector3, radius: float, exclude: Array[RID] = []) -> bool:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 1.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = GameConfig.LAYER_WORLD
	query.exclude = exclude
	query.transform = Transform3D(Basis(), Vector3(at.x, 0.5, at.z))
	return not main.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _inspect(main: Node3D) -> void:
	var map: MapDef = main.map
	var mode: GameMode = main.game_mode
	_log("== %s / %s (world %.0f m)" % [map.display_name, Net.MODE_NAMES[Net.settings.mode], GameConfig.world_half * 2.0])
	_check(map.id == _map().id, "  playing the picked map (every map in every mode)")
	var solids: int = main.world.find_children("Solid*", "StaticBody3D", true, false).size()
	_check(solids > 0, "  landmarks / layout with collision (%d)" % solids)
	var spawns := mode.world_spawn_points()
	var objectives := mode.world_clear_areas()
	if map.layout == null:
		var blocked_spawn := 0
		var blocked_objective := 0
		for node in main.world.get_children():
			var body := node as Node3D
			if not (body is ChoppableTree or str(body.name).begins_with("Graveyard_") \
					or (body is StaticBody3D and str(body.name).begins_with("Solid_"))):
				continue
			var flat := Vector2(body.global_position.x, body.global_position.z)
			for spawn in spawns:
				if flat.distance_to(Vector2(spawn.x, spawn.z)) < WorldBuilder.SPAWN_SAFE_RADIUS - 1.0:
					blocked_spawn += 1
			for area in objectives:
				if flat.distance_to(Vector2(area.x, area.z)) < mode.world_clear_radius() - 1.0:
					blocked_objective += 1
		_check(blocked_spawn == 0, "  spawn areas clear (%d in the way)" % blocked_spawn)
		_check(blocked_objective == 0, "  objectives clear (%d in the way)" % blocked_objective)
	var stuck := PackedStringArray()
	for spawn in spawns:
		if _solid_at(main, spawn, 0.5):
			stuck.append("spawn %s" % spawn)
	for area in objectives:
		# A circle may hold cover (the hill's statue), but heroes need room to stand in it.
		var open := 0
		for i in 8:
			if not _solid_at(main, area + Vector3(cos(i * PI * 0.25), 0.0, sin(i * PI * 0.25)) * 3.5, 0.5):
				open += 1
		if Net.settings.mode == Net.Mode.LAST_STAND and open < 6:
			stuck.append("circle %s (%d / 8 open)" % [area, open])
	_check(stuck.is_empty(), "  nothing solid on a spawn, room to stand in every circle %s" % ", ".join(stuck))
	var veins := get_tree().get_nodes_in_group(&"gold_veins")
	var at_spawns := 0
	var buried := 0
	for spawn in spawns:
		if veins.any(func(v: Node) -> bool: return (v as Node3D).global_position.distance_to(spawn) < 5.0):
			at_spawns += 1
	for vein: GoldVein in veins:
		if _solid_at(main, vein.global_position, 0.75, [vein.get_rid()]):
			buried += 1
	_check(veins.size() > spawns.size() and at_spawns == spawns.size(), "  gold veins (%d, at %d / %d spawns)" % [veins.size(), at_spawns, spawns.size()])
	_check(buried == 0, "  no gold vein inside something solid (%d)" % buried)
	var env := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	_check(env.background_color.is_equal_approx(map.sky_color) and main.hud.minimap.background == map.minimap_color, "  map light + minimap color")
	_check(get_tree().get_nodes_in_group(&"warbands").size() > 0, "  warbands (%d)" % get_tree().get_nodes_in_group(&"warbands").size())
	match Net.settings.mode:
		Net.Mode.KING_OF_THE_HILL:
			_check(get_tree().get_first_node_in_group(&"hill") != null, "  the hill")
		Net.Mode.LAST_STAND:
			_check(get_tree().get_first_node_in_group(&"hold_circles") != null and mode.circles.size() == GameMode.CIRCLE_COUNT, "  the circles")

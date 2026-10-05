extends Node
## Every map in every mode (offline): the world builds with the map's landmarks (collision), gold veins (one at
## every spawn), the map's light and minimap color; spawn areas and the mode's objectives (hill / circles) stay clear
## of trees, camps and landmark collision; the hero spawns and plays for a moment.
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


func _next_case() -> void:
	_case += 1
	if _case >= MapCatalog.MAPS.size() * MODES.size():
		_log("done: %d failure(s)" % failures)
		get_tree().quit(1 if failures > 0 else 0)
		return
	Net.open_offline_lobby()
	Net.settings.map = _case / MODES.size()
	Net.settings.mode = MODES[_case % MODES.size()]
	Net.settings.seed = 1000 + _case
	Net.settings.events = false
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
	if not _checked:
		_checked = true
		_inspect(main)
		return
	if pt > 1.5:
		_check(not main.local_player.is_dead, "  the hero plays")
		_next_case()


func _inspect(main: Node) -> void:
	var map := MapCatalog.get_map(Net.settings.map)
	var mode: GameMode = main.game_mode
	_log("== %s / %s (world %.0f m)" % [map.name, Net.MODE_NAMES[Net.settings.mode], GameConfig.world_half * 2.0])
	var solids := 0
	var blocked_spawn := 0
	var blocked_objective := 0
	var spawns := mode.world_spawn_points()
	var objectives := mode.world_clear_areas()
	for node in main.world.get_children():
		var body := node as Node3D
		var is_solid := body is StaticBody3D and str(body.name).begins_with("Solid_")
		if is_solid:
			solids += 1
		if not (is_solid or body is ChoppableTree or body is Camp):
			continue
		var flat := Vector2(body.global_position.x, body.global_position.z)
		for spawn in spawns:
			if flat.distance_to(Vector2(spawn.x, spawn.z)) < WorldBuilder.SPAWN_SAFE_RADIUS - 1.0:
				blocked_spawn += 1
		for area in objectives:
			if flat.distance_to(Vector2(area.x, area.z)) < mode.world_clear_radius() - 1.0:
				blocked_objective += 1
	_check(solids > 0, "  landmarks with collision (%d)" % solids)
	_check(blocked_spawn == 0, "  spawn areas clear (%d in the way)" % blocked_spawn)
	_check(blocked_objective == 0, "  objectives clear (%d in the way)" % blocked_objective)
	var veins := get_tree().get_nodes_in_group(&"gold_veins")
	var at_spawns := 0
	for spawn in spawns:
		if veins.any(func(v: Node) -> bool: return (v as Node3D).global_position.distance_to(spawn) < 5.0):
			at_spawns += 1
	_check(veins.size() > spawns.size() and at_spawns == spawns.size(), "  gold veins (%d, at %d / %d spawns)" % [veins.size(), at_spawns, spawns.size()])
	var env := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	_check(env.background_color.is_equal_approx(map.sky) and main.hud.minimap.background == map.minimap, "  map light + minimap color")
	_check(get_tree().get_nodes_in_group(&"camps").size() > 0, "  orc camps (%d)" % get_tree().get_nodes_in_group(&"camps").size())
	match Net.settings.mode:
		Net.Mode.KING_OF_THE_HILL:
			_check(get_tree().get_first_node_in_group(&"hill") != null, "  the hill")
		Net.Mode.LAST_STAND:
			_check(get_tree().get_first_node_in_group(&"hold_circles") != null and mode.circles.size() == GameMode.CIRCLE_COUNT, "  the circles")

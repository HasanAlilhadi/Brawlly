extends Node
## Screenshots of every map (MapCatalog.all()) in Last Stand: the spawn area from above, the nearest landmark, a gold
## vein up close and the first circle. Needs a window (not --headless; keep it off-screen):
##   "$G" --path . --position -4000,-4000 --resolution 1280x720 res://tests/test_runner.tscn -- --test=res://tests/map_shots_test.gd --out=/tmp/shots [--mode=<Net.Mode>]

const SHOTS := ["spawn", "landmark", "vein", "circle"]

var _out := "user://screenshots"
var _mode := Net.Mode.LAST_STAND
var _map := -1
var _shot := 0
var _wait := 0.0
var _loading := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--mode="):
			_mode = int(arg.substr(7))
	DirAccess.make_dir_recursive_absolute(_out)
	_next_map()


func _next_map() -> void:
	_map += 1
	if _map >= MapCatalog.all().size():
		get_tree().quit()
		return
	Net.open_offline_lobby()
	Net.settings.mode = _mode
	Net.settings.map = String(MapCatalog.all()[_map].id)
	Net.settings.seed = 777
	Net.settings.events = []
	_shot = -1
	_loading = true
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _process(delta: float) -> void:
	var main := get_tree().current_scene
	if main == null or main.name != "Main" or main.get("local_player") == null:
		return
	if _loading:
		_loading = false
		var player: Player = main.local_player
		player.max_health = 1e6
		player.health = 1e6
		_set_shot(main, 0)
		return
	_wait -= delta
	if _wait > 0.0:
		return
	var image := get_viewport().get_texture().get_image()
	var path := "%s/map_%s_%s.png" % [_out, MapCatalog.all()[_map].id, SHOTS[_shot]]
	image.save_png(path)
	printerr("saved ", path)
	if _shot + 1 >= SHOTS.size():
		_next_map()
	else:
		_set_shot(main, _shot + 1)


func _set_shot(main: Node, index: int) -> void:
	_shot = index
	_wait = 3.5 if index == 0 else 1.5
	var player: Player = main.local_player
	var at := Vector3.ZERO
	var zoom := 1.0
	match SHOTS[index]:
		"spawn":
			zoom = 2.6
		"landmark":
			var best := INF
			for node in main.world.get_children():
				if node is StaticBody3D and str(node.name).begins_with("Solid_") or str(node.name).begins_with("Graveyard_"):
					var d := (node as Node3D).global_position.length()
					if d > WorldBuilder.SPAWN_SAFE_RADIUS + 3.0 and d < best:
						best = d
						at = (node as Node3D).global_position
			at += Vector3(0, 0, 3.0)
			zoom = 1.5
		"vein":
			var vein := get_tree().get_nodes_in_group(&"gold_veins")[0] as Node3D
			at = vein.global_position + Vector3(1.5, 0, 1.2)
			zoom = 0.6
		"circle":
			at = main.game_mode.circles[0] if not main.game_mode.circles.is_empty() else Vector3.ZERO
			zoom = 2.0
	player.global_position = at
	player.net_position = at
	main.camera.zoom = main.CAMERA_ZOOM * zoom
	main.camera.snap()
	main.set_process(false)  # keep our zoom (main sets it every frame)

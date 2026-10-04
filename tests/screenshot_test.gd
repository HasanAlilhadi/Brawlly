extends Node
## Saves a screenshot of every screen (menus, lobby, match, trading post, shop, pause) to check layouts.
## Needs a window (not --headless):
##   "$G" --path . res://tests/test_runner.tscn -- --test=res://tests/screenshot_test.gd --out=/tmp/shots [--mobile]

const STEPS := [
	["main_menu", "res://scenes/ui/main_menu.tscn", 2.0],
	["server_browser", "res://scenes/ui/server_browser.tscn", 2.0],
	["host_menu", "res://scenes/ui/host_menu.tscn", 2.0],
	["controls", "res://scenes/ui/controls_menu.tscn", 2.0],
	["lobby", "lobby", 2.0],
	["match", "res://scenes/main/main.tscn", 5.0],
	["town", "town", 2.0],
	["stalls", "stalls", 1.5],
	["barracks", "barracks", 2.5],
	["barracks_turned_90", "turn", 1.5],  # R: the camera orbits 90° (the sides normally unseen)
	["barracks_turned_180", "turn", 1.5],
	["barracks_close", "barracks_close", 1.5],
	["blacksmith_close", "blacksmith_close", 1.5],
	["armory_close", "armory_close", 1.5],
	["healer_close", "healer_close", 1.5],
	["shop", "shop", 1.0],
	["pause", "pause", 1.0],
]

var _out := "user://screenshots"
var _step := -1
var _wait := 0.0
var _zoom := 1.0  # camera offset factor of the close-up shots (undone before the shop)


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_next()


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s%s.png" % [_out, STEPS[_step][0], "_mobile" if Platform.mobile_layout else ""]
	image.save_png(path)
	printerr("saved ", path, " ", image.get_size())
	_next()


func _next() -> void:
	_step += 1
	if _step >= STEPS.size():
		get_tree().quit()
		return
	var target: String = STEPS[_step][1]
	_wait = STEPS[_step][2]
	match target:
		"lobby":
			Net.host()
			get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")
		"barracks":
			var barracks: ShopStation = get_tree().get_nodes_in_group(&"shop_stations").filter(
					func(n: Node) -> bool: return n.stall_id == &"barracks")[0]
			var player: Player = get_tree().get_nodes_in_group(&"players")[0]
			player.global_position = barracks.gate_point()
			for i in 6:  # soldiers waiting in the courtyard (drawn smaller)
				NetSpawn.unit(&"ally", barracks.pen_spot(), {"team": player.team_id, "owner": player.peer_id,
						"color": player.unit_color, "pen": barracks.get_path()})
		"turn":
			get_tree().current_scene.camera.rotate_step(1)
		"barracks_close":  # zoomed in on the watchtower and stairs, to check the model's surfaces up close
			var main := get_tree().current_scene
			main.camera.rotate_step(2)  # back to the default view after the turned shots
			var barracks: ShopStation = get_tree().get_nodes_in_group(&"shop_stations").filter(
					func(n: Node) -> bool: return n.stall_id == &"barracks")[0]
			get_tree().get_nodes_in_group(&"players")[0].global_position = barracks.to_global(Vector3(-1.2, 0, -3.2))
			_set_zoom(0.4)
		"blacksmith_close":  # the blacksmith workshop up close
			_set_zoom(0.6)
			var blacksmith: ShopStation = get_tree().get_nodes_in_group(&"shop_stations").filter(
					func(n: Node) -> bool: return n.stall_id == &"blacksmith")[0]
			get_tree().get_nodes_in_group(&"players")[0].global_position = blacksmith.front()
		"armory_close":  # the Bows & Spears cabin up close
			var armory: ShopStation = get_tree().get_nodes_in_group(&"shop_stations").filter(
					func(n: Node) -> bool: return n.stall_id == &"armory")[0]
			get_tree().get_nodes_in_group(&"players")[0].global_position = armory.front()
		"healer_close":  # the Healer cottage up close
			var healer: ShopStation = get_tree().get_nodes_in_group(&"shop_stations").filter(
					func(n: Node) -> bool: return n.stall_id == &"healer")[0]
			get_tree().get_nodes_in_group(&"players")[0].global_position = healer.front()
		"town":  # zoomed out over the whole town at the spawn
			_set_zoom(2.4)
		"stalls":
			_set_zoom(1.0)
			var blacksmith: ShopStation = get_tree().get_nodes_in_group(&"shop_stations").filter(
					func(n: Node) -> bool: return n.stall_id == &"blacksmith")[0]
			get_tree().get_nodes_in_group(&"players")[0].global_position = blacksmith.front()
		"shop":
			_set_zoom(1.0)  # back to the normal camera after the close-ups
			var armory: ShopStation = get_tree().get_nodes_in_group(&"shop_stations").filter(
					func(n: Node) -> bool: return n.stall_id == &"armory")[0]
			get_tree().current_scene.get_node("ShopMenu").open(armory)
		"pause":
			get_tree().current_scene.get_node("ShopMenu").close()
			get_tree().current_scene.get_node("PauseMenu").open()
		_:
			get_tree().change_scene_to_file(target)


func _set_zoom(factor: float) -> void:
	get_tree().current_scene.camera.offset *= factor / _zoom
	_zoom = factor

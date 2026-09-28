extends Node
## Saves a screenshot of every screen (menus, lobby, match, shop, pause) to check layouts.
## Needs a window (not --headless):
##   "$G" --path . res://tests/test_runner.tscn -- --test=res://tests/screenshot_test.gd --out=/tmp/shots [--mobile]

const STEPS := [
	["main_menu", "res://scenes/ui/main_menu.tscn", 2.0],
	["multiplayer_menu", "res://scenes/ui/multiplayer_menu.tscn", 2.0],
	["controls", "res://scenes/ui/controls_menu.tscn", 2.0],
	["lobby", "lobby", 2.0],
	["match", "res://scenes/main/main.tscn", 5.0],
	["shop", "shop", 1.0],
	["pause", "pause", 1.0],
]

var _out := "user://screenshots"
var _step := -1
var _wait := 0.0


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
			Net.open_solo_lobby()
			get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")
		"shop":
			get_tree().current_scene.get_node("ShopMenu").open()
		"pause":
			get_tree().current_scene.get_node("ShopMenu").close()
			get_tree().current_scene.get_node("PauseMenu").open()
		_:
			get_tree().change_scene_to_file(target)
